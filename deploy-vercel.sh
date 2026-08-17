#!/usr/bin/env bash
# Exports the current source to a web build and publishes it to Vercel, which serves it
# at https://creature-lab-esl.vercel.app/.
#
# Run from anywhere; it cd's to its own location first. Usage:
#   ./deploy-vercel.sh
#
# Why Vercel and not GitHub Pages: Pages stopped publishing this repo after 2026-08-09.
# Every deploy since then pushed to gh-pages fine, but the Deploy Pages workflow sat
# "pending" with no jobs ever assigned until it was cancelled - no runner, no error, no
# diagnostics. The same GitHub-side failure hit the vacation-adventure project on
# 2026-08-06 and was never resolved there either. deploy-web.sh still works and is kept
# around in case Pages ever recovers; this script is the one that actually publishes.
#
# One-time setup already done: `vercel link --project creature-lab` inside web-build,
# and the SSO deployment protection that new Vercel projects get by default was turned
# off (`vercel project protection disable creature-lab --sso`) - with it on, the site
# 302s every visitor to a Vercel login page, which is useless for a classroom.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GODOT="/c/Users/nolan/Downloads/godot462/Godot_v4.6.2-stable_win64_console.exe"
ALIAS="creature-lab-esl.vercel.app"

if [ ! -f "$GODOT" ]; then
	echo "error: Godot not found at $GODOT" >&2
	echo "       edit the GODOT path in this script if it has moved." >&2
	exit 1
fi

if [ -n "$(git status --porcelain -- ':!web-build')" ]; then
	echo "warning: there are uncommitted source changes." >&2
	echo "         this deploys whatever is on disk right now, committed or not." >&2
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

echo "==> Deploying to Vercel..."
pushd web-build >/dev/null
# --prod publishes to the project's production deployment; the stable alias below is
# what people actually visit, so it is re-pointed at whatever this run produced.
URL=$(vercel deploy --prod --yes | tail -1 | tr -d '\r')
vercel alias set "$URL" "$ALIAS"
popd >/dev/null

echo "==> Live at: https://$ALIAS"
echo "    (verify with: curl -sI https://$ALIAS/index.pck | grep -i content-length)"
