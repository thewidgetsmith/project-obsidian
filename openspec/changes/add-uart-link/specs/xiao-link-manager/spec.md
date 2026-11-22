# Spec Delta

## Purpose

The XIAO side of the UART link: it brings the link up, sends the control state
at 100 Hz, notices when the ATmega goes quiet, and gives later features a
small API for drive commands and battery data.

## ADDED Requirements

### Requirement: Link state

The link SHALL be up while a valid uplink frame (other than a
`HELLO_ACK` with `VERSION_MISMATCH`) has arrived within the last
`CONFIG_LINK_WATCHDOG_MS` (500 ms), and down otherwise. Transitions SHALL be
logged.

#### Scenario: Up on first uplink frame

- **GIVEN** the link is down
- **WHEN** a valid TELEMETRY frame arrives
- **THEN** `link_mgr_is_up()` returns true

#### Scenario: Down after the watchdog

- **GIVEN** the link is up and the last uplink frame arrived at t
- **WHEN** `link_mgr_poll()` runs at t + 500 ms with no new frame
- **THEN** `link_mgr_is_up()` returns false

#### Scenario: HIL: Unplug and replug

- **WHEN** the UART wires are disconnected and later reconnected
- **THEN** the XIAO logs link down within about 500 ms and link up within 1 s of reconnecting

### Requirement: Handshake

While the link is down, the XIAO SHALL send `HELLO {PROTOCOL_VERSION}` on the
first poll and then every `CONFIG_LINK_HELLO_RETRY_MS` (1000 ms). A
`HELLO_ACK` with `VERSION_MISMATCH` SHALL keep the link down until a
`HELLO_ACK` with `OK` arrives.

#### Scenario: HELLO retries

- **GIVEN** the link is down
- **WHEN** the XIAO polls continuously for 2500 ms with no uplink traffic
- **THEN** exactly three HELLO frames were sent, at 0, 1000 and 2000 ms

#### Scenario: Version mismatch

- **WHEN** a `HELLO_ACK {version 2, VERSION_MISMATCH}` arrives, followed by TELEMETRY frames
- **THEN** the link stays down

#### Scenario: HIL: Handshake

- **WHEN** both boards are powered in either order
- **THEN** the XIAO log shows HELLO, HELLO_ACK and link up within 1 s

### Requirement: Control tick

The XIAO SHALL send `DRIVE` every `CONFIG_LINK_CONTROL_TICK_MS` (10 ms)
whether or not the link is up, carrying the current drive state with every
field clamped to −1000..1000. The state is neutral zeros until set.
`link_mgr_send_stop()` SHALL send `STOP` immediately and zero the drive state.

#### Scenario: Tick rate

- **WHEN** the XIAO polls every 1 ms for 100 ms
- **THEN** 10 DRIVE frames were sent

#### Scenario: Clamping

- **WHEN** `link_mgr_set_drive(5000, -5000, 7, 0)` is called
- **THEN** the next DRIVE frame carries 1000, −1000, 7, 0

#### Scenario: Stop

- **WHEN** `link_mgr_send_stop()` is called after a non-zero drive was set
- **THEN** a STOP frame is sent and the next DRIVE frame carries all zeros

### Requirement: Battery data

The XIAO SHALL store the latest TELEMETRY values and report them as stale
while the link is down or before any TELEMETRY has arrived.

#### Scenario: Stored telemetry

- **WHEN** TELEMETRY {11800 mV, 1500 mA, flags 0x01} arrives
- **THEN** `link_mgr_get_battery()` returns those values, not stale

#### Scenario: Stale after link loss

- **WHEN** the watchdog marks the link down
- **THEN** `link_mgr_get_battery()` reports the last values as stale

### Requirement: Never blocks

`link_mgr_poll()` SHALL return without waiting on the UART and SHALL NOT
create FreeRTOS tasks or timers; all timing uses `hal::now_ms()`.

#### Scenario: Empty RX

- **WHEN** `link_mgr_poll()` runs with no bytes available
- **THEN** it returns without the mock clock advancing
