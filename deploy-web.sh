#!/usr/bin/env bash
# Exports the current source on `main` to a web build and publishes it to `gh-pages`,
# which GitHub Pages serves at https://nolancasama.github.io/creature-lab/.
#
# Run from anywhere; it cd's to its own location first. Usage:
#   ./deploy-web.sh
#   ./deploy-web.sh "custom deploy message"
#
# Why a worktree instead of `git checkout gh-pages`: switching branches in place in this
# same folder is exactly what caused a lost afternoon earlier in this project's history
# (forgot to switch back, kept editing source that wasn't there). A worktree opens
# gh-pages as a second folder, so `main` here is never checked out away from under you.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GODOT="/c/Users/nolan/Downloads/godot462/Godot_v4.6.2-stable_win64_console.exe"
WORKTREE_DIR="../creature-lab-pages"
DEPLOY_MSG="${1:-Deploy web build}"

if [ ! -f "$GODOT" ]; then
	echo "error: Godot not found at $GODOT" >&2
	echo "       edit the GODOT path in this script if it has moved." >&2
	exit 1
fi

if [ -n "$(git status --porcelain -- ':!web-build')" ]; then
	echo "warning: main has uncommitted source changes." >&2
	echo "         this deploys whatever is on disk right now, committed or not -" >&2
	echo "         consider 'git commit' first so the live build matches a real commit." >&2
fi

echo "==> Exporting release build..."
mkdir -p web-build
"$GODOT" --headless --path . --export-release "Web" web-build/index.html
rm -f web-build/*.import web-build/server.log

if [ ! -s web-build/index.wasm ]; then
	echo "error: export did not produce web-build/index.wasm" >&2
	exit 1
fi
echo "    built: $(du -h web-build/index.wasm | cut -f1) wasm"

# Clean up a stale worktree from an interrupted previous run, if one is lying around.
if git worktree list | grep -q "$WORKTREE_DIR"; then
	git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || true
fi
rm -rf "$WORKTREE_DIR" 2>/dev/null || true

echo "==> Opening gh-pages as a worktree..."
git worktree add "$WORKTREE_DIR" gh-pages

cleanup() {
	git worktree remove --force "$WORKTREE_DIR" 2>/dev/null || true
	rm -rf "$WORKTREE_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# Windows briefly locks large files right after `git checkout` writes them (real-time
# antivirus scanning a fresh 37MB write is the usual cause) - it clears on its own
# within a second or two, so retry instead of failing the whole deploy over it.
for attempt in 1 2 3 4 5; do
	if cp web-build/index.* "$WORKTREE_DIR"/ 2>/tmp/cp_err; then
		break
	fi
	if [ "$attempt" -eq 5 ]; then
		echo "error: could not copy build into worktree after 5 attempts:" >&2
		cat /tmp/cp_err >&2
		exit 1
	fi
	echo "    (file briefly locked, retrying...)"
	sleep 2
done

pushd "$WORKTREE_DIR" >/dev/null
git add -A
if git diff --cached --quiet; then
	echo "==> No changes since the last deploy - nothing to push."
	popd >/dev/null
	exit 0
fi
git commit -q -m "$DEPLOY_MSG"
git push origin gh-pages
COMMIT=$(git rev-parse --short HEAD)
popd >/dev/null

echo "==> Pushed $COMMIT. GitHub Actions will publish it automatically in ~30s:"
echo "    https://github.com/nolancasama/creature-lab/actions/workflows/pages.yml"
echo "==> Live at: https://nolancasama.github.io/creature-lab/"
