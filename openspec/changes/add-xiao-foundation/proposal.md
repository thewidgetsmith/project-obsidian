# Proposal

## Why

`firmware/xiao/` is empty after the clean-slate restart. Every XIAO feature
(camera streaming, web UI, intercom, joystick handling, the UART link) needs a
project that builds, a hardware abstraction that host tests can mock, and a
non-blocking main loop to hang off. This change provides that foundation.

## What Changes

- Create the PlatformIO/ESP-IDF project `firmware/xiao/` following
  `docs/reference/layout-xiao.md`: board env
  `xiao_esp32s3`, host test env `test_xiao_esp32s3`, clang-tidy config.
- Add `obsidian::hal` (time, GPIO, link UART) with a real ESP-IDF
  implementation and a host mock that records and injects state.
- Add `obsidian::utils` (logging, bit helpers, clamping, hex/decimal
  formatting).
- Add `config.h` with `CONFIG_*` tunables and pin macros matching
  the "Firmware Assignments" table in `docs/hardware/xiao-esp32s3-sense.md`.
- Add stub modules `wifi_mgr` and `uart_if` that initialize without error.
- Add `app_main`: init sequence, then a main loop that never blocks and yields
  every pass.

## Capabilities

### New Capabilities

- `xiao-hal`: the XIAO hardware abstraction contract and its host mock.
- `xiao-runtime`: the XIAO build, boot sequence, main loop, utilities and
  module stubs.

### Modified Capabilities

None.

## Impact

- New tree `firmware/xiao/`; `tools/verify.sh xiao` stops skipping the lint,
  build and test steps.
- No new third-party dependencies (ESP-IDF components and PlatformIO's
  bundled Unity only).
- Out of scope: Wi-Fi behavior (a later Wi-Fi change), the UART protocol
  (`add-uart-link`), camera, audio, SD.
- HIL (user): boots and prints init status on the USB console; `wifi_mgr` and
  `uart_if` initialize without panic; console shows
  `XIAO firmware initialized — all subsystems ready`; main loop runs ≥ 60 s
  with no reset or watchdog message.
