# Design

## Context

`firmware/atmega/` is empty. The structure rules are in
`docs/reference/layout-atmega.md`; pins, timers and UART sharing in
`docs/hardware/atmega328p-arduino.md`; shield wiring and the safe
initialization order in `docs/hardware/adafruit-motor-shield-v1.md`. AVR
constraints (no heap, floats, exceptions, RTTI or `std::`; 16-bit `int`;
flash strings) are in `AGENTS.md` and enforced by `tools/check-rules.py`.
The HAL and mock deliberately match `add-xiao-foundation` plus `adc_read` and
a GPIO write history.

## Goals / Non-Goals

**Goals:**
- A tree that passes `tools/verify.sh atmega --all-files` within budget.
- A motor safe state that is unit-tested for order, not just end state.
- A mock in its final split TX/RX form so `add-uart-link` needs no mock rework.

**Non-Goals:**
- Motor speed/direction control, kinematics, servo, real telemetry, the link
  protocol.
- An upload helper script; the user uploads with `pio run -t upload` (see
  "UART Sharing" in the hardware page).

## Decisions

### D1. Build files (planner decision: copy exactly)

`firmware/atmega/platformio.ini`:

```ini
; Project Obsidian — ATmega328P motor controller (Arduino)

; ─── Board build ───
[env:atmega328p]
platform = atmelavr@5.3.0
board = uno
framework = arduino
board_build.mcu = atmega328p
board_build.f_cpu = 16000000L
monitor_speed = 115200
lib_ldf_mode = off
lib_deps = SoftwareSerial   ; bundled with the Arduino AVR core, not third-party
build_unflags = -std=gnu++11
build_flags =
    -std=gnu++17
    -Wall
    -Wextra
    -Wpedantic
    -Os
    -fno-rtti
    -fno-exceptions
    -ffunction-sections
    -fdata-sections
    -Wl,--gc-sections
    -I../shared
build_src_flags = -Werror

; ─── Host unit tests ───
[env:test_atmega328p]
platform = native@1.2.1
test_framework = unity
test_build_src = yes
build_flags =
    -std=gnu++17
    -Wall
    -Wextra
    -Wpedantic
    -Werror
    -DUNIT_TEST
    -Iinclude
    -Itest
    -I../shared
build_src_filter =
    -<*>
    +<utils/utils.cpp>
    +<motor.cpp>
    +<telemetry.cpp>
    +<uart_if.cpp>
```

The platform versions must equal `tools/container/versions.env`.

`firmware/atmega/.cppcheck-suppressions` (one id per line, `#` comments
allowed): `unusedFunction`, `missingInclude`, `missingIncludeSystem`,
`unmatchedSuppression`.

### D2. HAL interface — `firmware/atmega/include/hal/hal.h`

```cpp
namespace obsidian {
namespace hal {
enum class PinDir : uint8_t { Input, Output };

uint32_t now_ms();                                   // millis()
void     delay_ms(uint32_t ms);                      // delay(); main.cpp only
void     gpio_init(uint8_t pin, PinDir dir);         // pinMode()
void     gpio_write(uint8_t pin, bool level);        // digitalWrite()
bool     gpio_read(uint8_t pin);                     // digitalRead()
uint16_t adc_read(uint8_t channel);                  // analogRead(A0 + channel), 0..1023
void     uart_init(uint32_t baud);                   // Serial.begin()
size_t   uart_write(const uint8_t* data, size_t len);  // Serial.write(); bytes written
size_t   uart_read(uint8_t* buf, size_t len, uint32_t timeout_ms);  // 0 = never block
void     log_init(uint32_t baud);                    // debug log port: SoftwareSerial(RX A3, TX D2)
void     log_write(const uint8_t* data, size_t len); // blocking, ~87 us per byte at 115200
}  // namespace hal
}  // namespace obsidian
```

Include `<stdint.h>` and `<stddef.h>` only. In `src/hal/hal.cpp`, guard the
Arduino code with `#ifndef UNIT_TEST` (the host build never compiles this
file, but cppcheck parses it). `uart_read` with a timeout polls
`Serial.available()` until `len` bytes or `millis() - start >= timeout_ms`
(compare with unsigned subtraction). `log_init` constructs a file-static
`SoftwareSerial log_port(CONFIG_LOG_RX_PIN, CONFIG_LOG_TX_PIN)`, calls
`begin(baud)` and then `stopListening()`, so the unused RX pin raises no
interrupts. The link UART (`Serial`) is never used for logs.

### D3. Mock controls — `firmware/atmega/test/test_mock_hal.h` (planner decision)

Implemented in `test/test_mock_hal.cpp`. Static storage: 20 pins, 8 ADC
channels, 128-byte RX, TX and log buffers, 64-entry write history.

```cpp
namespace obsidian { namespace hal { namespace mock {
struct GpioWrite { uint8_t pin; bool level; };
void            reset();                 // clock 0, pins input/low, ADC 0, buffers/history empty
void            set_now_ms(uint32_t ms);
void            advance_ms(uint32_t ms);
PinDir          gpio_dir(uint8_t pin);
void            gpio_inject(uint8_t pin, bool level);
size_t          gpio_history_len();
GpioWrite       gpio_history(size_t index);
void            adc_inject(uint8_t channel, uint16_t value);
uint32_t        uart_baud();
void            uart_inject_rx(const uint8_t* data, size_t len);
size_t          uart_tx_len();
const uint8_t*  uart_tx_data();
void            uart_tx_clear();
size_t          log_len();               // bytes passed to log_write since reset
const uint8_t*  log_data();
void            log_clear();
}}}
```

`test/test_main.cpp` calls `obsidian::hal::mock::reset()` in `setUp()`.

### D4. Utils — `firmware/atmega/include/utils/utils.h`

Same functions as the XIAO (`bit_set`, `bit_clear`, `bit_toggle`,
`bit_test`, `clamp_i32`, `format_hex`, `format_u32`) plus:

```cpp
void log_println_P(const char* pgm_str);   // reads with pgm_read_byte, writes via hal::log_write, then "\r\n"
void log_println(const char* ram_str);     // RAM string; avoid for literals
```

On the host, `PSTR(s)` is `(s)` and `pgm_read_byte(p)` is `(*(const uint8_t*)(p))`:
define both in `utils.h` under `#ifdef UNIT_TEST`, otherwise include
`<avr/pgmspace.h>`. Shifts use `(uint32_t)1 << bit`.

### D5. Config — `firmware/atmega/include/config.h`

`CONFIG_UART_BAUD 115200` (link), `CONFIG_LOG_BAUD 115200`,
`CONFIG_LOG_TX_PIN 2`, `CONFIG_LOG_RX_PIN 17` (A3, unused),
`CONFIG_LOOP_PERIOD_MS 10`, and pin macros with
these names and the values from the hardware pages:
`CONFIG_MOTOR_PWM_M1_PIN` … `CONFIG_MOTOR_PWM_M4_PIN`,
`CONFIG_SR_CLOCK_PIN`, `CONFIG_SR_LATCH_PIN`, `CONFIG_SR_DATA_PIN`,
`CONFIG_SR_OE_PIN`, `CONFIG_SERVO_GIMBAL_PIN`, `CONFIG_ADC_VOLTAGE_CHANNEL`,
`CONFIG_ADC_CURRENT_CHANNEL`.

### D6. Motor safe state — `include/motor.h`, `src/motor.cpp`

```cpp
void motor_init();   // safe state, exact order below
void motor_stop();   // PWM pins low, shift out 0x00, latch
```

`motor_init()` order: (1) `gpio_init(OE, Output)`, `gpio_write(OE, true)`;
(2) each PWM pin `gpio_init(Output)` + `gpio_write(false)`; (3) clock, latch,
data pins to output and low, then shift out `0x00` MSB first (for each bit:
data, clock high, clock low), then latch high, latch low; (4)
`gpio_write(OE, false)`. A file-static shadow byte holds the latched value.

### D7. Stubs and boot

`include/telemetry.h`, `include/uart_if.h`: `bool telemetry_init();`,
`void telemetry_poll();`, `bool uart_if_init();`, `void uart_if_poll();`.

`src/main.cpp`: `setup()` calls `motor_init()` first, then
`hal::log_init(CONFIG_LOG_BAUD)` and `hal::uart_init(CONFIG_UART_BAUD)`, logs
`ATmega firmware starting`, inits
`telemetry` and `uart_if` logging `telemetry: OK|FAIL` and `uart_if: OK|FAIL`
(all via `log_println_P(PSTR(...))`), then logs
`ATmega firmware initialized — all subsystems ready`. `loop()` calls
`telemetry_poll(); uart_if_poll();` and returns.

### D8. Tests (Unity, env `test_atmega328p`)

| File | Tests |
| --- | --- |
| `test/test_hal.cpp` | `test_hal_delay_advances_clock`, `test_hal_gpio_write_read`, `test_hal_gpio_history_order`, `test_hal_adc_inject`, `test_hal_adc_default_zero`, `test_hal_uart_rx_inject_read`, `test_hal_uart_tx_captured`, `test_hal_uart_read_empty_returns_zero`, `test_hal_log_separate_from_uart` |
| `test/test_utils.cpp` | `test_utils_bit_set`, `test_utils_bit_clear`, `test_utils_bit_toggle`, `test_utils_bit_test`, `test_utils_bit_high_bits` (bit 31), `test_utils_clamp_i32`, `test_utils_format_hex`, `test_utils_format_u32`, `test_utils_log_println_p` |
| `test/test_motor.cpp` | `test_motor_init_oe_high_first`, `test_motor_init_oe_low_last`, `test_motor_init_pwm_low`, `test_motor_init_latches_zero`, `test_motor_stop_pwm_low_and_latch` |
| `test/test_stubs.cpp` | `test_stubs_telemetry_init`, `test_stubs_uart_if_init` |

Group 1 is scaffolding: verify it with `tools/build.sh atmega`. From group 2
on, every group leaves `tools/verify.sh atmega` passing.

## Risks / Trade-offs

- [`-Wpedantic` warnings from the Arduino core] → `-Werror` applies only to project sources (`build_src_flags`).
- [Debug logging blocks ~87 µs per byte and briefly disables interrupts] → keep log lines short and rate-limited; at 115200 at most one link byte arrives per logged byte, which the USART's receive buffer absorbs.
- [Flash budget] → `-Os`, gc-sections, flash strings; the build step enforces the budget.

## Open Questions

None.
