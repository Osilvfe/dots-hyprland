//! Heart Rate BLE & Network Broadcast Bridge for Quickshell in pure Rust.
//!
//! Features:
//! - BLE GATT Heart Rate Service (0x180D / 0x2A37) integration via bluetoothctl
//! - Local network UDP/OSC broadcast listener (port 9000 by default)
//! - Simulation / Mock mode for UI testing and demonstration
//! - Thread-safe state aggregator, calculating BPM, heart rate zones, min/max/avg, and rolling history
//! - Atomic state export to $XDG_RUNTIME_DIR/quickshell-heart-rate.json + stdout JSON lines
//! - Stdin command interface for IPC control (scan, connect, disconnect, mock, reset_stats)

use std::convert::TryInto;
use std::env;
use std::fs::{self, File};
use std::io::{self, BufRead, BufReader, Write};
use std::net::UdpSocket;
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const _HRS_UUID_SHORT: &str = "180d";
const HRM_UUID_SHORT: &str = "2a37";

#[derive(Clone, Debug)]
struct DiscoveredDevice {
    address: String,
    name: String,
    rssi: i32,
    connected: bool,
}

#[derive(Clone, Debug)]
struct Stats {
    min: u32,
    max: u32,
    avg: f64,
    duration: u64,
    total_samples: u64,
    history: Vec<u32>,
}

#[derive(Clone, Debug)]
struct HeartRateState {
    connected: bool,
    source: String, // "ble", "udp", "mock", "none"
    device_name: String,
    device_address: String,
    sensor_location: String,
    bpm: u32,
    last_update_epoch_sec: u64,
    zone: u32, // 0..5
    zone_name: String,
    zone_color: String,
    battery: i32,
    rr_intervals: Vec<f64>,
    is_mock: bool,
    stats: Stats,
    discovered_devices: Vec<DiscoveredDevice>,

    // Internal trackers
    stats_start_instant: Option<Instant>,
    sum_bpm: u64,
}

impl HeartRateState {
    fn new() -> Self {
        Self {
            connected: false,
            source: "none".to_string(),
            device_name: String::new(),
            device_address: String::new(),
            sensor_location: String::new(),
            bpm: 0,
            last_update_epoch_sec: 0,
            zone: 0,
            zone_name: "No Data".to_string(),
            zone_color: "#64748b".to_string(),
            battery: -1,
            rr_intervals: Vec::new(),
            is_mock: false,
            stats: Stats {
                min: 0,
                max: 0,
                avg: 0.0,
                duration: 0,
                total_samples: 0,
                history: Vec::new(),
            },
            discovered_devices: Vec::new(),
            stats_start_instant: None,
            sum_bpm: 0,
        }
    }

    fn calculate_zone(bpm: u32, max_hr: u32) -> (u32, &'static str, &'static str) {
        if bpm == 0 {
            return (0, "No Data", "#64748b");
        }
        let ratio = bpm as f64 / max_hr as f64;
        if ratio < 0.50 {
            (0, "Resting", "#4ade80") // Green
        } else if ratio < 0.60 {
            (1, "Warm Up", "#38bdf8") // Sky blue
        } else if ratio < 0.70 {
            (2, "Fat Burn", "#22c55e") // Lime green
        } else if ratio < 0.80 {
            (3, "Aerobic", "#eab308") // Yellow
        } else if ratio < 0.90 {
            (4, "Anaerobic", "#f97316") // Orange
        } else {
            (5, "Maximum", "#ef4444") // Crimson red
        }
    }

    fn update_bpm(&mut self, bpm: u32, source: &str, device_name: &str, device_address: &str, max_hr: u32) {
        if bpm == 0 {
            return;
        }
        self.bpm = bpm;
        self.source = source.to_string();
        self.connected = true;
        if !device_name.is_empty() {
            self.device_name = device_name.to_string();
        }
        if !device_address.is_empty() {
            self.device_address = device_address.to_string();
        }

        self.last_update_epoch_sec = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        let (z, z_name, z_color) = Self::calculate_zone(bpm, max_hr);
        self.zone = z;
        self.zone_name = z_name.to_string();
        self.zone_color = z_color.to_string();

        if self.stats_start_instant.is_none() {
            self.stats_start_instant = Some(Instant::now());
            self.stats.min = bpm;
            self.stats.max = bpm;
        } else {
            if self.stats.min == 0 || bpm < self.stats.min {
                self.stats.min = bpm;
            }
            if bpm > self.stats.max {
                self.stats.max = bpm;
            }
        }

        self.stats.total_samples += 1;
        self.sum_bpm += bpm as u64;
        self.stats.avg = (self.sum_bpm as f64 / self.stats.total_samples as f64 * 10.0).round() / 10.0;

        if let Some(start) = self.stats_start_instant {
            self.stats.duration = start.elapsed().as_secs();
        }

        self.stats.history.push(bpm);
        if self.stats.history.len() > 60 {
            self.stats.history.remove(0);
        }
    }

    fn reset_stats(&mut self) {
        if self.bpm > 0 {
            self.stats_start_instant = Some(Instant::now());
            self.stats.min = self.bpm;
            self.stats.max = self.bpm;
            self.stats.total_samples = 1;
            self.sum_bpm = self.bpm as u64;
            self.stats.avg = self.bpm as f64;
            self.stats.duration = 0;
            self.stats.history = vec![self.bpm];
        } else {
            self.stats_start_instant = None;
            self.stats.min = 0;
            self.stats.max = 0;
            self.stats.total_samples = 0;
            self.sum_bpm = 0;
            self.stats.avg = 0.0;
            self.stats.duration = 0;
            self.stats.history.clear();
        }
    }

    fn to_json(&self) -> String {
        let history_str: Vec<String> = self.stats.history.iter().map(|n| n.to_string()).collect();
        let rr_str: Vec<String> = self.rr_intervals.iter().map(|f| format!("{:.1}", f)).collect();

        let mut devices_json = Vec::new();
        for dev in &self.discovered_devices {
            devices_json.push(format!(
                r#"{{"address":"{}","name":"{}","rssi":{},"connected":{}}}"#,
                escape_json(&dev.address),
                escape_json(&dev.name),
                dev.rssi,
                dev.connected
            ));
        }

        format!(
            r#"{{"type":"heart_rate","connected":{},"source":"{}","device_name":"{}","device_address":"{}","sensor_location":"{}","bpm":{},"last_update":{},"zone":{},"zone_name":"{}","zone_color":"{}","battery":{},"rr_intervals":[{}],"is_mock":{},"stats":{{"min":{},"max":{},"avg":{:.1},"duration":{},"total_samples":{},"history":[{}]}},"discovered_devices":[{}]}}"#,
            self.connected,
            escape_json(&self.source),
            escape_json(&self.device_name),
            escape_json(&self.device_address),
            escape_json(&self.sensor_location),
            self.bpm,
            self.last_update_epoch_sec,
            self.zone,
            escape_json(&self.zone_name),
            escape_json(&self.zone_color),
            self.battery,
            rr_str.join(","),
            self.is_mock,
            self.stats.min,
            self.stats.max,
            self.stats.avg,
            self.stats.duration,
            self.stats.total_samples,
            history_str.join(","),
            devices_json.join(",")
        )
    }
}

fn strip_ansi(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut in_csi = false;
    for c in input.chars() {
        if c == '\x1b' {
            in_csi = true;
        } else if in_csi {
            if c.is_ascii_alphabetic() {
                in_csi = false;
            }
        } else if c != '\r' {
            out.push(c);
        }
    }
    out
}

fn escape_json(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            _ => out.push(c),
        }
    }
    out
}

fn write_state_file(state_file: &PathBuf, json: &str) {
    let tmp_file = state_file.with_extension("tmp");
    if let Ok(mut f) = File::create(&tmp_file) {
        let _ = f.write_all(json.as_bytes());
        let _ = f.write_all(b"\n");
        let _ = fs::rename(&tmp_file, state_file);
    }
}

fn emit_state(state: &HeartRateState, state_file: &PathBuf) {
    let json = state.to_json();
    write_state_file(state_file, &json);
    let stdout = io::stdout();
    let mut handle = stdout.lock();
    let _ = writeln!(handle, "{}", json);
    let _ = handle.flush();
}

fn parse_hex_bytes(line: &str) -> Vec<u8> {
    let mut bytes = Vec::new();
    if let Some(pos) = line.find("Value:") {
        let after = &line[pos + 6..];
        for part in after.split_whitespace() {
            let t = part.trim();
            let clean = if t.starts_with("0x") || t.starts_with("0X") {
                &t[2..]
            } else {
                t
            };
            if clean.len() == 2 || clean.len() == 1 {
                if let Ok(b) = u8::from_str_radix(clean, 16) {
                    bytes.push(b);
                }
            }
        }
    }
    bytes
}

fn parse_hrm_payload(data: &[u8]) -> Option<(u32, Vec<f64>)> {
    if data.len() < 2 {
        return None;
    }
    let flags = data[0];
    let hr_is_u16 = (flags & 0x01) != 0;
    let energy_present = (flags & 0x08) != 0;
    let rr_present = (flags & 0x10) != 0;

    let mut idx = 1;
    let bpm = if hr_is_u16 {
        if data.len() < idx + 2 {
            return None;
        }
        let v = data[idx] as u32 | ((data[idx + 1] as u32) << 8);
        idx += 2;
        v
    } else {
        let v = data[idx] as u32;
        idx += 1;
        v
    };

    if energy_present && data.len() >= idx + 2 {
        idx += 2;
    }

    let mut rr_list = Vec::new();
    if rr_present {
        while idx + 1 < data.len() {
            let raw = data[idx] as u32 | ((data[idx + 1] as u32) << 8);
            let rr_ms = (raw as f64 / 1024.0 * 1000.0 * 10.0).round() / 10.0;
            rr_list.push(rr_ms);
            idx += 2;
        }
    }

    Some((bpm, rr_list))
}

fn parse_network_packet(buf: &[u8]) -> Option<(u32, String)> {
    // 1. OSC Protocol: starts with "/"
    if buf.starts_with(b"/") {
        let parts: Vec<&[u8]> = buf.split(|&b| b == 0).collect();
        if let Ok(addr_str) = std::str::from_utf8(parts[0]) {
            let lower = addr_str.to_lowercase();
            if lower.contains("heart") || lower.contains("hr") {
                // Find type tag starting with ','
                let mut type_idx = 1;
                while type_idx < parts.len() && !parts[type_idx].starts_with(b",") {
                    type_idx += 1;
                }
                if type_idx < parts.len() {
                    let type_tag = parts[type_idx];
                    if type_tag.len() > 1 {
                        // Offset calculation: align to 4-byte boundary
                        let tag_str_len = parts[..=type_idx].iter().map(|p| p.len() + 1).sum::<usize>();
                        let payload_offset = ((tag_str_len + 3) / 4) * 4;
                        if buf.len() >= payload_offset + 4 {
                            match type_tag[1] {
                                b'f' => {
                                    let val = f32::from_be_bytes(buf[payload_offset..payload_offset + 4].try_into().unwrap_or_default());
                                    let mut bpm = val as f64;
                                    if bpm <= 1.0 && bpm > 0.0 {
                                        bpm *= 220.0;
                                    }
                                    if (30.0..=250.0).contains(&bpm) {
                                        return Some((bpm.round() as u32, "VRChat/OSC".to_string()));
                                    }
                                }
                                b'i' => {
                                    let val = i32::from_be_bytes(buf[payload_offset..payload_offset + 4].try_into().unwrap_or_default());
                                    if (30..=250).contains(&val) {
                                        return Some((val as u32, "VRChat/OSC".to_string()));
                                    }
                                }
                                _ => {}
                            }
                        }
                    }
                }
            }
        }
    }

    // 2. Plain text or JSON
    if let Ok(text) = std::str::from_utf8(buf) {
        let s = text.trim();
        if s.starts_with('{') && s.ends_with('}') {
            for key in &["bpm", "hr", "heartrate", "heart_rate", "rate"] {
                let pattern = format!("\"{}\":", key);
                if let Some(pos) = s.find(&pattern) {
                    let after = &s[pos + pattern.len()..].trim_start();
                    let num_str: String = after.chars().take_while(|c| c.is_ascii_digit() || *c == '.').collect();
                    if let Ok(val) = num_str.parse::<f64>() {
                        if (30.0..=250.0).contains(&val) {
                            return Some((val.round() as u32, "UDP JSON".to_string()));
                        }
                    }
                }
            }
        }

        if let Ok(val) = s.parse::<f64>() {
            if (30.0..=250.0).contains(&val) {
                return Some((val.round() as u32, "UDP Broadcast".to_string()));
            }
        }
    }

    None
}

struct BtCtlSession {
    child: Child,
    stdin: ChildStdin,
}

impl BtCtlSession {
    fn spawn() -> io::Result<(Self, BufReader<std::process::ChildStdout>)> {
        let mut child = Command::new("stdbuf")
            .args(&["-oL", "-eL", "bluetoothctl"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .or_else(|_| {
                Command::new("bluetoothctl")
                    .stdin(Stdio::piped())
                    .stdout(Stdio::piped())
                    .stderr(Stdio::null())
                    .spawn()
            })?;

        let stdin = child.stdin.take().expect("Failed to open bluetoothctl stdin");
        let stdout = child.stdout.take().expect("Failed to open bluetoothctl stdout");
        let reader = BufReader::new(stdout);

        Ok((Self { child, stdin }, reader))
    }

    fn send(&mut self, cmd: &str) {
        let _ = writeln!(self.stdin, "{}", cmd);
        let _ = self.stdin.flush();
    }
}

impl Drop for BtCtlSession {
    fn drop(&mut self) {
        let _ = writeln!(self.stdin, "quit");
        let _ = self.stdin.flush();
        let _ = self.child.kill();
    }
}

fn main() {
    let mut preferred_device = String::new();
    let mut auto_connect = true;
    let mut max_hr = 190u32;
    let mut _resting_hr = 60u32;
    let mut udp_port = 9000u16;
    let mut enable_mock = false;

    let args: Vec<String> = env::args().collect();
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--preferred-device" if i + 1 < args.len() => {
                preferred_device = args[i + 1].trim().to_uppercase();
                i += 1;
            }
            "--no-auto-connect" => {
                auto_connect = false;
            }
            "--max-hr" if i + 1 < args.len() => {
                if let Ok(val) = args[i + 1].parse::<u32>() {
                    max_hr = val.max(100);
                }
                i += 1;
            }
            "--resting-hr" if i + 1 < args.len() => {
                if let Ok(val) = args[i + 1].parse::<u32>() {
                    _resting_hr = val.max(30);
                }
                i += 1;
            }
            "--udp-port" if i + 1 < args.len() => {
                if let Ok(val) = args[i + 1].parse::<u16>() {
                    udp_port = val;
                }
                i += 1;
            }
            "--mock" => {
                enable_mock = true;
            }
            _ => {}
        }
        i += 1;
    }

    let runtime_dir = env::var("XDG_RUNTIME_DIR")
        .unwrap_or_else(|_| format!("/run/user/{}", unsafe {
            extern "C" { fn getuid() -> u32; }
            getuid()
        }));
    let state_file = PathBuf::from(runtime_dir).join("quickshell-heart-rate.json");

    let state = Arc::new(Mutex::new(HeartRateState::new()));
    {
        let mut s = state.lock().unwrap();
        s.is_mock = enable_mock;
        emit_state(&s, &state_file);
    }

    let running = Arc::new(AtomicBool::new(true));

    // Stdin command channel thread
    let (tx_cmd, rx_cmd) = std::sync::mpsc::channel::<String>();
    {
        let running_stdin = Arc::clone(&running);
        thread::spawn(move || {
            let stdin = io::stdin();
            for line in stdin.lock().lines() {
                if !running_stdin.load(Ordering::SeqCst) {
                    break;
                }
                if let Ok(l) = line {
                    let trimmed = l.trim().to_string();
                    if !trimmed.is_empty() {
                        let _ = tx_cmd.send(trimmed);
                    }
                }
            }
        });
    }

    // UDP broadcast receiver thread
    if udp_port > 0 {
        let state_udp = Arc::clone(&state);
        let state_file_udp = state_file.clone();
        let running_udp = Arc::clone(&running);
        thread::spawn(move || {
            if let Ok(socket) = UdpSocket::bind(("0.0.0.0", udp_port)) {
                let _ = socket.set_read_timeout(Some(Duration::from_millis(1000)));
                eprintln!("[HeartRateBridge] UDP listener bound on 0.0.0.0:{}", udp_port);
                let mut buf = [0u8; 2048];
                while running_udp.load(Ordering::SeqCst) {
                    if let Ok((n, src)) = socket.recv_from(&mut buf) {
                        if n > 0 {
                            if let Some((bpm, source_name)) = parse_network_packet(&buf[..n]) {
                                let mut s = state_udp.lock().unwrap();
                                let dev_name = format!("{} ({})", source_name, src.ip());
                                s.update_bpm(bpm, "udp", &dev_name, "", max_hr);
                                emit_state(&s, &state_file_udp);
                            }
                        }
                    }
                }
            }
        });
    }

    // Mock mode generator thread
    {
        let state_mock = Arc::clone(&state);
        let state_file_mock = state_file.clone();
        let running_mock = Arc::clone(&running);
        thread::spawn(move || {
            let mut current_mock = 72.0f64;
            let mut target_mock = 80.0f64;
            let mut step = 0u64;
            let targets = [68.0, 75.0, 84.0, 102.0, 125.0, 142.0, 88.0, 70.0];

            while running_mock.load(Ordering::SeqCst) {
                thread::sleep(Duration::from_millis(1000));
                let is_mock_active = {
                    let s = state_mock.lock().unwrap();
                    s.is_mock
                };
                if !is_mock_active {
                    continue;
                }

                step += 1;
                if step % 14 == 0 {
                    let idx = (step / 14) as usize % targets.len();
                    target_mock = targets[idx];
                }

                let delta = (target_mock - current_mock) * 0.15;
                // Micro jitter without external rand crate
                let pseudo_jitter = ((step.wrapping_mul(1103515245).wrapping_add(12345) % 100) as f64 - 50.0) * 0.03;
                current_mock += delta + pseudo_jitter;
                let bpm = (current_mock.round() as u32).clamp(45, 195);

                let mut s = state_mock.lock().unwrap();
                s.update_bpm(bpm, "mock", "Virtual HR Sensor (Mock)", "00:00:00:00:00:00", max_hr);
                emit_state(&s, &state_file_mock);
            }
        });
    }

    // Bluetoothctl session & controller thread
    let (mut btctl, bt_reader) = match BtCtlSession::spawn() {
        Ok(res) => res,
        Err(e) => {
            eprintln!("[HeartRateBridge] Error launching bluetoothctl: {}", e);
            loop {
                thread::sleep(Duration::from_secs(1));
            }
        }
    };

    // Clear filters and enable duplicate data for reliable beacon discovery
    btctl.send("menu scan");
    btctl.send("clear");
    btctl.send("duplicate-data on");
    btctl.send("back");
    if auto_connect || !preferred_device.is_empty() {
        btctl.send("scan on");
    }

    let (tx_bt_lines, rx_bt_lines) = std::sync::mpsc::channel::<String>();
    {
        let running_reader = Arc::clone(&running);
        thread::spawn(move || {
            for line in bt_reader.lines() {
                if !running_reader.load(Ordering::SeqCst) {
                    break;
                }
                if let Ok(l) = line {
                    let _ = tx_bt_lines.send(l);
                }
            }
        });
    }

    let mut current_connected_mac = String::new();
    let mut hrm_attr_path = String::new();
    let mut last_bt_scan_trigger = Instant::now();

    loop {
        // Handle incoming IPC commands
        while let Ok(cmd) = rx_cmd.try_recv() {
            let parts: Vec<&str> = cmd.split_whitespace().collect();
            if parts.is_empty() {
                continue;
            }
            match parts[0].to_lowercase().as_str() {
                "mock" => {
                    let mut s = state.lock().unwrap();
                    let new_mock = if parts.len() > 1 {
                        matches!(parts[1].to_lowercase().as_str(), "1" | "true" | "on" | "yes")
                    } else {
                        !s.is_mock
                    };
                    s.is_mock = new_mock;
                    if !new_mock && s.source == "mock" {
                        s.connected = false;
                        s.bpm = 0;
                        s.source = "none".to_string();
                    }
                    emit_state(&s, &state_file);
                }
                "scan" => {
                    btctl.send("scan.uuids 0000180d-0000-1000-8000-00805f9b34fb");
                    btctl.send("scan on");
                }
                "connect" if parts.len() > 1 => {
                    let mac = parts[1].to_uppercase();
                    current_connected_mac = mac.clone();
                    btctl.send(&format!("connect {}", mac));
                }
                "disconnect" => {
                    if !current_connected_mac.is_empty() {
                        btctl.send(&format!("disconnect {}", current_connected_mac));
                        current_connected_mac.clear();
                    }
                    let mut s = state.lock().unwrap();
                    s.connected = false;
                    s.bpm = 0;
                    s.source = "none".to_string();
                    emit_state(&s, &state_file);
                }
                "reset_stats" => {
                    let mut s = state.lock().unwrap();
                    s.reset_stats();
                    emit_state(&s, &state_file);
                }
                "quit" | "exit" => {
                    running.store(false, Ordering::SeqCst);
                    let _ = fs::remove_file(&state_file);
                    return;
                }
                _ => {}
            }
        }

        // Handle bluetoothctl output lines
        while let Ok(line) = rx_bt_lines.try_recv() {
            let clean = strip_ansi(&line);
            let trimmed = if let Some(idx) = clean.rfind("[bluetoothctl]>") {
                clean[idx + 15..].trim()
            } else {
                clean.trim()
            };
            if trimmed.is_empty() {
                continue;
            }

            // Device discovery: [NEW] Device AA:BB:CC:DD:EE:FF Name
            if trimmed.contains("Device ") && (trimmed.contains("[NEW]") || trimmed.contains("[CHG]")) && trimmed.contains(":") {
                let parts: Vec<&str> = trimmed.split_whitespace().collect();
                if let Some(pos) = parts.iter().position(|&p| p == "Device") {
                    if pos + 1 < parts.len() {
                        let mac = parts[pos + 1].to_uppercase();
                        let name = if pos + 2 < parts.len() {
                            parts[pos + 2..].join(" ")
                        } else {
                            String::new()
                        };

                        let mut s = state.lock().unwrap();
                        let mut found = false;
                        for d in &mut s.discovered_devices {
                            if d.address == mac {
                                if !name.is_empty() {
                                    d.name = name.clone();
                                }
                                found = true;
                                break;
                            }
                        }
                        if !found {
                            s.discovered_devices.push(DiscoveredDevice {
                                address: mac.clone(),
                                name: name.clone(),
                                rssi: -60,
                                connected: false,
                            });
                        }

                        // Auto-connect condition
                        let lower_name = name.to_lowercase();
                        let is_phone = lower_name.contains("xiaomi 14")
                            || lower_name.contains("oppo")
                            || lower_name.contains("phone")
                            || lower_name.contains("pencil")
                            || lower_name.contains("controller");

                        let is_hr_device = !is_phone && ((!preferred_device.is_empty() && (preferred_device == mac || name.contains(&preferred_device)))
                            || name.to_uppercase().contains("5D3C")
                            || lower_name.contains("smart band")
                            || lower_name.contains("band 9")
                            || lower_name.contains("band 8")
                            || lower_name.contains("band 7")
                            || lower_name.contains("band")
                            || lower_name.contains("heart")
                            || lower_name.contains("hrm")
                            || lower_name.contains("polar")
                            || lower_name.contains("garmin")
                            || lower_name.contains("magene")
                            || lower_name.contains("coros")
                            || lower_name.contains("suunto")
                            || lower_name.contains("coospo")
                            || lower_name.contains("wahoo"));

                        if !s.connected && !s.is_mock && auto_connect && is_hr_device {
                            eprintln!("[HeartRateBridge] Auto-connecting to potential HR device: {} ({})", name, mac);
                            current_connected_mac = mac.clone();
                            btctl.send(&format!("connect {}", mac));
                        }
                    }
                }
            }

            // Connection success: Connection successful
            if trimmed.contains("Connection successful") {
                eprintln!("[HeartRateBridge] Connected successfully to {}", current_connected_mac);
                if !current_connected_mac.is_empty() {
                    btctl.send(&format!("trust {}", current_connected_mac));
                }
                btctl.send("menu gatt");
                btctl.send("select-attribute 00002a37-0000-1000-8000-00805f9b34fb");
                btctl.send("notify on");
                btctl.send("select-attribute 2a37");
                btctl.send("notify on");
                if !current_connected_mac.is_empty() {
                    btctl.send(&format!("list-attributes {}", current_connected_mac));
                } else {
                    btctl.send("list-attributes");
                }

                let mut s = state.lock().unwrap();
                s.connected = true;
                s.source = "ble".to_string();
                if !current_connected_mac.is_empty() {
                    s.device_address = current_connected_mac.clone();
                    if let Some(dev) = s.discovered_devices.iter().find(|d| d.address == current_connected_mac) {
                        s.device_name = dev.name.clone();
                    }
                }
                emit_state(&s, &state_file);
            }

            // Detect Heart Rate Measurement characteristic attribute
            if trimmed.contains(HRM_UUID_SHORT) && (trimmed.contains("Characteristic") || trimmed.contains("attribute")) {
                let parts: Vec<&str> = trimmed.split_whitespace().collect();
                for token in parts {
                    if token.starts_with("/org/bluez/") && token.contains("char") {
                        hrm_attr_path = token.to_string();
                        btctl.send(&format!("select-attribute {}", hrm_attr_path));
                        btctl.send("notify on");
                        btctl.send("back");
                        eprintln!("[HeartRateBridge] Subscribing to HRM attribute: {}", hrm_attr_path);
                        break;
                    }
                }
            }

            // Attribute notification with Value
            if trimmed.contains("Attribute") && trimmed.contains("Value:") {
                let bytes = parse_hex_bytes(trimmed);
                if let Some((bpm, rr_list)) = parse_hrm_payload(&bytes) {
                    let mut s = state.lock().unwrap();
                    let dev_name = if !current_connected_mac.is_empty() {
                        let name = s.discovered_devices.iter()
                            .find(|d| d.address == current_connected_mac)
                            .map(|d| d.name.clone())
                            .unwrap_or_else(|| current_connected_mac.clone());
                        name
                    } else {
                        "BLE Heart Rate Monitor".to_string()
                    };

                    s.rr_intervals = rr_list;
                    s.update_bpm(bpm, "ble", &dev_name, &current_connected_mac, max_hr);
                    emit_state(&s, &state_file);
                }
            }

            // Disconnection detection
            if trimmed.contains("Connected: no") || trimmed.contains("Successful disconnected") {
                let mut s = state.lock().unwrap();
                if s.source == "ble" {
                    s.connected = false;
                    s.bpm = 0;
                    s.source = "none".to_string();
                    emit_state(&s, &state_file);
                }
                hrm_attr_path.clear();
                // Resume scan to auto-reconnect
                if auto_connect {
                    btctl.send("scan on");
                }
            }
        }

        // Periodic maintenance: watchdog timeout (if no update for 8s on live stream, reset bpm)
        {
            let mut s = state.lock().unwrap();
            let now_sec = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs();

            if s.connected && s.bpm > 0 && !s.is_mock && (now_sec - s.last_update_epoch_sec > 8) {
                s.bpm = 0;
                if s.source == "udp" {
                    s.connected = false;
                    s.source = "none".to_string();
                }
                emit_state(&s, &state_file);
            }
        }

        // Periodically refresh scan if disconnected
        if last_bt_scan_trigger.elapsed() > Duration::from_secs(15) {
            last_bt_scan_trigger = Instant::now();
            let is_conn = {
                let s = state.lock().unwrap();
                s.connected || s.is_mock
            };
            if !is_conn && auto_connect {
                btctl.send("scan on");
            }
        }

        thread::sleep(Duration::from_millis(50));
    }
}
