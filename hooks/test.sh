#!/usr/bin/env bash
# Tests for the hooks in this directory. Builds throwaway repos under mktemp; touches nothing else.
# Usage: hooks/test.sh   (exit 0 = all passed)

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FAIL=0

g() { git -C "$1" -c user.name=t -c user.email=t@t -c init.defaultBranch=main "${@:2}" >/dev/null 2>&1; }
g "$TMP" init --bare remote.git
g "$TMP" init work; W="$TMP/work"
g "$W" commit --allow-empty -m init
g "$W" remote add origin "$TMP/remote.git"
git -C "$W" -c init.defaultBranch=main push -q origin main 2>/dev/null
g "$W" remote set-head origin main
g "$W" switch -c topic

push() { # $1 deny|allow, $2 cwd, $3 command
  got=$(jq -n --arg c "$3" --arg d "$2" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' \
    | python3 "$HERE/default-branch.py" pre-push | jq -r '.hookSpecificOutput.permissionDecision // "allow"')
  if [ "${got:-allow}" = "$1" ]; then printf 'ok    %-5s %s\n' "$1" "$3"; else printf 'FAIL  want %s got %s: %s\n' "$1" "$got" "$3"; FAIL=1; fi
}

echo "# pre-push, HEAD on topic"
push deny "$W" 'git push origin main'
push deny "$W" 'git push -u origin main'
push deny "$W" 'git push origin HEAD:main'
push deny "$W" 'git push origin topic:refs/heads/main'
push deny "$W" 'git push --force origin +topic:master'
push deny "$W" 'git push origin --delete main'
push deny "$W" 'git push --all origin'
push deny "$W" 'git push --mirror'
push deny "$W" 'git add . && git commit -m x && git push origin main'
push deny "$W" 'bash -lc "git push origin main"'
push deny "$TMP" "cd work && git switch main && git push origin main"
push deny "$TMP" "git -C work push origin main"
push deny "$W" 'FOO=1 git -c push.default=current push origin main 2>&1 | tail -1'
push deny "$W" 'git switch main && git pull && git push'
push deny "$W" 'git checkout main; git push origin HEAD'
push allow "$W" 'git push'
push allow "$W" 'git push -u origin topic'
push allow "$W" 'git push origin HEAD'
push allow "$W" 'git push origin topic 2>&1'
push allow "$W" 'git push origin topic # then PR into main'
push allow "$W" 'git push origin v1.0 --tags'
push allow "$W" 'git push origin maintenance'
push allow "$W" 'git commit -m "never git push origin main"'
push allow "$W" 'echo "git push origin main"'
push allow "$W" 'git log origin/main..HEAD'
push allow "$W" 'gh pr merge 12 --squash'

echo "# pre-push, push.default=upstream with topic tracking main"
g "$W" branch -u origin/main topic; g "$W" config push.default upstream
push deny "$W" 'git push'
g "$W" config --unset push.default

echo "# pre-push, HEAD on main"
g "$W" switch main
push deny "$W" 'git push'
push deny "$W" 'git push origin HEAD'
push deny "$W" 'git push -u origin @'
push allow "$W" 'git push origin topic'
push allow "$W" 'git switch -c fix-typo && git commit -am x && git push -u origin HEAD'
push allow "$W" 'git checkout -b fix-typo && git push'

echo "# pre-push, default branch with another name"
g "$W" branch trunk; git -C "$W" push -q origin trunk 2>/dev/null; g "$W" remote set-head origin trunk
g "$W" switch topic
push deny "$W" 'git push origin topic:trunk'
g "$W" remote set-head origin main

cpush() { # Cursor beforeShellExecution: $1 deny|allow, $2 cwd, $3 command
  out=$(jq -n --arg c "$3" --arg d "$2" '{hook_event_name:"beforeShellExecution",cursor_version:"3.0.0",workspace_roots:[$d],command:$c,cwd:$d,sandbox:false}' \
    | python3 "$HERE/default-branch.py" pre-push)
  if [ "$1" = allow ]; then [ -z "$out" ]; else [ "$(printf '%s' "$out" | jq -r '.permission + ":" + (.agent_message|test("git switch -c")|tostring) + ":" + (.user_message|length>0|tostring)')" = "deny:true:true" ]; fi
  if [ $? = 0 ]; then printf 'ok    %-5s %s\n' "$1" "$3"; else printf 'FAIL  want %s: %s -> %s\n' "$1" "$3" "$out"; FAIL=1; fi
}

echo "# pre-push, Cursor dialect (allow must print nothing, never an explicit allow)"
cpush deny "$W" 'git push origin topic:main'
cpush deny "$TMP" 'cd work && git push origin main'
cpush allow "$W" 'git push -u origin topic'
cpush allow "$W" 'git status'

echo "# pre-push, garbage in"
out=$(printf 'not json' | python3 "$HERE/default-branch.py" pre-push); [ $? = 0 ] && [ -z "$out" ] && echo "ok    bad stdin fails open" || { echo "FAIL  bad stdin"; FAIL=1; }

expect() { # $1 label, $2 "empty"|pattern, $3 output
  if { [ "$2" = empty ] && [ -z "$3" ]; } || { [ "$2" != empty ] && printf '%s' "$3" | grep -q -- "$2"; }; then
    printf 'ok    %s\n' "$1"; else printf 'FAIL  %s: %s\n' "$1" "$3"; FAIL=1; fi
}
session() { printf '{"cwd":"%s"}' "$1" | python3 "$HERE/default-branch.py" session-start; }
csession() { printf '{"hook_event_name":"sessionStart","cursor_version":"3.0.0","workspace_roots":["%s"]}' "$1" | python3 "$HERE/default-branch.py" session-start | jq -r .additional_context; }

echo "# session-start"
expect "silent on topic" empty "$(session "$W")"
g "$W" switch main
expect "nudges on main" 'git switch -c' "$(session "$W")"
expect "Cursor: nudges on main as additional_context" 'git switch -c' "$(csession "$W")"
expect "silent outside a repo" empty "$(session "$TMP")"

offer() { printf '{"hook_event_name":"SessionStart"}' | CLAUDE_PROJECT_DIR="$1" PATH="$TMP/nogh:$PATH" bash "$HERE/d-github-offer.sh"; }
coffer() { printf '{"hook_event_name":"sessionStart","cursor_version":"3.0.0"}' | CLAUDE_PROJECT_DIR="$1" PATH="$TMP/nogh:$PATH" bash "$HERE/d-github-offer.sh" | jq -r .additional_context; }
mkdir "$TMP/nogh"; printf '#!/bin/sh\nexit 1\n' > "$TMP/nogh/gh"; chmod +x "$TMP/nogh/gh"

echo "# d-github-offer"
expect "silent when origin is not github" empty "$(offer "$W")"
g "$W" remote set-url origin git@github.com:someone/thing.git
expect "offers when both files are missing" 'someone/thing misses .*dependabot.yml; no ruleset' "$(offer "$W")"
expect "Claude Code names the namespaced skill" 'Offer /deej-stack:d-github once' "$(offer "$W")"
expect "Cursor: valid JSON naming the bare skill" 'Offer /d-github once.*`git config --local' "$(coffer "$W")"
mkdir -p "$W/.github/rulesets"; echo '{}' > "$W/.github/rulesets/default-branch.json"
expect "names only what is missing" 'misses GitHub standards (no .github/dependabot.yml)' "$(offer "$W")"
touch "$W/.github/dependabot.yml"
expect "silent when visibility is unknown" empty "$(offer "$W")"
printf '#!/bin/sh\necho PUBLIC\n' > "$TMP/nogh/gh"
expect "offers on a public repo without private-patterns" 'public with no' "$(offer "$W")"
mkdir -p "$W/.github/workflows"; touch "$W/.github/workflows/private-patterns.yml"
expect "silent when every standard is met" empty "$(offer "$W")"
rm "$W/.github/dependabot.yml"; g "$W" config deej-stack.d-github-offer declined
expect "silent once declined" empty "$(offer "$W")"

[ "$FAIL" = 0 ] && echo "all passed" || echo "FAILURES"
exit "$FAIL"
