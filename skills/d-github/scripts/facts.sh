#!/usr/bin/env bash
# Fact sheet for the d-github standards. Read-only: prints what the Facts sections of
# references/*.md ask for, one labelled line each, and never changes the repo or GitHub.
# Usage: scripts/facts.sh [repo-root]   (default: current directory)
# A value the script cannot establish prints as "unknown (<reason>)"; the skill treats that
# as a question, never as a "no".

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
cd "${1:-.}" 2>/dev/null || { echo "repo-root: unknown (not a directory: ${1:-.})"; exit 0; }
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "repo-root: unknown (not a git repository)"; exit 0; }
cd "$(git rev-parse --show-toplevel)"

say() { printf '%s: %s\n' "$1" "$2"; }
section() { printf '\n## %s\n' "$1"; }

# ---------- repo ----------
section "repo"
ORIGIN=$(git remote get-url origin 2>/dev/null || echo "")
say "origin" "${ORIGIN:-unknown (no origin remote)}"
SLUG=""
case "$ORIGIN" in
  *github.com[:/]*) SLUG=$(printf '%s' "$ORIGIN" | sed -E 's#.*github\.com[:/]##; s#\.git$##; s#/$##') ;;
esac
say "on-github" "$([ -n "$SLUG" ] && echo yes || echo no)"
say "owner-repo" "${SLUG:-unknown (origin is not on github.com)}"

GH=no
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then GH=yes; else say "gh" "unknown (gh installed but not logged in)"; fi
else
  say "gh" "unknown (gh not installed)"
fi
API=no
if [ "$GH" = yes ] && [ -n "$SLUG" ]; then
  if gh repo view "$SLUG" --json name >/dev/null 2>&1; then API=yes; else say "api" "unknown (gh cannot see $SLUG: not pushed, private to another account, or wrong login)"; fi
fi
[ "$API" = yes ] && say "api" "reachable"

DEFAULT=""
if [ "$API" = yes ]; then
  DEFAULT=$(gh repo view "$SLUG" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)
  say "default-branch" "${DEFAULT:-unknown (API returned nothing)} (source: api)"
fi
if [ -z "$DEFAULT" ]; then
  DEFAULT=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
  [ -n "$DEFAULT" ] && say "default-branch" "$DEFAULT (source: origin/HEAD)"
fi
if [ -z "$DEFAULT" ]; then
  DEFAULT=$(grep -rhoE 'branches:\s*\[\s*[A-Za-z0-9._/-]+' .github/workflows 2>/dev/null | head -1 | sed -E 's/.*\[\s*//')
  [ -n "$DEFAULT" ] && say "default-branch" "$DEFAULT (source: first CI push trigger; confirm)"
fi
[ -z "$DEFAULT" ] && say "default-branch" "unknown (no API, no origin/HEAD, no CI branch trigger)"

# ---------- ecosystems ----------
section "ecosystems (manifest -> package-ecosystem, directory)"
FILES=$(git ls-files)
eco() { # $1 pattern (grep -E on paths), $2 key
  printf '%s\n' "$FILES" | grep -E "$1" | while read -r f; do
    d=$(dirname "$f"); [ "$d" = "." ] && d="" ; printf '%s -> %s, /%s\n' "$f" "$2" "$d"
  done
}
[ -d .github/workflows ] && printf '%s\n' ".github/workflows/ -> github-actions, /"
eco '(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml)$' npm
eco '(^|/)bun\.lockb?$' bun
eco '(^|/)uv\.lock$' uv
eco '(^|/)(poetry\.lock|Pipfile\.lock|requirements[^/]*\.(txt|in))$' pip
eco '(^|/)Cargo\.lock$' cargo
eco '(^|/)go\.sum$' gomod
eco '(^|/)Gemfile\.lock$' bundler
eco '(^|/)composer\.lock$' composer
eco '(^|/)[^/]*Dockerfile[^/]*$' 'docker (only if FROM is digest- or version-pinned; see docker section)'
eco '(^|/)(docker-)?compose[^/]*\.ya?ml$' 'docker-compose (only if image tags are pinned; see docker section)'
eco '\.tf$' terraform
eco '(^|/)\.pre-commit-config\.yaml$' pre-commit
eco '(^|/)\.devcontainer/devcontainer\.json$' devcontainers
eco '(^|/)build\.gradle(\.kts)?$' gradle
eco '(^|/)pom\.xml$' maven
eco '(^|/)([^/]*\.csproj|packages\.lock\.json)$' nuget
eco '(^|/)pubspec\.lock$' pub
eco '(^|/)mix\.lock$' mix
eco '(^|/)Package\.resolved$' swift
eco '(^|/)flake\.lock$' nix
eco '(^|/)\.gitmodules$' gitsubmodule
say "existing-dependabot-config" "$([ -f .github/dependabot.yml ] && echo "present$(git ls-files --error-unmatch .github/dependabot.yml >/dev/null 2>&1 || echo ' (untracked: not yet landed)')" || echo absent)"
ls .github/dependabot.yaml dependabot.yml 2>/dev/null | sed 's/^/misplaced-config: /'

# ---------- deploy signals ----------
section "deploy signals (each is one signal; any positive is yes, with paths)"
if [ -d .github/workflows ]; then
  hits=$(grep -lE '\b(ssh|rsync|scp|docker push|fly deploy|wrangler|vercel|netlify|gcloud run|aws |kubectl|helm)\b|(name|id):\s*(deploy|release|publish)' .github/workflows/*.y*ml 2>/dev/null)
  say "workflow-deploy-steps" "${hits:-none}"
  for f in .github/workflows/*.y*ml; do
    grep -qE '^\s*push:' "$f" 2>/dev/null && say "workflow-on-push" "$f"
  done
fi
hits=$(ls fly.toml vercel.json netlify.toml render.yaml app.yaml Procfile railway.json wrangler.toml 2>/dev/null | tr '\n' ' ')
say "host-config-files" "${hits:-none}"
hits=$(grep -rniE 'watch path|auto[- ]?deploy|deploys? on push|coolify|dokploy|vercel|netlify|render\.com|fly\.io' README* docs 2>/dev/null | cut -c1-160)
say "host-words-in-docs" "${hits:-none}"
if [ "$API" = yes ]; then
  say "github-deployments" "$(gh api "repos/$SLUG/deployments" -q length 2>/dev/null || echo 'unknown (api error)')"
  say "github-environments" "$(gh api "repos/$SLUG/environments" -q .total_count 2>/dev/null || echo 'unknown (api error)')"
else
  say "github-deployments" "unknown (api unreachable)"; say "github-environments" "unknown (api unreachable)"
fi
say "looks-like-service" "$( { ls Dockerfile* */Dockerfile* >/dev/null 2>&1 || grep -qsE '^\s*build:' docker-compose*.y*ml compose*.y*ml; } && echo yes || echo no)"

# ---------- actions ----------
section "actions"
if [ -d .github/workflows ]; then
  say "uses-sha-pinned" "$(grep -rEho 'uses: [^ ]+@[0-9a-f]{40}' .github/workflows 2>/dev/null | wc -l | tr -d ' ')"
  say "uses-third-party-total" "$(grep -rEho 'uses: [^ ]+@' .github/workflows 2>/dev/null | grep -v 'docker://' | wc -l | tr -d ' ')"
  for f in .github/workflows/*.y*ml; do
    grep -qE '^\s*pull_request(:|\s*$)' "$f" 2>/dev/null || continue
    jobs=$(awk '/^jobs:/{injobs=1;next} injobs && /^[^ \t#]/{injobs=0} injobs && match($0,/^[ \t]+[A-Za-z0-9_-]+:[ \t]*$/){ if(!ind){match($0,/^[ \t]+/);ind=RLENGTH} match($0,/^[ \t]+/); if(RLENGTH==ind){s=$0;gsub(/^[ \t]+|:[ \t]*$/,"",s);print s} }' "$f" | tr '\n' ' ')
    say "pr-workflow" "$f jobs: ${jobs:-none}"
    grep -nE '^\s*(paths|paths-ignore):|^\s*if:' "$f" 2>/dev/null | sed "s#^#  filter in $f line #"
  done
else
  say "workflows" "none"
fi
if [ "$API" = yes ] && [ -n "$DEFAULT" ]; then
  sha=$(git rev-parse "origin/$DEFAULT" 2>/dev/null || git rev-parse HEAD)
  names=$(gh api "repos/$SLUG/commits/$sha/check-runs" -q '.check_runs[].name' 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')
  say "check-run-names-on-$DEFAULT" "${names:-unknown (no check runs on $sha, or api error)}"
else
  say "check-run-names" "unknown (api unreachable)"
fi

# ---------- security & protection ----------
section "security and protection"
if [ "$API" = yes ]; then
  code=$(gh api "repos/$SLUG/vulnerability-alerts" 2>/dev/null >/dev/null && echo on || echo off)
  say "vulnerability-alerts" "$code"
  say "automated-security-fixes" "$(gh api "repos/$SLUG/automated-security-fixes" -q '"enabled=\(.enabled) paused=\(.paused)"' 2>/dev/null || echo 'unknown (api error)')"
  if [ -n "$DEFAULT" ]; then
    if gh api "repos/$SLUG/branches/$DEFAULT/protection" >/dev/null 2>&1; then
      say "classic-protection" "present: $(gh api "repos/$SLUG/branches/$DEFAULT/protection" -q '"strict=\(.required_status_checks.strict // "n/a") reviews=\(.required_pull_request_reviews.required_approving_review_count // "none") enforce_admins=\(.enforce_admins.enabled) force_push=\(.allow_force_pushes.enabled) deletions=\(.allow_deletions.enabled)"' 2>/dev/null)"
    else
      say "classic-protection" "none"
    fi
    rs=$(gh api "repos/$SLUG/rulesets" -q '.[] | "\(.id) \(.name) \(.enforcement) \(.source_type)"' 2>/dev/null | tr '\n' ';')
    say "repo-rulesets" "${rs:-none}"
    inforce=$(gh api "repos/$SLUG/rules/branches/$DEFAULT" -q '.[] | "\(.type)@\(.ruleset_source_type // "?")"' 2>/dev/null | sort -u | tr '\n' ' ')
    say "rules-in-force-on-$DEFAULT" "${inforce:-none}"
  fi
  say "merge-methods" "$(gh repo view "$SLUG" --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed -q '"merge=\(.mergeCommitAllowed) squash=\(.squashMergeAllowed) rebase=\(.rebaseMergeAllowed)"' 2>/dev/null || echo 'unknown (api error)')"
  OWNER=${SLUG%%/*}
  otype=$(gh api "users/$OWNER" -q .type 2>/dev/null || echo unknown)
  say "owner-type" "$otype"
  say "collaborators" "$(gh api "repos/$SLUG/collaborators" -q length 2>/dev/null || echo 'unknown (api error; needs push access)')"
  vis=$(gh repo view "$SLUG" --json visibility -q .visibility 2>/dev/null || echo unknown)
  say "visibility" "$vis"
  if [ "$vis" != "PUBLIC" ]; then
    if [ "$otype" = "Organization" ]; then plan=$(gh api "orgs/$OWNER" -q .plan.name 2>/dev/null); else plan=$(gh api user -q .plan.name 2>/dev/null); fi
    say "plan" "${plan:-unknown (token lacks scope to read plan)}"
  else
    say "plan" "irrelevant (public repo: rulesets available on every plan)"
  fi
  sa=$(gh api "repos/$SLUG" -q '.security_and_analysis | to_entries | map("\(.key)=\(.value.status)") | join(" ")' 2>/dev/null)
  say "security-and-analysis" "${sa:-unknown (api error, or token lacks admin)}"
  if out=$(gh secret list -R "$SLUG" 2>/dev/null); then
    say "private-patterns-secret" "$(printf '%s\n' "$out" | grep -q '^PRIVATE_PATTERNS' && echo present || echo absent)"
  else
    say "private-patterns-secret" "unknown (gh secret list failed; needs admin)"
  fi
else
  for k in vulnerability-alerts automated-security-fixes classic-protection repo-rulesets rules-in-force merge-methods owner-type collaborators visibility plan security-and-analysis private-patterns-secret; do say "$k" "unknown (api unreachable)"; done
fi
co=$(ls .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS 2>/dev/null | tr '\n' ' ' | sed 's/ $//'); say "codeowners" "${co:-none}"
say "rulesets-file" "$([ -f .github/rulesets/default-branch.json ] && echo present || echo absent)"

# ---------- private patterns ----------
section "private patterns"
PF="${DEEJ_PRIVATE_PATTERNS:-$HOME/.config/deej-stack/private-patterns}"
if [ -r "$PF" ]; then
  say "user-pattern-file" "present: $PF ($(grep -cvE '^[[:space:]]*(#|$)' "$PF") patterns)"
else
  say "user-pattern-file" "absent ($PF)"
fi
say "script" "$([ -f .github/scripts/private-patterns.sh ] && echo present || echo absent)"
say "workflow" "$([ -f .github/workflows/private-patterns.yml ] && echo present || echo absent)"
if [ -f .pre-commit-config.yaml ]; then
  say "pre-commit-config" "present, hook $(grep -q 'id: private-patterns' .pre-commit-config.yaml && echo present || echo absent)"
else
  say "pre-commit-config" "absent"
fi
GHP=$(git config --global --get core.hooksPath 2>/dev/null || echo ""); GHP="${GHP/#\~/$HOME}"
say "global-hooks-path" "${GHP:-unset}"
if [ -n "$GHP" ] && [ -f "$GHP/pre-push" ]; then
  say "pre-push-hook" "$(cmp -s "$HERE/git-hooks/pre-push" "$GHP/pre-push" && echo current || echo "outdated (differs from $HERE/git-hooks/pre-push)")"
else
  say "pre-push-hook" "absent"
fi
LHP=$(git config --local --get core.hooksPath 2>/dev/null || echo "")
say "local-hooks-path" "${LHP:-none}${LHP:+ (overrides the global path: the machine-wide pre-push does not run in this clone)}"
if [ "$GH" = yes ]; then
  tag=$(gh api repos/actions/checkout/releases/latest -q .tag_name 2>/dev/null)
  sha=$([ -n "$tag" ] && gh api "repos/actions/checkout/commits/$tag" -q .sha 2>/dev/null)
  say "checkout-latest" "${tag:-unknown} ${sha:-unknown (api error)}"
else
  say "checkout-latest" "unknown (gh unavailable)"
fi
if [ -r "$PF" ]; then
  pats=$(mktemp); grep -vE '^[[:space:]]*(#|$)' "$PF" > "$pats"
  if [ -s "$pats" ]; then
    hits=$(git grep -IniE -f "$pats" -- . ':!.github/scripts/private-patterns.sh' ':!.pre-commit-config.yaml' 2>/dev/null | cut -d: -f1,2)
    say "tree-hits" "$(printf '%s' "$hits" | grep -c .) (path:line only; matched text is never printed)"
    [ -n "$hits" ] && printf '%s\n' "$hits" | head -20 | sed 's/^/  /'
  else
    say "tree-hits" "unknown (pattern file has no patterns)"
  fi
  rm -f "$pats"
else
  say "tree-hits" "unknown (no user pattern file)"
fi

# ---------- docker ----------
section "docker"
for f in $(printf '%s\n' "$FILES" | grep -E '(^|/)[^/]*Dockerfile[^/]*$'); do
  grep -hE '^FROM' "$f" 2>/dev/null | sed "s#^#$f: #"
done
for f in $(printf '%s\n' "$FILES" | grep -E '(^|/)(docker-)?compose[^/]*\.ya?ml$'); do
  grep -nE '^\s*(image|pull):' "$f" 2>/dev/null | sed "s#^#$f: #"
done
say "pinned-hint" "an image is pinned only if its tag carries a digest (@sha256:...) or an exact version; :alpine, :slim, :latest and major-only tags float"

# ---------- commits ----------
section "commits"
say "conventional-prefixes-in-last-30" "$(git log --oneline -30 2>/dev/null | grep -cE '^[0-9a-f]+ (feat|fix|chore|docs|refactor|test|ci|build|perf)(\(.*\))?!?:' | tr -d ' ')"
say "commits-sampled" "$(git log --oneline -30 2>/dev/null | wc -l | tr -d ' ')"
