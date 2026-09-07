//! OnePlus Buds 3 RFCOMM SPP bridge in Rust for Quickshell.
//!
//! Protocol reverse engineered from Osilvfe/OppoPodsManager-linux (Product 063C14).
//! Owns the RFCOMM connection to the earbuds and exposes a line-oriented JSON protocol
//! over standard I/O (stdin/stdout).

use std::env;
use std::ffi::c_void;
use std::io::{self, Write};
use std::os::raw::{c_int, c_short, c_ulong};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

const AF_BLUETOOTH: c_int = 31;
const SOCK_STREAM: c_int = 1;
const BTPROTO_RFCOMM: c_int = 3;

const SOL_SOCKET: c_int = 1;
const SO_ERROR: c_int = 4;
const F_GETFL: c_int = 3;
const F_SETFL: c_int = 4;
const O_NONBLOCK: c_int = 0o4000;

const POLLIN: c_short = 0x0001;
const POLLOUT: c_short = 0x0004;
const POLLERR: c_short = 0x0008;
const POLLHUP: c_short = 0x0010;
const POLLNVAL: c_short = 0x0020;

const EINPROGRESS: c_int = 115;
const EINTR: c_int = 4;
const EAGAIN: c_int = 11;
const EWOULDBLOCK: c_int = 11;

const STDIN_FILENO: c_int = 0;
const MSG_NOSIGNAL: c_int = 0x4000;

const MAX_RFCOMM_CHANNEL: u8 = 30;
const CONNECT_TIMEOUT_MS: c_int = 350;
const PROBE_TIMEOUT_MS: c_int = 550;

const CMD_BATTERY: u16 = 0x0106;
const CMD_BATTERY_RESP: u16 = 0x8106;
const CMD_QUERY_ANC: u16 = 0x010c;
const CMD_ANC_RESP: u16 = 0x810c;
const CMD_QUERY_EQ: u16 = 0x010f;
const CMD_EQ_RESP: u16 = 0x810f;
const CMD_BATCH_QUERY: u16 = 0x010d;
const CMD_BATCH_RESP: u16 = 0x810d;
const CMD_QUERY_SPATIAL: u16 = 0x012a;
const CMD_SPATIAL_RESP: u16 = 0x812a;
const CMD_QUERY_GAME_SOUND: u16 = 0x012b;
const CMD_GAME_SOUND_RESP: u16 = 0x812b;
const CMD_ACTIVE_REPORT: u16 = 0x0204;
const CMD_REGISTER_NOTIFY: u16 = 0x0205;
const CMD_SET_FEATURE: u16 = 0x0403;
const CMD_SET_ANC: u16 = 0x0404;
const CMD_SET_EQ: u16 = 0x0406;
const CMD_SET_SPATIAL: u16 = 0x0422;
const CMD_SET_GAME_SOUND: u16 = 0x0423;
const CMD_EQ_NOTIFY: u16 = 0x0504;

const FEATURE_WEAR_DETECTION: u8 = 0x04;
const FEATURE_DUAL_DEVICE: u8 = 0x11;
const FEATURE_HI_RES: u8 = 0x18;
const FEATURE_SPATIAL: u8 = 0x1b;
const FEATURE_GAME_SOUND: u8 = 0x27;
const FEATURE_GAME_MAIN: u8 = 0x28;

static KEEP_RUNNING: AtomicBool = AtomicBool::new(true);

#[repr(C)]
#[derive(Copy, Clone)]
struct PollFd {
    fd: c_int,
    events: c_short,
    revents: c_short,
}

#[repr(C)]
#[derive(Copy, Clone)]
struct SockAddrRc {
    rc_family: u16,
    rc_bdaddr: [u8; 6],
    rc_channel: u8,
    _padding: u8,
}

const PR_SET_PDEATHSIG: c_int = 1;

unsafe extern "C" {
    fn socket(domain: c_int, ty: c_int, protocol: c_int) -> c_int;
    fn connect(sockfd: c_int, addr: *const c_void, addrlen: u32) -> c_int;
    fn close(fd: c_int) -> c_int;
    fn poll(fds: *mut PollFd, nfds: c_ulong, timeout: c_int) -> c_int;
    fn getsockopt(sockfd: c_int, level: c_int, optname: c_int, optval: *mut c_void, optlen: *mut u32) -> c_int;
    fn fcntl(fd: c_int, cmd: c_int, ...) -> c_int;
    fn send(sockfd: c_int, buf: *const c_void, len: usize, flags: c_int) -> isize;
    fn recv(sockfd: c_int, buf: *mut c_void, len: usize, flags: c_int) -> isize;
    fn read(fd: c_int, buf: *mut c_void, count: usize) -> isize;
    fn __errno_location() -> *mut c_int;
    fn signal(signum: c_int, handler: extern "C" fn(c_int)) -> *mut c_void;
    fn prctl(option: c_int, arg2: c_ulong, arg3: c_ulong, arg4: c_ulong, arg5: c_ulong) -> c_int;
}

fn get_errno() -> c_int {
    unsafe { *__errno_location() }
}

extern "C" fn sig_handler(_: c_int) {
    KEEP_RUNNING.store(false, Ordering::SeqCst);
}

#[derive(Default, Debug, Clone)]
struct BudsState {
    battery_left: Option<i32>,
    battery_right: Option<i32>,
    battery_case: Option<i32>,
    charging_left: Option<bool>,
    charging_right: Option<bool>,
    charging_case: Option<bool>,
    anc: String,
    eq: Option<i32>,
    spatial: Option<bool>,
    spatial_v2: bool,
    game_mode: Option<bool>,
    game_sound: Option<bool>,
    dual_device: Option<bool>,
    wear_detection: Option<bool>,
    hi_res: Option<bool>,
}

impl BudsState {
    fn new() -> Self {
        Self {
            anc: "unknown".to_string(),
            ..Default::default()
        }
    }

    fn to_json(&self, address: &str, channel: i32, connected: bool) -> String {
        fn opt_int(v: Option<i32>) -> String {
            match v {
                Some(n) => n.to_string(),
                None => "null".to_string(),
            }
        }
        fn opt_bool(v: Option<bool>) -> String {
            match v {
                Some(b) => if b { "true" } else { "false" }.to_string(),
                None => "null".to_string(),
            }
        }

        format!(
            "{{\"type\":\"state\",\"connected\":{},\"address\":\"{}\",\"channel\":{},\
\"batteryLeft\":{},\"batteryRight\":{},\"batteryCase\":{},\
\"chargingLeft\":{},\"chargingRight\":{},\"chargingCase\":{},\
\"anc\":\"{}\",\"eq\":{},\"spatial\":{},\"gameMode\":{},\
\"gameSound\":{},\"dualDevice\":{},\"wearDetection\":{},\"hiRes\":{}}}\n",
            if connected { "true" } else { "false" },
            address,
            channel,
            opt_int(self.battery_left),
            opt_int(self.battery_right),
            opt_int(self.battery_case),
            opt_bool(self.charging_left),
            opt_bool(self.charging_right),
            opt_bool(self.charging_case),
            self.anc,
            opt_int(self.eq),
            opt_bool(self.spatial),
            opt_bool(self.game_mode),
            opt_bool(self.game_sound),
            opt_bool(self.dual_device),
            opt_bool(self.wear_detection),
            opt_bool(self.hi_res),
        )
    }
}

fn parse_mac(s: &str) -> Option<[u8; 6]> {
    let parts: Vec<&str> = s.split(':').collect();
    if parts.len() != 6 {
        return None;
    }
    let mut addr = [0u8; 6];
    for (i, p) in parts.iter().enumerate() {
        let b = u8::from_str_radix(p, 16).ok()?;
        // BlueZ bdaddr_t is little-endian (reversed)
        addr[5 - i] = b;
    }
    Some(addr)
}

fn build_frame(command: u16, payload: &[u8]) -> Vec<u8> {
    let total_length = 7 + payload.len();
    let mut frame = Vec::with_capacity(total_length + 2);
    frame.push(0xaa);
    frame.push(total_length as u8);
    frame.push(0x00);
    frame.push(0x00);
    frame.push((command & 0xff) as u8);
    frame.push((command >> 8) as u8);
    frame.push(0xf0);
    frame.push(payload.len() as u8);
    frame.push(0x00);
    frame.extend_from_slice(payload);
    frame
}

fn write_all(fd: c_int, data: &[u8]) -> bool {
    let mut offset = 0;
    while offset < data.len() {
        let n = unsafe {
            send(
                fd,
                data[offset..].as_ptr() as *const c_void,
                data.len() - offset,
                MSG_NOSIGNAL,
            )
        };
        if n > 0 {
            offset += n as usize;
            continue;
        }
        let err = get_errno();
        if n < 0 && err == EINTR {
            continue;
        }
        if n < 0 && (err == EAGAIN || err == EWOULDBLOCK) {
            let mut pfd = PollFd {
                fd,
                events: POLLOUT,
                revents: 0,
            };
            let ret = unsafe { poll(&mut pfd, 1, 500) };
            if ret > 0 {
                continue;
            }
        }
        return false;
    }
    true
}

fn send_cmd(fd: c_int, command: u16, payload: &[u8]) -> bool {
    let frame = build_frame(command, payload);
    write_all(fd, &frame)
}

fn connect_with_timeout(fd: c_int, addr: &SockAddrRc, timeout_ms: c_int) -> bool {
    let old_flags = unsafe { fcntl(fd, F_GETFL, 0) };
    if old_flags < 0 || unsafe { fcntl(fd, F_SETFL, old_flags | O_NONBLOCK) } < 0 {
        return false;
    }

    let ret = unsafe {
        connect(
            fd,
            addr as *const SockAddrRc as *const c_void,
            std::mem::size_of::<SockAddrRc>() as u32,
        )
    };

    let ok = if ret == 0 {
        true
    } else {
        let err = get_errno();
        if err == EINPROGRESS {
            let mut pfd = PollFd {
                fd,
                events: POLLOUT,
                revents: 0,
            };
            let polled = unsafe { poll(&mut pfd, 1, timeout_ms) };
            if polled > 0 {
                let mut so_err: c_int = 0;
                let mut len = std::mem::size_of::<c_int>() as u32;
                let g = unsafe {
                    getsockopt(
                        fd,
                        SOL_SOCKET,
                        SO_ERROR,
                        &mut so_err as *mut c_int as *mut c_void,
                        &mut len,
                    )
                };
                g == 0 && so_err == 0
            } else {
                false
            }
        } else {
            false
        }
    };

    unsafe { fcntl(fd, F_SETFL, old_flags) };
    ok
}

fn probe_channel(fd: c_int) -> bool {
    if !send_cmd(fd, CMD_BATTERY, &[]) {
        return false;
    }

    let mut pfd = PollFd {
        fd,
        events: POLLIN,
        revents: 0,
    };
    let ret = unsafe { poll(&mut pfd, 1, PROBE_TIMEOUT_MS) };
    if ret <= 0 {
        return false;
    }

    let mut resp = [0u8; 128];
    let n = unsafe { recv(fd, resp.as_mut_ptr() as *mut c_void, resp.len(), 0) };
    if n < 9 {
        return false;
    }
    let count = n as usize;
    for i in 0..=(count.saturating_sub(9)) {
        if resp[i] == 0xaa {
            let frame_len = (resp[i + 1] as usize) + 2;
            if frame_len >= 9 && i + frame_len <= count {
                return true;
            }
        }
    }
    false
}

fn connect_buds(addr_bytes: [u8; 6]) -> Option<(c_int, u8)> {
    let mut channels = Vec::with_capacity(MAX_RFCOMM_CHANNEL as usize);
    channels.push(15);
    channels.push(14);
    channels.push(16);
    for c in 1..=MAX_RFCOMM_CHANNEL {
        if !channels.contains(&c) {
            channels.push(c);
        }
    }

    for channel in channels {
        let fd = unsafe { socket(AF_BLUETOOTH, SOCK_STREAM, BTPROTO_RFCOMM) };
        if fd < 0 {
            continue;
        }

        let target = SockAddrRc {
            rc_family: AF_BLUETOOTH as u16,
            rc_bdaddr: addr_bytes,
            rc_channel: channel,
            _padding: 0,
        };

        if !connect_with_timeout(fd, &target, CONNECT_TIMEOUT_MS) {
            unsafe { close(fd) };
            continue;
        }

        if probe_channel(fd) {
            let flags = unsafe { fcntl(fd, F_GETFL, 0) };
            if flags >= 0 {
                unsafe { fcntl(fd, F_SETFL, flags | O_NONBLOCK) };
            }
            return Some((fd, channel));
        }

        unsafe { close(fd) };
    }
    None
}

fn anc_from_bitmap(data: &[u8]) -> Option<&'static str> {
    if data.len() < 2 || data[0] != 0x01 {
        return None;
    }
    let mut bitmap: u32 = 0;
    for (idx, &b) in data[1..].iter().take(3).enumerate() {
        bitmap |= (b as u32) << (idx * 8);
    }
    if bitmap & (1 << 7) != 0 { return Some("smart"); }
    if bitmap & (1 << 4) != 0 { return Some("deep"); }
    if bitmap & (1 << 5) != 0 { return Some("medium"); }
    if bitmap & (1 << 6) != 0 { return Some("light"); }
    if bitmap & (1 << 8) != 0 { return Some("transparency"); }
    if bitmap & (1 << 3) != 0 { return Some("off"); }
    None
}

fn parse_battery(payload: &[u8], state: &mut BudsState) {
    if payload.len() >= 8 && payload[0] == 0x00 && payload[1] == 0x04 {
        state.battery_left = Some(payload[2] as i32);
        state.charging_left = Some(payload[3] != 0);
        state.battery_right = Some(payload[4] as i32);
        state.charging_right = Some(payload[5] != 0);
        state.battery_case = Some(payload[6] as i32);
        state.charging_case = Some(payload[7] != 0);
        return;
    }

    let mut offset = 0;
    while offset + 1 < payload.len() {
        let component = payload[offset];
        let raw = payload[offset + 1];
        let level = (raw & 0x7f) as i32;
        let charging = (raw & 0x80) != 0;
        match component {
            1 => {
                state.battery_left = Some(level);
                state.charging_left = Some(charging);
            }
            2 => {
                state.battery_right = Some(level);
                state.charging_right = Some(charging);
            }
            3 => {
                state.battery_case = Some(level);
                state.charging_case = Some(charging);
            }
            _ => {}
        }
        offset += 2;
    }
}

fn parse_battery_notification(payload: &[u8], state: &mut BudsState) {
    if payload.len() >= 8 && payload[0] == 0x00 && payload[1] == 0x04 {
        parse_battery(payload, state);
        return;
    }
    if payload.len() < 3 {
        return;
    }
    let count = payload[0] as usize;
    for i in 0..count {
        let start = 1 + i * 2;
        if start + 1 < payload.len() {
            parse_battery(&payload[start..start + 2], state);
        }
    }
}

fn parse_batch(payload: &[u8], state: &mut BudsState) {
    let mut i = 0;
    while i + 1 < payload.len() {
        let feature = payload[i];
        let enabled = payload[i + 1] != 0;
        match feature {
            FEATURE_DUAL_DEVICE => state.dual_device = Some(enabled),
            FEATURE_GAME_MAIN => state.game_mode = Some(enabled),
            FEATURE_GAME_SOUND => state.game_sound = Some(enabled),
            FEATURE_SPATIAL => state.spatial = Some(enabled),
            FEATURE_WEAR_DETECTION => state.wear_detection = Some(enabled),
            FEATURE_HI_RES => state.hi_res = Some(enabled),
            _ => {}
        }
        i += 2;
    }
}

fn parse_frame(cmd: u16, payload: &[u8], state: &mut BudsState) -> bool {
    let mut changed = false;
    match cmd {
        CMD_BATTERY_RESP => {
            parse_battery(payload, state);
            changed = true;
        }
        CMD_ANC_RESP => {
            for i in 0..payload.len().saturating_sub(2) {
                if payload[i] == 0x01 {
                    if let Some(mode) = anc_from_bitmap(&payload[i..]) {
                        state.anc = mode.to_string();
                        changed = true;
                        break;
                    }
                }
            }
        }
        CMD_EQ_RESP | CMD_EQ_NOTIFY => {
            if payload.len() >= 2 {
                state.eq = Some(payload[1] as i32);
                changed = true;
            }
        }
        CMD_BATCH_RESP => {
            parse_batch(payload, state);
            changed = true;
        }
        CMD_SPATIAL_RESP => {
            if payload.len() >= 2 && payload[0] == 0x00 {
                state.spatial = Some(payload[1] != 0);
                state.spatial_v2 = true;
                changed = true;
            }
        }
        CMD_GAME_SOUND_RESP => {
            if payload.len() >= 2 && payload[0] == 0x00 {
                state.game_sound = Some(payload[1] != 0);
                changed = true;
            }
        }
        CMD_ACTIVE_REPORT => {
            if !payload.is_empty() {
                match payload[0] {
                    0x01 => {
                        parse_battery_notification(&payload[1..], state);
                        changed = true;
                    }
                    0x03 if payload.len() >= 3 => {
                        if let Some(mode) = anc_from_bitmap(&payload[2..]) {
                            state.anc = mode.to_string();
                            changed = true;
                        }
                    }
                    0x05 if payload.len() >= 2 => {
                        state.game_mode = Some(payload[1] != 0);
                        changed = true;
                    }
                    _ => {}
                }
            }
        }
        _ => {}
    }
    changed
}

fn send_fast_queries(fd: c_int) {
    send_cmd(fd, CMD_BATTERY, &[]);
    std::thread::sleep(Duration::from_millis(60));
    send_cmd(fd, CMD_QUERY_ANC, &[0x01, 0x01]);
}

fn send_slow_queries(fd: c_int) {
    static BATCH: [u8; 9] = [0x08, 0x04, 0x05, 0x11, 0x18, 0x06, 0x1b, 0x27, 0x28];
    static NOTIFY: [u8; 4] = [0x01, 0x01, 0x02, 0x02];
    static NOTIFY_WEAR: [u8; 2] = [0x02, 0x02];

    send_cmd(fd, CMD_QUERY_EQ, &[]);
    std::thread::sleep(Duration::from_millis(60));
    send_cmd(fd, CMD_BATCH_QUERY, &BATCH);
    std::thread::sleep(Duration::from_millis(60));
    send_cmd(fd, CMD_QUERY_GAME_SOUND, &[]);
    std::thread::sleep(Duration::from_millis(60));
    send_cmd(fd, CMD_QUERY_SPATIAL, &[]);
    std::thread::sleep(Duration::from_millis(60));
    send_cmd(fd, CMD_REGISTER_NOTIFY, &NOTIFY);
    std::thread::sleep(Duration::from_millis(60));
    send_cmd(fd, CMD_REGISTER_NOTIFY, &NOTIFY_WEAR);
}

fn set_spatial(fd: c_int, state: &mut BudsState, enabled: bool) {
    if state.spatial_v2 {
        send_cmd(fd, CMD_SET_SPATIAL, &[if enabled { 0x01 } else { 0x00 }]);
    } else {
        send_cmd(fd, CMD_SET_FEATURE, &[FEATURE_SPATIAL, if enabled { 0x01 } else { 0x00 }]);
    }
    state.spatial = Some(enabled);
}

fn set_game_sound(fd: c_int, state: &mut BudsState, enabled: bool) {
    send_cmd(fd, CMD_SET_GAME_SOUND, &[if enabled { 0x01 } else { 0x00 }, 0x01]);
    state.game_sound = Some(enabled);
}

fn handle_command(fd: c_int, state: &mut BudsState, line: &str) -> bool {
    let line = line.trim();
    if line == "query" {
        send_fast_queries(fd);
        send_slow_queries(fd);
        return false;
    }
    if line == "status" {
        return true;
    }
    if line == "quit" {
        KEEP_RUNNING.store(false, Ordering::SeqCst);
        return false;
    }
    if let Some(mode) = line.strip_prefix("anc ") {
        let (payload, len): ([u8; 4], usize) = match mode {
            "off" => ([0x01, 0x01, 0x08, 0x00], 3),
            "deep" => ([0x01, 0x01, 0x10, 0x00], 3),
            "medium" => ([0x01, 0x01, 0x20, 0x00], 3),
            "light" => ([0x01, 0x01, 0x40, 0x00], 3),
            "smart" => ([0x01, 0x01, 0x80, 0x00], 3),
            "transparency" => ([0x01, 0x01, 0x00, 0x01], 4),
            _ => {
                println!("{{\"type\":\"error\",\"message\":\"Unknown ANC mode\"}}");
                let _ = io::stdout().flush();
                return false;
            }
        };
        send_cmd(fd, CMD_SET_ANC, &payload[..len]);
        state.anc = mode.to_string();
        return true;
    }
    if let Some(val_str) = line.strip_prefix("eq ") {
        if let Ok(val) = val_str.parse::<u8>() {
            if val <= 3 {
                if val != 0 && state.game_sound == Some(true) {
                    set_game_sound(fd, state, false);
                }
                send_cmd(fd, CMD_SET_EQ, &[val]);
                state.eq = Some(val as i32);
                return true;
            }
        }
        println!("{{\"type\":\"error\",\"message\":\"EQ must be 0..3\"}}");
        let _ = io::stdout().flush();
        return false;
    }
    if let Some(val_str) = line.strip_prefix("spatial ") {
        let enabled = val_str == "1";
        if enabled && state.game_sound == Some(true) {
            set_game_sound(fd, state, false);
        }
        set_spatial(fd, state, enabled);
        return true;
    }
    if let Some(val_str) = line.strip_prefix("game ") {
        let enabled = val_str == "1";
        send_cmd(fd, CMD_SET_FEATURE, &[FEATURE_GAME_MAIN, if enabled { 0x01 } else { 0x00 }]);
        state.game_mode = Some(enabled);
        return true;
    }
    if let Some(val_str) = line.strip_prefix("game_sound ") {
        let enabled = val_str == "1";
        if enabled {
            if state.eq.unwrap_or(0) > 0 {
                send_cmd(fd, CMD_SET_EQ, &[0x00]);
                state.eq = Some(0);
            }
            if state.spatial == Some(true) {
                set_spatial(fd, state, false);
            }
        }
        set_game_sound(fd, state, enabled);
        return true;
    }
    if let Some(val_str) = line.strip_prefix("dual ") {
        let enabled = val_str == "1";
        send_cmd(fd, CMD_SET_FEATURE, &[FEATURE_DUAL_DEVICE, if enabled { 0x01 } else { 0x00 }]);
        state.dual_device = Some(enabled);
        return true;
    }
    if let Some(val_str) = line.strip_prefix("wear ") {
        let enabled = val_str == "1";
        send_cmd(fd, CMD_SET_FEATURE, &[FEATURE_WEAR_DETECTION, if enabled { 0x01 } else { 0x00 }]);
        state.wear_detection = Some(enabled);
        return true;
    }
    if let Some(val_str) = line.strip_prefix("hires ") {
        let enabled = val_str == "1";
        send_cmd(fd, CMD_SET_FEATURE, &[FEATURE_HI_RES, if enabled { 0x01 } else { 0x00 }]);
        state.hi_res = Some(enabled);
        return true;
    }

    if !line.is_empty() {
        println!("{{\"type\":\"error\",\"message\":\"Unknown command\"}}");
        let _ = io::stdout().flush();
    }
    false
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 2 {
        eprintln!("usage: oplus-buds3-bridge AA:BB:CC:DD:EE:FF");
        std::process::exit(2);
    }
    let address = &args[1];
    let addr_bytes = match parse_mac(address) {
        Some(b) => b,
        None => {
            eprintln!("Invalid Bluetooth MAC address: {}", address);
            std::process::exit(2);
        }
    };

    unsafe {
        prctl(PR_SET_PDEATHSIG, 15, 0, 0, 0);
        signal(2, sig_handler);  // SIGINT
        signal(15, sig_handler); // SIGTERM
        signal(13, sig_handler); // SIGPIPE
    }

    let (socket_fd, channel) = match connect_buds(addr_bytes) {
        Some(pair) => pair,
        None => {
            println!("{{\"type\":\"error\",\"message\":\"Unable to open the OnePlus Buds 3 control channel\"}}");
            let _ = io::stdout().flush();
            std::process::exit(3);
        }
    };

    let mut state = BudsState::new();
    print!("{}", state.to_json(address, channel as i32, true));
    let _ = io::stdout().flush();

    send_fast_queries(socket_fd);
    send_slow_queries(socket_fd);

    let mut next_fast = Instant::now() + Duration::from_secs(5);
    let mut next_slow = Instant::now() + Duration::from_secs(15);
    let mut rx_buf = Vec::with_capacity(4096);
    let mut stdin_buf = Vec::with_capacity(512);

    // Make stdin nonblocking
    let stdin_flags = unsafe { fcntl(STDIN_FILENO, F_GETFL, 0) };
    if stdin_flags >= 0 {
        unsafe { fcntl(STDIN_FILENO, F_SETFL, stdin_flags | O_NONBLOCK) };
    }

    let mut stdin_alive = true;

    while KEEP_RUNNING.load(Ordering::SeqCst) {
        let now = Instant::now();
        let timeout_fast = next_fast.saturating_duration_since(now);
        let timeout_slow = next_slow.saturating_duration_since(now);
        let min_timeout = timeout_fast.min(timeout_slow).min(Duration::from_millis(500));
        let timeout_ms = min_timeout.as_millis().min(500) as c_int;

        let mut pfds = [
            PollFd { fd: socket_fd, events: POLLIN | POLLHUP | POLLERR, revents: 0 },
            PollFd { fd: if stdin_alive { STDIN_FILENO } else { -1 }, events: POLLIN | POLLHUP, revents: 0 },
        ];

        let ret = unsafe { poll(pfds.as_mut_ptr(), 2, timeout_ms) };
        if ret < 0 {
            let err = get_errno();
            if err != EINTR {
                break;
            }
        }

        if ret > 0 {
            if pfds[0].revents & (POLLHUP | POLLERR | POLLNVAL) != 0 {
                break;
            }
            if pfds[0].revents & POLLIN != 0 {
                let mut chunk = [0u8; 512];
                let n = unsafe { recv(socket_fd, chunk.as_mut_ptr() as *mut c_void, chunk.len(), 0) };
                if n <= 0 {
                    let err = get_errno();
                    if n < 0 && (err == EINTR || err == EAGAIN || err == EWOULDBLOCK) {
                        // continue
                    } else {
                        break;
                    }
                } else {
                    rx_buf.extend_from_slice(&chunk[..n as usize]);
                    let mut changed = false;

                    // Consume rx_buf
                    while rx_buf.len() >= 2 {
                        let start = rx_buf.iter().position(|&b| b == 0xaa).unwrap_or(rx_buf.len());
                        if start > 0 {
                            rx_buf.drain(0..start);
                        }
                        if rx_buf.len() < 2 {
                            break;
                        }
                        let frame_len = (rx_buf[1] as usize) + 2;
                        if frame_len < 9 || frame_len > 512 {
                            rx_buf.drain(0..1);
                            continue;
                        }
                        if rx_buf.len() < frame_len {
                            break;
                        }
                        let cmd = (rx_buf[4] as u16) | ((rx_buf[5] as u16) << 8);
                        let declared = (rx_buf[7] as usize) | ((rx_buf[8] as usize) << 8);
                        let available = frame_len - 9;
                        let payload_len = declared.min(available);
                        if parse_frame(cmd, &rx_buf[9..9 + payload_len], &mut state) {
                            changed = true;
                        }
                        rx_buf.drain(0..frame_len);
                    }

                    if changed {
                        print!("{}", state.to_json(address, channel as i32, true));
                        let _ = io::stdout().flush();
                    }
                }
            }

            if stdin_alive && (pfds[1].revents & (POLLHUP | POLLERR | POLLNVAL) != 0) {
                stdin_alive = false;
            }
            if stdin_alive && (pfds[1].revents & POLLIN != 0) {
                let mut chunk = [0u8; 256];
                let n = unsafe { read(STDIN_FILENO, chunk.as_mut_ptr() as *mut c_void, chunk.len()) };
                if n <= 0 {
                    let err = get_errno();
                    if n < 0 && (err == EINTR || err == EAGAIN || err == EWOULDBLOCK) {
                        // continue
                    } else {
                        stdin_alive = false;
                    }
                } else {
                    stdin_buf.extend_from_slice(&chunk[..n as usize]);
                    while let Some(pos) = stdin_buf.iter().position(|&b| b == b'\n') {
                        let line_bytes = stdin_buf.drain(0..=pos).collect::<Vec<u8>>();
                        if let Ok(line) = std::str::from_utf8(&line_bytes) {
                            if handle_command(socket_fd, &mut state, line) {
                                print!("{}", state.to_json(address, channel as i32, true));
                                let _ = io::stdout().flush();
                            }
                        }
                    }
                }
            }
        }

        let now = Instant::now();
        if now >= next_fast {
            send_fast_queries(socket_fd);
            next_fast = now + Duration::from_secs(5);
        }
        if now >= next_slow {
            send_slow_queries(socket_fd);
            next_slow = now + Duration::from_secs(15);
        }
    }

    unsafe { close(socket_fd) };
}
