# Design decisions

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

