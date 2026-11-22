# Spec Delta

## Purpose

The ATmega hardware abstraction: the only code that touches the Arduino core
or AVR registers, plus a host mock so every other module builds and is tested
on the PC.

## ADDED Requirements

### Requirement: All hardware access goes through the HAL

ATmega modules other than `src/hal/hal.cpp` and `src/main.cpp` SHALL NOT call
the Arduino API or touch registers; they SHALL use `obsidian::hal`. The host
test build SHALL NOT link the Arduino core.

#### Scenario: Module compiles on the host

- **WHEN** the `test_atmega328p` environment builds a module listed in its `build_src_filter`
- **THEN** it compiles and links with `-DUNIT_TEST` against the mock HAL and no Arduino headers

### Requirement: Mock clock

The mock HAL SHALL keep a millisecond clock that tests can set and advance.
`delay_ms(n)` on the mock SHALL advance `now_ms()` by exactly `n`.

#### Scenario: Delay advances the clock

- **GIVEN** the mock clock is at 1000 ms
- **WHEN** `delay_ms(25)` is called
- **THEN** `now_ms()` returns 1025

### Requirement: Mock GPIO with write history

The mock HAL SHALL record each pin's direction and level, return the last
written or injected level from `gpio_read`, and keep an ordered history of
`gpio_write` calls so tests can check sequences.

#### Scenario: Write then read

- **WHEN** a pin is initialized as output and `gpio_write(pin, true)` is called
- **THEN** `gpio_read(pin)` returns true

#### Scenario: Write order is visible

- **WHEN** pin 7 is written high and then low
- **THEN** the history holds (7, high) before (7, low)

### Requirement: Mock ADC

The mock HAL SHALL return, from `adc_read(channel)`, the value a test injected
for that channel, and 0 for a channel with no injected value.

#### Scenario: Injected ADC value

- **WHEN** a test injects 512 on channel 0
- **THEN** `adc_read(0)` returns 512 and `adc_read(1)` returns 0

### Requirement: Debug log port

Log output SHALL go through `hal::log_write` to the debug log port (D2,
`CONFIG_LOG_BAUD`), never through the link UART. The mock HAL SHALL capture
log bytes separately from the UART TX capture.

#### Scenario: Logs stay off the link

- **WHEN** a module logs a line through `obsidian::utils`
- **THEN** the mock log capture holds the line and the UART TX capture is empty

#### Scenario: HIL: Debug port output

- **WHEN** a USB-serial adapter is wired to D2 and GND and opened at 115200 baud
- **THEN** the firmware's log lines appear and nothing but protocol frames leaves D1

### Requirement: Mock UART

The mock HAL SHALL keep separate TX-capture and RX-inject buffers. Bytes
injected into RX SHALL be returned by `uart_read` in order. `uart_read` with
`timeout_ms = 0` SHALL never block, on the mock or on hardware.

#### Scenario: Injected bytes are read back

- **WHEN** a test injects bytes `01 02 03` and calls `uart_read(buf, 8, 0)`
- **THEN** it returns 3 and `buf` starts with `01 02 03`

#### Scenario: Writes are captured

- **WHEN** a module calls `uart_write` with 4 bytes
- **THEN** the TX capture holds exactly those bytes and nothing is echoed into RX
