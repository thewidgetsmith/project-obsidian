# dev-tooling Specification

## Purpose

The verification tools in `tools/` that developers, AI agents and CI share: one
pinned toolbox image, and check scripts that print little on success and only
the relevant errors on failure, so an agent's context is not flooded.

## Requirements

### Requirement: Single toolbox image

All checks SHALL run with the tools from one image defined in
`tools/container/Containerfile`, with PlatformIO and OpenSpec at pinned
versions. Locally the image SHALL run as the `obsidian-dev` distrobox; CI
SHALL run the same image.

#### Scenario: Script started on the host

- **WHEN** a `tools/*.sh` check script is started on the host and the `obsidian-dev` distrobox exists
- **THEN** it re-runs itself inside the distrobox with the same arguments and working directory

#### Scenario: Toolbox missing

- **WHEN** a check script is started on the host and the distrobox does not exist
- **THEN** it exits non-zero with one line naming `tools/container.sh create`

#### Scenario: Host tools override

- **WHEN** `OBSIDIAN_HOST_TOOLS=1` is set
- **THEN** the script runs on the host and takes every tool from `PATH`

### Requirement: Shared PlatformIO packages

PlatformIO packages and toolchains SHALL be stored in `PLATFORMIO_CORE_DIR`,
defaulting to `~/.cache/obsidian/platformio`, so every git worktree and every
rebuilt container reuses one download.

#### Scenario: New worktree

- **WHEN** `tools/verify.sh` runs in a newly created worktree on a machine that has built before
- **THEN** no platform or toolchain is downloaded again

### Requirement: Single quality gate

`tools/verify.sh` (also run as `tools/check.sh`) SHALL run the steps
secrets, docs, specs, format, rules, lint, build and test, print one `PASS`,
`FAIL` or `SKIP` line per step, and end with `VERIFY PASS` or `VERIFY FAIL`.
Its exit status SHALL be 0 only on `VERIFY PASS`. `tools/format.sh`,
`tools/lint.sh`, `tools/build.sh` and `tools/test.sh` SHALL run the single
step of the same name. No printed line SHALL exceed `VERIFY_MAX_COLS`
(default 240) characters.

#### Scenario: Everything passes

- **WHEN** every step passes
- **THEN** the output is at most one line per step plus the header and the `VERIFY PASS` line, and the exit status is 0

#### Scenario: A step fails

- **WHEN** a step fails
- **THEN** its line reads `FAIL`, at most `VERIFY_MAX_LINES` (default 25) matching error lines follow it, the full output is in `.verify/<step>.log`, and the exit status is 1

#### Scenario: Board not scaffolded

- **WHEN** `firmware/<board>/platformio.ini` does not exist
- **THEN** that board's lint, build and test steps print `SKIP` and do not fail the run

#### Scenario: Board selection

- **WHEN** no board is given
- **THEN** only boards with uncommitted changes under `firmware/<board>/` are checked, and both boards when `firmware/shared/` changed or nothing under `firmware/` changed

### Requirement: Failure detail on demand

`tools/log.sh STEP` SHALL print the first error lines of one step's log with
context, bounded by `-n` lines (default 60), and never the whole log.

#### Scenario: Inspect a failed build

- **WHEN** `tools/log.sh build:xiao` runs after a failed build
- **THEN** it prints at most 60 lines, starting with the first error and its context

### Requirement: Project conventions are checked

`tools/check-rules.py` SHALL check the `AGENTS.md` conventions that compilers
miss and print one `path:line: [rule-id] message` line per violation. A
`rules-ok: <rule-id>` comment on the line or the line above SHALL accept a
deliberate exception.

#### Scenario: Float in ATmega code

- **WHEN** a file under `firmware/atmega/src/` declares a `float`
- **THEN** the rules step fails with an `[avr-float]` line naming the file and line

### Requirement: Specs and docs are checked

The docs step SHALL fail on any broken relative Markdown link, and the specs
step SHALL fail when `openspec validate --all --strict` fails.

#### Scenario: Broken link

- **WHEN** a Markdown file under `docs/` links to a file that does not exist
- **THEN** the docs step fails and names the file, line and target

#### Scenario: Requirement without a scenario

- **WHEN** a spec or change delta has a requirement with no `#### Scenario:`
- **THEN** the specs step fails

### Requirement: ATmega size budget

The ATmega build step SHALL fail when flash use exceeds 28672 bytes or SRAM
use exceeds 1536 bytes, and its line SHALL show both against the budget.

#### Scenario: Over budget

- **WHEN** the ATmega build reports 1600 bytes of RAM
- **THEN** the build step fails with a `BUDGET:` line

### Requirement: No secrets in the repo

`tools/check-secrets.py` SHALL fail when a tracked or unignored file contains
a key-shaped string, a literal `apiKey` or `baseURL` in `opencode.json`
(anything but `{env:NAME}`), or any value or hostname from the local secrets
file `~/.config/litellm/obsidian.env`. Findings SHALL name the
file, line and variable but never print the secret.

#### Scenario: Hostname leaked into a doc

- **WHEN** a Markdown file contains the hostname of `LITELLM_BASE_URL` from the local secrets file
- **THEN** the secrets step fails with `[env-value] value of LITELLM_BASE_URL` and the value is not printed

#### Scenario: Literal key in agent config

- **WHEN** `opencode.json` sets `apiKey` to a literal string
- **THEN** the secrets step fails with a `[config-literal]` line

### Requirement: Agent launcher loads secrets

`tools/opencode.sh` SHALL load `~/.config/litellm/obsidian.env`
(or `OBSIDIAN_ENV_FILE`), require `LITELLM_BASE_URL` and `LITELLM_API_KEY`,
and start OpenCode with a private server so the variables reach it.

#### Scenario: Missing secrets file

- **WHEN** the secrets file does not exist
- **THEN** the launcher exits non-zero naming the file and `tools/obsidian.env.example`

### Requirement: Review-sized reading tools

`tools/diff.sh [RANGE] [PATH]` SHALL print a diff without generated files,
including new untracked files when RANGE is `HEAD`, and SHALL print only a
per-file line count when the diff exceeds `DIFF_MAX_LINES` (default 400) and
no PATH is given. `tools/outline.sh FILE` SHALL print at most 80 lines of
functions, types, macros or headings with line numbers.

#### Scenario: Large diff

- **WHEN** `tools/diff.sh origin/main...HEAD` covers 2000 changed lines
- **THEN** it prints one line per file with its added and removed line counts
