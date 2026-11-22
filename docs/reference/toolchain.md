# Toolchain Reference

Agents normally need only the scripts in
[tools/README.md](../../tools/README.md). This page documents what
`tools/verify.sh` runs, for humans and for debugging the scripts themselves.

## Toolbox

All checks run in the toolbox image
([tools/container/Containerfile](../../tools/container/Containerfile)):
Debian trixie with PlatformIO 6.2.0, gcc 14, clang-format/clang-tidy 19,
cppcheck 2.17, Python 3.13, Node 22 and OpenSpec 2.1.1. Locally it runs as
the `obsidian-dev` distrobox; CI runs the same image. Setup:
[tools/README.md](../../tools/README.md#the-toolbox).

- Platform versions (espressif32, atmelavr, native) are pinned in
  [tools/container/versions.env](../../tools/container/versions.env), and
  each `platformio.ini` must use the same versions.
- PlatformIO packages live in `PLATFORMIO_CORE_DIR`
  (`~/.cache/obsidian/platformio` by default).
- `VERIFY_MAX_LINES=<n>` shows more error lines per failing step (default 25).

## What `verify.sh` Runs

| Step | Board | Command |
| --- | --- | --- |
| docs | — | `python3 tools/check-docs.py` (broken relative links) |
| specs | — | `openspec validate --all --strict --no-interactive` |
| format | both | `clang-format --dry-run --Werror <changed files>` (`--fix` runs `clang-format -i` first) |
| rules | both | `python3 tools/check-rules.py <boards>`: `AGENTS.md` conventions ([rule list](../../tools/README.md#check-rulespy)) |
| lint | XIAO | `clang-tidy --quiet --config-file=firmware/xiao/.clang-tidy firmware/xiao/src/**/*.cpp -- -std=gnu++17 -Ifirmware/xiao/include -Ifirmware/shared` |
| lint | ATmega | `cppcheck --enable=all --std=c++17 --quiet --inline-suppr --suppressions-list=firmware/atmega/.cppcheck-suppressions firmware/atmega/src/**/*.cpp`; any non-informational finding fails |
| build | XIAO | `pio run -d firmware/xiao -e xiao_esp32s3` |
| build | ATmega | `pio run -d firmware/atmega -e atmega328p`; fails over the budget (flash 28672 B, RAM 1536 B) |
| test | XIAO | `pio test -d firmware/xiao -e test_xiao_esp32s3` |
| test | ATmega | `pio test -d firmware/atmega -e test_atmega328p` |

Lint, build and test are skipped for a board that has no `platformio.ini`
yet. Format checks cover `src/`, `include/`, `test/`, and `firmware/shared/`
for the selected boards: only changed files by default, every file with
`--all-files`. Rules and lint always cover the board's whole tree.

The XIAO lint passes flags after `--` and ignores `compile_commands.json`:
stock clang can't parse the Xtensa ESP-IDF database, so ESP-IDF code must sit
inside `#ifdef ESP_PLATFORM` and isn't linted.

## Configuration Files

- `.clang-format` — shared formatting rules (LLVM base, 4-space indent, 100 columns)
- `firmware/xiao/.clang-tidy` — ESP32-S3 analysis rules; all warnings are errors
- `firmware/atmega/.cppcheck-suppressions` — ATmega328P false positives
- `firmware/xiao/platformio.ini` — ESP32-S3 build and native test env
- `firmware/atmega/platformio.ini` — ATmega328P build and native test env
- `openspec/config.yaml` — project context and rules injected into OpenSpec artifacts

## Testing

Unit tests use [Unity](https://www.throwtheswitch.org/unity) through
PlatformIO's `test_framework = unity` on the host (`platform = native`).
Hardware is replaced by mocks in `test/test_mock_*.cpp`. PlatformIO compiles
`src/` into a native test build only when the env sets `test_build_src = yes`;
`build_src_filter` then selects which host-safe modules are included. A `.c`
file in `test/` is compiled as C, which is how `protocol.h` is checked as C.

Automated testing stops at the host: unit tests of functions, state machines
and mocked hardware. Anything that needs a board is a hardware-in-the-loop
check listed in the change's `tasks.md` for the user.

## CI

[.github/workflows/ci.yml](../../.github/workflows/ci.yml) (Gitea Actions,
self-hosted runner) builds the toolbox image and runs
`tools/verify.sh all --all-files` in it on every push and pull request to
`main`. Runner setup: [.github/README.md](../../.github/README.md).
