# Spec Delta

## Purpose

The XIAO firmware skeleton: a clean build, a boot sequence that brings up every
module, a main loop that never blocks, and the shared utility functions.

## ADDED Requirements

### Requirement: Clean build and checks

The `xiao_esp32s3` build SHALL produce `.pio/build/xiao_esp32s3/firmware.elf`
with `-Wall -Wextra -Werror` and no warnings, and `tools/verify.sh xiao` SHALL
print `VERIFY PASS`.

#### Scenario: Verify the board

- **WHEN** `tools/verify.sh xiao --all-files` runs on the finished tree
- **THEN** the format, rules, lint, build and test steps all print `PASS`

### Requirement: Console on USB-Serial-JTAG

Logs SHALL go to the USB-Serial-JTAG console, never to UART0, whose default
pins carry the ATmega link
(see "UART Link" in `docs/hardware/xiao-esp32s3-sense.md`).

#### Scenario: HIL: Boot log

- **WHEN** the board boots with USB connected
- **THEN** init status lines appear on the USB console, ending with `XIAO firmware initialized — all subsystems ready`

### Requirement: Boot sequence

`app_main` SHALL initialize, in order, the console log, `wifi_mgr` and
`uart_if`, log each result, then log
`XIAO firmware initialized — all subsystems ready` and enter the main loop.
`app_main` SHALL NOT return.

#### Scenario: HIL: Stubs initialize

- **WHEN** the firmware boots
- **THEN** `wifi_mgr` and `uart_if` report success and no panic or reset follows

### Requirement: Non-blocking main loop

Each main-loop pass SHALL call every module's poll function and then yield to
FreeRTOS for `CONFIG_LOOP_PERIOD_MS`, so the task watchdog never fires. Module
code SHALL NOT block.

#### Scenario: HIL: Long run

- **WHEN** the firmware runs for 60 s
- **THEN** no reset and no task-watchdog message appears

### Requirement: Module stubs

`wifi_mgr` and `uart_if` SHALL each expose a documented `<module>_init()` that
returns true and a `<module>_poll()` that does nothing yet, with a
`// TODO(<change>):` marker where later changes add behavior.

#### Scenario: Stub init succeeds

- **WHEN** a host test calls `wifi_mgr_init()` and `uart_if_init()`
- **THEN** both return true

### Requirement: Utility functions

`obsidian::utils` SHALL provide bit set/clear/toggle/test on `uint32_t`,
`int32_t` clamping, fixed-width hex formatting and unsigned decimal formatting,
each covered by a test that fails if the implementation is wrong.

#### Scenario: Hex formatting

- **WHEN** `format_hex(0x1A2B, buf)` is called
- **THEN** `buf` holds `0x00001A2B`

#### Scenario: Clamp

- **WHEN** `clamp_i32(5000, -1000, 1000)` is called
- **THEN** it returns 1000

#### Scenario: Deterministic tests

- **WHEN** the host tests run twice
- **THEN** both runs report the same results
