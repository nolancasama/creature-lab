# Current state

Creature Lab's speech path is browser -> `SpeechSession` -> `SpeechAttemptClassifier` ->
animal-selection attempt controller -> game. Typed answers share the classifier without
entering microphone lifecycle state.

Teacher Settings selects English or Japanese as the student target language. The
`TargetLanguage` autoload reads the frozen Japanese pack and supplies category-keyed display
text, sentence forms, STT/TTS locales, and exact Japanese recognition data while all creature
state and saved entries remain English semantic IDs.

The Chrome bridge uses real `onstart`, one fresh recogniser per session, four alternatives,
and session IDs on every callback. Voice recording remains a separate browser feature driven
only by session capture start/finish and the game's keep/discard decision.

Automated speech coverage lives in the existing `--speechtest` and `--scaffoldtest` harness
commands. It includes Japanese difficulty, tense, protected-vocabulary, pack-completeness,
and web-font fixtures. Real Chrome permission, microphone, and Web Speech behaviour still
require browser verification.
