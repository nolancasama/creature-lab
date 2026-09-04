# Design decisions

## Target language

- Creature and save data remain English semantic IDs. `TargetLanguage` resolves
  `CATEGORY/word` keys only at display, recognition, and TTS boundaries, so the two meanings
  of `short` cannot collide and changing languages cannot change a creature fingerprint.
- English keeps its existing sentence and token-matching path. Japanese uses exact
  containment over authored surface forms after width, punctuation, and whitespace
  normalization. Overlapping matches belong to the longest authored form, so `きいろ`
  inside `むらさきいろ` cannot become a protected-word collision; difficulty changes
  required sentence structure, never character fuzziness.
- Student-facing Japanese is kana; recognition forms carry kanji. The bundled font subset
  holds every kana but only some kanji, and Chrome's ja-JP recogniser returns 大きい whether
  or not the game ever draws it - a transcript is compared as a string and never rendered.
  So display and recognition are separate axes, and a fixture asserts every `display` string
  is renderable, because the --selftest font check only scans source literals and would miss
  text loaded from JSON.
- Vocabulary is keyed CATEGORY/word because English reuses one word across two pairs:
  HEIGHT/short (せがひくい, the legs) and LENGTH/short (みじかい, the body). Keyed by word
  alone those collapse into one another, in display and in protected-vocabulary conflicts.
- AGE/old is the one entry with no adjectival antonym - 若い has none that suits an animal
  and 古い is for objects. Settled on 年を取っています; 年寄り stays an accepted alternate,
  because a child saying the simpler correct thing must not be marked wrong. It is also the
  pack's only verb phrase, so the polite-ending test covers ます/ました as well as です/でした
  - a です-only rule would have failed the canonical answer in Challenge while accepting the
  alternate, which is exactly backwards.
- A language change cancels the live recogniser before rebuilding its backend and TTS voice.
  CHECKING/FINISHING deliberately cannot be cancelled, so a change requested in that tail is
  applied as soon as `onend` closes it. Browser sessions therefore finish under the locale
  they started with, and the next tap uses the new locale without reloading the page.

## Creature continuity into the chamber

- `CreatureRig._ready()` re-runs `deformer.apply()`. Traits are deliberately applied while
  a rig is still outside the tree - the chamber builds its creature complete so no plain
  animal is ever visible - but `CreatureDeformer._recentre()` measures how far the body
  grew via `get_bone_global_pose()`, and an out-of-tree skeleton reports none. So a
  lengthened animal was never slid back and arrived sitting where an ordinary one would:
  0.245 units off on a dog, 0.275 on a horse, 0.011 on a penguin. It stayed wrong until
  some later `apply()` ran inside the tree - which the first LONG beat did, hence a
  creature that looked like it reset to normal and then jumped into place at the first
  "Now it is short", and hence why it was only sometimes noticed.
- The reported symptom was "the creature reverts to its base form", and the plan proposed
  reparenting the live rig across the handoff to avoid reconstruction. Measurement showed
  the reconstruction was fine - body length was already correct on frame one - and only
  the model offset differed. The rig transfer was not needed and was not done.
- `--recentretest` compares an in-tree lengthened rig against one lengthened before being
  added, per animal. It asserts a real offset exists first, because a test that only
  compared the two paths would pass with both at zero - which is exactly how the first
  version of it passed against the bug.

## Teacher Settings

- Settings is an overlay mounted above the live scene by `Main`, not a routed phase.
  `Phase.TEACHER_SETTINGS` is gone. Routing it freed the running scene and built a fresh
  one on return, and a fresh Animal Selection only knows how to resume into the Before
  pass - so adjusting a setting during the present-tense pass dropped the student back
  into adjective recording. Restoring that state onto `Game` instead would have meant a
  growing set of fields describing UI that never needed to stop existing.
- The scene underneath is frozen with `PROCESS_MODE_DISABLED` rather than covered by an
  input blocker: one move stops processing, input, timers and tweens across the subtree,
  so the turntable stops rather than spinning behind an opaque panel. Autoloads are
  untouched, so audio and saving keep working. Any live microphone session is cancelled on
  open, because `_exit_tree()` used to do that and nothing leaves the tree now.
- `--settingstest` asserts the scene's *instance ID* is unchanged across a settings visit,
  not merely that the mode looks right afterwards - a rebuild-and-restore implementation
  would satisfy a mode check and still be the architecture this replaced.

## Loading screen

- The splash waits on `ShaderWarmup.finished`, not a duration. The compile cost is
  whatever a given driver makes it and a classroom's Chromebooks disagree; `MINIMUM` only
  stops it flashing and `MAXIMUM` only stops it looking hung. Dots rather than a bar: the
  per-item compile cost ranges from 17ms to 3.2s, so a determinate bar would visibly
  stall, and a stalled bar reads as broken. The stalls block the main thread, so any
  indicator stutters - dots are the one whose stutter still reads as working.

## Stage ground

- `StageKit.GROUND_RADIUS` / `GROUND_COLOR` are shared constants, not per-scene literals.
  Animal Selection hands off into the transformation chamber with the router's fade
  skipped (`request_seamless_next_swap()`) specifically so the cut is invisible; a radius
  or colour drift between the two scenes' `StageKit.ground()` calls (previously 9.0 vs
  30.0) becomes the one-frame pop that swap exists to avoid. The camera and platform were
  already hair-matched (`apply_before_view()`); the ground was the one thing that wasn't.

## Speech difficulty and the checking state

- The assisted-pass threshold belongs to the mode, not the scene: Easy 3, Standard 4,
  Challenge 5 (`Settings.ASSIST_AFTER`). Tolerance and patience move together, because a
  recogniser that is harder to satisfy owes the student more tries. One flat threshold of
  three gave the strictest mode the fewest real chances, which is backwards. From
  classroom use: students enjoyed the challenge and several retried past three of their
  own accord, and an assisted pass arriving too early took that away.
- Standard is the default for a machine with no saved teacher configuration. Existing
  configs are untouched - `load_settings()` reads whatever key is already there.
- `きびしい` became `チャレンジ`: the mode is a harder game, not a harsher judgement of the
  child, and it now also grants the most retries.
- `SpeechSession.State.CHECKING` covers the gap between Chrome's `onspeechend` and the
  transcript returning from its server. It is a real state, not a caption, because the
  microphone must be shut to taps for its duration - a second attempt started there races
  the first one's result. `timeout()` deliberately still excludes it: timing out while a
  result is in flight would discard an answer the student already gave.
- Adding it meant admitting CHECKING to the `final`, `interim`, `start` and `browser_ended`
  guards. Missing `final` alone would have ignored every utterance in a real browser,
  since `speechend` always precedes `final`; the injected-backend fixtures caught that.

## Speech attempts

- One microphone tap creates one monotonic `SpeechSession`. Browser callbacks carry its ID;
  stale and duplicate callbacks cannot produce another result.
- Attempt classification has four outcomes: `PASS`, `EFFORTFUL_WRONG`, `UNCERTAIN`, and
  `TECHNICAL_ERROR`. Only effortful wrong answers advance the three-try scaffold.
- Grammar requires `was` or `is` plus the target adjective. `it` and `now` remain optional;
  protected vocabulary and grammar tokens cannot fuzzy-match into different game answers.
- A bare protected adjective is uncertain unless it is the target adjective itself or the
  opposite the lesson pairs it with. Frame evidence, target-specific aliases, and safe
  near-matches also count as relevant effort. The target adjective was briefly excluded on
  the grounds that a clean game word is easy to pick up from a neighbouring table; that
  ranked the commonest beginner under-answer ("strong" for "It was strong") below its own
  opposite and left those children looping on "try again" without ever being shown the
  modelled sentence, which is the help they specifically needed. A stray word from the next
  table triggering that help costs a child nothing; withholding it costs them the lesson.
- Interim hypotheses may only pass through exact or known-alias matching. Recognition stops
  immediately, while voice capture keeps a 0.7-second tail.
- A retry tapped during `FINISHING` is queued and begins from `onend`. Timeout and an empty
  `onend` each produce one neutral uncertainty; cancellation produces no result.
- Effortful-failure counts reset for every target clause, including the separate past and
  present colour prompts.
