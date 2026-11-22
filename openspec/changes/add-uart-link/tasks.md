# Tasks

## 1. Shared protocol header

- [ ] 1.1 Create `firmware/shared/protocol.h` per design D1; verify `tools/verify.sh all --only rules,format` passes.
- [ ] 1.2 Add `firmware/xiao/test/test_protocol.cpp` and `firmware/xiao/test/test_protocol_c.c` with the `test_protocol_*` tests from design D6, registered in `firmware/xiao/test/test_main.cpp`; verify `tools/verify.sh xiao` passes.
- [ ] 1.3 Copy both files unchanged to `firmware/atmega/test/` and register the tests in `firmware/atmega/test/test_main.cpp`; verify `tools/verify.sh atmega` passes.

## 2. XIAO transport

- [ ] 2.1 Replace the stub in `firmware/xiao/include/uart_if.h` and `firmware/xiao/src/uart_if.cpp` with the transport from design D2, replace `test_stubs_uart_if_init` with `firmware/xiao/test/test_uart_if.cpp` (`test_uart_if_*` tests), and drop the `uart_if_poll()` call from `firmware/xiao/src/main.cpp`; verify `tools/verify.sh xiao` passes.

## 3. XIAO link manager

- [ ] 3.1 Add the link constants to `firmware/xiao/include/config.h`, create `firmware/xiao/include/link_mgr.h` and `firmware/xiao/src/link_mgr.cpp` per design D3, append `+<link_mgr.cpp>` to `build_src_filter` in `firmware/xiao/platformio.ini`, and add `firmware/xiao/test/test_link_mgr.cpp` with the `test_link_mgr_*` tests; verify `tools/verify.sh xiao` passes.
- [ ] 3.2 Wire `link_mgr_init()` / `link_mgr_poll()` into `firmware/xiao/src/main.cpp` per design D3; verify `tools/verify.sh xiao --all-files` prints `VERIFY PASS`.

## 4. ATmega transport and command handler

- [ ] 4.1 Replace the stub in `firmware/atmega/include/uart_if.h` and `firmware/atmega/src/uart_if.cpp` with the transport from design D2, replace `test_stubs_uart_if_init` with `firmware/atmega/test/test_uart_if.cpp`; verify `tools/verify.sh atmega` passes.
- [ ] 4.2 Add the command-handler constants to `firmware/atmega/include/config.h`, create `firmware/atmega/include/cmd_handler.h` and `firmware/atmega/src/cmd_handler.cpp` per design D4, append `+<cmd_handler.cpp>` to `build_src_filter` in `firmware/atmega/platformio.ini`, and add `firmware/atmega/test/test_cmd_handler.cpp` with the `test_cmd_handler_*` tests; verify `tools/verify.sh atmega` passes.

## 5. ATmega telemetry

- [ ] 5.1 Add `motor_outputs_enabled()` to `firmware/atmega/include/motor.h` / `firmware/atmega/src/motor.cpp` with test `test_motor_outputs_enabled_after_init` in `firmware/atmega/test/test_motor.cpp`; verify `tools/verify.sh atmega` passes.
- [ ] 5.2 Add the battery constants to `firmware/atmega/include/config.h`, replace the stub in `firmware/atmega/include/telemetry.h` / `firmware/atmega/src/telemetry.cpp` per design D5, and add `firmware/atmega/test/test_telemetry.cpp` with the `test_telemetry_*` tests; verify `tools/verify.sh atmega` passes.
- [ ] 5.3 Wire `cmd_handler` and `telemetry` into `firmware/atmega/src/main.cpp` per design D5; verify `tools/verify.sh atmega --all-files` prints `VERIFY PASS` with flash ≤ 28672 B and RAM ≤ 1536 B.

## HIL checks (user)

- XIAO log shows HELLO → HELLO_ACK → link up within 1 s of both boards being powered.
- ATmega log shows DRIVE received at ~100 Hz and ACKs sent.
- XIAO log shows TELEMETRY at 10 Hz; voltage within ±5 % of a multimeter at the pack.
- Unplugging the UART wires: link down within ~500 ms; reconnecting: link up within 1 s.
- Power-cycling either board re-establishes the link without resetting the other.
- XIAO held in reset: ATmega applies zero drive within 100 ms; LINK_TIMEOUT visible.

## Workflow follow-up

- Archive after the user confirms the HIL checks.
