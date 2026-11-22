# Spec Delta

## Purpose

The ATmega side of the downlink: it validates and stores drive commands,
answers every valid frame, and stops the motors when commands stop arriving.

## ADDED Requirements

### Requirement: One reply per valid downlink frame

For every valid frame the ATmega SHALL send exactly one reply: `HELLO_ACK` for
`HELLO`, and `ACK {cmd, status}` for anything else. An `ACK` SHALL carry only
the command ID and a status, never state.

#### Scenario: HELLO

- **WHEN** `HELLO {0x01}` arrives
- **THEN** the ATmega sends `HELLO_ACK {0x01, OK}`

#### Scenario: HELLO with another version

- **WHEN** `HELLO {0x02}` arrives
- **THEN** the ATmega sends `HELLO_ACK {0x01, VERSION_MISMATCH}`

#### Scenario: Unknown command

- **WHEN** a valid frame with CMD 0x10 arrives
- **THEN** the ATmega sends `ACK {0x10, UNKNOWN_COMMAND}`

#### Scenario: Wrong payload length

- **WHEN** a `DRIVE` frame with LEN 6 arrives
- **THEN** the ATmega sends `ACK {0x01, RANGE_ERROR}` and keeps the previous command

### Requirement: Drive validation

A `DRIVE` with every field in −1000..1000 SHALL be stored and acknowledged
`OK`. A `DRIVE` with any field out of range SHALL be rejected with
`RANGE_ERROR`, and the previous command SHALL be kept. `STOP` SHALL zero the
stored command, stop the motors and be acknowledged `OK`.

#### Scenario: Valid drive

- **WHEN** `DRIVE {500, -200, 0, 1000}` arrives
- **THEN** the stored command is {500, −200, 0, 1000} and `ACK {0x01, OK}` is sent

#### Scenario: Out of range

- **GIVEN** the stored command is {500, 0, 0, 0}
- **WHEN** `DRIVE {1001, 0, 0, 0}` arrives
- **THEN** `ACK {0x01, RANGE_ERROR}` is sent and the stored command is still {500, 0, 0, 0}

#### Scenario: Stop

- **WHEN** `STOP` arrives after a non-zero drive
- **THEN** the stored command is all zeros and `ACK {0x02, OK}` is sent

### Requirement: Motion-timeout failsafe

If no valid `DRIVE` or `STOP` has arrived for `CONFIG_MOTION_TIMEOUT_MS`
(100 ms), the ATmega SHALL zero the stored command, call `motor_stop()` and
report the link as timed out until the next valid `DRIVE` or `STOP`. It SHALL
start timed out at boot.

#### Scenario: Timeout boundary

- **GIVEN** a valid DRIVE arrived at t = 0
- **WHEN** the handler polls at t = 99 ms and again at t = 100 ms
- **THEN** it is not timed out at 99 ms and is timed out with a zero command at 100 ms

#### Scenario: Boot state

- **WHEN** the handler has been initialized and no command has arrived
- **THEN** it reports timed out

#### Scenario: HIL: XIAO held in reset

- **WHEN** the XIAO is held in reset while the rover is driving
- **THEN** the motors stop within 100 ms and LINK_TIMEOUT is visible in telemetry

### Requirement: Gimbal angle mapping

The gimbal field SHALL map to a servo angle as `90 + gimbal × 90 / 1000`
degrees using 32-bit integer math (−1000 → 0°, 0 → 90°, 1000 → 180°).

#### Scenario: Mapping endpoints

- **WHEN** gimbal values −1000, 0 and 1000 are mapped
- **THEN** the angles are 0, 90 and 180

### Requirement: Rate-limited logging

The ATmega SHALL log received commands at most once per
`CONFIG_CMD_LOG_INTERVAL_MS` (100 ms) and SHALL log every ACK it sends, on
the debug log port only; no log byte SHALL be written to the link UART.

#### Scenario: Log rate

- **WHEN** 10 DRIVE frames arrive within 100 ms
- **THEN** at most one command log line is written to the debug log in that window, and the link UART carries only ACK frames
