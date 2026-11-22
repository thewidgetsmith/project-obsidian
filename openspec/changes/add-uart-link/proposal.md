# Proposal

## Why

The two MCUs have no data path. Joystick-driven drive commands must reach the
motor controller at 100 Hz, battery state must come back for the HUD, the
link must come up on its own whatever the power-up order, and the rover must
stop within 100 ms if commands stop arriving. Both foundation changes left
`uart_if` as a placeholder for exactly this.

## What Changes

- Add `firmware/shared/protocol.h`: the single, header-only, C-compatible
  definition of the wire protocol (frame format, CRC-8, command IDs, status
  codes, flags, payload encoders, byte-wise parser).
- Replace the `uart_if` stubs on both boards with a framed transport over the
  HAL UART (non-blocking receive with inter-byte timeout, frame send).
- XIAO: add `link_mgr` (HELLO handshake, 100 Hz `DRIVE` tick, 500 ms uplink
  watchdog, battery storage with staleness, public control API).
- ATmega: add `cmd_handler` (validate and store `DRIVE`, `STOP`,
  `HELLO_ACK`, `ACK` per frame, 100 ms motion-timeout failsafe) and replace
  the `telemetry` stub with 10 Hz ADC sampling, conversion, flags and
  `TELEMETRY` frames.
- Wire both into `main.cpp`; add the protocol tunables to both `config.h`.

## Capabilities

### New Capabilities

- `uart-protocol`: wire format, CRC, command set, payload layouts, parser
  behavior and versioning shared by both boards.
- `xiao-link-manager`: link establishment, control tick, uplink watchdog and
  the control/battery API for later XIAO features.
- `atmega-command-handler`: command validation, replies and the motion-timeout
  failsafe on the motor controller.
- `battery-telemetry`: battery sampling, conversion, status flags and the
  10 Hz telemetry stream.

### Modified Capabilities

None. (Depends on `add-xiao-foundation` and `add-atmega-foundation` being
applied first; their stub `uart_if`/`telemetry` modules are filled in here
without changing their init contract.)

## Impact

- New: `firmware/shared/protocol.h`, `firmware/xiao/{include,src}/link_mgr.*`,
  `firmware/atmega/{include,src}/cmd_handler.*`, tests on both boards.
- Changed: both boards' `uart_if`, `main.cpp`, `config.h`, `platformio.ini`
  test filters; ATmega `telemetry` and `motor` (adds
  `motor_outputs_enabled()`).
- No new third-party dependencies.
- Out of scope: per-wheel feedback, kinematics, servo output, LED/IO commands,
  HUD display, retransmission/sequence numbers, baud negotiation. Their
  command IDs stay reserved.
- HIL (user): handshake to link-up within 1 s; `DRIVE` at ~100 Hz with `ACK`s;
  `TELEMETRY` at 10 Hz with voltage within ±5 % of a multimeter; link down
  within ~500 ms of unplugging and back up within 1 s; either board can be
  power-cycled without resetting the other; with the XIAO held in reset the
  ATmega stops the motors within 100 ms.
