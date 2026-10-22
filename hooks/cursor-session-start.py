#!/usr/bin/env python3
"""Cursor's one sessionStart entry point.

Cursor merges the answers of several hooks on one event, and for `additional_context` the last
answer wins, so two hooks that both have something to say lose one of them (seen 2026-09-18: in a
repo on `main` the branch reminder replaced the d-github offer). This runs every session-start
script with the same stdin and joins what they return. Claude Code adds each hook's plain stdout
to context itself, so hooks.json keeps calling the scripts directly. Fails open.
"""

import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = [
    ["bash", os.path.join(HERE, "d-github-offer.sh")],
    [sys.executable, os.path.join(HERE, "default-branch.py"), "session-start"],
]


def main():
    stdin = sys.stdin.read()
    parts = []
    for cmd in SCRIPTS:
        try:
            out = subprocess.run(cmd, input=stdin, capture_output=True, text=True, timeout=8).stdout
            context = json.loads(out).get("additional_context") if out.strip() else None
        except (OSError, ValueError, AttributeError, subprocess.SubprocessError):
            context = None
        if context:
            parts.append(context)
    if parts:
        json.dump({"additional_context": "\n\n".join(parts)}, sys.stdout)


if __name__ == "__main__":
    try:
        main()
    except Exception:  # fail open
        pass
    sys.exit(0)
