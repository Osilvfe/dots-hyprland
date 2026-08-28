#!/usr/bin/env python3

"""Manage per-device PipeWire EQ filters for Quickshell.

Profiles and desired device states are stored outside the repository in the
user's illogical-impulse configuration directory. Connected devices are
updated through their node Props parameter, so the physical sink keeps its
identity and A/B switching does not interrupt playback.
"""

from __future__ import annotations

import argparse
import cmath
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from typing import Any


FIR_RATES = (44_100, 48_000, 96_000, 192_000)
MAX_SAMPLE_RATE = max(FIR_RATES)
FIR_FREQUENCY_RESOLUTION = 3.0
RUNTIME_GRAPH_ORDER = 7
PIPEWIRE_COMMAND_TIMEOUT = 5.0
STATE_VERSION = 1

CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
DATA_DIR = CONFIG_HOME / "illogical-impulse" / "pipewire-eq"
PROFILE_DIR = DATA_DIR / "profiles"
STATE_PATH = DATA_DIR / "devices.json"
PARAMETRIC_RE = re.compile(
    r"^Filter\s+\d+\s*:\s*(ON|OFF)\s+(PK|LSC|HSC)\s+"
    r"Fc\s+([-+]?\d+(?:\.\d+)?)\s*Hz\s+"
    r"Gain\s+([-+]?\d+(?:\.\d+)?)\s*dB\s+"
    r"Q\s+([-+]?\d+(?:\.\d+)?)\s*$",
    re.IGNORECASE,
)
PREAMP_RE = re.compile(
    r"^Preamp\s*:\s*([-+]?\d+(?:\.\d+)?)\s*dB\s*$", re.IGNORECASE
)


class EqError(RuntimeError):
    pass


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).astimezone().isoformat(timespec="seconds")


def atomic_write(path: Path, data: str | bytes, mode: str = "w") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    binary = "b" in mode
    with tempfile.NamedTemporaryFile(
        mode=mode,
        dir=path.parent,
        prefix=f".{path.name}.",
        delete=False,
        encoding=None if binary else "utf-8",
    ) as handle:
        handle.write(data)
        temporary_path = Path(handle.name)
    os.replace(temporary_path, path)


def load_state() -> dict[str, Any]:
    if not STATE_PATH.exists():
        return {"version": STATE_VERSION, "devices": {}}
    try:
        state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise EqError(f"无法读取 EQ 状态：{error}") from error
    if not isinstance(state, dict) or not isinstance(state.get("devices", {}), dict):
        raise EqError("EQ 状态文件格式无效")
    state.setdefault("version", STATE_VERSION)
    state.setdefault("devices", {})
    return state


def save_state(state: dict[str, Any]) -> None:
    atomic_write(STATE_PATH, json.dumps(state, ensure_ascii=False, indent=2) + "\n")


def profile_key(device: str) -> str:
    return hashlib.sha256(device.encode("utf-8")).hexdigest()[:16]


def spa_quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def parse_curve(text: str) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        fields = [part for part in re.split(r"[\s,;]+", line) if part]
        if len(fields) != 2:
            raise EqError(f"第 {line_number} 行不是频率/增益二列数据")
        try:
            frequency, gain = map(float, fields)
        except ValueError as error:
            raise EqError(f"第 {line_number} 行包含非数字数据") from error
        if not 1.0 <= frequency <= MAX_SAMPLE_RATE / 2:
            raise EqError(f"第 {line_number} 行频率超出 1–96000 Hz")
        if not -60.0 <= gain <= 24.0:
            raise EqError(f"第 {line_number} 行增益超出 -60–24 dB")
        points.append((frequency, gain))

    if not 16 <= len(points) <= 512:
        raise EqError("频率曲线必须包含 16–512 个节点")
    points.sort(key=lambda item: item[0])
    if len({frequency for frequency, _ in points}) != len(points):
        raise EqError("频率曲线包含重复频率")
    return points


def parse_parametric(text: str) -> tuple[str, dict[str, Any]]:
    preamp: float | None = None
    filters: list[tuple[int, str, float, float, float]] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        preamp_match = PREAMP_RE.match(line)
        if preamp_match:
            preamp = float(preamp_match.group(1))
            continue
        filter_match = PARAMETRIC_RE.match(line)
        if not filter_match:
            raise EqError(f"无法识别 ParametricEQ 行：{line}")
        enabled, kind, frequency_text, gain_text, q_text = filter_match.groups()
        if enabled.upper() == "OFF":
            continue
        frequency = float(frequency_text)
        gain = float(gain_text)
        quality = float(q_text)
        if not 1.0 <= frequency <= MAX_SAMPLE_RATE / 2:
            raise EqError(f"滤镜频率 {frequency:g} Hz 超出范围")
        if not -60.0 <= gain <= 24.0:
            raise EqError(f"滤镜增益 {gain:g} dB 超出范围")
        if not 0.01 <= quality <= 100.0:
            raise EqError(f"滤镜 Q {quality:g} 超出范围")
        filters.append((len(filters) + 1, kind.upper(), frequency, gain, quality))

    if preamp is None:
        raise EqError("ParametricEQ 缺少 Preamp，无法保证削波余量")
    if not -60.0 <= preamp <= 12.0:
        raise EqError("Preamp 超出 -60–12 dB")
    if not filters:
        raise EqError("ParametricEQ 没有已启用的滤镜")
    if len(filters) > 64:
        raise EqError("ParametricEQ 最多支持 64 个已启用滤镜")

    lines = [f"Preamp: {preamp:g} dB"]
    for index, kind, frequency, gain, quality in filters:
        lines.append(
            f"Filter {index}: ON {kind} Fc {frequency:g} Hz "
            f"Gain {gain:g} dB Q {quality:g}"
        )
    return "\n".join(lines) + "\n", {
        "kind": "parametric",
        "filters": len(filters),
        "preamp": preamp,
    }


def inspect_profile(path: Path) -> tuple[str, Any, dict[str, Any]]:
    if not path.is_file():
        raise EqError(f"找不到导入文件：{path}")
    try:
        text = path.read_text(encoding="utf-8-sig")
    except (OSError, UnicodeError) as error:
        raise EqError(f"无法读取导入文件：{error}") from error

    if PREAMP_RE.search(text) or re.search(r"^Filter\s+\d+\s*:", text, re.MULTILINE):
        normalized, metadata = parse_parametric(text)
        return "parametric", normalized, metadata

    points = parse_curve(text)
    source_max_gain = max(gain for _, gain in points)
    headroom = max(0.0, source_max_gain + 0.2)
    if headroom > 0.0:
        points = [(frequency, gain - headroom) for frequency, gain in points]
    metadata = {
        "kind": "fir",
        "points": len(points),
        "minFrequency": points[0][0],
        "maxFrequency": points[-1][0],
        "sourceMaxGain": source_max_gain,
        "headroomAdjustment": -headroom,
        "maxGain": max(gain for _, gain in points),
        "sampleRates": list(FIR_RATES),
    }
    return "fir", points, metadata


def fft(values: list[complex], inverse: bool = False) -> list[complex]:
    size = len(values)
    if size == 0 or size & (size - 1):
        raise ValueError("FFT size must be a power of two")
    output = list(values)
    target = 0
    for index in range(1, size):
        bit = size >> 1
        while target & bit:
            target ^= bit
            bit >>= 1
        target ^= bit
        if index < target:
            output[index], output[target] = output[target], output[index]

    length = 2
    direction = 1.0 if inverse else -1.0
    while length <= size:
        step = cmath.exp(direction * 2j * math.pi / length)
        half = length // 2
        for start in range(0, size, length):
            factor = 1.0 + 0.0j
            for offset in range(half):
                even = output[start + offset]
                odd = output[start + offset + half] * factor
                output[start + offset] = even + odd
                output[start + offset + half] = even - odd
                factor *= step
        length <<= 1
    if inverse:
        output = [value / size for value in output]
    return output


def interpolate_curve(points: list[tuple[float, float]], frequency: float) -> float:
    if frequency <= points[0][0]:
        return points[0][1]
    if frequency >= points[-1][0]:
        return points[-1][1]
    low = 0
    high = len(points) - 1
    while high - low > 1:
        middle = (low + high) // 2
        if points[middle][0] <= frequency:
            low = middle
        else:
            high = middle
    low_frequency, low_gain = points[low]
    high_frequency, high_gain = points[high]
    fraction = (
        math.log(frequency / low_frequency)
        / math.log(high_frequency / low_frequency)
    )
    return low_gain + fraction * (high_gain - low_gain)


def make_minimum_phase_fir(
    points: list[tuple[float, float]], sample_rate: int
) -> list[float]:
    minimum_length = math.ceil(sample_rate / FIR_FREQUENCY_RESOLUTION)
    fir_length = 1 << (minimum_length - 1).bit_length()
    fft_size = fir_length * 2
    half = fft_size // 2
    log_magnitude = [0j] * fft_size
    for index in range(half + 1):
        frequency = index * sample_rate / fft_size
        gain_db = interpolate_curve(points, frequency)
        log_magnitude[index] = complex(math.log(10.0) * gain_db / 20.0, 0.0)
    for index in range(half + 1, fft_size):
        log_magnitude[index] = log_magnitude[fft_size - index]

    cepstrum = fft(log_magnitude, inverse=True)
    minimum_cepstrum = [0j] * fft_size
    minimum_cepstrum[0] = complex(cepstrum[0].real, 0.0)
    minimum_cepstrum[half] = complex(cepstrum[half].real, 0.0)
    for index in range(1, half):
        minimum_cepstrum[index] = complex(2.0 * cepstrum[index].real, 0.0)

    minimum_log_spectrum = fft(minimum_cepstrum)
    spectrum = [cmath.exp(value) for value in minimum_log_spectrum]
    impulse = [value.real for value in fft(spectrum, inverse=True)[:fir_length]]

    fade_samples = max(256, round(1024 * sample_rate / 48_000))
    fade_start = len(impulse) - fade_samples
    for index in range(fade_start, len(impulse)):
        phase = (index - fade_start) / (fade_samples - 1)
        impulse[index] *= 0.5 * (1.0 + math.cos(math.pi * phase))
    return impulse


def write_float_wav(path: Path, samples: list[float], sample_rate: int) -> None:
    payload = struct.pack(f"<{len(samples)}f", *samples)
    format_chunk = struct.pack(
        "<HHIIHH", 3, 1, sample_rate, sample_rate * 4, 4, 32
    )
    riff_size = 4 + (8 + len(format_chunk)) + (8 + len(payload))
    wav = (
        b"RIFF"
        + struct.pack("<I", riff_size)
        + b"WAVE"
        + b"fmt "
        + struct.pack("<I", len(format_chunk))
        + format_chunk
        + b"data"
        + struct.pack("<I", len(payload))
        + payload
    )
    atomic_write(path, wav, mode="wb")


def graph_for_profile(entry: dict[str, Any], graph_name: str) -> list[str]:
    if entry["kind"] == "fir":
        profile = "[ " + " ".join(spa_quote(path) for path in entry["profiles"]) + " ]"
    else:
        profile = spa_quote(entry["profile"])
    channels = max(1, min(int(entry.get("channels", 2)), 8))
    lines = ["          {", "            nodes = ["]
    if entry["kind"] == "fir":
        for channel in range(channels):
            channel_name = f"{graph_name}_{channel + 1}"
            lines.extend(
                [
                    "              {",
                    "                type = builtin",
                    f"                name = {channel_name}",
                    "                label = convolver",
                    "                config = {",
                    f"                  filename = {profile}",
                    "                  blocksize = 256",
                    "                  tailsize = 4096",
                    "                  resample_quality = 4",
                    "                  latency = 0.0",
                    "                }",
                    "              }",
                ]
            )
    else:
        lines.extend(
            [
                "              {",
                "                type = builtin",
                f"                name = {graph_name}",
                "                label = param_eq",
                "                config = {",
                f"                  filename = {profile}",
                "                }",
                "              }",
            ]
        )
    lines.extend(["            ]", "            inputs = ["])
    for channel in range(channels):
        port = (
            f"{graph_name}_{channel + 1}:In"
            if entry["kind"] == "fir"
            else f"{graph_name}:In {channel + 1}"
        )
        lines.append(f"              {spa_quote(port)}")
    lines.extend(["            ]", "            outputs = ["])
    for channel in range(channels):
        port = (
            f"{graph_name}_{channel + 1}:Out"
            if entry["kind"] == "fir"
            else f"{graph_name}:Out {channel + 1}"
        )
        lines.append(f"              {spa_quote(port)}")
    lines.append("            ]")
    lines.append("          }")
    return lines


def graph_name_for_device(device: str) -> str:
    return f"ii_eq_{profile_key(device)[:8]}"


def graph_description(entry: dict[str, Any], device: str) -> str:
    """Return the SPA-JSON graph accepted by audioconvert at runtime."""
    return " ".join(
        line.strip() for line in graph_for_profile(entry, graph_name_for_device(device))
    )


def run_pipewire(command: list[str]) -> str:
    try:
        result = subprocess.run(
            command,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=PIPEWIRE_COMMAND_TIMEOUT,
        )
    except FileNotFoundError as error:
        raise EqError(f"找不到 PipeWire 命令：{command[0]}") from error
    except subprocess.TimeoutExpired as error:
        raise EqError(f"PipeWire 命令超时：{command[0]}") from error
    except subprocess.CalledProcessError as error:
        detail = error.stderr.strip() or error.stdout.strip() or str(error)
        raise EqError(f"PipeWire 运行时操作失败：{detail}") from error
    return result.stdout


def live_sink_nodes() -> dict[str, dict[str, int]]:
    """Map connected physical sink names to their current id and serial."""
    try:
        objects = json.loads(run_pipewire(["pw-dump"]))
    except json.JSONDecodeError as error:
        raise EqError("无法解析 pw-dump 输出") from error
    nodes: dict[str, dict[str, int]] = {}
    for item in objects:
        if item.get("type") != "PipeWire:Interface:Node":
            continue
        properties = item.get("info", {}).get("props", {})
        name = properties.get("node.name")
        if (
            isinstance(name, str)
            and properties.get("media.class") == "Audio/Sink"
            and name.startswith(("alsa_output.", "bluez_output."))
        ):
            nodes[name] = {
                "id": int(item["id"]),
                "serial": int(properties.get("object.serial", item["id"])),
            }
    return nodes


def set_runtime_graph(node_id: int, order: int, description: str) -> None:
    key = f"audioconvert.filter-graph.{order}"
    pod = f"{{ params = [ {spa_quote(key)} {spa_quote(description)} ] }}"
    run_pipewire(["pw-cli", "set-param", str(node_id), "Props", pod])


def runtime_status(
    device: str,
    entry: dict[str, Any],
    nodes: dict[str, dict[str, int]],
) -> dict[str, Any]:
    node = nodes.get(device)
    if node is None:
        return {
            "runtimeConnected": False,
            "runtimeActive": False,
            "runtimeOrder": -1,
        }
    runtime = entry.get("runtime", {})
    active = bool(
        runtime.get("active")
        and int(runtime.get("serial", -1)) == node["serial"]
    )
    return {
        "runtimeConnected": True,
        "runtimeActive": active,
        "runtimeOrder": int(runtime.get("order", -1)) if active else -1,
    }


def set_entry_runtime(
    device: str,
    entry: dict[str, Any],
    enabled: bool,
    nodes: dict[str, dict[str, int]],
    *,
    force: bool = False,
) -> str:
    """Hot-load or remove this manager's graph without restarting audio."""
    node = nodes.get(device)
    if node is None:
        entry.pop("runtime", None)
        entry.pop("runtimeError", None)
        return "offline"

    node_id = node["id"]
    serial = node["serial"]
    runtime = entry.get("runtime", {})
    graph = graph_description(entry, device)
    graph_hash = hashlib.sha256(graph.encode("utf-8")).hexdigest()
    tracked_active = bool(
        runtime.get("active")
        and int(runtime.get("serial", -1)) == serial
    )
    if not enabled:
        if tracked_active or force:
            order = int(runtime.get("order", RUNTIME_GRAPH_ORDER))
            set_runtime_graph(node_id, order, "")
        entry["runtime"] = {
            "serial": serial,
            "active": False,
            "order": -1,
            "updatedAt": now_iso(),
        }
        entry.pop("runtimeError", None)
        return "disabled"

    if (
        tracked_active
        and runtime.get("graphHash") == graph_hash
        and not force
    ):
        entry.pop("runtimeError", None)
        return "enabled"
    set_runtime_graph(node_id, RUNTIME_GRAPH_ORDER, graph)
    current = live_sink_nodes().get(device)
    if current is None or current["serial"] != serial:
        raise EqError("应用 EQ 时设备已断开")
    entry["runtime"] = {
        "serial": serial,
        "active": True,
        "order": RUNTIME_GRAPH_ORDER,
        "graphHash": graph_hash,
        "updatedAt": now_iso(),
    }
    entry.pop("runtimeError", None)
    return "enabled"


def status_payload(state: dict[str, Any]) -> dict[str, Any]:
    try:
        nodes = live_sink_nodes()
        runtime_error = ""
    except EqError as error:
        nodes = {}
        runtime_error = str(error)
    devices = []
    for device, entry in sorted(state["devices"].items()):
        item = dict(entry)
        item["device"] = device
        item.update(runtime_status(device, entry, nodes))
        if runtime_error:
            item["runtimeError"] = runtime_error
        devices.append(item)
    return {
        "ok": True,
        "available": all(
            shutil.which(command) is not None for command in ("pw-cli", "pw-dump")
        ),
        "devices": devices,
        "configPath": str(STATE_PATH),
        "dataPath": str(DATA_DIR),
    }


def import_profile(args: argparse.Namespace, state: dict[str, Any]) -> dict[str, Any]:
    source = Path(args.file).expanduser().resolve()
    kind, parsed, metadata = inspect_profile(source)
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    key = profile_key(args.device)
    if kind == "fir":
        destinations = []
        lengths: dict[str, int] = {}
        for sample_rate in FIR_RATES:
            destination = PROFILE_DIR / f"{key}-{sample_rate}.wav"
            impulse = make_minimum_phase_fir(parsed, sample_rate)
            write_float_wav(destination, impulse, sample_rate)
            destinations.append(destination)
            lengths[str(sample_rate)] = len(impulse)
        destination = destinations[0]
        metadata["firLengths"] = lengths
    else:
        destination = PROFILE_DIR / f"{key}.txt"
        atomic_write(destination, parsed)
        destinations = [destination]

    old_entry = state["devices"].get(args.device, {})
    old_profile = Path(old_entry.get("profile", "")) if old_entry.get("profile") else None
    state["devices"][args.device] = {
        "description": args.description or args.device,
        "profile": str(destination),
        "profiles": [str(path) for path in destinations],
        "profileName": source.stem,
        "sourcePath": str(source),
        "kind": kind,
        "channels": args.channels,
        "enabled": bool(old_entry.get("enabled", False)),
        "importedAt": now_iso(),
        **metadata,
    }
    old_profiles = old_entry.get("profiles", [str(old_profile)] if old_profile else [])
    for old_path_text in old_profiles:
        old_path = Path(old_path_text)
        if old_path not in destinations and old_path.parent == PROFILE_DIR:
            old_path.unlink(missing_ok=True)
    if state["devices"][args.device]["enabled"]:
        try:
            set_entry_runtime(
                args.device,
                state["devices"][args.device],
                True,
                live_sink_nodes(),
                force=True,
            )
        except EqError as error:
            state["devices"][args.device]["runtimeError"] = str(error)
    save_state(state)
    payload = status_payload(state)
    payload["message"] = (
        "配置已导入，默认保持关闭"
        if not old_entry.get("enabled")
        else "配置已导入并热更新"
    )
    return payload


def set_enabled(args: argparse.Namespace, state: dict[str, Any], enabled: bool) -> dict[str, Any]:
    entry = state["devices"].get(args.device)
    if not entry:
        raise EqError("该设备尚未导入 EQ 配置")
    entry["enabled"] = enabled
    entry["updatedAt"] = now_iso()
    save_state(state)
    try:
        result = set_entry_runtime(args.device, entry, enabled, live_sink_nodes())
        runtime_error = ""
    except EqError as error:
        result = "error"
        runtime_error = str(error)
        entry["runtimeError"] = runtime_error
    save_state(state)
    payload = status_payload(state)
    if runtime_error:
        payload["message"] = f"设置已保存，但实时切换失败：{runtime_error}"
    elif result == "offline":
        payload["message"] = "设置已保存，设备下次连接时自动应用"
    else:
        payload["message"] = "已无缝启用 EQ" if enabled else "已无缝旁路 EQ"
    return payload


def forget_device(args: argparse.Namespace, state: dict[str, Any]) -> dict[str, Any]:
    entry = state["devices"].get(args.device)
    if entry:
        try:
            set_entry_runtime(args.device, entry, False, live_sink_nodes())
        except EqError:
            pass
        state["devices"].pop(args.device, None)
        for profile_text in entry.get("profiles", [entry.get("profile", "")]):
            profile = Path(profile_text)
            if profile.parent == PROFILE_DIR:
                profile.unlink(missing_ok=True)
    save_state(state)
    payload = status_payload(state)
    payload["message"] = "已旁路并移除设备 EQ 配置"
    return payload


def reconcile_config(state: dict[str, Any]) -> dict[str, Any]:
    nodes = live_sink_nodes()
    changed = 0
    errors = []
    for device, entry in state["devices"].items():
        try:
            result = set_entry_runtime(
                device,
                entry,
                bool(entry.get("enabled")),
                nodes,
            )
            if result != "offline":
                changed += 1
        except EqError as error:
            entry["runtimeError"] = str(error)
            errors.append(f"{entry.get('description', device)}：{error}")
    state["appliedAt"] = now_iso()
    save_state(state)
    payload = status_payload(state)
    payload["message"] = (
        "运行时同步失败：" + "；".join(errors)
        if errors
        else f"已无中断同步 {changed} 个在线设备"
    )
    return payload


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("status")

    inspect_parser = subparsers.add_parser("inspect")
    inspect_parser.add_argument("file")

    import_parser = subparsers.add_parser("import")
    import_parser.add_argument("--device", required=True)
    import_parser.add_argument("--description", default="")
    import_parser.add_argument("--channels", type=int, choices=range(1, 9), default=2)
    import_parser.add_argument("--file", required=True)

    for command in ("enable", "disable", "forget"):
        action_parser = subparsers.add_parser(command)
        action_parser.add_argument("--device", required=True)
    subparsers.add_parser("apply")
    subparsers.add_parser("reconcile")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "inspect":
            _, _, metadata = inspect_profile(Path(args.file).expanduser())
            payload = {"ok": True, **metadata}
        else:
            state = load_state()
            if args.command == "status":
                payload = status_payload(state)
            elif args.command == "import":
                payload = import_profile(args, state)
            elif args.command == "enable":
                payload = set_enabled(args, state, True)
            elif args.command == "disable":
                payload = set_enabled(args, state, False)
            elif args.command == "forget":
                payload = forget_device(args, state)
            elif args.command in ("apply", "reconcile"):
                payload = reconcile_config(state)
            else:
                raise EqError(f"未知操作：{args.command}")
    except EqError as error:
        print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False))
        return 1
    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
