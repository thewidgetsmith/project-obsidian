# Proposal

## Why

`firmware/atmega/` is empty after the clean-slate restart. UART command
handling, Mecanum kinematics, motor and gimbal control and battery telemetry
all need a project that builds within the ATmega328P's budget, a mockable
hardware abstraction, and a boot path that never lets a motor twitch. This
change mirrors `add-xiao-foundation` for the motor controller.

## What Changes

- Create the PlatformIO/Arduino project `firmware/atmega/` following
  `docs/reference/layout-atmega.md`: board env `atmega328p`, host test env
  `test_atmega328p`, cppcheck suppressions.
- Add `obsidian::hal` (time, GPIO, ADC, link UART, debug log port) on the
  Arduino core, and a host mock that records and injects state, including the
  order of GPIO writes. Logs leave on D2 (debug log port), never on the
  D0/D1 UART that carries the XIAO link.
- Add `obsidian::utils` (flash-string logging, bit helpers, clamping,
  formatting) with no heap, floats or `std::`.
- Add `config.h` with `CONFIG_*` tunables and pin macros matching
  `docs/hardware/atmega328p-arduino.md` and
  `docs/hardware/adafruit-motor-shield-v1.md`.
- Add `motor` (safe-state init and stop through the 74HC595), and stubs
  `telemetry` and `uart_if`.
- Add `setup()` (safe motor outputs first, then init) and a non-blocking
  `loop()`.

## Capabilities

### New Capabilities

- `atmega-hal`: the ATmega hardware abstraction contract and its host mock.
- `atmega-runtime`: the ATmega build and size budget, boot sequence with the
  motor safe state, main loop, utilities and module stubs.

### Modified Capabilities

None.

## Impact

- New tree `firmware/atmega/`; `tools/verify.sh atmega` stops skipping lint,
  build and test.
- No new third-party dependencies (Arduino AVR core and bundled Unity only).
- Out of scope: motor PWM and direction control beyond the safe state (the
  kinematics change), servo output (the gimbal change), the UART protocol
  (`add-uart-link`), real battery sampling (`add-uart-link`).
- HIL (user): boots and prints init status on the debug log port (USB-serial
  adapter on D2, see "Debug Log Port" in `docs/hardware/atmega328p-arduino.md`); no motor
  moves or twitches at power-up, reset or after upload; stubs initialize
  without a reset loop; console shows
  `ATmega firmware initialized — all subsystems ready`; main loop runs ≥ 60 s
  with no reset.
