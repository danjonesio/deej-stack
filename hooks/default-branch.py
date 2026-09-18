#!/usr/bin/env python3
"""Default-branch guard. All work goes on a branch; nothing the agent runs pushes to the default one.

  default-branch.py pre-push       Before a shell command: deny (the reason goes to the agent) when the
                                   command contains a `git push` that would update the default branch,
                                   `main`, or `master` on any remote.
  default-branch.py session-start  At session start: when HEAD is on such a branch, tell the agent to
                                   branch before committing.

One script, two harnesses; the stdin JSON says which is calling (Cursor sends `cursor_version`).
                 Claude Code (hooks.json)                     Cursor (hooks-cursor.json)
  pre-push       PreToolUse/Bash, tool_input.command          beforeShellExecution, command
  deny           hookSpecificOutput.permissionDecision        permission + agent_message + user_message
  allow          no output                                    no output (an explicit "allow" is never sent:
                                                              it could outrank the user's own approval prompt)
  session-start  plain stdout                                 {"additional_context": ...}

Read-only: it runs git queries and nothing else. It fails open: input it cannot parse exits 0, so a
bug here never blocks an unrelated command. The server-side counterpart is the d-github ruleset.
"""

import json
import os
import re
import shlex
import subprocess
import sys

ALWAYS_PROTECTED = {"main", "master"}
WRAPPERS = {"sudo", "command", "env", "nohup", "time", "exec"}
SHELLS = {"bash", "sh", "zsh", "dash"}
GIT_VALUE_OPTS = {"-c", "--git-dir", "--work-tree", "--namespace", "--config-env"}
PUSH_VALUE_OPTS = {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}
PUSH_EVERYTHING = {"--all", "--branches", "--mirror"}


def git(cwd, *args):
    try:
        out = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return ""
    return out.stdout.strip() if out.returncode == 0 else ""


def current_branch(cwd):
    return git(cwd, "symbolic-ref", "--short", "-q", "HEAD")


def protected(cwd, remote="origin"):
    names = set(ALWAYS_PROTECTED)
    for r in {remote, "origin"}:
        head = git(cwd, "symbolic-ref", "--short", "-q", f"refs/remotes/{r}/HEAD")
        if head.startswith(r + "/"):
            names.add(head[len(r) + 1:])
    return names


def tokens(command):
    command = command.replace("\n", " ; ")
    lex = shlex.shlex(command, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.commenters = ""
    try:
        return list(lex)
    except ValueError:  # unbalanced quotes, usually a heredoc body
        return command.split()


def simple_commands(toks):
    """Split on shell operators; drop redirections with their targets, and comments."""
    cur, skip, comment = [], False, False
    for t in toks:
        if skip:
            skip = False
        elif t and all(c in ";&|()<>" for c in t):
            if "<" in t or ">" in t:
                skip = True
            else:
                if cur:
                    yield cur
                cur, comment = [], False
        elif comment or t.startswith("#"):
            comment = True  # runs to the next operator; a newline is one
        else:
            cur.append(t)
    if cur:
        yield cur


def switched_to(args):
    """Branch a `git switch` / `git checkout` earlier in the same command line lands on, or None."""
    for flag in ("-c", "-C", "-b", "-B", "--create", "--force-create", "--orphan"):
        if flag in args[:-1]:
            return args[args.index(flag) + 1]
    names = [a for a in args if not a.startswith("-")]
    return names[0] if names and "--" not in args else None


def push_verdict(args, cwd, head=None):
    """Reason the push is denied, or None. `head` overrides the branch HEAD is on."""
    flags, pos, i = set(), [], 0
    while i < len(args):
        a = args[i]
        if a == "--":
            pos += args[i + 1:]
            break
        if a in PUSH_VALUE_OPTS:
            i += 2
            continue
        if a.startswith("-"):
            flags.add(a.split("=")[0])
        else:
            pos.append(a)
        i += 1

    cur = head or current_branch(cwd)
    remote = pos[0] if pos else (git(cwd, "config", "--get", f"branch.{cur}.remote") or "origin")
    guarded = protected(cwd, remote)

    if flags & PUSH_EVERYTHING:
        return f"`{' '.join(sorted(flags & PUSH_EVERYTHING))}` pushes every branch, the default one included"

    for spec in pos[1:]:
        spec = spec.lstrip("+")
        if spec == ":":
            return "the `:` refspec pushes every matching branch, the default one included"
        dst = spec.split(":", 1)[1] if ":" in spec else spec
        if ":" not in spec and dst in ("HEAD", "@"):
            dst = cur
        dst = dst[len("refs/heads/"):] if dst.startswith("refs/heads/") else dst
        if dst in guarded:
            return f"`{spec}` updates `{dst}` on `{remote}`"

    if not pos[1:]:
        if cur in guarded:
            return f"HEAD is on `{cur}`, so a bare push updates `{cur}` on `{remote}`"
        mode = git(cwd, "config", "--get", "push.default")
        if mode == "matching":
            return "`push.default=matching` pushes every matching branch, the default one included"
        if mode in ("upstream", "tracking"):
            up = git(cwd, "config", "--get", f"branch.{cur}.merge").replace("refs/heads/", "", 1)
            if up in guarded:
                return f"`push.default={mode}` and `{cur}` tracks `{up}`, so a bare push updates `{up}`"
    return None


def command_verdict(command, cwd, depth=0):
    if "push" not in command or depth > 3:
        return None
    head = None  # the hook runs before the command, so a switch inside it has not happened yet
    for cmd in simple_commands(tokens(command)):
        while cmd and (re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", cmd[0]) or cmd[0] in WRAPPERS):
            cmd = cmd[1:]
        if not cmd:
            continue
        name = os.path.basename(cmd[0])
        if name == "cd" and len(cmd) > 1 and cmd[1] != "-":
            cwd = os.path.normpath(os.path.join(cwd, os.path.expanduser(cmd[1])))
        elif name in SHELLS:
            for i, t in enumerate(cmd[1:-1], 1):
                if re.match(r"^-[a-z]*c$", t):
                    reason = command_verdict(cmd[i + 1], cwd, depth + 1)
                    if reason:
                        return reason
        elif name == "git":
            where, i = cwd, 1
            while i < len(cmd) and cmd[i].startswith("-"):
                if cmd[i] == "-C" and i + 1 < len(cmd):
                    where = os.path.normpath(os.path.join(where, os.path.expanduser(cmd[i + 1])))
                    i += 1
                elif cmd[i] in GIT_VALUE_OPTS:
                    i += 1
                i += 1
            if i < len(cmd) and cmd[i] in ("switch", "checkout"):
                head = switched_to(cmd[i + 1:]) or head
            elif i < len(cmd) and cmd[i] == "push":
                reason = push_verdict(cmd[i + 1:], where, head)
                if reason:
                    return reason
    return None


def read_input():
    try:
        return json.load(sys.stdin)
    except (ValueError, OSError):
        return {}


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    data = read_input()
    cursor = "cursor_version" in data
    roots = data.get("workspace_roots") or []
    cwd = data.get("cwd") or (roots[0] if roots else "") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()

    if mode == "pre-push":
        command = (data.get("command") if cursor else (data.get("tool_input") or {}).get("command")) or ""
        reason = command_verdict(command, cwd)
        if reason:
            message = (
                f"deej-stack: push denied: {reason}. All work goes on a branch: "
                "`git switch -c <topic>` (commits already made come along), push that branch, and open a PR. "
                "Do not try another form of this push; if the user wants it, they run it themselves."
            )
            if cursor:
                json.dump({"permission": "deny", "agent_message": message,
                           "user_message": f"deej-stack blocked a push to the default branch: {reason}."}, sys.stdout)
            else:
                json.dump({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                                  "permissionDecisionReason": message}}, sys.stdout)
    elif mode == "session-start":
        cur = current_branch(cwd)
        if cur and cur in protected(cwd) and git(cwd, "remote") and git(cwd, "rev-parse", "-q", "--verify", "HEAD"):
            message = (
                f"deej-stack: HEAD is on `{cur}`, the default branch. Before the first change you will commit, "
                f"run `git switch -c <topic>`; a hook denies every push to `{cur}`."
            )
            if cursor:
                json.dump({"additional_context": message}, sys.stdout)
            else:
                print(message)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:  # fail open
        sys.exit(0)
