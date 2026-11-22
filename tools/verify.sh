#!/usr/bin/env bash
#
# tools/verify.sh — the single quality gate for Obsidian, for agents and CI.
#
# Runs secrets, docs, specs, format, project rules, lint, build, and host unit tests for
# the boards affected by uncommitted changes and prints one PASS/FAIL/SKIP line
# per step. On failure it prints only the relevant error lines; the full output
# of every step is saved under .verify/ (git-ignored), so an AI agent's context
# is not flooded with build logs.
#
# Started on the host, it re-runs itself inside the obsidian-dev toolbox
# (tools/lib/env.sh); CI runs it inside the same image.

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/env.sh"
toolbox_reexec "$@"

usage() {
    cat <<'EOF'
Usage: tools/verify.sh [BOARD...] [options]

Boards:
  xiao | atmega | all   default: boards touched by uncommitted changes
                        (both if firmware/shared/ changed or nothing changed)
Options:
  --fix          apply clang-format to the checked files first
  --all-files    format-check every source file, not just changed ones
  --only LIST    comma-separated subset of: secrets,docs,specs,format,rules,lint,build,test
  -h, --help     show this help

Prints one PASS/FAIL/SKIP line per step and ends with "VERIFY PASS" or
"VERIFY FAIL". Exit status is 0 only on VERIFY PASS.
Logs: .verify/<step>.log   Summary: .verify/summary.txt
Details of a failed step: tools/log.sh <step>
Shortcuts: tools/format.sh, tools/lint.sh, tools/build.sh, tools/test.sh
EOF
}

cd "$ROOT" || exit 2

LOG_DIR="$ROOT/.verify"

MAX_LINES="${VERIFY_MAX_LINES:-25}"
# Long lines (CMake component lists) are cut so one line can't flood a context.
MAX_COLS="${VERIFY_MAX_COLS:-240}"

# ATmega size budget (AGENTS.md): flash <= 28 KB, SRAM <= 1.5 KB.
ATMEGA_FLASH_MAX=28672
ATMEGA_RAM_MAX=1536

boards=()
steps="secrets,docs,specs,format,rules,lint,build,test"
fix=0
all_files=0

# ─── Arguments ────────────────────────────────────────────────

while [ $# -gt 0 ]; do
    case "$1" in
        xiao | atmega) boards+=("$1") ;;
        all) boards=(xiao atmega) ;;
        --fix) fix=1 ;;
        --all-files) all_files=1 ;;
        --only)
            if [ $# -lt 2 ]; then
                echo "verify.sh: --only needs a list" >&2
                exit 2
            fi
            steps="$2"
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "verify.sh: unknown argument '$1'" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

IFS=',' read -ra step_list <<<"$steps"
for s in "${step_list[@]}"; do
    case "$s" in
        secrets | docs | specs | format | rules | lint | build | test) ;;
        *)
            echo "verify.sh: unknown step '$s' (use secrets,docs,specs,format,rules,lint,build,test)" >&2
            exit 2
            ;;
    esac
done

want() { [[ ",$steps," == *",$1,"* ]]; }

has_board() {
    local b
    for b in "${boards[@]}"; do
        [ "$b" = "$1" ] && return 0
    done
    return 1
}

# A board without a PlatformIO project (not scaffolded yet) is skipped.
has_project() { [ -f "firmware/$1/platformio.ini" ]; }

# ─── Helpers ──────────────────────────────────────────────────

# Run a tool from PATH. A missing tool almost always means the command is
# running on the host instead of in the dev container.
run_tool() {
    if command -v "$1" >/dev/null 2>&1; then
        "$@"
    else
        echo "verify.sh: '$1' not found. Rebuild the toolbox: tools/container.sh recreate" >&2
        return 127
    fi
}

# run_logged LOG CMD... — run CMD, write ANSI-stripped output to LOG.
run_logged() {
    local log=$1
    shift
    "$@" 2>&1 | sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' >"$log"
    return "${PIPESTATUS[0]}"
}

failures=0
total=0

say() { printf '%s\n' "$*" | tee -a "$LOG_DIR/summary.txt"; }

skip() { say "$(printf 'SKIP  %-14s %s' "$1" "$2")"; }

# report NAME STATUS LOG DETAIL FILTER_REGEX
report() {
    local name=$1 status=$2 log=$3 detail=$4 filter=$5 lines
    total=$((total + 1))
    if [ "$status" -eq 0 ]; then
        say "$(printf 'PASS  %-14s %s' "$name" "$detail")"
        return
    fi
    failures=$((failures + 1))
    say "$(printf 'FAIL  %-14s %s  [log: %s]' "$name" "$detail" "${log#"$ROOT"/}")"
    lines=$(grep -E "$filter" "$log" | head -n "$MAX_LINES")
    [ -n "$lines" ] || lines=$(tail -n "$MAX_LINES" "$log")
    printf '%s\n' "$lines" | cut -c "1-$MAX_COLS" | sed 's/^/    /' | tee -a "$LOG_DIR/summary.txt"
}

is_source() {
    case "$1" in
        *.c | *.cpp | *.h) return 0 ;;
    esac
    return 1
}

# ─── Scope: changed files and boards ──────────────────────────

mapfile -t changed < <(
    {
        git diff --name-only HEAD -- firmware 2>/dev/null
        git ls-files --others --exclude-standard -- firmware 2>/dev/null
    } | sort -u
)

if [ ${#boards[@]} -eq 0 ]; then
    for f in "${changed[@]}"; do
        case "$f" in
            firmware/xiao/*) has_board xiao || boards+=(xiao) ;;
            firmware/atmega/*) has_board atmega || boards+=(atmega) ;;
            *)
                boards=(xiao atmega)
                break
                ;;
        esac
    done
    [ ${#boards[@]} -gt 0 ] || boards=(xiao atmega)
fi

format_dirs=(firmware/shared)
has_board xiao && format_dirs+=(firmware/xiao/src firmware/xiao/include firmware/xiao/test)
has_board atmega && format_dirs+=(firmware/atmega/src firmware/atmega/include firmware/atmega/test)

in_format_dirs() {
    local d
    for d in "${format_dirs[@]}"; do
        [[ "$1" == "$d"/* ]] && return 0
    done
    return 1
}

fmt_files=()
if [ "$all_files" -eq 1 ]; then
    mapfile -t fmt_files < <(find "${format_dirs[@]}" -type f \
        \( -name '*.c' -o -name '*.cpp' -o -name '*.h' \) 2>/dev/null | sort)
else
    for f in "${changed[@]}"; do
        if [ -f "$f" ] && is_source "$f" && in_format_dirs "$f"; then
            fmt_files+=("$f")
        fi
    done
fi

mkdir -p "$LOG_DIR"
: >"$LOG_DIR/summary.txt"
say "verify: boards=${boards[*]} steps=$steps changed_files=${#changed[@]}"

# ─── Secrets (tools/check-secrets.py) ─────────────────────────

if want secrets; then
    log="$LOG_DIR/secrets.log"
    t0=$SECONDS
    run_logged "$log" run_tool python3 tools/check-secrets.py
    st=$?
    report secrets "$st" "$log" "$(grep -oE '[0-9]+ files[^)]*' "$log" | tail -n 1), $((SECONDS - t0))s" \
        '\] |not found|Error'
fi

# ─── Docs (broken links; tools/check-docs.py) ──────────────────

if want docs; then
    log="$LOG_DIR/docs.log"
    t0=$SECONDS
    run_logged "$log" run_tool python3 tools/check-docs.py
    st=$?
    report docs "$st" "$log" "links, $((SECONDS - t0))s" '^[^ ].*:[0-9]+:|not found|Error'
fi

# ─── Specs (openspec validate) ────────────────────────────────

if want specs; then
    if [ ! -d openspec ]; then
        skip specs "no openspec/"
    else
        log="$LOG_DIR/specs.log"
        t0=$SECONDS
        run_logged "$log" run_tool openspec validate --all --strict --no-interactive
        st=$?
        report specs "$st" "$log" "openspec validate --strict, $((SECONDS - t0))s" \
            '✗|ERROR|WARN|[Ee]rror|not found'
    fi
fi

# ─── Format (clang-format) ────────────────────────────────────

if want format; then
    if [ ${#fmt_files[@]} -eq 0 ]; then
        skip format "no changed source files"
    else
        log="$LOG_DIR/format.log"
        t0=$SECONDS
        if [ "$fix" -eq 1 ]; then
            run_logged "$LOG_DIR/format-fix.log" run_tool clang-format -i "${fmt_files[@]}"
        fi
        run_logged "$log" run_tool clang-format --dry-run --Werror "${fmt_files[@]}"
        st=$?
        detail="${#fmt_files[@]} files, $((SECONDS - t0))s"
        [ "$st" -eq 0 ] || detail="$detail — rerun with --fix"
        report format "$st" "$log" "$detail" 'error:|not found'
    fi
fi

# ─── Rules (AGENTS.md conventions; tools/check-rules.py) ───────

if want rules; then
    log="$LOG_DIR/rules.log"
    t0=$SECONDS
    run_logged "$log" run_tool python3 tools/check-rules.py "${boards[@]}"
    st=$?
    report rules "$st" "$log" "$(grep -oE '[0-9]+ (violations in [0-9]+ )?files' "$log" | tail -n 1), $((SECONDS - t0))s" \
        '\] |not found|Error'
fi

# ─── Lint (clang-tidy for XIAO, cppcheck for ATmega) ──────────

if want lint && has_board xiao && ! has_project xiao; then
    skip lint:xiao "no firmware/xiao/platformio.ini"
elif want lint && has_board xiao; then
    mapfile -t files < <(find firmware/xiao/src -type f -name '*.cpp' | sort)
    log="$LOG_DIR/lint-xiao.log"
    t0=$SECONDS
    # Flags after `--` stop clang-tidy from loading compile_commands.json: the
    # ESP-IDF database (pio run -t compiledb) targets Xtensa, which stock clang
    # can't parse.
    run_logged "$log" run_tool clang-tidy --quiet --config-file=firmware/xiao/.clang-tidy \
        "${files[@]}" -- -std=gnu++17 -Ifirmware/xiao/include -Ifirmware/shared
    st=$?
    report lint:xiao "$st" "$log" "clang-tidy, ${#files[@]} files, $((SECONDS - t0))s" \
        '(error|warning):|not found'
fi

if want lint && has_board atmega && ! has_project atmega; then
    skip lint:atmega "no firmware/atmega/platformio.ini"
elif want lint && has_board atmega; then
    mapfile -t files < <(find firmware/atmega/src -type f -name '*.cpp' | sort)
    log="$LOG_DIR/lint-atmega.log"
    t0=$SECONDS
    run_logged "$log" run_tool cppcheck --enable=all --std=c++17 --quiet --inline-suppr \
        --suppressions-list=firmware/atmega/.cppcheck-suppressions \
        --template='{file}:{line}: {severity}: {message} [{id}]' "${files[@]}"
    st=$?
    # cppcheck's exit code ignores findings, so fail on any non-informational one.
    findings=': (error|warning|style|performance|portability): '
    if [ "$st" -eq 0 ] && grep -qE "$findings" "$log"; then
        st=1
    fi
    report lint:atmega "$st" "$log" "cppcheck, ${#files[@]} files, $((SECONDS - t0))s" \
        "$findings|not found"
fi

# ─── Build (PlatformIO firmware envs) ─────────────────────────

# used_bytes LOG KIND — bytes used from PlatformIO's "RAM:"/"Flash:" line.
used_bytes() {
    grep -E "^$2:" "$1" | grep -oE 'used [0-9]+' | grep -oE '[0-9]+' | tail -n 1
}

build_board() { # build_board BOARD ENV
    local log="$LOG_DIR/build-$1.log" t0=$SECONDS st ram flash usage_info
    if ! has_project "$1"; then
        skip "build:$1" "no firmware/$1/platformio.ini"
        return
    fi
    run_logged "$log" run_tool pio run -d "firmware/$1" -e "$2"
    st=$?
    ram=$(used_bytes "$log" RAM)
    flash=$(used_bytes "$log" Flash)
    usage_info="${ram:+RAM ${ram} B, flash ${flash} B}"
    if [ "$st" -eq 0 ] && [ "$1" = atmega ] && [ -n "$ram" ]; then
        usage_info="RAM ${ram}/${ATMEGA_RAM_MAX} B, flash ${flash}/${ATMEGA_FLASH_MAX} B"
        if [ "$flash" -gt "$ATMEGA_FLASH_MAX" ] || [ "$ram" -gt "$ATMEGA_RAM_MAX" ]; then
            echo "BUDGET: over the ATmega budget (flash ${flash}/${ATMEGA_FLASH_MAX} B," \
                "RAM ${ram}/${ATMEGA_RAM_MAX} B) — shrink buffers, move strings to flash" >>"$log"
            st=1
        fi
    fi
    report "build:$1" "$st" "$log" "${usage_info:-$2}, $((SECONDS - t0))s" \
        '(error|warning):|undefined reference|Error [0-9]|CMake Error|FAILED:|fatal:|BUDGET:|not found'
}

if want build; then
    has_board xiao && build_board xiao xiao_esp32s3
    has_board atmega && build_board atmega atmega328p
fi

# ─── Test (PlatformIO native Unity envs) ──────────────────────

test_board() { # test_board BOARD ENV
    local log="$LOG_DIR/test-$1.log" t0=$SECONDS st result
    if ! has_project "$1"; then
        skip "test:$1" "no firmware/$1/platformio.ini"
        return
    fi
    run_logged "$log" run_tool pio test -d "firmware/$1" -e "$2"
    st=$?
    result=$(grep -oE '[0-9]+ test cases?: [^=]*' "$log" | tail -n 1 | sed -E 's/ in [0-9:.]+ *$//')
    report "test:$1" "$st" "$log" "${result:-$2}, $((SECONDS - t0))s" \
        ':FAIL|FAILED|(error|warning):|undefined reference|not found'
}

if want test; then
    has_board xiao && test_board xiao test_xiao_esp32s3
    has_board atmega && test_board atmega test_atmega328p
fi

# ─── Result ───────────────────────────────────────────────────

if [ "$failures" -eq 0 ]; then
    say "VERIFY PASS ($total steps)"
    exit 0
else
    say "VERIFY FAIL ($failures of $total steps failed)"
    exit 1
fi
