# AGENTS.md

Project Obsidian is firmware for a Mecanum-wheel rover with two MCUs joined by
a UART link. Overview: [README.md](README.md). How work flows:
[docs/workflow.md](docs/workflow.md).

| Path | What |
| --- | --- |
| `firmware/xiao/` | XIAO ESP32-S3 Sense, ESP-IDF via PlatformIO — camera, Wi-Fi web UI, I2S audio, SD, UART link manager |
| `firmware/atmega/` | ATmega328P, Arduino via PlatformIO — motor PWM, Mecanum kinematics, gimbal servo, battery ADC |
| `firmware/shared/protocol.h` | UART wire protocol — single source of truth, header-only, C-compatible |
| `openspec/specs/` | What the firmware does today (capabilities, requirements, scenarios) |
| `openspec/changes/` | Proposed work: `proposal.md`, delta `specs/`, `design.md`, `tasks.md` |
| `docs/hardware/` | Pin maps and wiring — the only place GPIO assignments are decided |
| `docs/reference/` | Board-tree layout rules and toolchain details |
| `tools/` | Verification scripts shared by agents and CI ([tools/README.md](tools/README.md)) |
| `.opencode/agents/` | OpenCode agent definitions (orchestrator and helpers) |
| `.agents/skills/` | OpenSpec skills, the single copy; OpenCode reads it directly, `.claude/skills/` links to it. `openspec update` regenerates it |
| `.claude/` | Claude Code settings and its guide, `spec-planning.md` |

## Your Role

**OpenCode agents** are defined in [.opencode/agents/](.opencode/agents/) ; each file's front matter sets its model,
step budget and permissions. Start OpenCode with `tools/opencode.sh`, which
loads the LiteLLM secrets.

| Agent | Role |
| --- | --- |
| [orchestrator](.opencode/agents/orchestrator.md) | Primary. Carries one OpenSpec change from tasks to an open PR by calling the helpers below; commits per task |
| [planner](.opencode/agents/planner.md) | Turns one task into steps and acceptance criteria |
| [developer](.opencode/agents/developer.md) | Implements one planned task with its tests |
| [reviewer](.opencode/agents/reviewer.md) | Reviews one task's diff |
| [auditor](.opencode/agents/auditor.md) | Safety, security and secrets audit of a whole change |
| [reviewer-claude](.opencode/agents/reviewer-claude.md), [reviewer-deepseek](.opencode/agents/reviewer-deepseek.md) | Independent whole-change reviews |
| [author](.opencode/agents/author.md) | Docs and changelog |
| [researcher](.opencode/agents/researcher.md) | One factual question |
| [reasoner](.opencode/agents/reasoner.md) | Hard decisions and repeated failures |

**Claude Code** writes and reviews OpenSpec changes (proposal, specs,
design, tasks) and archives them after merge:
[.claude/spec-planning.md](.claude/spec-planning.md).

## Tooling

Use these instead of composing your own `pio`, `clang-tidy`, `cppcheck` or
log-grepping commands. The shell scripts run inside the `obsidian-dev`
toolbox on their own, print `PASS`/`OK` or one line per step on success and
only the relevant lines on failure. Details: [tools/README.md](tools/README.md).

| Command | Use |
| --- | --- |
| `tools/check.sh --fix` | The check: secrets, docs, specs, format, rules, lint, build and unit tests for the boards your changes touch. Work is done only when it ends with `VERIFY PASS`. (`tools/verify.sh` is the same script.) |
| `tools/test.sh` / `build.sh` / `lint.sh` / `format.sh` `[xiao\|atmega\|all]` | One step of the check |
| `tools/log.sh STEP` | The first errors of one failed step (e.g. `build:xiao`), with context |
| `tools/diff.sh [RANGE] [PATH]` | A review-sized diff (default `HEAD`: uncommitted work, new files included); lists files when large |
| `tools/outline.sh FILE` | Functions, types, macros or headings with line numbers, before reading a big file |
| `tools/check-secrets.py` | Fails if a key, token or value from the local secrets file is in the repo |
| `tools/pr.sh TITLE BODY_FILE` | Opens a PR for the pushed branch (orchestrator only) |
| `openspec list` / `status` / `show` / `validate` / `instructions` | Read and check changes and specs |

Never hand-format code (`--fix` does it), never read `.verify/*.log` whole,
and never run `pio` yourself. If a tool says the toolbox is missing, stop and
tell the user to run `tools/container.sh create`. Never install tools, call
`distrobox` or use `sudo`.

## Conventions

`tools/verify.sh` checks most of these; a violation names its rule, e.g.
`[avr-float]`.

- Language: both boards are C++17 (gnu++17). AVR has no C++ standard
  library: in ATmega and `firmware/shared/` code use `<stdint.h>`, never
  `<cstdint>` or `std::`. `firmware/shared/` must also compile as C.
- Names: HAL and utilities are in `obsidian::hal` / `obsidian::utils`. Module
  APIs are free functions prefixed by module (`link_mgr_poll`,
  `cmd_handler_init`). `shared/` uses the `protocol_` prefix and no namespace.
- Headers: `#ifndef MODULE_H` include guards; Doxygen `@param`/`@return` on
  public declarations; section rulers `// ─── Name ───`.
- Config: tunables are `CONFIG_*` macros in each board's `include/config.h`.
  Protocol constants live only in `protocol.h` — never duplicate them.
- Hardware access only through `hal::`, so modules compile in the host tests
  (`-DUNIT_TEST`, mocks in `test/test_mock_*.cpp`).
- ATmega: no heap, floats, exceptions, or RTTI; 32-bit integer math; static
  buffers. `int` is 16 bits: shift `uint32_t` values, not `1U`. Log with
  `utils::log_println_P(PSTR("..."))` so strings stay in flash. Budget
  ≤ 28 KB flash, ≤ 1.5 KB SRAM.
- XIAO: never block the main loop; no new FreeRTOS tasks or timers unless the
  change's `design.md` says so.
- Tests: Unity, named `test_<module>_<behavior>`, registered in
  `test/test_main.cpp`. Each task adds tests for the code it adds.
- OpenSpec artifacts refer to files as backticked repo-root paths, never
  relative links (they move when a change is archived).

## Rules

- No new third-party dependencies without the user's approval.
- Specs change only through an OpenSpec change that the user approves.
  `docs/hardware/` changes only when the user confirms the wiring.
- Hardware-in-the-loop (HIL) checks need the user: list them, never claim
  them, never tick them.
- Same failure 3 times → stop and report the failing lines.
- Keep tool output small: use the tools, `grep` and line ranges; never dump
  large files or logs. Never `grep`/`find` inside `.pio/`, and add
  `--exclude-dir=.pio` to recursive greps. Never read `sdkconfig.*` whole.
- Only the orchestrator commits (one commit per task, on the change's
  branch), pushes that branch and opens its PR. No other agent commits,
  pushes or creates branches unless the user asks. Never push to `main` or
  force-push.
- Secrets (the LiteLLM URL and key) live only in
  `~/.config/litellm/obsidian.env` and are read through
  `{env:NAME}`. Never read that file, print environment variables, or write a
  secret into the repo; `tools/check-secrets.py` must pass.
