#!/usr/bin/env python3
"""tools/check-docs.py — find broken relative links in Markdown files.

Usage: tools/check-docs.py [PATH...]

PATHs are Markdown files or directories (default: AGENTS.md, README.md,
docs/, openspec/, tools/). Checks that every relative link points at an
existing file and, for `file.md#anchor` links, at an existing heading.
Links inside code blocks and inline code are ignored.

Prints one line per broken link, or a single "docs: OK" line. Exit status is
0 when every link resolves.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PATHS = ["AGENTS.md", "CLAUDE.md", "README.md", "docs", "openspec", "tools", ".github", ".claude/spec-planning.md", ".opencode/agents"]

LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
INLINE_CODE_RE = re.compile(r"`[^`]*`")
HEADING_RE = re.compile(r"^#{1,6}\s+(.*?)\s*#*\s*$")


def slug(heading: str) -> str:
    """GitHub-style heading anchor."""
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", heading)  # [text](url) → text
    text = text.lower()
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def strip_code(lines, inline=True):
    """Yield (line_number, text) outside fenced blocks, minus inline code."""
    fence = None
    for num, line in enumerate(lines, 1):
        stripped = line.lstrip()
        if fence:
            if stripped.startswith(fence):
                fence = None
            continue
        if stripped.startswith("```") or stripped.startswith("~~~"):
            fence = stripped[:3]
            continue
        yield num, INLINE_CODE_RE.sub("", line) if inline else line


_anchor_cache = {}


def anchors(path: Path):
    if path not in _anchor_cache:
        found, seen = set(), {}
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        for _, line in strip_code(lines, inline=False):
            m = HEADING_RE.match(line)
            if m:
                base = slug(m.group(1))
                n = seen.get(base, 0)
                seen[base] = n + 1
                found.add(base if n == 0 else f"{base}-{n}")
        _anchor_cache[path] = found
    return _anchor_cache[path]


def check_file(path: Path):
    errors, count = [], 0
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    for num, line in strip_code(lines):
        for m in LINK_RE.finditer(line):
            target = m.group(1)
            if re.match(r"^[a-z][a-z0-9+.-]*:", target) or target.startswith("<"):
                continue  # http:, mailto:, file: …
            count += 1
            file_part, _, anchor = target.partition("#")
            dest = (path.parent / file_part).resolve() if file_part else path
            rel = path.relative_to(ROOT)
            if not dest.exists():
                errors.append(f"{rel}:{num}: missing file: {target}")
            elif anchor and dest.suffix == ".md" and anchor not in anchors(dest):
                errors.append(f"{rel}:{num}: missing heading: {target}")
    return errors, count


def collect(args):
    files = []
    for arg in args or DEFAULT_PATHS:
        p = (ROOT / arg) if not Path(arg).is_absolute() else Path(arg)
        if p.is_dir():
            files.extend(sorted(p.rglob("*.md")))
        elif p.suffix == ".md" and p.exists():
            files.append(p)
        elif not p.exists():
            print(f"check-docs: no such path: {arg}", file=sys.stderr)
            sys.exit(2)
    return [f.resolve() for f in files if ".pio" not in f.parts]


def main():
    if any(a in ("-h", "--help") for a in sys.argv[1:]):
        print(__doc__.strip())
        return 0
    errors, links = [], 0
    files = collect(sys.argv[1:])
    for f in files:
        e, n = check_file(f)
        errors.extend(e)
        links += n
    for e in errors:
        print(e)
    if errors:
        print(f"docs: FAIL ({len(errors)} broken of {links} links)")
        return 1
    print(f"docs: OK ({links} links in {len(files)} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
