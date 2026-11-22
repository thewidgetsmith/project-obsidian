# Spec Delta

## Purpose

The ATmega firmware skeleton: a clean build inside the flash and SRAM budget,
a boot sequence that puts the motor outputs in a safe state before anything
else, a non-blocking main loop, and the shared utility functions.

## ADDED Requirements

### Requirement: Clean build within budget

The `atmega328p` build SHALL produce `.pio/build/atmega328p/firmware.hex`
with no warnings in project sources, flash use ≤ 28672 bytes and SRAM use
≤ 1536 bytes, and `tools/verify.sh atmega` SHALL print `VERIFY PASS`.

#### Scenario: Verify the board

- **WHEN** `tools/verify.sh atmega --all-files` runs on the finished tree
- **THEN** the format, rules, lint, build and test steps all print `PASS` and the build line shows use within the budget

### Requirement: Motor safe state first

`setup()` SHALL call `motor_init()` before any other initialization.
`motor_init()` SHALL follow the shield's safe initialization order: OE (active
low) high, all four PWM pins output and low, shift out and latch `0x00`, then
OE low. `motor_stop()` SHALL drive all four PWM pins low and latch `0x00`.

#### Scenario: Safe-state order

- **WHEN** a host test calls `motor_init()` on a freshly reset mock
- **THEN** the GPIO history shows OE written high before any PWM or shift-register write, OE written low last, all four PWM pins low, and the eight data bits shifted for the latched byte are all 0

#### Scenario: Stop

- **WHEN** `motor_stop()` is called after `motor_init()`
- **THEN** all four PWM pins read low and a latch pulse with all-zero data follows

#### Scenario: HIL: No twitch

- **WHEN** the board powers up, resets, or finishes an upload with motors connected
- **THEN** no motor moves or twitches

### Requirement: Boot sequence

After `motor_init()`, `setup()` SHALL initialize the debug log port at
`CONFIG_LOG_BAUD` and the link UART at `CONFIG_UART_BAUD`, then `telemetry`
and `uart_if`, log each result, and log
`ATmega firmware initialized — all subsystems ready`.

#### Scenario: HIL: Boot log

- **WHEN** the board boots with a USB-serial adapter on the debug log port
- **THEN** init status lines appear, ending with `ATmega firmware initialized — all subsystems ready`, and no reset loop follows

### Requirement: Non-blocking main loop

`loop()` SHALL call every module's poll function and return without blocking.

#### Scenario: HIL: Long run

- **WHEN** the firmware runs for 60 s
- **THEN** no reset occurs

### Requirement: Module stubs

`telemetry` and `uart_if` SHALL each expose a documented `<module>_init()`
that returns true and a `<module>_poll()` that does nothing yet, with a
`// TODO(add-uart-link):` marker.

#### Scenario: Stub init succeeds

- **WHEN** a host test calls `telemetry_init()` and `uart_if_init()`
- **THEN** both return true

### Requirement: Utility functions

`obsidian::utils` SHALL provide bit set/clear/toggle/test on `uint32_t`,
`int32_t` clamping, fixed-width hex formatting, unsigned decimal formatting,
and logging of flash-resident strings, each covered by a test that fails if
the implementation is wrong. No function SHALL use the heap, floating point
or `std::`.

#### Scenario: Hex formatting

- **WHEN** `format_hex(0x1A2B, buf)` is called
- **THEN** `buf` holds `0x00001A2B`

#### Scenario: Flash-string log

- **WHEN** `log_println_P(PSTR("hi"))` is called on the host
- **THEN** the mock log capture holds `hi\r\n` and the UART TX capture is empty
