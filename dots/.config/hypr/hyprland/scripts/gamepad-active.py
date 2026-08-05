#!/usr/bin/env python3
# 检测手柄（gamepad）最近 1 秒内是否有输入活动。
# 退出码 0 = 手柄有活动（应跳过锁屏/关屏/挂起），1 = 无活动或未插手柄。
import fcntl
import os
import select
import sys
import time

EV_KEY = 0x01
KEY_MAX = 0x2FF
KEY_BYTES = (KEY_MAX + 1 + 7) // 8
EVIOCGBIT = 0x80044521 | (KEY_BYTES << 16)  # _IOC(READ, 'E', 0x20+EV_KEY, len)
GAMEPAD_BITS = (0x120, 0x130, 0x140, 0x2C0)  # BTN_JOYSTICK, BTN_GAMEPAD, BTN_TRIGGER, BTN_TRIGGER_HAPPY


def is_gamepad(path: str) -> bool:
    try:
        fd = os.open(path, os.O_RDONLY)
    except OSError:
        return False
    try:
        buf = fcntl.ioctl(fd, EVIOCGBIT, b"\0" * KEY_BYTES)
    except OSError:
        os.close(fd)
        return False
    os.close(fd)
    for bit in GAMEPAD_BITS:
        if bit < len(buf) * 8 and (buf[bit // 8] >> (bit % 8)) & 1:
            return True
    return False


def main() -> int:
    window = 1.0
    deadline = time.monotonic() + window
    fds = []
    try:
        for name in sorted(os.listdir("/dev/input")):
            if not name.startswith("event"):
                continue
            path = "/dev/input/" + name
            if not is_gamepad(path):
                continue
            try:
                fd = os.open(path, os.O_RDONLY)
            except OSError:
                continue
            os.set_blocking(fd, False)
            fds.append(fd)
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return 1
            r, _, _ = select.select(fds, [], [], remaining)
            for fd in r:
                try:
                    data = os.read(fd, 4096)
                except BlockingIOError:
                    continue
                if data:
                    return 0
    finally:
        for fd in fds:
            os.close(fd)
    return 1


if __name__ == "__main__":
    sys.exit(main())
