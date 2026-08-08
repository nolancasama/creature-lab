# Creature Lab

A 3D classroom ESL game (Godot 4.6.2) where the grammar **"It was… Now it is…"** *is* the
gameplay. A student picks an animal, programmes its DNA with three spoken sentences, and
the transformation chamber executes all three at once. The new creature goes to their zoo.

The rule the whole design turns on: **the animal on the platform always shows the combined
"It was…" state.** Choosing `small → big` makes the dog shrink *now*; "big" is only
recorded, never rendered, until the chamber runs. Past tense and present tense are two
objects on screen at the same time.

---

## Running it

```
godot --path .                       # play
godot --path . --headless -- --selftest    # content + assembly + grammar checks
godot --path . -- --autoplay              # plays a whole round through the real UI
godot --path . -- --phase=lab             # jump to a screen: select|lab|naming|zoo|settings
godot --path . -- --shot=zoo              # jump there, screenshot to user://, quit
```

`--selftest` builds every animal, every trait on every animal, every fantasy creature, and
runs the grammar validator against a table of transcripts (including homophones and
half-finished sentences). `--autoplay` drives the real `WordLab → LabController → Speech`
signal path and asserts the round ends in the naming screen. Both exit non-zero on failure.

**Speech:** Godot ships no speech-to-text. On a **web export** the game uses the browser's
Web Speech API (`scripts/speech/web_speech_backend.gd`); everywhere else — and whenever a
mic is unavailable or a teacher switches it off — students type the sentence instead. The
game plays identically either way, because both go through `SpeechService`. Text-to-speech
does work natively via `DisplayServer.tts_*`.

---

## What was changed from the two spec documents, and why

Everything below is a deliberate departure. The core loop, the DNA log, the chamber, the
Word Lab, the naming screen and the zoo are as specified.

| Spec said | What this does | Why |
|---|---|---|
| Word Lab lists `old ↔ new` **and** `young ↔ old`; `tall ↔ short` **and** `long ↔ short` | The validator checks the transcript against **the pair the student selected**, never "which pair did they say" | `old` and `short` are each the opposite of two different words. Word-level matching would be guesswork; pair-scoped matching is exact. |
| Zoo is "session only" (gameplay doc) / SaveManager stores the zoo (architecture doc) | Zoo is a session concept, mirrored to `user://zoo_session.json` | The two docs contradicted each other. A crash or an accidental Alt+F4 should not delete a child's morning. Teacher Settings has a switch and a Reset. |
| *(no failure path anywhere)* | Scaffold ladder: retry → "I heard *It was small*, now say *Now it is big*" → TTS models the sentence → teacher can accept it | The success path was fully specified and the failure path was not. In a classroom the failure path decides whether a child keeps going. Nothing can dead-end a lesson. |
| "Easy Mode is the default gameplay mode" (no other mode defined) | Split into three independent teacher dials: **who chooses** (free/guided), **how strict** (lenient/normal/exact), **how much is printed** (whole sentence / frame with gaps / nothing) | One undefined word became three settings a teacher can actually raise over a term. Hidden mode is where the student stops reading and starts producing. |
| *(nothing about mis-taps)* | "Change card" reverts the pending BEFORE trait; used categories lock out | A child who mis-taps was otherwise stuck with it. |
| `TransformationSequence` as its own scene | TRANSFORMATION is a real FSM phase that routes back to the **same** lab scene | The animal is supposed to *walk into* the chamber standing in the lab. Cutting to a fresh scene at that exact moment breaks the one beat the design is built around. |
| Zoo creatures use `NavigationAgent3D` | Steering wander inside `CreatureBrain` | The yard is flat and has no obstacles: a navmesh is bake time and per-frame agent cost for a problem that does not exist. Movement is contained in one class, so swapping the agent in later touches nothing else. |
| Content as `Resources/*.tres` | Content as `content/*.json`, loaded into the same typed `Resource` classes | Hand-authoring this much data as `.tres` is unmaintainable, and a teacher can edit JSON in Notepad. The Resource classes still exist, so `.tres` authoring stays possible. |
| *(no art pipeline)* | Animals are **rigged models** from `models/animals.glb`, driven by **bone** names listed in data | Started as runtime-assembled primitives, since no art existed. Swapped to the ITHappy "Animals FREE" pack once it was available. The data-driven promise survived the swap: "Length Modifier → ears / tail / wings" is still a JSON field, now naming a bone instead of a shape. |
| Creature reveal, then a separate naming screen | The naming screen shows the **before-animal as a translucent ghost beside the finished creature**, with the three sentences underneath | The contrast *is* the grammar point, and a scene change was hiding it. Seeing a small red dog next to a big blue horned hound is the moment the lesson lands. |

---

## Architecture

```
Game (FSM + the one CreatureState)  ──phase_changed──▶  Router (swaps scenes)
       ▲                                                     │
       │ record_sentence()                                   ▼
LabController ◀── pair_selected ── WordLab              CreatureLab / Zoo / …
       │
       ├─▶ CreatureState ─▶ CreatureFactory ─▶ CreatureRig (assembled from data)
       └─▶ Speech ─▶ SpeechBackend ─▶ GrammarValidator
```

`Game` owns *what is true*; `Router` owns *which scene shows it*; they only talk through a
signal, so no scene reaches into another. The Word Lab never touches the animal — it
reports a choice, `LabController` decides what that means, `CreatureState` records it, and
the rig is rebuilt from that state. Speech never touches grammar: recognition,
normalisation and validation are three separable stages.

```
content/            traits, colours, animals, fantasy parts (JSON)
scripts/autoload/   Content, Settings, SaveService, Game, Router, Audio, Tts, Speech
scripts/data/       typed Resource classes + CreatureState
scripts/speech/     backends, normaliser, validator
scripts/creature/   rig assembly, trait visuals, fantasy builder, namer, zoo AI
scripts/scenes/     one controller per screen
scripts/ui/         UiKit (2D theme), StageKit (3D staging), debug overlay
```

Trait visuals are applied **as a whole set from a clean baseline**, never incrementally, so
the result never depends on the order the student picked their cards and "undo that card"
is just another call with one fewer entry.

Fantasy creatures are deterministic: `CreatureState.fingerprint()` seeds everything, so the
same three sentences always grow the same creature on any machine, in any session.

---

## Extending it — no code changes needed

**A new opposite pair** → add a row to `content/traits.json` and pick a `modifier` from the
ones `scripts/creature/trait_visuals.gd` implements (`SCALE_UNIFORM`, `SCALE_Y`,
`SCALE_FEATURE`, `BULK`, `TEMPO`, `THERMAL`, `AGE`, `SURFACE`, `MATERIAL`). It appears in
the Word Lab and in Teacher Settings immediately.

**A new colour** → one row in `content/colors.json`.

**A new animal** → one entry in `content/animals.json` naming a node inside
`models/animals.glb` plus the bones the traits drive: `body_bones` (the torso segments
LONG/SHORT pushes apart), `legs` (each leg's telescoping segments, listed in the order
they pop out for TALL), `bulk_bones` (what STRENGTH thickens), `leg_bones` (what the
walk cycle swings), and four sockets for fantasy parts. `--selftest` verifies **every bone name
against the real skeleton**, so a typo fails the build instead of silently doing nothing.
Models are auto-scaled to `stand_height`, so source scale does not matter.

**A new fantasy part** → one entry in `content/fantasy_parts.json` with the `trigger` word
and a socket.

---

## Status

**Phase 1 is complete and playable**: title → animal selection *and* sentence recording on
one screen → transformation chamber → naming → zoo, plus Teacher Settings, the debug
overlay (F3), procedural audio, and TTS. Seven animals, eight opposite pairs and ten
colours ship as data.

**Art:** animal models are the [ITHappy "Animals FREE" pack](https://ithappystudios.com/free/animals-free/)
(free for commercial and non-commercial use). Fantasy add-on parts — horns, crests, wings —
are still generated from primitives at runtime.

**Transformations are cartoon animations, not scale changes.** `long/short` stretches
only the torso (bones are *translated* apart, so the head, legs and tail keep their own
shape) with a taffy overshoot and rebound; `tall/short` floats the body to its new height
and then drops each leg to the ground one at a time. The two "short"s are deliberately
different — one squashes the body, the other retracts the legs. See
`scripts/creature/creature_deformer.gd`.

**Not done (Phase 2/3):** the pack ships **no animations**, so idle and walk are posed
procedurally in `CreatureRig._swing_legs()`; a real animation set would look considerably
better. Also outstanding: richer zoo interactions, camera moves, and a low-graphics
toggle for weaker Chromebooks. The zoo is designed for 20–30 creatures and caps at 30.
