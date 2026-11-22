# ATmega Firmware Layout

This is the single source of truth for the structure of `firmware/atmega/`.
Specs and changes link here instead of restating the tree. It lists the
fixed skeleton and the placement rules, not every module: when a change adds a
module, follow [Adding a Module](#adding-a-module) and leave this page alone
unless a rule changes. Pins are defined in
[docs/hardware/atmega328p-arduino.md](../hardware/atmega328p-arduino.md) and
[docs/hardware/adafruit-motor-shield-v1.md](../hardware/adafruit-motor-shield-v1.md).
The XIAO counterpart is [layout-xiao.md](layout-xiao.md).

## Skeleton

```
firmware/atmega/
├── platformio.ini          # Environments: atmega328p (board), test_atmega328p (host)
├── .cppcheck-suppressions  # Lint suppressions for AVR/Arduino patterns
├── include/                # All headers
│   ├── config.h            # CONFIG_* tunables and pin macros
│   ├── hal/hal.h           # obsidian::hal interface
│   └── utils/utils.h       # obsidian::utils interface
├── src/
│   ├── main.cpp            # Arduino setup() + loop()
│   ├── config.cpp          # Only if config needs runtime definitions
│   ├── hal/hal.cpp         # Real HAL on the Arduino core and registers
│   └── utils/utils.cpp
├── test/
│   ├── test_main.cpp       # Unity runner; registers every test
│   ├── test_mock_hal.h     # Mock controls (set clock, inject RX, read TX)
│   ├── test_mock_hal.cpp   # Mock HAL for host builds
│   └── test_<module>.cpp   # One file per module under test
└── lib/                    # Third-party libraries (user approval required)
```

## Placement Rules

- **Headers live only in `include/`.** Host tests compile against them, and
  `src/` holds no headers. The one exception is test-only headers such as
  `test/test_mock_hal.h` (mock controls), which live in `test/`.
- **Hardware access only in `src/hal/hal.cpp`.** Every other module calls
  `obsidian::hal`, so it builds on the host with `-DUNIT_TEST`. The HAL may
  wrap the Arduino API or use registers directly; callers can't tell.
- **Mocks live in `test/test_mock_*.cpp`.** They replace real
  implementations at link time. Only the HAL is mocked by default.
- **Tunables and pins go in `include/config.h`** as `CONFIG_*` macros. Pin
  values must match the hardware pages. Protocol constants stay in
  `firmware/shared/protocol.h`.
- **The entry point is Arduino `setup()` / `loop()`.** `setup()` puts the
  motor outputs in a safe state before anything else (see
  [Safe Initialization Order](../hardware/adafruit-motor-shield-v1.md#safe-initialization-order)).
  `loop()` never blocks.
- **AVR rules** (no heap, floats, exceptions, RTTI or `std::`; strings in
  flash) are in [AGENTS.md](../../AGENTS.md#conventions).

## Adding a Module

A module named `foo` adds:

| File | Contents |
| --- | --- |
| `include/foo.h` | `foo_*` free-function API with Doxygen comments |
| `src/foo.cpp` | Implementation (`build_src_filter = +<*>` picks it up) |
| `test/test_foo.cpp` | `test_foo_<behavior>` tests, registered in `test/test_main.cpp` |

Module sources sit directly in `src/`. Only `hal/` and `utils/`, which are
namespaces, get subdirectories.

If `foo` is host-safe, append `+<foo.cpp>` to `build_src_filter` in
`[env:test_atmega328p]` so tests link the real code. Append only; never
remove entries.

## Build Files

- **C++ standard:** the Arduino builder adds `-std=gnu++11`, so
  `platformio.ini` removes it with `build_unflags` and sets `-std=gnu++17`.
- **Warnings:** `-Wall -Wextra -Wpedantic` apply to everything. `-Werror`
  applies only to project sources (`build_src_flags`), so warnings inside the
  Arduino core don't break the build.
- **Size:** `-Os`, `-fno-rtti`, `-fno-exceptions`, and section garbage
  collection (`-ffunction-sections -fdata-sections -Wl,--gc-sections`).
  Budget: flash ≤ 28 KB, SRAM ≤ 1.5 KB.
- **Libraries:** `lib_ldf_mode = off`; there are no third-party libraries.
- **Checks:** `tools/verify.sh atmega` formats, lints (cppcheck with
  `.cppcheck-suppressions`), builds and tests this tree. See
  [toolchain.md](toolchain.md).
