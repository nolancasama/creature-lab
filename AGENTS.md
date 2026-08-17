# Working in this repo

Godot 4.6.2 classroom ESL game. `README.md` has the design rules — read it before
changing gameplay; several things that look like bugs are deliberate.

## Git

Work on `main` in this repo (`github.com/nolancasama/creature-lab`). `main` already
tracks `origin/main`, so plain `git push` needs no arguments.

**If you can push, push before you finish.** Claude Code can (the `gh` login and the
`wincred` helper are both in place).

**If you cannot push — Codex runs sandboxed with no network — say so in your last
message, with the number of unpushed commits.** That is the part that actually matters:
a commit that never leaves the machine looks like lost work to the next tool that opens
the repo, and silence about it is what makes it look lost. On 2026-08-18 four commits sat
unpushed and a UI redesign appeared to have vanished.

## Before saying a change works

`--selftest` PASSES even when a scene script has a parse error, because it never loads
the scene. In game, a parse error looks like a silent **grey screen** and nothing else —
no crash, no message. So after touching anything under `scripts/scenes/`, run one of
these, which print the parse error on stderr:

    godot --path . -- --autoplay       # drives a whole round through the real signal path
    godot --path . -- --shot=select    # renders one scene to a PNG in user://
                                       # (also lab|naming|zoo|settings|title)

Godot lives at `C:\Users\nolan\Downloads\godot462\Godot_v4.6.2-stable_win64_console.exe`.

A grey screen reached the live site this way once already: a redesign deleted the DNA Log
panel but left one call to it behind, and selftest stayed green the whole time.

## Deploying

    ./deploy-vercel.sh

Exports and publishes to https://creature-lab-esl.vercel.app/. It re-links the Vercel
project on every run and fails unless the live URL answers 200. Do not "simplify" either
of those — both guard against failures that have actually happened, described in the
script's header comment.
