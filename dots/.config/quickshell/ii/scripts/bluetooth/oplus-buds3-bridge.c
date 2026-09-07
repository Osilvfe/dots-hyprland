#define _POSIX_C_SOURCE 200809L

#include <bluetooth/bluetooth.h>
#include <bluetooth/rfcomm.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

/*
 * Minimal OnePlus Buds 3 bridge for Quickshell.
 *
 * The byte-level commands and model indices come from
 * Osilvfe/OppoPodsManager-linux (OnePlus Buds 3, product 063C14). The bridge
 * deliberately supports this one model only. It owns the RFCOMM connection
 * and exposes a line-oriented command/JSON protocol over stdin/stdout.
 */

#define MAX_RFCOMM_CHANNEL 30
#define CONNECT_TIMEOUT_MS 350
#define PROBE_TIMEOUT_MS 550
#define RX_CAPACITY 4096

#define CMD_BATTERY 0x0106
#define CMD_BATTERY_RESP 0x8106
#define CMD_QUERY_ANC 0x010c
#define CMD_ANC_RESP 0x810c
#define CMD_QUERY_EQ 0x010f
#define CMD_EQ_RESP 0x810f
#define CMD_BATCH_QUERY 0x010d
#define CMD_BATCH_RESP 0x810d
#define CMD_QUERY_SPATIAL 0x012a
#define CMD_SPATIAL_RESP 0x812a
#define CMD_QUERY_GAME_SOUND 0x012b
#define CMD_GAME_SOUND_RESP 0x812b
#define CMD_ACTIVE_REPORT 0x0204
#define CMD_REGISTER_NOTIFY 0x0205
#define CMD_SET_FEATURE 0x0403
#define CMD_SET_ANC 0x0404
#define CMD_SET_EQ 0x0406
#define CMD_SET_SPATIAL 0x0422
#define CMD_SET_GAME_SOUND 0x0423
#define CMD_EQ_NOTIFY 0x0504

#define FEATURE_WEAR_DETECTION 0x04
#define FEATURE_DUAL_DEVICE 0x11
#define FEATURE_HI_RES 0x18
#define FEATURE_SPATIAL 0x1b
#define FEATURE_GAME_SOUND 0x27
#define FEATURE_GAME_MAIN 0x28

struct buds_state {
    int battery_left;
    int battery_right;
    int battery_case;
    int charging_left;
    int charging_right;
    int charging_case;
    char anc[20];
    int eq;
    int spatial;
    int spatial_v2;
    int game_mode;
    int game_sound;
    int dual_device;
    int wear_detection;
    int hi_res;
};

static volatile sig_atomic_t keep_running = 1;
static int socket_fd = -1;
static int rfcomm_channel = -1;
static char device_address[18];
static uint8_t rx_buffer[RX_CAPACITY];
static size_t rx_length = 0;
static struct buds_state state;
static bool debug_enabled = false;

#define DEBUG_LOG(...) do { \
    if (debug_enabled) { \
        fprintf(stderr, __VA_ARGS__); \
        fputc('\n', stderr); \
        fflush(stderr); \
    } \
} while (0)

static void on_signal(int sig)
{
    (void)sig;
    keep_running = 0;
}

static int64_t monotonic_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void reset_state(void)
{
    state.battery_left = -1;
    state.battery_right = -1;
    state.battery_case = -1;
    state.charging_left = -1;
    state.charging_right = -1;
    state.charging_case = -1;
    strcpy(state.anc, "unknown");
    state.eq = -1;
    state.spatial = -1;
    state.spatial_v2 = -1;
    state.game_mode = -1;
    state.game_sound = -1;
    state.dual_device = -1;
    state.wear_detection = -1;
    state.hi_res = -1;
}

#define MAX_CLIENTS 8

struct client_slot {
    int fd;
    char rx_buf[512];
    size_t rx_len;
};

static char socket_path[108] = "";
static struct client_slot clients[MAX_CLIENTS];
static size_t num_clients = 0;
static bool stdin_active = true;

static void send_to_fd(int fd, const char *data, size_t len)
{
    if (fd < 0 || len == 0)
        return;
    send(fd, data, len, MSG_NOSIGNAL);
}

static size_t format_state_json(char *buf, size_t capacity, bool connected)
{
    char left_str[16], right_str[16], case_str[16];
    char ch_left[16], ch_right[16], ch_case[16];
    char eq_str[16], sp_str[16], gm_str[16], gs_str[16], dd_str[16], wd_str[16], hr_str[16];

    if (state.battery_left < 0) strcpy(left_str, "null"); else snprintf(left_str, sizeof(left_str), "%d", state.battery_left);
    if (state.battery_right < 0) strcpy(right_str, "null"); else snprintf(right_str, sizeof(right_str), "%d", state.battery_right);
    if (state.battery_case < 0) strcpy(case_str, "null"); else snprintf(case_str, sizeof(case_str), "%d", state.battery_case);

    if (state.charging_left < 0) strcpy(ch_left, "null"); else strcpy(ch_left, state.charging_left ? "true" : "false");
    if (state.charging_right < 0) strcpy(ch_right, "null"); else strcpy(ch_right, state.charging_right ? "true" : "false");
    if (state.charging_case < 0) strcpy(ch_case, "null"); else strcpy(ch_case, state.charging_case ? "true" : "false");

    if (state.eq < 0) strcpy(eq_str, "null"); else snprintf(eq_str, sizeof(eq_str), "%d", state.eq);
    if (state.spatial < 0) strcpy(sp_str, "null"); else strcpy(sp_str, state.spatial ? "true" : "false");
    if (state.game_mode < 0) strcpy(gm_str, "null"); else strcpy(gm_str, state.game_mode ? "true" : "false");
    if (state.game_sound < 0) strcpy(gs_str, "null"); else strcpy(gs_str, state.game_sound ? "true" : "false");
    if (state.dual_device < 0) strcpy(dd_str, "null"); else strcpy(dd_str, state.dual_device ? "true" : "false");
    if (state.wear_detection < 0) strcpy(wd_str, "null"); else strcpy(wd_str, state.wear_detection ? "true" : "false");
    if (state.hi_res < 0) strcpy(hr_str, "null"); else strcpy(hr_str, state.hi_res ? "true" : "false");

    int n = snprintf(buf, capacity,
        "{\"type\":\"state\",\"connected\":%s,\"address\":\"%s\",\"channel\":%d,"
        "\"batteryLeft\":%s,\"batteryRight\":%s,\"batteryCase\":%s,"
        "\"chargingLeft\":%s,\"chargingRight\":%s,\"chargingCase\":%s,"
        "\"anc\":\"%s\",\"eq\":%s,\"spatial\":%s,\"gameMode\":%s,"
        "\"gameSound\":%s,\"dualDevice\":%s,\"wearDetection\":%s,\"hiRes\":%s}\n",
        connected ? "true" : "false", device_address, rfcomm_channel,
        left_str, right_str, case_str,
        ch_left, ch_right, ch_case,
        state.anc, eq_str, sp_str, gm_str,
        gs_str, dd_str, wd_str, hr_str);

    if (n < 0 || (size_t)n >= capacity)
        return 0;
    return (size_t)n;
}

static void emit_state(bool connected)
{
    char buf[1024];
    size_t len = format_state_json(buf, sizeof(buf), connected);
    if (len == 0)
        return;

    if (stdin_active) {
        fwrite(buf, 1, len, stdout);
        fflush(stdout);
    }

    for (size_t i = 0; i < num_clients; ++i) {
        if (clients[i].fd >= 0)
            send_to_fd(clients[i].fd, buf, len);
    }
}

static void emit_error(const char *message)
{
    char buf[512];
    int n = snprintf(buf, sizeof(buf), "{\"type\":\"error\",\"message\":\"%s\"}\n", message);
    if (n <= 0)
        return;

    if (stdin_active) {
        fwrite(buf, 1, (size_t)n, stdout);
        fflush(stdout);
    }

    for (size_t i = 0; i < num_clients; ++i) {
        if (clients[i].fd >= 0)
            send_to_fd(clients[i].fd, buf, (size_t)n);
    }
}

static size_t build_frame(uint16_t command, const uint8_t *payload,
                          size_t payload_length, uint8_t *frame,
                          size_t frame_capacity)
{
    size_t total_length = 7 + payload_length;
    size_t frame_length = total_length + 2;
    if (payload_length > 255 || frame_length > frame_capacity)
        return 0;

    frame[0] = 0xaa;
    frame[1] = (uint8_t)total_length;
    frame[2] = 0x00;
    frame[3] = 0x00;
    frame[4] = (uint8_t)(command & 0xff);
    frame[5] = (uint8_t)(command >> 8);
    frame[6] = 0xf0;
    frame[7] = (uint8_t)payload_length;
    frame[8] = 0x00;
    if (payload_length > 0)
        memcpy(frame + 9, payload, payload_length);
    return frame_length;
}

static bool write_all(int fd, const uint8_t *data, size_t length)
{
    size_t offset = 0;
    while (offset < length) {
        ssize_t written = send(fd, data + offset, length - offset, MSG_NOSIGNAL);
        if (written > 0) {
            offset += (size_t)written;
            continue;
        }
        if (written < 0 && errno == EINTR)
            continue;
        if (written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            struct pollfd item = { .fd = fd, .events = POLLOUT };
            if (poll(&item, 1, 500) > 0)
                continue;
        }
        return false;
    }
    return true;
}

static bool send_command(uint16_t command, const uint8_t *payload,
                         size_t payload_length)
{
    uint8_t frame[300];
    size_t frame_length = build_frame(command, payload, payload_length,
                                      frame, sizeof(frame));
    if (socket_fd < 0 || frame_length == 0)
        return false;
    return write_all(socket_fd, frame, frame_length);
}

static int connect_with_timeout(int fd, const struct sockaddr *address,
                                socklen_t address_length, int timeout_ms)
{
    int old_flags = fcntl(fd, F_GETFL, 0);
    if (old_flags < 0 || fcntl(fd, F_SETFL, old_flags | O_NONBLOCK) < 0)
        return -1;

    int result = connect(fd, address, address_length);
    if (result < 0 && errno == EINPROGRESS) {
        struct pollfd item = { .fd = fd, .events = POLLOUT };
        result = poll(&item, 1, timeout_ms);
        if (result > 0) {
            int socket_error = 0;
            socklen_t error_length = sizeof(socket_error);
            if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &socket_error,
                           &error_length) < 0 || socket_error != 0) {
                errno = socket_error;
                result = -1;
            } else {
                result = 0;
            }
        } else {
            if (result == 0)
                errno = ETIMEDOUT;
            result = -1;
        }
    }

    fcntl(fd, F_SETFL, old_flags);
    return result;
}

static bool probe_channel(int fd)
{
    uint8_t frame[16];
    size_t frame_length = build_frame(CMD_BATTERY, NULL, 0, frame,
                                      sizeof(frame));
    if (!write_all(fd, frame, frame_length)) {
        DEBUG_LOG("probe write failed: %s", strerror(errno));
        return false;
    }

    struct pollfd item = { .fd = fd, .events = POLLIN };
    if (poll(&item, 1, PROBE_TIMEOUT_MS) <= 0) {
        DEBUG_LOG("probe timed out");
        return false;
    }

    uint8_t response[128];
    ssize_t count = recv(fd, response, sizeof(response), 0);
    if (debug_enabled && count > 0) {
        fprintf(stderr, "probe bytes:");
        for (ssize_t i = 0; i < count; ++i)
            fprintf(stderr, " %02x", response[i]);
        fputc('\n', stderr);
        fflush(stderr);
    }
    if (count < 9) {
        DEBUG_LOG("probe short read: %zd bytes", count);
        return false;
    }

    for (ssize_t i = 0; i + 8 < count; ++i) {
        if (response[i] != 0xaa)
            continue;
        size_t frame_length = (size_t)response[i + 1] + 2;
        if (frame_length >= 9 && i + (ssize_t)frame_length <= count) {
            uint16_t command = (uint16_t)response[i + 4]
                             | ((uint16_t)response[i + 5] << 8);
            DEBUG_LOG("probe received valid SPP frame cmd=0x%04x", command);
            return true;
        }
    }
    DEBUG_LOG("probe got %zd bytes but no battery response", count);
    return false;
}

static int connect_buds(const char *address)
{
    bdaddr_t bluetooth_address;
    if (str2ba(address, &bluetooth_address) != 0)
        return -1;

    for (int channel = 1; channel <= MAX_RFCOMM_CHANNEL; ++channel) {
        int fd = socket(AF_BLUETOOTH, SOCK_STREAM, BTPROTO_RFCOMM);
        if (fd < 0)
            continue;

        struct sockaddr_rc target = { 0 };
        target.rc_family = AF_BLUETOOTH;
        target.rc_bdaddr = bluetooth_address;
        target.rc_channel = (uint8_t)channel;

        if (connect_with_timeout(fd, (struct sockaddr *)&target,
                                 sizeof(target), CONNECT_TIMEOUT_MS) != 0) {
            DEBUG_LOG("channel %d connect failed: errno=%d (%s)",
                      channel, errno, strerror(errno));
            close(fd);
            continue;
        }

        DEBUG_LOG("channel %d connected", channel);
        if (probe_channel(fd)) {
            int flags = fcntl(fd, F_GETFL, 0);
            if (flags >= 0)
                fcntl(fd, F_SETFL, flags | O_NONBLOCK);
            rfcomm_channel = channel;
            return fd;
        }
        DEBUG_LOG("channel %d rejected by protocol probe", channel);
        close(fd);
    }
    return -1;
}

static const char *anc_from_bitmap(const uint8_t *data, size_t length)
{
    if (length < 2 || data[0] != 0x01)
        return NULL;
    uint32_t bitmap = 0;
    for (size_t i = 1; i < length && i <= 4; ++i)
        bitmap |= (uint32_t)data[i] << ((i - 1) * 8);

    if (bitmap & (1u << 7)) return "smart";
    if (bitmap & (1u << 4)) return "deep";
    if (bitmap & (1u << 5)) return "medium";
    if (bitmap & (1u << 6)) return "light";
    if (bitmap & (1u << 8)) return "transparency";
    if (bitmap & (1u << 3)) return "off";
    return NULL;
}

static void parse_battery(const uint8_t *payload, size_t length)
{
    if (length >= 8 && payload[0] == 0x00 && payload[1] == 0x04) {
        state.battery_left = payload[2];
        state.charging_left = payload[3] != 0;
        state.battery_right = payload[4];
        state.charging_right = payload[5] != 0;
        state.battery_case = payload[6];
        state.charging_case = payload[7] != 0;
        return;
    }

    size_t offset = 0;
    while (offset + 1 < length) {
        int component = payload[offset];
        int raw = payload[offset + 1];
        int level = raw & 0x7f;
        int charging = (raw & 0x80) != 0;
        if (component == 1) {
            state.battery_left = level;
            state.charging_left = charging;
        } else if (component == 2) {
            state.battery_right = level;
            state.charging_right = charging;
        } else if (component == 3) {
            state.battery_case = level;
            state.charging_case = charging;
        }
        offset += 2;
    }
}

static void parse_battery_notification(const uint8_t *payload, size_t length)
{
    if (length >= 8 && payload[0] == 0x00 && payload[1] == 0x04) {
        parse_battery(payload, length);
        return;
    }
    if (length < 3)
        return;

    int count = payload[0];
    size_t available = (length - 1) / 2;
    if (count > (int)available)
        count = (int)available;
    for (int i = 0; i < count; ++i) {
        const uint8_t pair[] = {
            payload[1 + (size_t)i * 2],
            payload[2 + (size_t)i * 2]
        };
        parse_battery(pair, sizeof(pair));
    }
}

static void parse_anc(const uint8_t *payload, size_t length)
{
    for (size_t i = 0; i + 2 < length; ++i) {
        if (payload[i] != 0x01)
            continue;
        const char *mode = anc_from_bitmap(payload + i,
                                           length - i);
        if (mode != NULL) {
            strncpy(state.anc, mode, sizeof(state.anc) - 1);
            state.anc[sizeof(state.anc) - 1] = '\0';
            return;
        }
    }
}

static void parse_batch(const uint8_t *payload, size_t length)
{
    for (size_t i = 0; i + 1 < length; i += 2) {
        int feature = payload[i];
        int enabled = payload[i + 1] != 0;
        if (feature == FEATURE_DUAL_DEVICE)
            state.dual_device = enabled;
        else if (feature == FEATURE_GAME_MAIN)
            state.game_mode = enabled;
        else if (feature == FEATURE_GAME_SOUND)
            state.game_sound = enabled;
        else if (feature == FEATURE_SPATIAL)
            state.spatial = enabled;
        else if (feature == FEATURE_WEAR_DETECTION)
            state.wear_detection = enabled;
        else if (feature == FEATURE_HI_RES)
            state.hi_res = enabled;
    }
}

static void parse_frame(uint16_t command, const uint8_t *payload,
                        size_t payload_length)
{
    if (debug_enabled) {
        fprintf(stderr, "rx cmd=0x%04x payload:", command);
        for (size_t i = 0; i < payload_length; ++i)
            fprintf(stderr, " %02x", payload[i]);
        fputc('\n', stderr);
        fflush(stderr);
    }
    bool changed = false;
    if (command == CMD_BATTERY_RESP) {
        parse_battery(payload, payload_length);
        changed = true;
    } else if (command == CMD_ANC_RESP) {
        parse_anc(payload, payload_length);
        changed = true;
    } else if (command == CMD_EQ_RESP || command == CMD_EQ_NOTIFY) {
        if (payload_length >= 2) {
            state.eq = payload[1];
            changed = true;
        }
    } else if (command == CMD_BATCH_RESP) {
        parse_batch(payload, payload_length);
        changed = true;
    } else if (command == CMD_SPATIAL_RESP) {
        if (payload_length >= 2 && payload[0] == 0x00) {
            state.spatial = payload[1] != 0;
            state.spatial_v2 = 1;
            changed = true;
        }
    } else if (command == CMD_GAME_SOUND_RESP) {
        if (payload_length >= 2 && payload[0] == 0x00) {
            state.game_sound = payload[1] != 0;
            changed = true;
        }
    } else if (command == CMD_ACTIVE_REPORT && payload_length >= 1) {
        int subtype = payload[0];
        if (subtype == 0x01) {
            parse_battery_notification(payload + 1, payload_length - 1);
            changed = true;
        } else if (subtype == 0x03 && payload_length >= 3) {
            parse_anc(payload + 2, payload_length - 2);
            changed = true;
        } else if (subtype == 0x05 && payload_length >= 2) {
            state.game_mode = payload[1] != 0;
            changed = true;
        }
    }

    if (changed)
        emit_state(true);
}

static void consume_rx_buffer(void)
{
    while (rx_length >= 2) {
        size_t start = 0;
        while (start < rx_length && rx_buffer[start] != 0xaa)
            ++start;
        if (start > 0) {
            memmove(rx_buffer, rx_buffer + start, rx_length - start);
            rx_length -= start;
        }
        if (rx_length < 2)
            return;

        size_t frame_length = (size_t)rx_buffer[1] + 2;
        if (frame_length < 9 || frame_length > 512) {
            memmove(rx_buffer, rx_buffer + 1, --rx_length);
            continue;
        }
        if (rx_length < frame_length)
            return;

        uint16_t command = (uint16_t)rx_buffer[4]
                         | ((uint16_t)rx_buffer[5] << 8);
        size_t declared_length = (size_t)rx_buffer[7]
                               | ((size_t)rx_buffer[8] << 8);
        size_t available = frame_length - 9;
        size_t payload_length = declared_length < available
                              ? declared_length : available;
        parse_frame(command, rx_buffer + 9, payload_length);

        memmove(rx_buffer, rx_buffer + frame_length,
                rx_length - frame_length);
        rx_length -= frame_length;
    }
}

static bool receive_socket_data(void)
{
    uint8_t chunk[512];
    ssize_t count = recv(socket_fd, chunk, sizeof(chunk), 0);
    if (count == 0)
        return false;
    if (count < 0) {
        if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)
            return true;
        return false;
    }

    size_t incoming = (size_t)count;
    if (incoming > RX_CAPACITY - rx_length) {
        rx_length = 0;
        if (incoming > RX_CAPACITY)
            return true;
    }
    memcpy(rx_buffer + rx_length, chunk, incoming);
    rx_length += incoming;
    consume_rx_buffer();
    return true;
}

static void short_pause(void)
{
    struct timespec duration = { .tv_sec = 0, .tv_nsec = 60000000 };
    nanosleep(&duration, NULL);
}

static void send_fast_queries(void)
{
    static const uint8_t query_anc[] = { 0x01, 0x01 };
    send_command(CMD_BATTERY, NULL, 0);
    short_pause();
    send_command(CMD_QUERY_ANC, query_anc, sizeof(query_anc));
}

static void send_slow_queries(void)
{
    static const uint8_t batch[] = {
        0x08, 0x04, 0x05, 0x11, 0x18, 0x06, 0x1b, 0x27, 0x28
    };
    static const uint8_t notify[] = { 0x01, 0x01, 0x02, 0x02 };
    static const uint8_t notify_wear[] = { 0x02, 0x02 };

    send_command(CMD_QUERY_EQ, NULL, 0);
    short_pause();
    send_command(CMD_BATCH_QUERY, batch, sizeof(batch));
    short_pause();
    send_command(CMD_QUERY_GAME_SOUND, NULL, 0);
    short_pause();
    send_command(CMD_QUERY_SPATIAL, NULL, 0);
    short_pause();
    send_command(CMD_REGISTER_NOTIFY, notify, sizeof(notify));
    short_pause();
    send_command(CMD_REGISTER_NOTIFY, notify_wear, sizeof(notify_wear));
}

static bool send_feature(uint8_t feature, bool enabled)
{
    uint8_t payload[] = { feature, enabled ? 0x01 : 0x00 };
    return send_command(CMD_SET_FEATURE, payload, sizeof(payload));
}

static void set_spatial(bool enabled)
{
    if (state.spatial_v2 == 1) {
        uint8_t payload[] = { enabled ? 0x01 : 0x00 };
        send_command(CMD_SET_SPATIAL, payload, sizeof(payload));
    } else {
        send_feature(FEATURE_SPATIAL, enabled);
    }
    state.spatial = enabled;
}

static void set_game_sound(bool enabled)
{
    uint8_t payload[] = { enabled ? 0x01 : 0x00, 0x01 };
    send_command(CMD_SET_GAME_SOUND, payload, sizeof(payload));
    state.game_sound = enabled;
}

static void handle_command(char *line)
{
    char *newline = strpbrk(line, "\r\n");
    if (newline != NULL)
        *newline = '\0';

    if (strcmp(line, "query") == 0) {
        send_fast_queries();
        send_slow_queries();
        return;
    }
    if (strcmp(line, "status") == 0) {
        emit_state(true);
        return;
    }
    if (strcmp(line, "quit") == 0) {
        keep_running = 0;
        return;
    }

    if (strncmp(line, "anc ", 4) == 0) {
        const char *mode = line + 4;
        uint8_t payload[4] = { 0x01, 0x01, 0x00, 0x00 };
        size_t length = 3;
        if (strcmp(mode, "off") == 0) payload[2] = 0x08;
        else if (strcmp(mode, "deep") == 0) payload[2] = 0x10;
        else if (strcmp(mode, "medium") == 0) payload[2] = 0x20;
        else if (strcmp(mode, "light") == 0) payload[2] = 0x40;
        else if (strcmp(mode, "smart") == 0) payload[2] = 0x80;
        else if (strcmp(mode, "transparency") == 0) {
            payload[3] = 0x01;
            length = 4;
        } else {
            emit_error("Unknown ANC mode");
            return;
        }
        send_command(CMD_SET_ANC, payload, length);
        strncpy(state.anc, mode, sizeof(state.anc) - 1);
        state.anc[sizeof(state.anc) - 1] = '\0';
        emit_state(true);
        return;
    }

    if (strncmp(line, "eq ", 3) == 0) {
        char *end = NULL;
        long value = strtol(line + 3, &end, 10);
        if (end == line + 3 || *end != '\0' || value < 0 || value > 3) {
            emit_error("EQ must be 0..3");
            return;
        }
        if (value != 0 && state.game_sound == 1)
            set_game_sound(false);
        uint8_t payload[] = { (uint8_t)value };
        send_command(CMD_SET_EQ, payload, sizeof(payload));
        state.eq = (int)value;
        emit_state(true);
        return;
    }

    if (strncmp(line, "spatial ", 8) == 0) {
        bool enabled = strcmp(line + 8, "1") == 0;
        if (enabled && state.game_sound == 1)
            set_game_sound(false);
        set_spatial(enabled);
        emit_state(true);
        return;
    }

    if (strncmp(line, "game ", 5) == 0) {
        bool enabled = strcmp(line + 5, "1") == 0;
        send_feature(FEATURE_GAME_MAIN, enabled);
        state.game_mode = enabled;
        emit_state(true);
        return;
    }

    if (strncmp(line, "game_sound ", 11) == 0) {
        bool enabled = strcmp(line + 11, "1") == 0;
        if (enabled) {
            if (state.eq > 0) {
                uint8_t eq_default[] = { 0x00 };
                send_command(CMD_SET_EQ, eq_default, sizeof(eq_default));
                state.eq = 0;
            }
            if (state.spatial == 1)
                set_spatial(false);
        }
        set_game_sound(enabled);
        emit_state(true);
        return;
    }

    if (strncmp(line, "dual ", 5) == 0) {
        bool enabled = strcmp(line + 5, "1") == 0;
        send_feature(FEATURE_DUAL_DEVICE, enabled);
        state.dual_device = enabled;
        emit_state(true);
        return;
    }

    if (strncmp(line, "wear ", 5) == 0) {
        bool enabled = strcmp(line + 5, "1") == 0;
        send_feature(FEATURE_WEAR_DETECTION, enabled);
        state.wear_detection = enabled;
        emit_state(true);
        return;
    }

    if (strncmp(line, "hires ", 6) == 0) {
        bool enabled = strcmp(line + 6, "1") == 0;
        send_feature(FEATURE_HI_RES, enabled);
        state.hi_res = enabled;
        emit_state(true);
        return;
    }

    if (*line != '\0')
        emit_error("Unknown command");
}

static void init_socket_path(const char *address)
{
    const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
    if (!runtime_dir || runtime_dir[0] == '\0')
        runtime_dir = "/tmp";

    char clean_addr[32];
    size_t j = 0;
    for (size_t i = 0; address[i] && j < sizeof(clean_addr) - 1; ++i) {
        if (address[i] == ':')
            clean_addr[j++] = '-';
        else
            clean_addr[j++] = (char)tolower((unsigned char)address[i]);
    }
    clean_addr[j] = '\0';

    snprintf(socket_path, sizeof(socket_path), "%s/oplus-buds3-%s.sock",
             runtime_dir, clean_addr);
}

static int try_connect_client(void)
{
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0)
        return -1;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", socket_path);

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) == 0) {
        DEBUG_LOG("Connected to running bridge daemon at %s", socket_path);
        return fd;
    }

    int err = errno;
    close(fd);

    if (err == ECONNREFUSED || err == ENOENT) {
        unlink(socket_path);
    }
    return -1;
}

static int run_client(int sock_fd)
{
    int flags = fcntl(sock_fd, F_GETFL, 0);
    if (flags >= 0)
        fcntl(sock_fd, F_SETFL, flags | O_NONBLOCK);

    char sock_buf[2048];
    char stdin_buf[512];

    while (keep_running) {
        struct pollfd items[2] = {
            { .fd = sock_fd, .events = POLLIN | POLLHUP | POLLERR },
            { .fd = STDIN_FILENO, .events = POLLIN | POLLHUP }
        };

        int ret = poll(items, 2, 500);
        if (ret < 0 && errno != EINTR)
            break;

        if (items[0].revents & POLLIN) {
            ssize_t n = read(sock_fd, sock_buf, sizeof(sock_buf));
            if (n <= 0) {
                DEBUG_LOG("Daemon connection closed");
                break;
            }
            fwrite(sock_buf, 1, (size_t)n, stdout);
            fflush(stdout);
        }
        if (items[0].revents & (POLLHUP | POLLERR | POLLNVAL)) {
            DEBUG_LOG("Daemon socket error/hup");
            break;
        }

        if (items[1].revents & POLLIN) {
            ssize_t n = read(STDIN_FILENO, stdin_buf, sizeof(stdin_buf));
            if (n <= 0) {
                DEBUG_LOG("Client stdin closed");
                break;
            }
            send_to_fd(sock_fd, stdin_buf, (size_t)n);
        }
        if (items[1].revents & (POLLHUP | POLLERR | POLLNVAL)) {
            DEBUG_LOG("Client stdin hup");
            break;
        }
    }

    close(sock_fd);
    return 0;
}

static int create_server_socket(void)
{
    unlink(socket_path);

    int listen_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (listen_fd < 0) {
        DEBUG_LOG("socket(AF_UNIX) failed: %s", strerror(errno));
        return -1;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", socket_path);

    if (bind(listen_fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        DEBUG_LOG("bind(AF_UNIX) failed: %s", strerror(errno));
        close(listen_fd);
        return -1;
    }

    if (listen(listen_fd, 8) != 0) {
        DEBUG_LOG("listen(AF_UNIX) failed: %s", strerror(errno));
        close(listen_fd);
        unlink(socket_path);
        return -1;
    }

    int flags = fcntl(listen_fd, F_GETFL, 0);
    if (flags >= 0)
        fcntl(listen_fd, F_SETFL, flags | O_NONBLOCK);

    DEBUG_LOG("Server listening on %s", socket_path);
    return listen_fd;
}

static bool valid_address(const char *address)
{
    if (strlen(address) != 17)
        return false;
    for (int i = 0; i < 17; ++i) {
        if ((i + 1) % 3 == 0) {
            if (address[i] != ':') return false;
        } else if (!((address[i] >= '0' && address[i] <= '9')
                     || (address[i] >= 'a' && address[i] <= 'f')
                     || (address[i] >= 'A' && address[i] <= 'F'))) {
            return false;
        }
    }
    return true;
}

int main(int argc, char **argv)
{
    if (argc != 2 || !valid_address(argv[1])) {
        fputs("usage: oplus-buds3-bridge AA:BB:CC:DD:EE:FF\n", stderr);
        return 2;
    }

    strncpy(device_address, argv[1], sizeof(device_address) - 1);
    device_address[sizeof(device_address) - 1] = '\0';
    reset_state();
    debug_enabled = getenv("OPLUS_BUDS3_DEBUG") != NULL;
    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
    signal(SIGPIPE, SIG_IGN);

    init_socket_path(device_address);

    // 1. Try to connect to an existing running bridge daemon
    int client_sock = try_connect_client();
    if (client_sock >= 0) {
        return run_client(client_sock);
    }

    // 2. We are the master / server instance
    int listen_fd = create_server_socket();
    if (listen_fd < 0) {
        short_pause();
        client_sock = try_connect_client();
        if (client_sock >= 0)
            return run_client(client_sock);
    }

    socket_fd = connect_buds(device_address);
    if (socket_fd < 0) {
        emit_error("Unable to open the OnePlus Buds 3 control channel");
        if (listen_fd >= 0) {
            close(listen_fd);
            unlink(socket_path);
        }
        return 3;
    }

    emit_state(true);
    send_fast_queries();
    send_slow_queries();

    int64_t next_fast_query = monotonic_ms() + 5000;
    int64_t next_slow_query = monotonic_ms() + 15000;
    char input[256];

    while (keep_running) {
        if (!stdin_active && num_clients == 0) {
            DEBUG_LOG("No active stdin and no connected clients, exiting server");
            break;
        }

        int64_t now = monotonic_ms();
        int timeout = 500;
        int64_t next_query = next_fast_query < next_slow_query
                           ? next_fast_query : next_slow_query;
        if (next_query > now && next_query - now < timeout)
            timeout = (int)(next_query - now);
        if (next_query <= now)
            timeout = 0;

        struct pollfd pfds[2 + 1 + MAX_CLIENTS];
        int pfd_count = 0;

        int rfcomm_idx = pfd_count++;
        pfds[rfcomm_idx].fd = socket_fd;
        pfds[rfcomm_idx].events = POLLIN | POLLHUP | POLLERR;

        int stdin_idx = -1;
        if (stdin_active) {
            stdin_idx = pfd_count++;
            pfds[stdin_idx].fd = STDIN_FILENO;
            pfds[stdin_idx].events = POLLIN | POLLHUP;
        }

        int listen_idx = -1;
        if (listen_fd >= 0) {
            listen_idx = pfd_count++;
            pfds[listen_idx].fd = listen_fd;
            pfds[listen_idx].events = POLLIN;
        }

        int client_map[MAX_CLIENTS];
        for (size_t i = 0; i < num_clients; ++i) {
            client_map[i] = pfd_count++;
            pfds[client_map[i]].fd = clients[i].fd;
            pfds[client_map[i]].events = POLLIN | POLLHUP | POLLERR;
        }

        int ready = poll(pfds, pfd_count, timeout);
        if (ready < 0 && errno != EINTR)
            break;

        if (ready > 0) {
            if (pfds[rfcomm_idx].revents & (POLLHUP | POLLERR | POLLNVAL)) {
                DEBUG_LOG("RFCOMM disconnected (hup/err)");
                break;
            }
            if ((pfds[rfcomm_idx].revents & POLLIN) && !receive_socket_data()) {
                DEBUG_LOG("RFCOMM receive error");
                break;
            }

            if (stdin_idx >= 0) {
                if (pfds[stdin_idx].revents & POLLIN) {
                    if (fgets(input, sizeof(input), stdin) == NULL) {
                        DEBUG_LOG("Server stdin reached EOF");
                        stdin_active = false;
                    } else {
                        handle_command(input);
                    }
                } else if (pfds[stdin_idx].revents & (POLLHUP | POLLERR | POLLNVAL)) {
                    DEBUG_LOG("Server stdin HUP");
                    stdin_active = false;
                }
            }

            if (listen_idx >= 0 && (pfds[listen_idx].revents & POLLIN)) {
                int new_fd = accept(listen_fd, NULL, NULL);
                if (new_fd >= 0) {
                    if (num_clients < MAX_CLIENTS) {
                        int flags = fcntl(new_fd, F_GETFL, 0);
                        if (flags >= 0)
                            fcntl(new_fd, F_SETFL, flags | O_NONBLOCK);
                        clients[num_clients].fd = new_fd;
                        clients[num_clients].rx_len = 0;
                        num_clients++;
                        DEBUG_LOG("Accepted client %d (total %zu)", new_fd, num_clients);

                        char json[1024];
                        size_t len = format_state_json(json, sizeof(json), true);
                        if (len > 0)
                            send_to_fd(new_fd, json, len);

                        send_fast_queries();
                        send_slow_queries();
                    } else {
                        DEBUG_LOG("Max clients reached, rejecting %d", new_fd);
                        close(new_fd);
                    }
                }
            }

            for (size_t i = 0; i < num_clients; ) {
                int p_idx = client_map[i];
                bool drop = false;

                if (pfds[p_idx].revents & POLLIN) {
                    ssize_t n = read(clients[i].fd,
                                     clients[i].rx_buf + clients[i].rx_len,
                                     sizeof(clients[i].rx_buf) - 1 - clients[i].rx_len);
                    if (n <= 0) {
                        drop = true;
                    } else {
                        clients[i].rx_len += (size_t)n;
                        clients[i].rx_buf[clients[i].rx_len] = '\0';

                        char *nl;
                        while ((nl = memchr(clients[i].rx_buf, '\n', clients[i].rx_len)) != NULL) {
                            *nl = '\0';
                            handle_command(clients[i].rx_buf);
                            size_t line_len = (size_t)(nl - clients[i].rx_buf) + 1;
                            memmove(clients[i].rx_buf, nl + 1, clients[i].rx_len - line_len);
                            clients[i].rx_len -= line_len;
                            clients[i].rx_buf[clients[i].rx_len] = '\0';
                        }
                    }
                }
                if (pfds[p_idx].revents & (POLLHUP | POLLERR | POLLNVAL)) {
                    drop = true;
                }

                if (drop) {
                    DEBUG_LOG("Closing client %d", clients[i].fd);
                    close(clients[i].fd);
                    for (size_t j = i; j + 1 < num_clients; ++j)
                        clients[j] = clients[j + 1];
                    num_clients--;
                } else {
                    ++i;
                }
            }
        }

        now = monotonic_ms();
        if (now >= next_fast_query) {
            send_fast_queries();
            next_fast_query = now + 5000;
        }
        if (now >= next_slow_query) {
            send_slow_queries();
            next_slow_query = now + 15000;
        }
    }

    if (listen_fd >= 0) {
        close(listen_fd);
        unlink(socket_path);
    }
    for (size_t i = 0; i < num_clients; ++i) {
        if (clients[i].fd >= 0)
            close(clients[i].fd);
    }
    num_clients = 0;

    if (socket_fd >= 0)
        close(socket_fd);
    socket_fd = -1;
    emit_state(false);
    return 0;
}
