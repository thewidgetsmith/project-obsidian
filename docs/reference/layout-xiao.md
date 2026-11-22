# XIAO Firmware Layout

This is the single source of truth for the structure of `firmware/xiao/`.
Specs and changes link here instead of restating the tree. It lists the
fixed skeleton and the placement rules, not every module: when a change adds a
module, follow [Adding a Module](#adding-a-module) and leave this page alone
unless a rule changes. Pins are defined in
[docs/hardware/xiao-esp32s3-sense.md](../hardware/xiao-esp32s3-sense.md).

## Skeleton

```
firmware/xiao/
├── platformio.ini         # Environments: xiao_esp32s3 (board), test_xiao_esp32s3 (host)
├── CMakeLists.txt         # ESP-IDF project file
├── sdkconfig.defaults     # Flash size, PSRAM, console routing
├── partitions.csv         # Partition table
├── .clang-tidy            # Lint config for this board
├── data/                  # Static web assets
├── include/               # All headers
│   ├── config.h           # CONFIG_* tunables and pin macros
│   ├── hal/hal.h          # obsidian::hal interface
│   └── utils/utils.h      # obsidian::utils interface
├── src/
│   ├── CMakeLists.txt     # App component; globs src/, sets gnu++17
│   ├── main.cpp           # app_main: init sequence + main loop
│   ├── config.cpp         # Only if config needs runtime definitions
│   ├── hal/hal.cpp        # Real HAL on ESP-IDF drivers
│   └── utils/utils.cpp
├── test/
│   ├── test_main.cpp      # Unity runner; registers every test
│   ├── test_mock_hal.h    # Mock controls (set clock, inject RX, read TX)
│   ├── test_mock_hal.cpp  # Mock HAL for host builds
│   └── test_<module>.cpp  # One file per module under test
└── lib/                   # Third-party libraries (user approval required)
```

## Placement Rules

- **Headers live only in `include/`.** Host tests compile against them, and
  `src/` holds no headers. The one exception is test-only headers such as
  `test/test_mock_hal.h` (mock controls), which live in `test/`.
- **Hardware access only in `src/hal/hal.cpp`.** Every other module calls
  `obsidian::hal`, so it builds on the host with `-DUNIT_TEST`.
- **Mocks live in `test/test_mock_*.cpp`.** They replace real
  implementations at link time. Only the HAL is mocked by default.
- **Tunables and pins go in `include/config.h`** as `CONFIG_*` macros. Pin
  values must match the hardware page. Protocol constants stay in
  `firmware/shared/protocol.h`.
- **`app_main` is `extern "C"`** and must not return. Its loop yields to
  FreeRTOS on every pass, so the task watchdog never fires.

## Adding a Module

A module named `foo` adds:

| File | Contents |
| --- | --- |
| `include/foo.h` | `foo_*` free-function API with Doxygen comments |
| `src/foo.cpp` | Implementation (picked up by the `src/` glob) |
| `test/test_foo.cpp` | `test_foo_<behavior>` tests, registered in `test/test_main.cpp` |

If `foo` is host-safe, append `+<foo.cpp>` to `build_src_filter` in
`[env:test_xiao_esp32s3]` so tests link the real code. Append only; never
remove entries.

## Build Files

- **C++ standard:** ESP-IDF overrides `-std` from `build_flags`, so gnu++17
  is set in `src/CMakeLists.txt`.
- **Warnings:** the board build uses `-Wall -Wextra -Werror` without
  `-Wpedantic`, because ESP-IDF headers use GCC extensions. The host test
  build adds `-Wpedantic`.
- **Board settings** (flash size, PSRAM, console) go in `sdkconfig.defaults`.
  The generated `sdkconfig.xiao_esp32s3` is derived from it.
- **Checks:** `tools/verify.sh xiao` formats, lints, builds and tests this
  tree. See [toolchain.md](toolchain.md).
