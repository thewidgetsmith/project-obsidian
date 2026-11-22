#!/usr/bin/env python3
"""tools/check-secrets.py — fail if a secret could be published with the repo.

Usage: tools/check-secrets.py

Scans every tracked file and every untracked file that git does not ignore:

  key-pattern    strings shaped like API keys, tokens or private keys
  config-literal opencode.json `apiKey` / `baseURL` values that are not {env:NAME}
  env-value      any value from the local secrets file
                 (OBSIDIAN_ENV_FILE, default ~/.config/litellm/obsidian.env),
                 or the hostname in it, appearing anywhere in the repo

Prints `path:line: [rule] NAME` per finding and never prints the secret itself,
then `secrets: OK` or `secrets: FAIL`. Exit status 0 only when clean. Put
`secrets-ok` in a comment on a line to accept a deliberate false positive.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = Path(
    os.environ.get(
        "OBSIDIAN_ENV_FILE",
        Path.home() / ".config/litellm/obsidian.env",
    )
)
MAX_BYTES = 1_000_000

KEY_PATTERNS = [
    ("openai-style key", re.compile(r"\bsk-[A-Za-z0-9_-]{20,}")),
    ("github token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}")),
    ("gitlab token", re.compile(r"\bglpat-[A-Za-z0-9_-]{20,}")),
    ("slack token", re.compile(r"\bxox[abposr]-[A-Za-z0-9-]{10,}")),
    ("aws key id", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("private key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("bearer token", re.compile(r"Bearer\s+[A-Za-z0-9._-]{20,}")),
]


def repo_files():
    out = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=ROOT,
        capture_output=True,
        check=True,
    ).stdout
    for name in out.decode().split("\0"):
        p = ROOT / name
        if name and p.is_file() and not p.is_symlink() and p.stat().st_size <= MAX_BYTES:
            yield p


def env_secrets():
    """NAME -> list of strings that must not appear in the repo."""
    found = {}
    if not ENV_FILE.is_file():
        return found
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        value = value.strip().strip("'\"")
        if len(value) < 6:
            continue
        needles = [value]
        host = urlparse(value).hostname
        if host:
            needles.append(host)
        found[name.strip()] = needles
    return found


def check_opencode_json(path, findings):
    try:
        data = json.loads(path.read_text())
    except (ValueError, OSError):
        findings.append(f"{path.relative_to(ROOT)}:1: [config-literal] not valid JSON")
        return
    text = path.read_text().splitlines()

    def walk(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if key in ("apiKey", "baseURL") and isinstance(value, str):
                    if not re.fullmatch(r"\{env:[A-Z0-9_]+\}", value):
                        line = next(
                            (i for i, t in enumerate(text, 1) if f'"{key}"' in t), 1
                        )
                        findings.append(
                            f"{path.relative_to(ROOT)}:{line}: [config-literal] {key} "
                            "must be {env:NAME}"
                        )
                walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(data)


def main():
    findings = []
    secrets = env_secrets()
    files = 0
    for path in repo_files():
        try:
            text = path.read_text()
        except (UnicodeDecodeError, OSError):
            continue
        files += 1
        rel = path.relative_to(ROOT)
        for no, line in enumerate(text.splitlines(), 1):
            if "secrets-ok" in line:
                continue
            for label, rx in KEY_PATTERNS:
                if rx.search(line):
                    findings.append(f"{rel}:{no}: [key-pattern] {label}")
            for name, needles in secrets.items():
                if any(n in line for n in needles):
                    findings.append(f"{rel}:{no}: [env-value] value of {name}")
        if path.name == "opencode.json":
            check_opencode_json(path, findings)

    for f in findings:
        print(f)
    source = "with local env file" if secrets else "no local env file"
    if findings:
        print(f"secrets: FAIL ({len(findings)} findings in {files} files, {source})")
        return 1
    print(f"secrets: OK ({files} files, {source})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
