#!/usr/bin/env bash
# Tests for git-hooks/ and install-git-hooks.sh. Real pushes between throwaway repos under mktemp,
# with HOME and the global git config pointed there; touches nothing else.
# Usage: skills/d-github/scripts/test-git-hooks.sh   (exit 0 = all passed)

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" GIT_CONFIG_GLOBAL="$TMP/home/.gitconfig" GIT_CONFIG_NOSYSTEM=1
unset XDG_CONFIG_HOME DEEJ_PRIVATE_PATTERNS DEEJ_GIT_HOOKS
mkdir -p "$HOME/.config/deej-stack" "$TMP/bin"
git config --global user.name t; git config --global user.email t@t; git config --global init.defaultBranch main
git config --global advice.detachedHead false
PF="$HOME/.config/deej-stack/private-patterns"
SECRET="box-1234.tail-scale.ts.net"
FAIL=0
ok()   { printf 'ok    %s\n' "$1"; }
bad()  { printf 'FAIL  %s\n      %s\n' "$1" "${2:-}"; FAIL=1; }

# gh stub: answers what $TMP/vis holds; empty file = API failure
printf '#!/bin/sh\n[ -s "%s/vis" ] || exit 1\ncat "%s/vis"\n' "$TMP" "$TMP" > "$TMP/bin/gh"; chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
vis() { printf '%s' "$1" > "$TMP/vis"; }

echo "# installer"
out=$("$HERE/install-git-hooks.sh" 2>&1) && [ "$(git config --global core.hooksPath)" = "$HOME/.config/deej-stack/git-hooks" ] \
  && [ -x "$HOME/.config/deej-stack/git-hooks/pre-push" ] && [ -x "$HOME/.config/deej-stack/git-hooks/pre-commit" ] \
  && ok "installs pre-push and chain hooks, sets global core.hooksPath" || bad "install" "$out"
"$HERE/install-git-hooks.sh" >/dev/null 2>&1 && ok "re-run is idempotent" || bad "re-run"
cmp -s "$HERE/git-hooks/pre-push" "$HOME/.config/deej-stack/git-hooks/pre-push" && ok "installed copy equals the shipped one" || bad "copy differs"
git config --global core.hooksPath /somewhere/else
out=$("$HERE/install-git-hooks.sh" 2>&1); [ $? = 1 ] && [ "$(git config --global core.hooksPath)" = /somewhere/else ] \
  && ok "refuses and changes nothing when another global hooksPath is set" || bad "refuse" "$out"
git config --global core.hooksPath "$HOME/.config/deej-stack/git-hooks"

# a "GitHub" remote that is really a local bare repo, via insteadOf
git init -q --bare "$TMP/remote.git"
git config --global "url.$TMP/remote.git.insteadOf" "https://github.com/someone/thing.git"
git init -q "$TMP/work"; W="$TMP/work"; cd "$W"
git remote add origin https://github.com/someone/thing.git
echo hello > a.txt; git add a.txt; git commit -qm init
printf '# private patterns\n\ntail-scale\\.ts\\.net\n' > "$PF"

push() { # $1 label, $2 want: pass|block, rest: git push args. Sets $OUT.
  local label="$1" want="$2"; shift 2
  OUT=$(git push "$@" 2>&1); local rc=$?
  if { [ "$want" = pass ] && [ $rc = 0 ]; } || { [ "$want" = block ] && [ $rc != 0 ] && printf '%s' "$OUT" | grep -q 'deej-stack pre-push: refused'; }; then
    ok "$label"; else bad "$label (want $want, rc=$rc)" "$OUT"; fi
}
has()  { printf '%s' "$OUT" | grep -q -- "$2" && ok "$1" || bad "$1" "$OUT"; }
hasnt(){ printf '%s' "$OUT" | grep -q -- "$2" && bad "$1" "$OUT" || ok "$1"; }

echo "# clean pushes"
vis ""   # API down: a clean push must not need it
push "clean first push of a new branch passes with no API" pass -u origin main
hasnt "and prints nothing from the hook" 'deej-stack'

echo "# a hit on a public remote"
vis PUBLIC
git switch -qc topic
echo "host = $SECRET" > conf.ini; git add conf.ini; git commit -qm "add config"
push "added line with a private pattern is refused" block -u origin topic
has  "names commit and path" "$(git rev-parse --short=12 HEAD)	conf.ini"
hasnt "never prints the matched text" 'tail-scale'
[ -z "$(git ls-remote origin topic)" ] && ok "nothing reached the remote" || bad "remote has topic"
[ "$(git config --local deej-stack.origin.visibility)" = PUBLIC ] && ok "visibility cached in the clone" || bad "cache"

echo "# fixing it"
git commit -q --amend -m "add config" --no-edit >/dev/null; echo "host = example.invalid" > conf.ini; git add conf.ini; git commit -q --amend --no-edit
push "after amending the value out, the push passes" pass -u origin topic

echo "# where a hit can hide"
git commit -q --allow-empty -m "point at $SECRET"
push "commit message" block origin topic
has  "reported as (commit message)" '(commit message)'
git reset -q --hard HEAD~1
echo "host = BOX-1234.Tail-Scale.TS.NET" > caps.ini; git add caps.ini; git commit -qm "caps"
push "a different case of the same value" block origin topic
git reset -q --hard HEAD~1
mkdir -p "hosts"; echo x > "hosts/$SECRET.yml"; git add hosts; git commit -qm "host file"
push "file path" block origin topic
git reset -q --hard HEAD~1
echo "one" > b.txt; git add b.txt; git commit -qm one
echo "$SECRET" >> b.txt; git commit -qam two
echo "three" > c.txt; git add c.txt; git commit -qm three
push "an older commit in the pushed range, even with a clean tip" block origin topic
has  "names the commit that added it" "$(git rev-parse --short=12 HEAD~1)	b.txt"
git reset -q --hard HEAD~3

echo "# what is not a hit"
git push -q --no-verify origin topic 2>/dev/null
git switch -q main
echo "$SECRET" > old.txt; git add old.txt; git commit -qm "leak that is already public"; git push -q --no-verify origin main
echo fine > d.txt; git add d.txt; git commit -qm fine
push "content the remote already has is not re-checked" pass origin main
git switch -qc gone; git push -q origin gone 2>/dev/null
push "deleting a branch" pass origin --delete gone
git switch -q main; git branch -qD gone

echo "# visibility decides"
git switch -qc priv
echo "$SECRET" > e.txt; git add e.txt; git commit -qm e
vis PRIVATE
push "private remote: allowed" pass origin priv
has  "with a one-line note" 'allowed because someone/thing is not public'
git switch -q main; git switch -qc unk; echo "$SECRET" > f.txt; git add f.txt; git commit -qm f
vis ""
push "API down, cached PRIVATE stands in" pass origin unk
git config --local --unset deej-stack.origin.visibility
git switch -q main; git switch -qc unk2; echo "$SECRET" > g.txt; git add g.txt; git commit -qm g
push "API down and no cache counts as public" block origin unk2
has  "says so" 'unknown visibility'
git init -q --bare "$TMP/gitea.git"; git remote add gitea "$TMP/gitea.git"
push "non-GitHub remote with no cached value counts as public" block gitea unk2
has  "and says how to mark it private" 'git config deej-stack.gitea.visibility private'
git config deej-stack.gitea.visibility private
push "non-GitHub remote marked private: allowed" pass gitea unk2

echo "# no patterns, no check"
vis PUBLIC
git switch -q main; git switch -qc nopat; echo "$SECRET" > h.txt; git add h.txt; git commit -qm h
printf '# only a comment\n\n' > "$PF"
push "empty pattern list: passes" pass origin nopat
rm "$PF"
git commit -q --allow-empty -m again
push "no pattern file: passes" pass origin nopat
printf 'tail-scale\\.ts\\.net\n' > "$PF"

echo "# the repo's own hooks still run"
printf '#!/bin/sh\ncat > "%s/chained-stdin"\necho "$1" > "%s/chained-arg"\nexit 0\n' "$TMP" "$TMP" > .git/hooks/pre-push; chmod +x .git/hooks/pre-push
git switch -q main; echo z > z.txt; git add z.txt; git commit -qm z
push "clean push still passes" pass origin main
grep -q 'refs/heads/main' "$TMP/chained-stdin" 2>/dev/null && [ "$(cat "$TMP/chained-arg")" = origin ] \
  && ok "repo pre-push got the ref lines on stdin and the remote as \$1" || bad "chain stdin/args"
printf '#!/bin/sh\necho "repo hook says no" >&2\nexit 1\n' > .git/hooks/pre-push
echo y > y.txt; git add y.txt; git commit -qm y
OUT=$(git push origin main 2>&1); [ $? != 0 ] && printf '%s' "$OUT" | grep -q 'repo hook says no' && ok "a failing repo pre-push still blocks" || bad "chain failure" "$OUT"
rm .git/hooks/pre-push
printf '#!/bin/sh\necho "repo pre-commit ran" >&2\nexit 1\n' > .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit
OUT=$(git commit --allow-empty -m blocked 2>&1); [ $? != 0 ] && printf '%s' "$OUT" | grep -q 'repo pre-commit ran' && ok "chain hook runs the repo's pre-commit" || bad "pre-commit chain" "$OUT"
rm .git/hooks/pre-commit

[ "$FAIL" = 0 ] && echo "all passed" || echo "FAILURES"
exit "$FAIL"
