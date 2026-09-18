#!/usr/bin/env bash
# Installs the machine-wide git hooks of the secret-protection standard. The one d-github script that
# writes, and only outside any repo: it copies git-hooks/ beside it into ~/.config/deej-stack/git-hooks
# (or $DEEJ_GIT_HOOKS) and points the global core.hooksPath there. Run it only after the user said yes.
# Copies, not symlinks: the plugin cache path changes with every version. Re-run after a plugin update;
# facts.sh reports the installed pre-push as `outdated` when it differs from the shipped one.
# Undo: git config --global --unset core.hooksPath

set -eu
SRC="$(cd "$(dirname "$0")" && pwd)/git-hooks"
DEST="${DEEJ_GIT_HOOKS:-$HOME/.config/deej-stack/git-hooks}"
CHAINED="applypatch-msg pre-applypatch post-applypatch pre-commit pre-merge-commit prepare-commit-msg commit-msg post-commit pre-rebase post-checkout post-merge post-rewrite pre-auto-gc push-to-checkout sendemail-validate"

cur=$(git config --global --get core.hooksPath 2>/dev/null || true)
cur="${cur/#\~/$HOME}"
if [ -n "$cur" ] && [ "$cur" != "$DEST" ]; then
  echo "refused: global core.hooksPath is already $cur. Nothing was changed. Either add a pre-push there that runs $SRC/pre-push, or unset it and re-run." >&2
  exit 1
fi

mkdir -p "$DEST"
install -m 755 "$SRC/pre-push" "$DEST/pre-push"
for name in $CHAINED; do install -m 755 "$SRC/chain" "$DEST/$name"; done
git config --global core.hooksPath "$DEST"
echo "installed: $DEST (pre-push + $(echo $CHAINED | wc -w | tr -d ' ') chain hooks); global core.hooksPath set."
echo "undo: git config --global --unset core.hooksPath"
