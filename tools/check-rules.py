#!/usr/bin/env python3
"""tools/check-rules.py — check the AGENTS.md conventions that compilers miss.

Usage: tools/check-rules.py [xiao] [atmega]     (default: both)

firmware/shared/ is always checked. Prints one line per violation:

    path:line: [rule-id] what is wrong — how to fix it

and ends with "rules: OK" or "rules: FAIL". Exit status is 0 only when there
are no violations.

To accept a deliberate exception (for example, a design.md that calls for a
FreeRTOS task), put `rules-ok: <rule-id>` in a comment on that line or the
line above it.

Rules
  avr-std        ATmega/shared device code: no <cstdint>-style headers, no std::
  avr-heap       ATmega/shared: no malloc/free/new/delete
  avr-float      ATmega/shared: no float/double
  avr-shift      ATmega/shared: 1/1U << n overflows 16-bit int unless n < 16
  avr-flash-str  ATmega: log string literals go through log_println_P(PSTR(...))
  shared-c       shared/: must also compile as C (no namespace, class, std:: …)
  guard          headers use #ifndef X_H / #define X_H, never #pragma once
  doxygen        public header declarations need /** */ with @param / @return
  no-block       modules other than main.cpp and hal/ must not delay
  no-rtos        XIAO: no new FreeRTOS tasks or timers
  protocol       protocol constants live only in firmware/shared/protocol.h
  test-name      tests in test_<module>.cpp are named test_<module>_<behavior>
  test-register  every test is RUN_TEST()-registered in test/test_main.cpp
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FW = ROOT / "firmware"

violations = []


def report(path, line, rule, msg):
    violations.append(f"{path.relative_to(ROOT)}:{line}: [{rule}] {msg}")


# ─── Source preprocessing ─────────────────────────────────────


def strip_comments(text):
    """Return lines with comments removed and string contents blanked.

    String literals keep their quotes ("" remains) so rules can still see
    that a literal was passed. Line structure is preserved.
    """
    out, i, n = [], 0, len(text)
    state = None  # None, "line", "block", '"', "'"
    while i < n:
        c, nxt = text[i], text[i + 1] if i + 1 < n else ""
        if state is None:
            if c == "/" and nxt == "/":
                state, i = "line", i + 2
                continue
            if c == "/" and nxt == "*":
                state, i = "block", i + 2
                continue
            if c in "\"'":
                state = c
            out.append(c)
        elif state == "line":
            if c == "\n":
                state = None
                out.append(c)
        elif state == "block":
            if c == "*" and nxt == "/":
                state, i = None, i + 2
                continue
            if c == "\n":
                out.append(c)
        else:  # inside a string or char literal
            if c == "\\":
                i += 2
                continue
            if c == state:
                state = None
                out.append(c)
            elif c == "\n":
                state = None
                out.append(c)
        i += 1
    return "".join(out).split("\n")


DEVICE_MACROS = ("ARDUINO", "__AVR__", "ESP_PLATFORM")
HOST_MACROS = ("UNIT_TEST",)


def host_only_lines(code_lines):
    """Flag lines compiled only in the host test build (e.g. #else of #ifdef ARDUINO)."""
    flags, stack = [], []  # stack of True (host-only), False (device-only), None
    for line in code_lines:
        s = line.strip()
        m = re.match(r"#\s*(ifdef|ifndef|if|elif|else|endif)\b\s*(.*)", s)
        if m:
            kind, cond = m.groups()
            if kind in ("ifdef", "ifndef", "if"):
                name = re.sub(r"defined\s*\(?\s*(\w+)\s*\)?", r"\1", cond).strip()
                negated = kind == "ifndef" or name.startswith("!")
                name = name.lstrip("!").strip()
                if name in DEVICE_MACROS:
                    stack.append(negated)
                elif name in HOST_MACROS:
                    stack.append(not negated)
                else:
                    stack.append(None)
            elif kind in ("else", "elif") and stack:
                top = stack.pop()
                stack.append(None if top is None or kind == "elif" else not top)
            elif kind == "endif" and stack:
                stack.pop()
        flags.append(any(v is True for v in stack))
    return flags


class Source:
    def __init__(self, path):
        self.path = path
        self.raw = path.read_text(encoding="utf-8", errors="replace").split("\n")
        self.code = strip_comments("\n".join(self.raw))
        self.host = host_only_lines(self.code)

    def allowed(self, idx, rule):
        tag = f"rules-ok: {rule}"
        return tag in self.raw[idx] or (idx > 0 and tag in self.raw[idx - 1])

    def grep(self, rule, pattern, msg, device_only=False, check=None):
        rx = re.compile(pattern)
        for idx, line in enumerate(self.code):
            if device_only and self.host[idx]:
                continue
            for m in rx.finditer(line):
                if check and not check(m):
                    continue
                if not self.allowed(idx, rule):
                    report(self.path, idx + 1, rule, msg)
                break


def sources(*dirs, exts=(".c", ".cpp", ".h")):
    for d in dirs:
        if d.is_dir():
            for p in sorted(d.rglob("*")):
                if p.suffix in exts and ".pio" not in p.parts and not p.name.startswith("_"):
                    yield p


# ─── Rules ────────────────────────────────────────────────────


def check_avr(src, shared=False):
    std_msg = "AVR has no C++ standard library — use <stdint.h>/<stddef.h>/<string.h>, no std::"
    src.grep("avr-std", r"#\s*include\s*<c[a-z]+>", std_msg, device_only=True)
    src.grep("avr-std", r"\bstd::", std_msg, device_only=True)
    src.grep(
        "avr-heap",
        r"\b(malloc|calloc|realloc|free)\s*\(|\bnew\s+[A-Za-z_(]|\bdelete\b",
        "no heap on the ATmega — use static buffers",
        device_only=True,
    )
    src.grep(
        "avr-float",
        r"\b(float|double)\b",
        "no floats on the ATmega — use 32-bit integer or fixed-point math",
        device_only=True,
    )
    src.grep(
        "avr-shift",
        r"(?<![\w.])1[uU]?(?![\w.])\s*<<\s*(\w+)",
        "int is 16 bits on AVR — shift a uint32_t, e.g. (uint32_t)1 << n",
        device_only=True,
        check=lambda m: not (m.group(1).isdigit() and int(m.group(1)) < 15),
    )
    if not shared:
        src.grep(
            "avr-flash-str",
            r"\b(log_print|log_println|Serial\.print|Serial\.println)\s*\(\s*\"",
            'string literal in SRAM — use utils::log_println_P(PSTR("..."))',
            device_only=True,
        )


def check_shared_c(src):
    src.grep(
        "shared-c",
        r"\b(namespace|class|template|nullptr|constexpr|static_cast|reinterpret_cast|"
        r"const_cast|std::)\b|#\s*include\s*<c[a-z]+>",
        "firmware/shared/ must compile as C — no C++-only syntax or <c...> headers",
    )


def check_guard(src):
    for idx, line in enumerate(src.raw):
        if re.match(r"\s*#\s*pragma\s+once", line) and not src.allowed(idx, "guard"):
            report(src.path, idx + 1, "guard", "use #ifndef X_H / #define X_H, not #pragma once")
    directives = [(i, l.strip()) for i, l in enumerate(src.code) if l.strip().startswith("#")]
    if len(directives) < 2:
        report(src.path, 1, "guard", "missing include guard (#ifndef X_H / #define X_H)")
        return
    (i1, d1), (_, d2) = directives[0], directives[1]
    m1 = re.match(r"#\s*ifndef\s+(\w+)$", d1)
    m2 = re.match(r"#\s*define\s+(\w+)$", d2)
    if not (m1 and m2 and m1.group(1) == m2.group(1) and m1.group(1).endswith("_H")):
        report(src.path, i1 + 1, "guard", "first lines must be #ifndef X_H / #define X_H")


DECL_RE = re.compile(
    r"^(?:(?:static|inline|extern)\s+)*"
    r"(?P<ret>[A-Za-z_][\w:<>\s\*&]*?[\s\*&])"
    r"(?P<name>[A-Za-z_]\w*)\s*\((?P<params>[^;{]*)\)\s*(?:const\s*)?[;{]"
)


def check_doxygen(src):
    """Each function declared in a header needs a /** */ block before it."""
    depth = 0  # brace depth outside namespaces/extern "C"
    stmt, start = "", None
    for idx, line in enumerate(src.code):
        s = line.strip()
        if s.startswith("#"):
            continue
        if depth == 0 and s:
            if start is None:
                start = idx
            stmt += " " + s
            if s.endswith((";", "{", "}")) or "{" in s:
                m = DECL_RE.match(stmt.strip())
                ret = m.group("ret").strip() if m else ""
                if m and ret not in ("return", "else") and not ret.startswith("typedef"):
                    check_doc_block(src, start, m)
                stmt, start = "", None
        # namespaces and extern "C" don't count as nesting
        opened = len(re.findall(r"\{", line))
        if re.match(r"\s*(namespace\b.*|extern\s+\"\"\s*)\{", line):
            opened -= 1
        closed = len(re.findall(r"\}", line))
        if re.match(r"\s*\}\s*(//.*)?$", line) and depth == 0:
            closed -= 1  # closing a namespace
        depth = max(0, depth + opened - closed)


def check_doc_block(src, start, m):
    if src.allowed(start, "doxygen"):
        return
    j = start - 1
    while j >= 0 and not src.raw[j].strip():
        j -= 1
    if j < 0 or not src.raw[j].strip().endswith("*/"):
        report(src.path, start + 1, "doxygen", f"{m.group('name')}() needs a /** ... */ comment")
        return
    k = j
    while k >= 0 and "/**" not in src.raw[k]:
        k -= 1
    block = "\n".join(src.raw[max(k, 0) : j + 1])
    params = m.group("params").strip()
    if params and params != "void" and "@param" not in block:
        report(src.path, start + 1, "doxygen", f"{m.group('name')}() comment needs @param")
    ret = re.sub(r"\b(static|inline|extern|const)\b", "", m.group("ret")).strip()
    if ret != "void" and "@return" not in block:
        report(src.path, start + 1, "doxygen", f"{m.group('name')}() comment needs @return")


def check_no_block(src, board):
    rel = src.path.relative_to(FW / board / "src").as_posix()
    if rel == "main.cpp" or rel.startswith("hal/"):
        return
    src.grep(
        "no-block",
        r"\b(delay_ms|delay|vTaskDelay|delayMicroseconds)\s*\(",
        "modules must not block — compare hal::now_ms() timestamps instead",
    )


def check_no_rtos(src):
    src.grep(
        "no-rtos",
        r"\b(xTaskCreate\w*|xTimerCreate\w*|esp_timer_create)\s*\(",
        "no new FreeRTOS tasks or timers unless the change's design.md says so (then add rules-ok)",
    )


def check_protocol(src):
    src.grep(
        "protocol",
        r"\b0x7[eE]\b",
        "protocol byte literal — use PROTOCOL_START / PROTOCOL_END from protocol.h",
    )
    src.grep(
        "protocol",
        r"#\s*define\s+PROTOCOL_\w+",
        "protocol constants live only in firmware/shared/protocol.h",
    )


TEST_DEF_RE = re.compile(r"^\s*void\s+(test_\w+)\s*\(\s*(?:void)?\s*\)\s*\{")


def check_tests(board):
    test_dir = FW / board / "test"
    main = test_dir / "test_main.cpp"
    if not main.exists():
        return
    defined = {}
    for p in sorted(test_dir.glob("test_*.cpp")):
        if p.name == "test_main.cpp" or p.name.startswith("test_mock"):
            continue
        module = p.stem[len("test_") :]
        src = Source(p)
        for idx, line in enumerate(src.code):
            m = TEST_DEF_RE.match(line)
            if not m:
                continue
            name = m.group(1)
            defined[name] = (p, idx + 1)
            if not name.startswith(f"test_{module}_") and not src.allowed(idx, "test-name"):
                report(p, idx + 1, "test-name", f"{name} should be test_{module}_<behavior>")
    main_src = Source(main)
    registered = {}
    for idx, line in enumerate(main_src.code):
        for name in re.findall(r"RUN_TEST\s*\(\s*(\w+)", line):
            registered[name] = idx + 1
    for name, (p, line) in defined.items():
        if name not in registered:
            report(p, line, "test-register", f"{name} is not RUN_TEST()-registered in test_main.cpp")
    for name, line in registered.items():
        if name not in defined and not re.search(rf"\bvoid\s+{name}\s*\([^;]*\{{", "\n".join(main_src.code)):
            report(main, line, "test-register", f"RUN_TEST({name}) has no test definition")


# ─── Main ─────────────────────────────────────────────────────


def main():
    args = sys.argv[1:]
    if any(a in ("-h", "--help") for a in args):
        print(__doc__.strip())
        return 0
    boards = [a for a in args if a in ("xiao", "atmega")] or ["xiao", "atmega"]
    bad = [a for a in args if a not in ("xiao", "atmega", "all")]
    if bad:
        print(f"check-rules: unknown argument '{bad[0]}' (use xiao, atmega)", file=sys.stderr)
        return 2

    files = 0
    for p in sources(FW / "shared"):
        src, files = Source(p), files + 1
        check_avr(src, shared=True)
        check_shared_c(src)
        check_protocol_ok = p.name == "protocol.h"
        if p.suffix == ".h":
            check_guard(src)
            check_doxygen(src)
        if not check_protocol_ok:
            check_protocol(src)

    for board in boards:
        base = FW / board
        for p in sources(base / "src", base / "include"):
            src, files = Source(p), files + 1
            if board == "atmega":
                check_avr(src)
            else:
                check_no_rtos(src)
            if p.suffix == ".h":
                check_guard(src)
                check_doxygen(src)
            else:
                check_no_block(src, board)
            check_protocol(src)
        check_tests(board)

    violations.sort(key=lambda v: (v.split(":")[0], int(v.split(":")[1])))
    for v in violations:
        print(v)
    if violations:
        print(f"rules: FAIL ({len(violations)} violations in {files} files)")
        return 1
    print(f"rules: OK ({files} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
