# Spec Delta

## Purpose

The XIAO hardware abstraction: the only code that touches ESP-IDF drivers, plus
a host mock so every other module builds and is tested on the PC.

## ADDED Requirements

### Requirement: All hardware access goes through the HAL

XIAO modules other than `src/hal/hal.cpp` and `src/main.cpp` SHALL NOT call
ESP-IDF driver or FreeRTOS APIs; they SHALL use `obsidian::hal`. The host test
build SHALL NOT link ESP-IDF.

#### Scenario: Module compiles on the host

- **WHEN** the `test_xiao_esp32s3` environment builds a module listed in its `build_src_filter`
- **THEN** it compiles and links with `-DUNIT_TEST` against the mock HAL and no ESP-IDF headers

### Requirement: Mock clock

The mock HAL SHALL keep a millisecond clock that tests can set and advance.
`delay_ms(n)` on the mock SHALL advance `now_ms()` by exactly `n` and return
immediately.

#### Scenario: Delay advances the clock

- **GIVEN** the mock clock is at 1000 ms
- **WHEN** `delay_ms(25)` is called
- **THEN** `now_ms()` returns 1025

### Requirement: Mock GPIO

The mock HAL SHALL record each pin's direction and level. `gpio_read` SHALL
return the last written or injected level.

#### Scenario: Write then read

- **WHEN** a pin is initialized as output and `gpio_write(pin, true)` is called
- **THEN** `gpio_read(pin)` returns true and the mock reports the pin's direction as output

#### Scenario: Injected input

- **WHEN** a test injects level true on an input pin
- **THEN** `gpio_read(pin)` returns true

### Requirement: Mock link UART

The mock HAL SHALL keep separate TX-capture and RX-inject buffers. Bytes passed
to `uart_write` SHALL be readable by the test; bytes injected into RX SHALL be
returned by `uart_read` in order. `uart_read` with `timeout_ms = 0` SHALL
never block, on the mock or on hardware.

#### Scenario: Injected bytes are read back

- **WHEN** a test injects bytes `01 02 03` and calls `uart_read(buf, 8, 0)`
- **THEN** it returns 3 and `buf` starts with `01 02 03`

#### Scenario: Writes are captured

- **WHEN** a module calls `uart_write` with 4 bytes
- **THEN** the mock's TX capture holds exactly those 4 bytes and nothing is echoed into RX

#### Scenario: HIL: Real UART initializes

- **WHEN** the firmware calls `uart_init(CONFIG_UART_BAUD)` on the board
- **THEN** the link UART is configured on the pins in the hardware page and no error is logged
