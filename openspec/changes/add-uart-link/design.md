# Design

## Context

Requires `add-xiao-foundation` and `add-atmega-foundation`: their HAL mocks
already have split TX-capture / RX-inject UART buffers and a settable clock
(`obsidian::hal::mock`), and both boards have `uart_if` stubs and
`CONFIG_UART_BAUD`. Pins: "UART Link" in `docs/hardware/xiao-esp32s3-sense.md`;
"UART Sharing" in `docs/hardware/atmega328p-arduino.md`.

## Goals / Non-Goals

**Goals:**
- One `protocol.h` both boards and C compile, unit-tested identically on both.
- The same transport API (`uart_if`) on both boards, so link logic is
  testable with injected frames.
- Every timing behavior testable with the mock clock.

**Non-Goals:**
- Driving motors from `DRIVE` (the kinematics change reads
  `cmd_handler_get_drive`), servo output, HUD, retransmission.

## Decisions

### D1. `firmware/shared/protocol.h` (C and C++, all functions `static inline`)

Guard `PROTOCOL_H`; wrap declarations in `extern "C"` under `__cplusplus`.
Includes only `<stdint.h>`, `<stddef.h>`, `<stdbool.h>`.

```c
#define PROTOCOL_START          0x7E
#define PROTOCOL_END            0x7E
#define PROTOCOL_MAX_PAYLOAD    16
#define PROTOCOL_FRAME_OVERHEAD 5      /* START LEN CMD CRC END */
#define PROTOCOL_MAX_FRAME      21
#define PROTOCOL_STAGE_SIZE     18     /* CMD + 16 payload + CRC */
#define PROTOCOL_VERSION        0x01
#define PROTOCOL_CRC_POLY       0x07
#define PROTOCOL_INTERBYTE_TIMEOUT_MS 10

#define PROTOCOL_CMD_HELLO      0x00   /* down, LEN 1 */
#define PROTOCOL_CMD_DRIVE      0x01   /* down, LEN 8 */
#define PROTOCOL_CMD_STOP       0x02   /* down, LEN 0 */
#define PROTOCOL_CMD_TELEMETRY  0x40   /* up,   LEN 5 */
#define PROTOCOL_CMD_HELLO_ACK  0x41   /* up,   LEN 2 */
#define PROTOCOL_CMD_ACK        0x80   /* up,   LEN 2 */
#define PROTOCOL_UPLINK_FIRST   0x40   /* cmd >= this is uplink */

#define PROTOCOL_LEN_HELLO 1
#define PROTOCOL_LEN_DRIVE 8
#define PROTOCOL_LEN_STOP 0
#define PROTOCOL_LEN_TELEMETRY 5
#define PROTOCOL_LEN_HELLO_ACK 2
#define PROTOCOL_LEN_ACK 2

#define PROTOCOL_STATUS_OK               0x00
#define PROTOCOL_STATUS_UNKNOWN_COMMAND  0x02
#define PROTOCOL_STATUS_RANGE_ERROR      0x03
#define PROTOCOL_STATUS_VERSION_MISMATCH 0x04

#define PROTOCOL_FLAG_MOTORS_ENABLED 0x01
#define PROTOCOL_FLAG_LINK_TIMEOUT   0x02
#define PROTOCOL_FLAG_OVERVOLTAGE    0x04
#define PROTOCOL_FLAG_UNDERVOLTAGE   0x08
#define PROTOCOL_FLAG_OVERCURRENT    0x10

#define PROTOCOL_DRIVE_MIN (-1000)
#define PROTOCOL_DRIVE_MAX 1000

typedef struct { int16_t thrust, strafe, yaw, gimbal; } protocol_drive_t;
typedef struct { uint16_t voltage_mv; int16_t current_ma; uint8_t flags; } protocol_telemetry_t;

typedef enum { PROTOCOL_STATE_WAIT_START, PROTOCOL_STATE_READ_LEN, PROTOCOL_STATE_READ_CMD,
               PROTOCOL_STATE_READ_PAYLOAD, PROTOCOL_STATE_READ_CRC, PROTOCOL_STATE_READ_END
} protocol_state_t;
typedef enum { PROTOCOL_PARSE_IGNORE,        /* byte outside a frame */
               PROTOCOL_PARSE_IN_PROGRESS,
               PROTOCOL_PARSE_FRAME_READY,   /* read with protocol_frame_*() */
               PROTOCOL_PARSE_ERROR          /* frame discarded */
} protocol_parse_result_t;
typedef struct { protocol_state_t state; uint8_t len; uint8_t index;
                 uint8_t stage[PROTOCOL_STAGE_SIZE]; } protocol_parser_t;

uint8_t  protocol_crc8(const uint8_t* data, size_t len);
size_t   protocol_build_frame(uint8_t cmd, const uint8_t* payload, uint8_t len,
                              uint8_t* out, size_t out_size);  /* wire size, or 0 if len > 16 or out too small */
void     protocol_parser_init(protocol_parser_t* p);
protocol_parse_result_t protocol_parse_byte(protocol_parser_t* p, uint8_t byte);
void     protocol_parser_timeout(protocol_parser_t* p);      /* back to WAIT_START */
bool     protocol_parser_busy(const protocol_parser_t* p);   /* state != WAIT_START */
uint8_t  protocol_frame_cmd(const protocol_parser_t* p);
uint8_t  protocol_frame_len(const protocol_parser_t* p);
const uint8_t* protocol_frame_payload(const protocol_parser_t* p);
void     protocol_put_u16(uint8_t* buf, uint16_t v);
uint16_t protocol_get_u16(const uint8_t* buf);
void     protocol_put_i16(uint8_t* buf, int16_t v);
int16_t  protocol_get_i16(const uint8_t* buf);
void     protocol_encode_drive(const protocol_drive_t* d, uint8_t* out8);
void     protocol_decode_drive(const uint8_t* in8, protocol_drive_t* d);
void     protocol_encode_telemetry(const protocol_telemetry_t* t, uint8_t* out5);
void     protocol_decode_telemetry(const uint8_t* in5, protocol_telemetry_t* t);
```

In `READ_LEN`, a value > 16 returns `PROTOCOL_PARSE_ERROR` and goes to
`WAIT_START`. In `READ_END`, the frame is ready only if the byte is 0x7E and
`protocol_crc8(stage, len + 1)` equals the received CRC; else ERROR. After
FRAME_READY or ERROR the state is `WAIT_START`. The stage keeps the last
frame until the next START.

Both boards' `platformio.ini` already pass `-I../shared`; the XIAO
`src/CMakeLists.txt` already lists `../../shared`.

### D2. Transport — `include/uart_if.h` on both boards (replaces the stub API)

```cpp
struct uart_frame_t { uint8_t cmd; uint8_t len; uint8_t payload[PROTOCOL_MAX_PAYLOAD]; };
bool     uart_if_init();                     // parser init; XIAO also calls hal::uart_init(CONFIG_UART_BAUD)
bool     uart_if_receive(uart_frame_t* out); // non-blocking; true when a frame is ready
bool     uart_if_send(uint8_t cmd, const uint8_t* payload, uint8_t len);  // false if build fails
uint16_t uart_if_error_count();              // frames discarded since init (saturates)
```

`uart_if_poll()` is removed (planner decision): callers loop on
`uart_if_receive`. `uart_if_receive` reads one byte at a time with
`hal::uart_read(&b, 1, 0)` until a frame is ready or no byte is waiting, so no
bytes after a frame are lost. It records the time of the last byte; when the
parser is busy and `hal::now_ms() - last_byte_ms >= PROTOCOL_INTERBYTE_TIMEOUT_MS`
it calls `protocol_parser_timeout()` and counts an error. On the ATmega,
`uart_if_init` does not call `hal::uart_init` (`setup()` already did).

### D3. XIAO `link_mgr` — `include/link_mgr.h`, `src/link_mgr.cpp`

```cpp
struct link_battery_t { uint16_t voltage_mv; int16_t current_ma; uint8_t flags; bool stale; };
bool link_mgr_init();                                   // uart_if_init(); link down; drive zero
void link_mgr_poll();
void link_mgr_set_drive(int16_t thrust, int16_t strafe, int16_t yaw, int16_t gimbal);  // clamps to ±1000
void link_mgr_send_stop();                              // send STOP now; drive zero
bool link_mgr_is_up();
bool link_mgr_get_battery(link_battery_t* out);         // false if no TELEMETRY ever received
```

`link_mgr_poll()` steps, with `now = hal::now_ms()`:
1. Drain `uart_if_receive`. For each frame with `cmd >= PROTOCOL_UPLINK_FIRST`:
   a `HELLO_ACK` with `VERSION_MISMATCH` sets `mismatch = true` and is not
   activity; a `HELLO_ACK` with `OK` clears `mismatch`. Any other uplink frame
   sets `last_rx_ms = now`; TELEMETRY (LEN 5) is decoded and stored.
2. `up = !mismatch && rx_seen && now - last_rx_ms < CONFIG_LINK_WATCHDOG_MS`.
   Log `link up` / `link down` / `link version mismatch` on change.
3. If down and (`!hello_sent || now - last_hello_ms >= CONFIG_LINK_HELLO_RETRY_MS`):
   send HELLO, `last_hello_ms = now`.
4. If `!tick_sent || now - last_tick_ms >= CONFIG_LINK_CONTROL_TICK_MS`: send
   DRIVE with the stored drive, `last_tick_ms = now`.

Battery `stale = !up`. Config additions in `firmware/xiao/include/config.h`:
`CONFIG_LINK_CONTROL_TICK_MS 10`, `CONFIG_LINK_HELLO_RETRY_MS 1000`,
`CONFIG_LINK_WATCHDOG_MS 500`. `main.cpp`: `link_mgr_init()` replaces
`uart_if_init()` in the boot log (`link_mgr: OK|FAIL`); the loop calls
`wifi_mgr_poll(); link_mgr_poll();`.

### D4. ATmega `cmd_handler` — `include/cmd_handler.h`, `src/cmd_handler.cpp`

```cpp
void    cmd_handler_init();                          // uart_if_init(); timed out; drive zero
void    cmd_handler_poll();                          // drain frames, dispatch, then timeout check
void    cmd_handler_get_drive(protocol_drive_t* out);
bool    cmd_handler_is_timed_out();
uint8_t cmd_handler_gimbal_angle(int16_t gimbal);    // 90 + (int32_t)gimbal * 90 / 1000
```

Dispatch: HELLO with LEN 1 → `HELLO_ACK {PROTOCOL_VERSION, OK | VERSION_MISMATCH}`.
DRIVE with LEN 8 → range check every field → store, `last_cmd_ms = now`,
`timed_out = false`, `ACK OK`; else `ACK RANGE_ERROR`. STOP with LEN 0 → zero
drive, `motor_stop()`, `last_cmd_ms = now`, `timed_out = false`, `ACK OK`. A
known downlink command with the wrong LEN → `ACK RANGE_ERROR` (planner
decision). Anything else → `ACK UNKNOWN_COMMAND`.
Timeout: if `!timed_out && now - last_cmd_ms >= CONFIG_MOTION_TIMEOUT_MS` →
zero drive, `motor_stop()`, `timed_out = true`.
Logging (debug log port via `log_println_P`, never the link UART): after
dispatching, `cmd` lines at most every `CONFIG_CMD_LOG_INTERVAL_MS`, and one
line per ACK. `test_cmd_handler_log_rate_limited` checks `mock::log_len()`
and that `mock::uart_tx_data()` holds only ACK frames.

### D5. ATmega telemetry — `include/telemetry.h`, `src/telemetry.cpp`

```cpp
bool     telemetry_init();                            // last_send_ms = now
void     telemetry_poll();                            // if now - last_send_ms >= period: sample, send
uint16_t telemetry_voltage_mv(uint16_t raw_avg);
int16_t  telemetry_current_ma(uint16_t raw_avg);
uint8_t  telemetry_flags(uint16_t voltage_mv, int16_t current_ma, bool motors_enabled, bool link_timeout);
```

Sampling: 8 iterations of `adc_read(CONFIG_ADC_VOLTAGE_CHANNEL)` then
`adc_read(CONFIG_ADC_CURRENT_CHANNEL)`, sums in `uint32_t`, `>> 3`.
Conversions exactly as the `battery-telemetry` spec, with `uint32_t` / `int32_t`
intermediates. `motors_enabled` comes from new `bool motor_outputs_enabled()`
in `motor` (true when OE was last written low); `link_timeout` from
`cmd_handler_is_timed_out()`. Config additions in
`firmware/atmega/include/config.h`: `CONFIG_MOTION_TIMEOUT_MS 100`,
`CONFIG_TELEMETRY_PERIOD_MS 100`, `CONFIG_CMD_LOG_INTERVAL_MS 100`,
`CONFIG_ADC_REF_MV 5000`,
`CONFIG_BATT_VDIV_RATIO_X1000 3000`, `CONFIG_BATT_CURRENT_OFFSET_RAW 512`,
`CONFIG_BATT_CURRENT_MV_PER_A 100`, `CONFIG_BATT_OVERVOLT_MV 13000`,
`CONFIG_BATT_UNDERVOLT_MV 10500`, `CONFIG_BATT_OVERCURRENT_MA 10000`
(divider and sensor values are placeholders until HIL calibration).
`main.cpp`: `setup()` inits `cmd_handler` (replacing `uart_if_init`) and
`telemetry`; `loop()` calls `cmd_handler_poll(); telemetry_poll();`.

### D6. Tests

Append each new module to the board's `build_src_filter` (never remove
entries). `test/test_protocol.cpp` is identical on both boards.

| Board | File | Tests |
| --- | --- | --- |
| both | `test/test_protocol.cpp` | `test_protocol_crc8_check_value`, `test_protocol_round_trip_len0`, `test_protocol_round_trip_len8`, `test_protocol_round_trip_len16`, `test_protocol_build_rejects_len17`, `test_protocol_build_rejects_short_buffer`, `test_protocol_bad_crc_rejected`, `test_protocol_bad_end_rejected`, `test_protocol_len_over_max_resyncs`, `test_protocol_timeout_discards_partial`, `test_protocol_resync_after_garbage`, `test_protocol_i16_little_endian`, `test_protocol_drive_layout`, `test_protocol_telemetry_layout`, `test_protocol_compiles_as_c` |
| both | `test/test_protocol_c.c` | C file: includes `protocol.h`, defines `int protocol_c_check(void)` returning `protocol_crc8((const uint8_t*)"123456789", 9)`; `test_protocol_compiles_as_c` asserts it returns 0xF4 |
| both | `test/test_uart_if.cpp` | `test_uart_if_receive_frame`, `test_uart_if_two_frames_one_read`, `test_uart_if_interbyte_timeout`, `test_uart_if_send_builds_frame` |
| xiao | `test/test_link_mgr.cpp` | `test_link_mgr_hello_on_first_poll`, `test_link_mgr_hello_retry_1hz`, `test_link_mgr_up_on_uplink_frame`, `test_link_mgr_down_after_watchdog`, `test_link_mgr_drive_tick_10ms`, `test_link_mgr_drive_clamping`, `test_link_mgr_send_stop`, `test_link_mgr_battery_stored`, `test_link_mgr_battery_stale_when_down`, `test_link_mgr_version_mismatch_keeps_down`, `test_link_mgr_poll_does_not_block` |
| atmega | `test/test_cmd_handler.cpp` | `test_cmd_handler_starts_timed_out`, `test_cmd_handler_drive_stored_and_acked`, `test_cmd_handler_drive_range_error_keeps_previous`, `test_cmd_handler_wrong_len_range_error`, `test_cmd_handler_unknown_command`, `test_cmd_handler_stop_zeroes`, `test_cmd_handler_hello_ack_ok`, `test_cmd_handler_hello_ack_mismatch`, `test_cmd_handler_no_timeout_at_99ms`, `test_cmd_handler_timeout_at_100ms`, `test_cmd_handler_gimbal_angle`, `test_cmd_handler_log_rate_limited` |
| atmega | `test/test_telemetry.cpp` | `test_telemetry_voltage_conversion`, `test_telemetry_current_conversion`, `test_telemetry_current_negative`, `test_telemetry_flags_undervoltage_timeout`, `test_telemetry_flags_overvoltage`, `test_telemetry_flags_overcurrent`, `test_telemetry_flags_boundaries`, `test_telemetry_averages_8_samples`, `test_telemetry_sends_at_10hz` |

Tests set the clock with `mock::set_now_ms` and build injected frames with
`protocol_build_frame`. The foundation `test_stubs_uart_if_init` test is
replaced by the `test_uart_if_*` tests; `test_stubs_telemetry_init` stays
valid.

## Risks / Trade-offs

- [ATmega debug logging blocks ~87 µs per byte] → command logs are
  rate-limited to one line per 100 ms; ACK logs are short. Logs never touch
  the link UART (debug port on D2, see `add-atmega-foundation`).
- [No retransmission] → harmless: DRIVE repeats at 100 Hz and TELEMETRY at
  10 Hz.
- [Conversion constants are placeholders] → calibrated during HIL; only
  `config.h` changes.

## Open Questions

None. (Resolved: ATmega logs use the debug log port on D2 from
`add-atmega-foundation`, so the link UART carries only frames.)
