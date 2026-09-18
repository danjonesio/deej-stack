#!/usr/bin/env bash
# Session-start hook: when the repo is on github.com and misses a d-github standard, or this
# machine lacks the standard's git pre-push hook, tell the agent to offer the d-github skill.
# Prints nothing otherwise.
# Both harnesses run it. Cursor's stdin JSON carries "cursor_version"; it wants the text as
# {"additional_context": ...} and names the skill /d-github. Claude Code takes plain stdout.
# Read-only, and local except for one case: visibility is asked of the API only when it alone
# decides the answer, and an API that does not answer is an unknown, not a "public".
# The user's "no" is stored per clone: git config --local deej-stack.d-github-offer declined
# A "no" to the machine hook alone is stored per machine: git config --global deej-stack.pre-push-offer declined

set -u
INPUT=""; [ -t 0 ] || IFS= read -r -t 2 -d '' INPUT
case "$INPUT" in *'"cursor_version"'*) CURSOR=yes; SKILL="/d-github" ;; *) CURSOR=no; SKILL="/deej-stack:d-github" ;; esac
cd "${CLAUDE_PROJECT_DIR:-${CURSOR_PROJECT_DIR:-.}}" 2>/dev/null || exit 0
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$ROOT" || exit 0

[ "$(git config --get deej-stack.d-github-offer 2>/dev/null)" = "declined" ] && exit 0

ORIGIN=$(git remote get-url origin 2>/dev/null || echo "")
case "$ORIGIN" in
  *github.com[:/]*) SLUG=$(printf '%s' "$ORIGIN" | sed -E 's#.*github\.com[:/]##; s#\.git$##; s#/$##') ;;
  *) exit 0 ;;
esac

MISSING=""
add() { MISSING="${MISSING:+$MISSING; }$1"; }
[ -f .github/dependabot.yml ] || add "no .github/dependabot.yml"
ls .github/rulesets/*.json >/dev/null 2>&1 || add "no ruleset file under .github/rulesets/"
if [ -z "$MISSING" ] && [ ! -f .github/workflows/private-patterns.yml ] \
  && command -v gh >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
  VIS=$(timeout 3 gh repo view "$SLUG" --json visibility -q .visibility 2>/dev/null || echo "")
  [ "$VIS" = "PUBLIC" ] && add "public with no .github/workflows/private-patterns.yml"
fi

# The machine-wide pre-push hook of the secret-protection standard: installed, and the copy this
# plugin version ships? Local checks only. Asked once per machine, so its "no" is global.
DECLINE="git config --local deej-stack.d-github-offer declined"
if [ "$(git config --global --get deej-stack.pre-push-offer 2>/dev/null)" != "declined" ]; then
  SHIPPED="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/skills/d-github/scripts/git-hooks/pre-push"
  GHP=$(git config --global --get core.hooksPath 2>/dev/null || echo ""); GHP="${GHP/#\~/$HOME}"
  HOOK=""
  if [ -z "$GHP" ] || ! grep -qs 'deej-stack pre-push' "$GHP/pre-push"; then HOOK="machine pre-push hook not installed"
  elif [ -f "$SHIPPED" ] && ! cmp -s "$SHIPPED" "$GHP/pre-push"; then HOOK="machine pre-push hook outdated"; fi
  if [ -n "$HOOK" ]; then
    [ -z "$MISSING" ] && DECLINE="git config --global deej-stack.pre-push-offer declined"
    add "$HOOK"
  fi
fi
[ -z "$MISSING" ] && exit 0

TEXT="deej-stack: $SLUG misses GitHub standards ($MISSING). Offer $SKILL once, in one line, with your reply to the user's first message; do not run it unasked. If the user declines, run \`$DECLINE\` so they are not asked again, and drop it."
if [ "$CURSOR" = yes ]; then
  TEXT=${TEXT//\\/\\\\}; TEXT=${TEXT//\"/\\\"}
  printf '{"additional_context": "%s"}\n' "$TEXT"
else
  printf '%s\n' "$TEXT"
fi
