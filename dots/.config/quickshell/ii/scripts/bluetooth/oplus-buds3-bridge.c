#define _POSIX_C_SOURCE 200809L

#include <bluetooth/bluetooth.h>
#include <bluetooth/rfcomm.h>
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
}

static void print_nullable_int(int value)
{
    if (value < 0)
        fputs("null", stdout);
    else
        printf("%d", value);
}

static void print_nullable_bool(int value)
{
    if (value < 0)
        fputs("null", stdout);
    else
        fputs(value ? "true" : "false", stdout);
}

static void emit_state(bool connected)
{
    printf("{\"type\":\"state\",\"connected\":%s,\"address\":\"%s\",\"channel\":%d,",
           connected ? "true" : "false", device_address, rfcomm_channel);
    fputs("\"batteryLeft\":", stdout);
    print_nullable_int(state.battery_left);
    fputs(",\"batteryRight\":", stdout);
    print_nullable_int(state.battery_right);
    fputs(",\"batteryCase\":", stdout);
    print_nullable_int(state.battery_case);
    fputs(",\"chargingLeft\":", stdout);
    print_nullable_bool(state.charging_left);
    fputs(",\"chargingRight\":", stdout);
    print_nullable_bool(state.charging_right);
    fputs(",\"chargingCase\":", stdout);
    print_nullable_bool(state.charging_case);
    printf(",\"anc\":\"%s\",\"eq\":", state.anc);
    print_nullable_int(state.eq);
    fputs(",\"spatial\":", stdout);
    print_nullable_bool(state.spatial);
    fputs(",\"gameMode\":", stdout);
    print_nullable_bool(state.game_mode);
    fputs(",\"gameSound\":", stdout);
    print_nullable_bool(state.game_sound);
    fputs(",\"dualDevice\":", stdout);
    print_nullable_bool(state.dual_device);
    fputs(",\"wearDetection\":", stdout);
    print_nullable_bool(state.wear_detection);
    fputs("}\n", stdout);
    fflush(stdout);
}

static void emit_error(const char *message)
{
    fputs("{\"type\":\"error\",\"message\":\"", stdout);
    for (const unsigned char *p = (const unsigned char *)message; *p; ++p) {
        if (*p == '\\' || *p == '"')
            fputc('\\', stdout);
        if (*p >= 0x20)
            fputc(*p, stdout);
    }
    fputs("\"}\n", stdout);
    fflush(stdout);
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
        0x07, 0x04, 0x05, 0x11, 0x06, 0x1b, 0x27, 0x28
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

    if (*line != '\0')
        emit_error("Unknown command");
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

    socket_fd = connect_buds(device_address);
    if (socket_fd < 0) {
        emit_error("Unable to open the OnePlus Buds 3 control channel");
        return 3;
    }

    emit_state(true);
    send_fast_queries();
    send_slow_queries();

    int64_t next_fast_query = monotonic_ms() + 5000;
    int64_t next_slow_query = monotonic_ms() + 15000;
    char input[256];

    while (keep_running) {
        int64_t now = monotonic_ms();
        int timeout = 500;
        int64_t next_query = next_fast_query < next_slow_query
                           ? next_fast_query : next_slow_query;
        if (next_query > now && next_query - now < timeout)
            timeout = (int)(next_query - now);
        if (next_query <= now)
            timeout = 0;

        struct pollfd items[2] = {
            { .fd = socket_fd, .events = POLLIN | POLLHUP | POLLERR },
            { .fd = STDIN_FILENO, .events = POLLIN | POLLHUP }
        };
        int ready = poll(items, 2, timeout);
        if (ready < 0 && errno != EINTR)
            break;
        if (ready > 0) {
            if (items[0].revents & (POLLHUP | POLLERR | POLLNVAL))
                break;
            if ((items[0].revents & POLLIN) && !receive_socket_data())
                break;
            if (items[1].revents & POLLIN) {
                if (fgets(input, sizeof(input), stdin) == NULL)
                    break;
                handle_command(input);
            } else if (items[1].revents & POLLHUP) {
                break;
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

    if (socket_fd >= 0)
        close(socket_fd);
    socket_fd = -1;
    emit_state(false);
    return 0;
}
