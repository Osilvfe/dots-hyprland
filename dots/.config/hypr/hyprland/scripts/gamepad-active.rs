use std::fs;
use std::os::raw::{c_int, c_short, c_ulong, c_void};
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::io::AsRawFd;
use std::time::{Duration, Instant};

const KEY_MAX: usize = 0x2ff;
const KEY_BYTES: usize = (KEY_MAX + 1 + 7) / 8; // 96 bytes
// EVIOCGBIT(EV_KEY, KEY_BYTES) = _IOC(_IOC_READ, 'E', 0x20 + 1, KEY_BYTES)
const EVIOCGBIT_KEY: c_ulong = 0x80004521 | ((KEY_BYTES as c_ulong) << 16);
const GAMEPAD_BITS: [usize; 4] = [0x120, 0x130, 0x140, 0x2c0]; // BTN_JOYSTICK, BTN_GAMEPAD, BTN_TRIGGER, BTN_TRIGGER_HAPPY

#[repr(C)]
struct PollFd {
    fd: c_int,
    events: c_short,
    revents: c_short,
}

const POLLIN: c_short = 0x0001;

extern "C" {
    fn ioctl(fd: c_int, request: c_ulong, ...) -> c_int;
    fn poll(fds: *mut PollFd, nfds: c_ulong, timeout: c_int) -> c_int;
    fn read(fd: c_int, buf: *mut c_void, count: usize) -> isize;
}

fn is_gamepad(fd: c_int) -> bool {
    let mut buf = [0u8; KEY_BYTES];
    let ret = unsafe { ioctl(fd, EVIOCGBIT_KEY, buf.as_mut_ptr()) };
    if ret < 0 {
        return false;
    }
    for &bit in &GAMEPAD_BITS {
        if bit < KEY_BYTES * 8 && (buf[bit / 8] >> (bit % 8)) & 1 != 0 {
            return true;
        }
    }
    false
}

fn main() {
    let mut files = Vec::new();

    if let Ok(entries) = fs::read_dir("/dev/input") {
        let mut paths: Vec<_> = entries
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().to_string_lossy().starts_with("event"))
            .map(|e| e.path())
            .collect();
        paths.sort();

        for path in paths {
            if let Ok(file) = fs::OpenOptions::new()
                .read(true)
                .custom_flags(0o4000) // O_NONBLOCK
                .open(&path)
            {
                if is_gamepad(file.as_raw_fd()) {
                    files.push(file);
                }
            }
        }
    }

    if files.is_empty() {
        std::process::exit(1);
    }

    let deadline = Instant::now() + Duration::from_secs(1);

    loop {
        let now = Instant::now();
        if now >= deadline {
            std::process::exit(1);
        }
        let remaining_ms = (deadline.saturating_duration_since(now)).as_millis().min(1000) as c_int;
        if remaining_ms <= 0 {
            std::process::exit(1);
        }

        let mut pfds: Vec<PollFd> = files
            .iter()
            .map(|f| PollFd {
                fd: f.as_raw_fd(),
                events: POLLIN,
                revents: 0,
            })
            .collect();

        let ret = unsafe { poll(pfds.as_mut_ptr(), pfds.len() as c_ulong, remaining_ms) };
        if ret > 0 {
            for pfd in &pfds {
                if pfd.revents & POLLIN != 0 {
                    let mut buf = [0u8; 1024];
                    let n = unsafe { read(pfd.fd, buf.as_mut_ptr() as *mut c_void, buf.len()) };
                    if n > 0 {
                        std::process::exit(0);
                    }
                }
            }
        } else if ret == 0 {
            std::process::exit(1);
        } else {
            // Check if interrupted by signal (EINTR = 4)
            if std::io::Error::last_os_error().raw_os_error() != Some(4) {
                std::process::exit(1);
            }
        }
    }
}
