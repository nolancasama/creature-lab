# Design decisions

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

