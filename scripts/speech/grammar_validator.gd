class_name GrammarValidator
extends RefCounted
## Shared lesson-frame constants and display helpers.
## Attempt classification lives in SpeechAttemptClassifier.

const BEFORE_FRAME := "it was"
const AFTER_FRAME := "now it is"

const HEAR_LENIENT := 0
const HEAR_NORMAL := 1
const HEAR_EXACT := 2

const CLAUSE_BOTH := 0
const CLAUSE_PAST := 1
const CLAUSE_PRESENT := 2


static func expected_sentence(before: String, after: String) -> String:
	return "%s %s %s %s" % [BEFORE_FRAME, before, AFTER_FRAME, after]


static func expected_past(before: String) -> String:
	return "%s %s" % [BEFORE_FRAME, before]


static func expected_present(after: String) -> String:
	return "%s %s" % [AFTER_FRAME, after]
