# Tasks

## 1. Project skeleton

- [ ] 1.1 Create `firmware/xiao/platformio.ini`, `firmware/xiao/CMakeLists.txt`, `firmware/xiao/src/CMakeLists.txt`, `firmware/xiao/sdkconfig.defaults`, `firmware/xiao/partitions.csv` and `firmware/xiao/.clang-tidy` exactly as in design D1 (platform pinned to the version in `tools/container/versions.env`), plus `firmware/xiao/data/README.md` (one line: "Static web assets go here."); verify the files exist.
- [ ] 1.2 Create `firmware/xiao/include/config.h` per design D5 and a minimal `firmware/xiao/src/main.cpp` whose `app_main` logs `XIAO firmware starting` and loops on `vTaskDelay`; verify `tools/build.sh xiao` passes.

## 2. Utils

- [ ] 2.1 Create `firmware/xiao/include/utils/utils.h` and `firmware/xiao/src/utils/utils.cpp` per design D4; verify `tools/build.sh xiao` passes.
- [ ] 2.2 Create `firmware/xiao/test/test_main.cpp` (Unity runner, empty `setUp`/`tearDown` for now) and `firmware/xiao/test/test_utils.cpp` with the `test_utils_*` tests from design D7; verify `tools/test.sh xiao` passes with 9 tests.

## 3. HAL and mock

- [ ] 3.1 Create `firmware/xiao/include/hal/hal.h` and `firmware/xiao/src/hal/hal.cpp` per design D2; verify `tools/build.sh xiao` passes.
- [ ] 3.2 Create `firmware/xiao/test/test_mock_hal.h` and `firmware/xiao/test/test_mock_hal.cpp` per design D3, call `mock::reset()` from `setUp()` in `firmware/xiao/test/test_main.cpp`, and add `firmware/xiao/test/test_hal.cpp` with the `test_hal_*` tests from design D7; verify `tools/test.sh xiao` passes with 18 tests.

## 4. Stubs and boot sequence

- [ ] 4.1 Create `firmware/xiao/include/wifi_mgr.h`, `firmware/xiao/src/wifi_mgr.cpp`, `firmware/xiao/include/uart_if.h`, `firmware/xiao/src/uart_if.cpp` per design D6, and `firmware/xiao/test/test_stubs.cpp` with the `test_stubs_*` tests; verify `tools/test.sh xiao` passes with 20 tests.
- [ ] 4.2 Complete `firmware/xiao/src/main.cpp` with the boot sequence and main loop from design D6; verify `tools/verify.sh xiao --all-files` prints `VERIFY PASS`.

## HIL checks (user)

- Firmware boots and prints init status on the USB console.
- `wifi_mgr` and `uart_if` initialize without panic.
- Console shows `XIAO firmware initialized — all subsystems ready`.
- Main loop runs for at least 60 s with no reset or watchdog message.

## Workflow follow-up

- Archive after the user confirms the HIL checks.
