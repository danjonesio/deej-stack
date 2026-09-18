#!/usr/bin/env bash
# private-patterns: fail when a private pattern appears in the tree. Written by /d-github on 2026-09-18.
# Patterns come from $PRIVATE_PATTERNS (CI: the repository secret), else the file named by
# $DEEJ_PRIVATE_PATTERNS, else ~/.config/deej-stack/private-patterns. One POSIX extended regex
# per line, matched case-insensitively; '#' comments and blank lines are ignored. With file
# arguments it greps those files; without, the whole tree. Prints path:line per hit, never the matched text.
set -u
self=".github/scripts/private-patterns.sh"
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
f="${DEEJ_PRIVATE_PATTERNS:-$HOME/.config/deej-stack/private-patterns}"
if [ -n "${PRIVATE_PATTERNS:-}" ]; then
  printf '%s\n' "$PRIVATE_PATTERNS" | grep -vE '^[[:space:]]*(#|$)' > "$tmp"
elif [ -r "$f" ]; then
  grep -vE '^[[:space:]]*(#|$)' "$f" > "$tmp"
else
  echo "::notice::private-patterns: no patterns ($f missing, PRIVATE_PATTERNS unset); nothing checked"
  exit 0
fi
if [ ! -s "$tmp" ]; then
  echo "::notice::private-patterns: pattern list is empty; nothing checked"
  exit 0
fi
if [ $# -gt 0 ]; then
  hits=$(grep -IHniE -f "$tmp" -- "$@" 2>/dev/null | cut -d: -f1,2)
else
  hits=$(git grep -IniE -f "$tmp" -- . ":!$self" ':!.pre-commit-config.yaml' | cut -d: -f1,2)
fi
[ -z "$hits" ] && exit 0
printf 'private-patterns: hit at\n%s\n' "$hits" >&2
exit 1
