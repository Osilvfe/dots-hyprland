use std::process::Command;

#[derive(Clone, Debug)]
struct SavedConnection {
    name: String,
    uuid: String,
    autoconnect: bool,
}

#[derive(Clone, Debug)]
struct EthernetDevice {
    device: String,
    state: String,
    connection: String,
    con_uuid: String,
    carrier: bool,
    speed: String,
    hwaddr: String,
    ipv4: Vec<String>,
    gateway4: String,
    dns4: Vec<String>,
    ipv6: Vec<String>,
    saved_connections: Vec<SavedConnection>,
    autoconnect: bool,
}

fn json_str(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                out.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn serialize_devices(devices: &[EthernetDevice]) -> String {
    let mut out = String::from("[");
    for (i, dev) in devices.iter().enumerate() {
        if i > 0 {
            out.push_str(", ");
        }
        out.push('{');
        out.push_str(&format!("\"device\": {}, ", json_str(&dev.device)));
        out.push_str(&format!("\"state\": {}, ", json_str(&dev.state)));
        out.push_str(&format!("\"connection\": {}, ", json_str(&dev.connection)));
        out.push_str(&format!("\"conUuid\": {}, ", json_str(&dev.con_uuid)));
        out.push_str(&format!("\"carrier\": {}, ", if dev.carrier { "true" } else { "false" }));
        out.push_str(&format!("\"speed\": {}, ", json_str(&dev.speed)));
        out.push_str(&format!("\"hwaddr\": {}, ", json_str(&dev.hwaddr)));

        out.push_str("\"ipv4\": [");
        for (j, ip) in dev.ipv4.iter().enumerate() {
            if j > 0 {
                out.push_str(", ");
            }
            out.push_str(&json_str(ip));
        }
        out.push_str("], ");

        out.push_str(&format!("\"gateway4\": {}, ", json_str(&dev.gateway4)));

        out.push_str("\"dns4\": [");
        for (j, dns) in dev.dns4.iter().enumerate() {
            if j > 0 {
                out.push_str(", ");
            }
            out.push_str(&json_str(dns));
        }
        out.push_str("], ");

        out.push_str("\"ipv6\": [");
        for (j, ip6) in dev.ipv6.iter().enumerate() {
            if j > 0 {
                out.push_str(", ");
            }
            out.push_str(&json_str(ip6));
        }
        out.push_str("], ");

        out.push_str("\"savedConnections\": [");
        for (j, conn) in dev.saved_connections.iter().enumerate() {
            if j > 0 {
                out.push_str(", ");
            }
            out.push('{');
            out.push_str(&format!("\"name\": {}, ", json_str(&conn.name)));
            out.push_str(&format!("\"uuid\": {}, ", json_str(&conn.uuid)));
            out.push_str(&format!("\"autoconnect\": {}", if conn.autoconnect { "true" } else { "false" }));
            out.push('}');
        }
        out.push_str("], ");

        out.push_str(&format!("\"autoconnect\": {}", if dev.autoconnect { "true" } else { "false" }));
        out.push('}');
    }
    out.push(']');
    out
}

struct RawSavedConn {
    name: String,
    uuid: String,
    autoconnect: bool,
    device: String,
}

fn main() {
    let status_output = Command::new("nmcli")
        .args(["-t", "-f", "DEVICE,TYPE,STATE,CONNECTION,CON-UUID", "device", "status"])
        .env("LANG", "C")
        .env("LC_ALL", "C")
        .output();

    let Ok(status_output) = status_output else {
        println!("[]");
        return;
    };

    if !status_output.status.success() {
        println!("[]");
        return;
    }

    let status_str = String::from_utf8_lossy(&status_output.stdout);

    let mut all_saved: Vec<RawSavedConn> = Vec::new();
    if let Ok(conn_output) = Command::new("nmcli")
        .args(["-t", "-f", "NAME,UUID,TYPE,AUTOCONNECT,DEVICE", "connection", "show"])
        .env("LANG", "C")
        .env("LC_ALL", "C")
        .output()
    {
        if conn_output.status.success() {
            let conn_str = String::from_utf8_lossy(&conn_output.stdout);
            for line in conn_str.lines() {
                let parts: Vec<&str> = line.split(':').collect();
                if parts.len() >= 4 {
                    let conn_type = parts[2].to_lowercase();
                    if conn_type.contains("ethernet") || conn_type.contains("802-3") {
                        let dev = if parts.len() > 4 { parts[4] } else { "" };
                        all_saved.push(RawSavedConn {
                            name: parts[0].to_string(),
                            uuid: parts[1].to_string(),
                            autoconnect: parts[3].eq_ignore_ascii_case("yes"),
                            device: dev.to_string(),
                        });
                    }
                }
            }
        }
    }

    let mut devices: Vec<EthernetDevice> = Vec::new();

    for line in status_str.lines() {
        if line.is_empty() {
            continue;
        }
        let parts: Vec<&str> = line.split(':').collect();
        if parts.len() >= 3 && parts[1] == "ethernet" {
            let dev_name = parts[0];
            let dev_state = parts[2];
            let active_conn = if parts.len() > 3 { parts[3] } else { "" };
            let active_uuid = if parts.len() > 4 { parts[4] } else { "" };

            let mut dev = EthernetDevice {
                device: dev_name.to_string(),
                state: dev_state.to_string(),
                connection: active_conn.to_string(),
                con_uuid: active_uuid.to_string(),
                carrier: false,
                speed: String::new(),
                hwaddr: String::new(),
                ipv4: Vec::new(),
                gateway4: String::new(),
                dns4: Vec::new(),
                ipv6: Vec::new(),
                saved_connections: Vec::new(),
                autoconnect: true,
            };

            if let Ok(show_output) = Command::new("nmcli")
                .args([
                    "-t",
                    "-m",
                    "multiline",
                    "-f",
                    "GENERAL.HWADDR,WIRED-PROPERTIES.CARRIER,CAPABILITIES.SPEED,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS",
                    "device",
                    "show",
                    dev_name,
                ])
                .env("LANG", "C")
                .env("LC_ALL", "C")
                .output()
            {
                if show_output.status.success() {
                    let show_str = String::from_utf8_lossy(&show_output.stdout);
                    for s_line in show_str.lines() {
                        if s_line.is_empty() {
                            continue;
                        }
                        if let Some((k, v)) = s_line.split_once(':') {
                            let k = k.trim();
                            let v = v.trim();
                            if k == "GENERAL.HWADDR" {
                                dev.hwaddr = v.to_string();
                            } else if k == "WIRED-PROPERTIES.CARRIER" {
                                dev.carrier = v.eq_ignore_ascii_case("on");
                            } else if k == "CAPABILITIES.SPEED" {
                                dev.speed = if v.eq_ignore_ascii_case("unknown") {
                                    String::new()
                                } else {
                                    v.to_string()
                                };
                            } else if k.starts_with("IP4.ADDRESS") {
                                if !v.is_empty() && !dev.ipv4.contains(&v.to_string()) {
                                    dev.ipv4.push(v.to_string());
                                }
                            } else if k == "IP4.GATEWAY" {
                                dev.gateway4 = v.to_string();
                            } else if k.starts_with("IP4.DNS") {
                                if !v.is_empty() && !dev.dns4.contains(&v.to_string()) {
                                    dev.dns4.push(v.to_string());
                                }
                            } else if k.starts_with("IP6.ADDRESS") {
                                if !v.is_empty() && !dev.ipv6.contains(&v.to_string()) {
                                    dev.ipv6.push(v.to_string());
                                }
                            }
                        }
                    }
                }
            }

            for saved in &all_saved {
                if saved.device == dev_name || saved.device.is_empty() || active_conn == saved.name {
                    dev.saved_connections.push(SavedConnection {
                        name: saved.name.clone(),
                        uuid: saved.uuid.clone(),
                        autoconnect: saved.autoconnect,
                    });
                    if dev.con_uuid.is_empty() {
                        dev.con_uuid = saved.uuid.clone();
                        dev.autoconnect = saved.autoconnect;
                    } else if dev.con_uuid == saved.uuid {
                        dev.autoconnect = saved.autoconnect;
                    }
                }
            }

            devices.push(dev);
        }
    }

    println!("{}", serialize_devices(&devices));
}
