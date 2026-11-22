# Tools

Verification scripts shared by AI agents, developers and CI. Each prints a
line or two on success and, on failure, only the lines that matter, so an
agent's context stays small. Run them from the repo root (any worktree).
Exit status is 0 on success.

| Script | Use it to |
| --- | --- |
| `tools/verify.sh` (alias `tools/check.sh`) | run secrets, docs, specs, format, rules, lint, build and test; the only definition of "done" |
| `tools/format.sh`, `lint.sh`, `build.sh`, `test.sh` | run one step of `verify.sh` (same arguments) |
| `tools/log.sh` | see one failed step's errors with context |
| `tools/diff.sh [RANGE] [PATH]` | review-sized diff; lists files when it is large |
| `tools/outline.sh FILE` | functions, types, macros or headings with line numbers |
| `tools/check-secrets.py` | fail on keys, tokens or local secret values in the repo (`verify.sh` step `secrets`) |
| `tools/check-docs.py` | find broken links in Markdown (`verify.sh` step `docs`) |
| `tools/check-rules.py` | check the `AGENTS.md` conventions (`verify.sh` step `rules`) |
| `tools/pr.sh TITLE BODY_FILE` | open a PR for the pushed branch with `gh` or `tea` (exit 3: none available) |
| `tools/opencode.sh` | start OpenCode with the LiteLLM secrets from `~/.config/litellm/obsidian.env` |
| `tools/container.sh` | build and manage the toolbox (setup only) |

## The Toolbox

Every check runs with the tools baked into one image,
[container/Containerfile](container/Containerfile): PlatformIO and OpenSpec
(pinned), gcc 14, clang-format/clang-tidy 19, cppcheck 2.17, Python 3,
Node 22. Platform versions are pinned in
[container/versions.env](container/versions.env).

- **Locally** the image runs as the `obsidian-dev` distrobox. Started on the
  host, the shell scripts re-run themselves inside it
  ([lib/env.sh](lib/env.sh)), so Claude Code, OpenCode and your terminal all
  call `tools/verify.sh` the same way.
- **In CI** the workflow builds the same image and runs `tools/verify.sh`
  in it ([.github/workflows/ci.yml](../.github/workflows/ci.yml)).
- PlatformIO packages live in `PLATFORMIO_CORE_DIR`
  (default `~/.cache/obsidian/platformio`), shared by every worktree and kept
  across image rebuilds.

```
tools/container.sh create      # first time: build image, create distrobox, prefetch toolchains
tools/container.sh recreate    # after editing the Containerfile
tools/container.sh status      # image, distrobox, pinned versions
tools/container.sh enter       # a shell inside the toolbox
```

`OBSIDIAN_HOST_TOOLS=1` skips the toolbox and uses whatever is on `PATH`.

## `verify.sh`

```
tools/verify.sh --fix                # boards touched by uncommitted changes; fix formatting
tools/verify.sh atmega               # one board (xiao | atmega | all)
tools/verify.sh --only build,test    # a subset of secrets,docs,specs,format,rules,lint,build,test
tools/verify.sh all --all-files      # everything (CI, before archiving a change)
tools/test.sh xiao                   # same as --only test
```

Output is one line per step, then `VERIFY PASS` or `VERIFY FAIL`:

```
verify: boards=atmega steps=secrets,docs,specs,format,rules,lint,build,test changed_files=3
PASS  secrets        83 files, no local env file, 0s
PASS  docs           links, 0s
PASS  specs          openspec validate --strict, 1s
PASS  format         2 files, 0s
FAIL  rules          1 violations in 14 files, 0s  [log: .verify/rules.log]
    firmware/atmega/src/motor.cpp:41: [avr-float] no floats on the ATmega — use 32-bit integer or fixed-point math
PASS  lint:atmega    cppcheck, 6 files, 1s
PASS  build:atmega   RAM 214/1536 B, flash 4102/28672 B, 2s
PASS  test:atmega    17 test cases: 17 succeeded, 1s
VERIFY FAIL (1 of 8 steps failed)
```

A failing step shows up to `VERIFY_MAX_LINES` (default 25) matching error
lines. A board without `firmware/<board>/platformio.ini` is `SKIP`ped. The
ATmega build fails if it exceeds the size budget. Full logs are in
`.verify/<step>.log`; don't read them directly, use `log.sh`. Tool details:
[docs/reference/toolchain.md](../docs/reference/toolchain.md).

## `log.sh`

```
tools/log.sh                         # the last run's step results
tools/log.sh build:xiao              # first errors of that step, 3 lines of context
tools/log.sh test:atmega -n 30 -C 1
```

Use it when the `verify.sh` summary isn't enough to fix a failure. Fix the
first error first: later errors often follow from it.

## `diff.sh` and `outline.sh`

```
tools/diff.sh                        # uncommitted work vs HEAD, new files included
tools/diff.sh origin/main...HEAD     # a whole branch; lists files if over 400 lines
tools/diff.sh HEAD~1 firmware/atmega/src/motor.cpp
tools/outline.sh firmware/atmega/src/cmd_handler.cpp
```

Generated files (`sdkconfig*`, `compile_commands.json`, `.pio/`) are skipped.

## `check-secrets.py`

Scans tracked and unignored files for key-shaped strings, for literal
`apiKey`/`baseURL` values in `opencode.json` (they must be `{env:NAME}`), and
for every value in the local secrets file (`OBSIDIAN_ENV_FILE`, default
`~/.config/litellm/obsidian.env`) and its hostname. Findings
name the file, line and variable, never the value. `secrets-ok` in a comment
accepts a false positive.

## `check-docs.py`

```
tools/check-docs.py                  # AGENTS.md, CLAUDE.md, README.md, docs/, openspec/, tools/, .github/
tools/check-docs.py docs/hardware
```

Prints `path:line: missing file|heading: target` per broken relative link,
then `docs: OK` or `docs: FAIL`.

## `check-rules.py`

`verify.sh` runs this as its `rules` step; run it alone with
`tools/check-rules.py [xiao] [atmega]`. Each violation reads
`path:line: [rule-id] problem — fix`. The rules:

| Rule | Checks |
| --- | --- |
| `avr-std` | ATmega and `shared/` code uses no `<cstdint>`-style headers and no `std::` |
| `avr-heap` | no `malloc`/`free`/`new`/`delete` on the ATmega |
| `avr-float` | no `float`/`double` on the ATmega |
| `avr-shift` | no `1 << n` / `1U << n` with n ≥ 15 or a variable n (16-bit `int`) |
| `avr-flash-str` | ATmega log literals use `log_println_P(PSTR("..."))` |
| `shared-c` | `firmware/shared/` has no C++-only syntax |
| `guard` | headers start with `#ifndef X_H` / `#define X_H`; no `#pragma once` |
| `doxygen` | each function declared in a header has `/** */` with `@param` and `@return` |
| `no-block` | only `main.cpp` and `hal/` may call `delay_ms`/`vTaskDelay` |
| `no-rtos` | no `xTaskCreate`/`xTimerCreate`/`esp_timer_create` on the XIAO |
| `protocol` | no `0x7E` literal or `#define PROTOCOL_*` outside `protocol.h` |
| `test-name` | tests in `test_<module>.cpp` are named `test_<module>_<behavior>` |
| `test-register` | every test is `RUN_TEST()`-registered in `test/test_main.cpp`, and vice versa |

Code inside `#ifndef ARDUINO`, `#ifdef UNIT_TEST` and the `#else` of
`#ifdef ARDUINO` counts as host-only and is exempt from the AVR rules. When a
change's `design.md` explicitly allows an exception (for example, "create a
FreeRTOS task"), mark the line with a comment containing `rules-ok: <rule-id>`.
