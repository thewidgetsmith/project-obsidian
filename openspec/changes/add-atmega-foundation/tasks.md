# Tasks

## 1. Project skeleton

- [ ] 1.1 Create `firmware/atmega/platformio.ini` and `firmware/atmega/.cppcheck-suppressions` exactly as in design D1, `firmware/atmega/include/config.h` per design D5, and a minimal `firmware/atmega/src/main.cpp` with empty `setup()`/`loop()`; verify `tools/build.sh atmega` passes.

## 2. Utils

- [ ] 2.1 Create `firmware/atmega/include/utils/utils.h` and `firmware/atmega/src/utils/utils.cpp` per design D4 (`log_println_P` writes through `obsidian::hal::log_write`); verify `tools/build.sh atmega` passes.
- [ ] 2.2 Create `firmware/atmega/include/hal/hal.h` (declarations only, design D2), `firmware/atmega/test/test_mock_hal.h` and `firmware/atmega/test/test_mock_hal.cpp` per design D3, `firmware/atmega/test/test_main.cpp` (Unity runner; `setUp()` calls `mock::reset()`), and `firmware/atmega/test/test_utils.cpp` with the `test_utils_*` tests from design D8; verify `tools/verify.sh atmega` passes with 9 tests.

## 3. HAL

- [ ] 3.1 Create `firmware/atmega/src/hal/hal.cpp` (real Arduino implementation, design D2) and `firmware/atmega/test/test_hal.cpp` with the `test_hal_*` tests from design D8; verify `tools/verify.sh atmega` passes with 18 tests.

## 4. Motor safe state

- [ ] 4.1 Create `firmware/atmega/include/motor.h` and `firmware/atmega/src/motor.cpp` per design D6, and `firmware/atmega/test/test_motor.cpp` with the `test_motor_*` tests from design D8; verify `tools/verify.sh atmega` passes with 23 tests.

## 5. Stubs and boot sequence

- [ ] 5.1 Create `firmware/atmega/include/telemetry.h`, `firmware/atmega/src/telemetry.cpp`, `firmware/atmega/include/uart_if.h`, `firmware/atmega/src/uart_if.cpp` per design D7, and `firmware/atmega/test/test_stubs.cpp`; verify `tools/verify.sh atmega` passes with 25 tests.
- [ ] 5.2 Complete `firmware/atmega/src/main.cpp` with the boot sequence and loop from design D7; verify `tools/verify.sh atmega --all-files` prints `VERIFY PASS` and the build line shows flash ≤ 28672 B and RAM ≤ 1536 B.

## HIL checks (user)

- Firmware boots and prints init status on the debug log port (USB-serial adapter on D2 and GND, 115200 baud).
- Nothing but protocol frames leaves D1 (no log text on the XIAO link).
- No motor moves or twitches at power-up, at reset, or after upload.
- All stubs initialize without a reset loop.
- Console shows `ATmega firmware initialized — all subsystems ready`.
- Main loop runs for at least 60 s with no reset.

## Workflow follow-up

- Archive after the user confirms the HIL checks.
