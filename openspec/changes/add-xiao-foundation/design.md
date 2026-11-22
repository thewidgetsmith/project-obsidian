# Design

## Context

`firmware/xiao/` is empty. The structure rules are in
`docs/reference/layout-xiao.md`; pins in `docs/hardware/xiao-esp32s3-sense.md`
(table "Firmware Assignments"). Conventions (namespaces, Doxygen, include
guards, section rulers, test naming) are in `AGENTS.md`. Earlier attempts
showed three traps this design avoids: host tests that link no real code, a
UART mock that loops TX back into RX, and ESP-IDF overriding `-std`.

## Goals / Non-Goals

**Goals:**
- A tree that passes `tools/verify.sh xiao --all-files`.
- A HAL small enough to mock completely, with the mock in its final split
  TX/RX form so `add-uart-link` needs no mock rework.
- Host tests that compile the real `utils` and stub modules.

**Non-Goals:**
- Wi-Fi, camera, audio, SD, the link protocol, web assets beyond a
  placeholder `data/README.md`.
- Linting code inside `#ifdef ESP_PLATFORM` (stock clang can't parse the
  Xtensa compile database; see `docs/reference/toolchain.md`).

## Decisions

### D1. Build files (planner decision: copy these exactly)

`firmware/xiao/platformio.ini`:

```ini
; Project Obsidian — XIAO ESP32-S3 Sense firmware (ESP-IDF)

; ─── Board build ───
[env:xiao_esp32s3]
platform = espressif32@8.0.0
board = seeed_xiao_esp32s3
framework = espidf
monitor_speed = 115200
board_build.partitions = partitions.csv
build_flags =
    -Wall
    -Wextra
    -Werror
    -I../shared

; ─── Host unit tests ───
[env:test_xiao_esp32s3]
platform = native@1.2.1
test_framework = unity
test_build_src = yes
build_flags =
    -std=gnu++17
    -Wall
    -Wextra
    -Wpedantic
    -Werror
    -DUNIT_TEST
    -Iinclude
    -I../shared
build_src_filter =
    -<*>
    +<utils/utils.cpp>
    +<wifi_mgr.cpp>
    +<uart_if.cpp>
```

The platform version must equal `ESPRESSIF32_VERSION` in
`tools/container/versions.env`. Never leave it unpinned.

`firmware/xiao/CMakeLists.txt`:

```cmake
cmake_minimum_required(VERSION 3.16.0)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(obsidian_xiao)
```

`firmware/xiao/src/CMakeLists.txt` (ESP-IDF ignores `-std` in `build_flags`):

```cmake
file(GLOB_RECURSE app_sources ${CMAKE_SOURCE_DIR}/src/*.cpp)
idf_component_register(SRCS ${app_sources} INCLUDE_DIRS ../include ../../shared)
target_compile_options(${COMPONENT_LIB} PRIVATE -std=gnu++17)
```

`firmware/xiao/sdkconfig.defaults`:

```
CONFIG_ESPTOOLPY_FLASHSIZE_8MB=y
CONFIG_SPIRAM=y
CONFIG_SPIRAM_MODE_OCT=y
CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG=y
CONFIG_LOG_DEFAULT_LEVEL_INFO=y
CONFIG_PARTITION_TABLE_CUSTOM=y
CONFIG_PARTITION_TABLE_CUSTOM_FILENAME="partitions.csv"
```

`firmware/xiao/partitions.csv`:

```
# Name,   Type, SubType, Offset,  Size
nvs,      data, nvs,     0x9000,  0x6000
phy_init, data, phy,     0xf000,  0x1000
factory,  app,  factory, 0x10000, 6M
```

`firmware/xiao/.clang-tidy`: enable `clang-analyzer-*, bugprone-*,
cppcoreguidelines-*, misc-*, modernize-*, performance-*, portability-*,
readability-*, cert-*`; `WarningsAsErrors: '*'`; `HeaderFilterRegex: '.*'`;
`FormatStyle: file`. Disable: `readability-magic-numbers,
cppcoreguidelines-avoid-magic-numbers, modernize-macro-to-enum,
cppcoreguidelines-macro-to-enum, cppcoreguidelines-macro-usage,
modernize-use-trailing-return-type, readability-identifier-length,
readability-braces-around-statements, readability-implicit-bool-conversion,
cppcoreguidelines-avoid-non-const-global-variables,
bugprone-easily-swappable-parameters, misc-unused-parameters,
cppcoreguidelines-avoid-c-arrays, modernize-avoid-c-arrays,
cppcoreguidelines-pro-bounds-constant-array-index,
cppcoreguidelines-pro-bounds-array-to-pointer-decay,
cppcoreguidelines-pro-type-vararg, misc-include-cleaner,
misc-const-correctness, performance-enum-size,
modernize-concat-nested-namespaces`.

### D2. HAL interface — `firmware/xiao/include/hal/hal.h`

```cpp
namespace obsidian::hal {
enum class PinDir : uint8_t { Input, Output };

uint32_t now_ms();                                   // ms since boot
void     delay_ms(uint32_t ms);                      // blocks; main.cpp only
bool     gpio_init(uint8_t pin, PinDir dir);         // true on success
void     gpio_write(uint8_t pin, bool level);
bool     gpio_read(uint8_t pin);
bool     uart_init(uint32_t baud);                   // link UART, CONFIG_UART_PORT
size_t   uart_write(const uint8_t* data, size_t len);  // bytes queued
size_t   uart_read(uint8_t* buf, size_t len, uint32_t timeout_ms);  // 0 = never block
}  // namespace obsidian::hal
```

Real (`src/hal/hal.cpp`): `esp_timer_get_time() / 1000`; `vTaskDelay(pdMS_TO_TICKS(ms))`;
`gpio_set_direction`; `gpio_set_level`; `gpio_get_level`;
`uart_param_config` + `uart_set_pin(CONFIG_UART_PORT, CONFIG_UART_TX_PIN,
CONFIG_UART_RX_PIN, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE)` +
`uart_driver_install(CONFIG_UART_PORT, 1024, 0, 0, nullptr, 0)`;
`uart_write_bytes`; `uart_read_bytes(port, buf, len, pdMS_TO_TICKS(timeout_ms))`.
Negative driver results return 0 / false and log once with `ESP_LOGE`.

### D3. Mock controls — `firmware/xiao/test/test_mock_hal.h` (planner decision)

Test-only header, so it lives in `test/`. Implemented in
`test/test_mock_hal.cpp` together with the mock HAL functions. Fixed-size
static storage: 64 pins, 256-byte RX and TX buffers.

```cpp
namespace obsidian::hal::mock {
void        reset();                          // clock 0, pins input/low, buffers empty, baud 0
void        set_now_ms(uint32_t ms);
void        advance_ms(uint32_t ms);
PinDir      gpio_dir(uint8_t pin);
void        gpio_inject(uint8_t pin, bool level);
uint32_t    uart_baud();                      // last uart_init() value
void        uart_inject_rx(const uint8_t* data, size_t len);
size_t      uart_tx_len();
const uint8_t* uart_tx_data();
void        uart_tx_clear();
}
```

`test/test_main.cpp` calls `obsidian::hal::mock::reset()` in `setUp()`.

### D4. Utils — `firmware/xiao/include/utils/utils.h`

```cpp
namespace obsidian::utils {
void    log_println(const char* msg);              // printf("%s\n") → USB console
void    bit_set(uint32_t* value, uint8_t bit);
void    bit_clear(uint32_t* value, uint8_t bit);
void    bit_toggle(uint32_t* value, uint8_t bit);
bool    bit_test(uint32_t value, uint8_t bit);
int32_t clamp_i32(int32_t value, int32_t lo, int32_t hi);
void    format_hex(uint32_t value, char* buf);     // buf ≥ 11: "0x" + 8 upper-case digits + NUL
size_t  format_u32(uint32_t value, char* buf, size_t len);  // decimal; returns chars written, 0 if len too small
}
```

`bit >= 32` is a no-op (and `bit_test` returns false). Shifts use
`uint32_t{1} << bit`.

### D5. Config — `firmware/xiao/include/config.h`

`CONFIG_UART_PORT 1`, `CONFIG_UART_BAUD 115200`, `CONFIG_LOOP_PERIOD_MS 10`,
and every pin macro in the hardware page's "Firmware Assignments" table, with
the same names and values. No `config.cpp` is needed.

### D6. Stubs and boot

`include/wifi_mgr.h`, `include/uart_if.h`: `bool wifi_mgr_init();`,
`void wifi_mgr_poll();`, `bool uart_if_init();`, `void uart_if_poll();`, with
`// TODO(wifi):` / `// TODO(add-uart-link):` markers in the `.cpp` files.

`src/main.cpp`: `extern "C" void app_main()` logs `XIAO firmware starting`,
calls each init and logs `wifi_mgr: OK|FAIL`, `uart_if: OK|FAIL`, logs
`XIAO firmware initialized — all subsystems ready`, then loops forever:
`wifi_mgr_poll(); uart_if_poll(); hal::delay_ms(CONFIG_LOOP_PERIOD_MS);`.

### D7. Tests (Unity, env `test_xiao_esp32s3`)

| File | Tests |
| --- | --- |
| `test/test_hal.cpp` | `test_hal_delay_advances_clock`, `test_hal_set_now_ms`, `test_hal_gpio_write_read`, `test_hal_gpio_dir_recorded`, `test_hal_gpio_inject`, `test_hal_uart_rx_inject_read`, `test_hal_uart_tx_captured`, `test_hal_uart_read_empty_returns_zero`, `test_hal_uart_init_records_baud` |
| `test/test_utils.cpp` | `test_utils_bit_set`, `test_utils_bit_clear`, `test_utils_bit_toggle`, `test_utils_bit_test`, `test_utils_bit_out_of_range`, `test_utils_clamp_i32`, `test_utils_format_hex`, `test_utils_format_u32`, `test_utils_format_u32_short_buffer` |
| `test/test_stubs.cpp` | `test_stubs_wifi_mgr_init`, `test_stubs_uart_if_init` |

All are registered with `RUN_TEST` in `test/test_main.cpp`.

### D8. Lint compatibility

The lint step runs host clang-tidy over every `src/**/*.cpp` with only
`-Ifirmware/xiao/include -Ifirmware/shared`, so ESP-IDF headers are not found.
In `src/hal/hal.cpp` and `src/main.cpp`, wrap every ESP-IDF/FreeRTOS
`#include` and the code that uses it in `#ifdef ESP_PLATFORM` … `#endif`.
Other modules include no ESP-IDF headers at all.

Group 1 is scaffolding: verify it with `tools/build.sh xiao`. From group 2 on,
every group leaves `tools/verify.sh xiao` passing.

## Risks / Trade-offs

- [ESP-IDF version drift changes build behavior] → the platform is pinned; bump it deliberately.
- [`-Werror` on the board build fails on an ESP-IDF header warning] → fix by narrowing the include, not by dropping `-Werror`; report if impossible.
- [Mock header in `test/` breaks the "headers only in include/" rule] → the rule is about `src/`; layout doc is updated to say so.

## Open Questions

None.
