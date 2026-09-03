# Current state

Creature Lab's speech path is browser -> `SpeechSession` -> `SpeechAttemptClassifier` ->
animal-selection attempt controller -> game. Typed answers share the classifier without
entering microphone lifecycle state.

The Chrome bridge uses real `onstart`, one fresh recogniser per session, four alternatives,
and session IDs on every callback. Voice recording remains a separate browser feature driven
only by session capture start/finish and the game's keep/discard decision.

Automated speech coverage lives in the existing `--speechtest` and `--scaffoldtest` harness
commands. Real Chrome permission, microphone, and Web Speech behaviour still require browser
verification.
