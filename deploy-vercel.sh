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
# The SSO deployment protection that new Vercel projects get by default has to stay off
# (`vercel project protection disable creature-lab --sso`) - with it on, the site 302s
# every visitor to a Vercel login page, which is useless for a classroom.
#
# The project link lives in web-build/.vercel/project.json, but web-build/ is gitignored
# and is recreated by every export, so that link cannot be trusted to survive. Linking
# was once treated as one-time setup, and on 2026-08-17 the consequence showed up: the
# link had gone missing, a bare `vercel deploy` in there silently created a SECOND
# project named after the folder ("web-build") rather than failing, and every deploy
# after that landed in it. The alias pointed into that stray project, whose default SSO
# protection 302'd every visitor - while `vercel project protection disable creature-lab
# --sso` kept reporting success, because it was clearing protection on the project that
# no longer served the alias. Hence the re-link on every run below.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GODOT="/c/Users/nolan/Downloads/godot462/Godot_v4.6.2-stable_win64_console.exe"
ALIAS="creature-lab-esl.vercel.app"
PROJECT="creature-lab"

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
# Re-assert the link before deploying, every time (see the note at the top of this file).
# Without it, a missing .vercel makes `vercel deploy` invent a project named after this
# folder and publish there, which looks like a successful deploy and isn't one.
vercel link --project "$PROJECT" --yes >/dev/null

# --prod publishes to the project's production deployment; the stable alias below is
# what people actually visit, so it is re-pointed at whatever this run produced.
#
# The URL is grepped out rather than taken from the last line: the CLI interleaves
# build logs and a JSON tail, so `tail -1` picks up a stray "}" and the alias fails.
DEPLOY_LOG=$(mktemp)
vercel deploy --prod --yes 2>&1 | tee "$DEPLOY_LOG"
URL=$(grep -oE 'https://[a-z0-9-]+-nolan-casamas-projects\.vercel\.app' "$DEPLOY_LOG" | tail -1)
rm -f "$DEPLOY_LOG"
if [ -z "$URL" ]; then
	echo "error: could not find the deployment URL in the Vercel output" >&2
	exit 1
fi
vercel alias set "$URL" "$ALIAS"
popd >/dev/null

# A "successful" deploy still fails the classroom if the alias answers with a login
# redirect, so confirm an actual 200 rather than trusting the CLI's output. Retried a
# couple of times because the alias takes a moment to propagate to the edge.
echo "==> Verifying https://$ALIAS is publicly reachable..."
STATUS=000
for _ in 1 2 3; do
	STATUS=$(curl -so /dev/null -w '%{http_code}' "https://$ALIAS/" || echo 000)
	[ "$STATUS" = "200" ] && break
	sleep 3
done

if [ "$STATUS" != "200" ]; then
	echo "error: https://$ALIAS/ returned HTTP $STATUS, not 200." >&2
	case "$STATUS" in
	302 | 401)
		echo "       a redirect or 401 here means deployment protection is back on. Check" >&2
		echo "       which project actually serves the alias, then clear it there:" >&2
		echo "         vercel alias ls | grep $ALIAS" >&2
		echo "         vercel project protection disable $PROJECT --sso" >&2
		;;
	esac
	exit 1
fi

echo "==> Live at: https://$ALIAS"
echo "    pack: $(curl -sI "https://$ALIAS/index.pck" | grep -i '^content-length' | tr -d '\r' | cut -d' ' -f2) bytes"
