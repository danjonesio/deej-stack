# Standard: Dependabot

Every GitHub repo gets a `.github/dependabot.yml` that someone chose, because the default (security updates only, if the repo setting is on) silently means SHA-pinned actions never move again and one advisory wave opens one PR per package. The file is short; the decision it encodes is whether a merge to the default branch deploys.

## Applies when

`.github/dependabot.yml` is absent, or the ask says `review` and the file exists. Dependabot reads that path; a `dependabot.yaml` or a copy outside `.github/` counts as absent, and the reply says so. A copy that exists but is untracked or not yet on the default branch (`git ls-files --error-unmatch .github/dependabot.yml` fails, or the file is not in `git ls-tree origin/<default> -- .github/dependabot.yml`) is met-pending: skip the standard and say in the reply that the file has not landed.

## Facts

Record each one as a value with the command or path that produced it. `unknown` is a valid value.

1. **Repo.** `OWNER/REPO` from `git remote get-url origin`; default branch from `gh repo view OWNER/REPO --json defaultBranchRef -q .defaultBranchRef.name`, or when the API cannot see the repo, from `git symbolic-ref refs/remotes/origin/HEAD` or the branch the CI `push` trigger names. This is the one fact where tree evidence stands in for the API.
2. **Ecosystems present.** `git ls-files` against the manifest table below. One entry per ecosystem per directory; the `directory` value starts with `/` and is relative to the repo root (`/web`, not `web/`). A manifest whose ecosystem is not in the verified-keys table is a follow-up, not an entry.
3. **Deploy on merge.** Does a merge to the default branch put something live? Four signals, each checked on its own; an API call that fails drops that one signal and nothing else:
   - Workflows: any job triggered by `push` to the default branch that deploys (steps calling `ssh`, `rsync`, `scp`, `docker push`, `fly deploy`, `wrangler`, `vercel`, `netlify`, `gcloud run`, `aws`, `kubectl`, `helm`, or a job or step named deploy/release/publish).
   - Host config in the tree: `fly.toml`, `vercel.json`, `netlify.toml`, `render.yaml`, `app.yaml`, `Procfile`, `railway.json`, `wrangler.toml`.
   - Host config outside the tree: README, `docs/`, and CI comments for words like "watch path", "auto deploy", "deploys on push", Coolify, Dokploy, Vercel, Netlify, Render, Fly. A watch-path list is the answer *per path*: record which paths deploy.
   - GitHub: `gh api repos/OWNER/REPO/deployments -q length` above zero, or `gh api repos/OWNER/REPO/environments -q .total_count` above zero.
   Any positive signal is `yes`, with the paths. No signal and a repo that is a library, a CLI, a plugin, or docs is `no`. No signal and a repo that looks like a service (a `Dockerfile`, a compose file with `build:`, a server entry point) is `unknown`: the deploy may hang off a host webhook the tree never sees.
4. **Actions pinning.** Pinned: `grep -rEho 'uses: [^ ]+@[0-9a-f]{40}' .github/workflows 2>/dev/null | wc -l`. Third-party total: `grep -rEho 'uses: [^ ]+@' .github/workflows 2>/dev/null | grep -v 'docker://' | wc -l` (local `./` actions carry no `@`). Record both. SHA-pinned actions are the case that makes the actions lane mandatory.
5. **Security features.** `gh api repos/OWNER/REPO/vulnerability-alerts` (204 on, 404 off) and `gh api repos/OWNER/REPO/automated-security-fixes` (`enabled`, `paused`). Off or unknown means the security-only lanes below open nothing until both are on. Enabling is a repo-settings change and so always a question: offer "enable both now" as the recommended answer, with `gh api -X PUT` on the same two paths as the action. When the question cannot be asked, leave the settings alone and put the two commands in the reply; never run them on a default.
6. **Branch protection.** `gh api repos/OWNER/REPO/branches/<default>/protection -q .required_status_checks.strict` (or the rulesets endpoint). Strict up-to-date means every open Dependabot PR rebases after every merge, which is why grouping matters; it goes in the header, it does not change the shape.
7. **Docker images.** `grep -h '^FROM' $(git ls-files '*Dockerfile*') 2>/dev/null` and every `image:` in compose files, plus whether compose sets `pull: true`. A floating tag (`python:3.14-slim`, `nginx:alpine`, `node:24-bookworm-slim`) has no version for Dependabot to move, whether it sits in a `FROM` or a compose `image:`; a pull on build makes it refresh on every rebuild as well. A digest-pinned or exact-version image is an ecosystem entry like any other (`docker` for a Dockerfile, `docker-compose` for a compose file).
8. **Commit convention.** `git log --oneline -30`: conventional prefixes (`chore:`, `feat:`) mean the entries set `commit-message.prefix: "chore(deps)"`; otherwise omit `commit-message`.

## Rules

**Two lanes.** Every ecosystem entry is one of:

- **Version updates on.** For ecosystems whose merges deploy nothing. Monthly schedule, `open-pull-requests-limit: 5`, two groups so a bump month is one PR and an advisory wave is one PR. `github-actions` is almost always here: an action pinned by SHA never moves unless something is watching, and nothing deploys when a workflow file changes.
- **Security only, grouped.** For ecosystems whose merges deploy. `open-pull-requests-limit: 0` turns version updates off for the entry; security updates are not subject to that limit and keep flowing. One group with `applies-to: security-updates` and `patterns: ["*"]` so one advisory wave against one lockfile is one PR, one CI run, one rebase, one deploy.

Deploy `yes` for a path puts every ecosystem rooted under that path in the security-only lane. Deploy `no` puts it in the version lane. Deploy `unknown` is a question, default security-only: a wrong "no" costs a deploy per patch bump every month; a wrong "yes" costs nothing until someone turns the lane up.

**The user wants version updates on a deploying path anyway.** Fine, with a reason in the header: cheap deploys, a preview environment, or `target-branch` pointed at a non-deploying integration branch. Without a reason, security-only.

**Groups need `applies-to`.** A group without it covers version updates only. A version lane therefore carries two groups, one per `applies-to` value; a security lane carries one. `patterns: ["*"]` in every group; split by `dependency-type` only when the user asks for separate dev and prod PRs.

**Schedule.** `interval: monthly` for version lanes. Security lanes need a `schedule` key to be valid YAML for Dependabot but the interval does not gate security PRs; those open when the advisory does. Leave `cooldown` alone: version updates already wait three days by default.

**Skip on purpose, in the header.** Floating Docker tags, in a Dockerfile or a compose `image:`. Ecosystems present in the tree with no verified key. Anything skipped is named in the header with the reason, so the next reader does not add it back by accident.

**Existing file (`review`).** Check it against every rule above and report each difference with the rule it breaks; the common ones are a group with no `applies-to` on a deploying ecosystem, a version lane on a deploying path with no reason, and an ecosystem in the tree with no entry. Write nothing.

**Never guess a key.** Only `package-ecosystem` values from the table below go in. If a manifest maps to a key that is not there, the entry is a follow-up line in the header and the reply, and the user re-checks the docs page once, not you on their behalf. An invalid key marks the whole file as a configuration error and every other entry stops with it.

## Output

`.github/dependabot.yml`. The header comment is the decision record, in this order:

```
# Dependabot config for OWNER/REPO. Written by /d-github on <date>.
#
# Deploy on merge: <yes per path / no / unknown>, because <fact>.
#
# <ecosystem> (<directory>): <version | security-only> lane. <fact that put it there>.
# ...one paragraph per entry...
#
# Not covered, on purpose:
#   - <ecosystem or path>: <reason>.
#
# Unknown at write time: <fact>: <what it would change>.   (omit when nothing is unknown)
#
# This file's own path <is / is not> a deploy trigger.
```

Below the header, the entries in this shape, one per ecosystem and directory:

```yaml
version: 2
updates:
  # Version lane: nothing deploys when a workflow file merges; SHA pins never move on their own.
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "monthly"
    open-pull-requests-limit: 5
    commit-message:
      prefix: "chore(deps)"
    groups:
      actions-versions:
        applies-to: version-updates
        patterns: ["*"]
      actions-security:
        applies-to: security-updates
        patterns: ["*"]

  # Security lane: web/** is a deploy watch path (README, "Deploying"). Version updates off via the
  # limit; security updates are not subject to it. One advisory wave against package-lock.json = one PR.
  - package-ecosystem: "npm"
    directory: "/web"
    schedule:
      interval: "monthly"
    open-pull-requests-limit: 0
    commit-message:
      prefix: "chore(deps)"
    groups:
      npm-security:
        applies-to: security-updates
        patterns: ["*"]
```

Several directories with the same ecosystem and the same lane: one entry with `directories: ["/a", "/b"]` instead of `directory`.

After the file lands on the default branch: the first run happens on merge. The user checks **Insights → Dependency graph → Dependabot**; a "configuration error" badge there means a key is wrong and nothing is running. Say this in the reply.

## Verified keys

Checked against the Dependabot options reference on 2026-09-12: <https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference>. Re-check the page before using a key that is not here; do not extend this table from memory.

| manifest or lockfile in the tree | `package-ecosystem` |
|---|---|
| `.github/workflows/*.yml` | `github-actions` (directory `/`) |
| `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml` | `npm` |
| `bun.lock`, `bun.lockb` | `bun` |
| `uv.lock` | `uv` |
| `poetry.lock`, `Pipfile.lock`, `requirements.txt`, `requirements*.in` | `pip` |
| `Cargo.lock` | `cargo` |
| `go.sum` | `gomod` |
| `Gemfile.lock` | `bundler` |
| `composer.lock` | `composer` |
| `Dockerfile*` with a digest-pinned `FROM` | `docker` |
| `docker-compose*.yml` with pinned image tags | `docker-compose` |
| `*.tf` | `terraform` |
| `.pre-commit-config.yaml` | `pre-commit` |
| `.devcontainer/devcontainer.json` | `devcontainers` |
| `build.gradle`, `build.gradle.kts` | `gradle` |
| `pom.xml` | `maven` |
| `*.csproj`, `packages.lock.json` | `nuget` |
| `pubspec.lock` | `pub` |
| `mix.lock` | `mix` |
| `Package.resolved` | `swift` |
| `flake.lock` | `nix` |
| `.gitmodules` | `gitsubmodule` |

Other keys on the page as of that date, for repos that need them: `bazel`, `conda`, `deno`, `dotnet-sdk`, `helm`, `julia`, `elm`, `opentofu`, `rust-toolchain`, `sbt`, `vcpkg`.

Option facts the rules depend on, from the same page: `open-pull-requests-limit` counts version-update PRs only, and `0` disables version updates for the entry; `groups.<name>.applies-to` defaults to `version-updates`; `cooldown` applies to version updates only and defaults to three days.
