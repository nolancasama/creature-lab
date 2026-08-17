class_name GrammarValidator
extends RefCounted
## Judges a transcript against the sentence the student was asked to say.
##
## It validates against *the pair the student selected*, never "which pair did they say".
## That single decision removes the ambiguity baked into the vocabulary list: `old` is the
## opposite of both `new` and `young`, and `short` is the opposite of both `tall` and
## `long`, so word-level matching would be guesswork. Pair-scoped matching is exact.
##
## Reason codes: ok, empty, nothing, no_before, no_after, swapped, frame_before,
## frame_after, exact. Past-only mode raises only: ok, empty, nothing, frame_before, exact.

const BEFORE_FRAME := "it was"
const AFTER_FRAME := "now it is"

## Kept local rather than read off Settings so the validator stays testable in isolation.
## These mirror Settings.STRICT_*.
const LENIENT := 0
const NORMAL := 1
const EXACT := 2


static func expected_sentence(before: String, after: String) -> String:
	return "%s %s %s %s" % [BEFORE_FRAME, before, AFTER_FRAME, after]


## Just the past half, which is all the student is asked for in Settings.SAY_PAST.
static func expected_past(before: String) -> String:
	return "%s %s" % [BEFORE_FRAME, before]


## `past_only` is passed in rather than read off Settings, for the same reason the
## strictness constants are duplicated here: this class stays testable on its own.
static func validate(transcript: String, before: String, after: String, strictness: int, past_only := false) -> Dictionary:
	var normalized := TextNormalizer.strip_edge_filler(TextNormalizer.normalize(transcript))
	var result := {
		"ok": false,
		"reason": "empty",
		"normalized": normalized,
		"said_before": false,
		"said_after": false,
		"frame_before": false,
		"frame_after": false,
	}
	if normalized.is_empty():
		return result

	# Word-level presence, in order. This drives the "I heard the first half" feedback
	# regardless of which strictness the teacher picked.
	var word_before := TextNormalizer.find_phrase(normalized, before)
	var word_after := TextNormalizer.find_phrase(normalized, after, maxi(word_before + 1, 0))
	result["said_before"] = word_before >= 0
	result["said_after"] = word_after >= 0

	var frame_before := TextNormalizer.find_phrase(normalized, "%s %s" % [BEFORE_FRAME, before])
	var frame_after := TextNormalizer.find_phrase(normalized, "%s %s" % [AFTER_FRAME, after], maxi(frame_before + 1, 0))
	result["frame_before"] = frame_before >= 0
	result["frame_after"] = frame_after >= 0

	if past_only:
		# Only the first clause is asked for, so the second is neither required nor
		# penalised - a student who runs on into "now it is big" has still said the part
		# that was set, and is not corrected for volunteering more.
		if strictness >= EXACT:
			result["ok"] = normalized == expected_past(before)
		elif strictness <= LENIENT:
			result["ok"] = word_before >= 0
		else:
			result["ok"] = frame_before >= 0
		result["reason"] = "ok" if result["ok"] else _diagnose_past(result, normalized, before)
		return result

	if strictness >= EXACT:
		result["ok"] = _matches_exactly(normalized, before, after)
		result["reason"] = "ok" if result["ok"] else _diagnose(result, normalized, before, after, true)
	elif strictness <= LENIENT:
		result["ok"] = word_before >= 0 and word_after > word_before
		result["reason"] = "ok" if result["ok"] else _diagnose(result, normalized, before, after, false)
	else:
		result["ok"] = frame_before >= 0 and frame_after > frame_before
		result["reason"] = "ok" if result["ok"] else _diagnose(result, normalized, before, after, false)
	return result


## Exact mode still tolerates the one join word children naturally insert.
static func _matches_exactly(normalized: String, before: String, after: String) -> bool:
	var target := expected_sentence(before, after)
	if normalized == target:
		return true
	return normalized == target.replace(AFTER_FRAME, "and " + AFTER_FRAME)


## Past-only never reports no_after or frame_after: the second clause was never asked for,
## so naming it as missing would teach the student they had failed at something they were
## not set.
static func _diagnose_past(result: Dictionary, normalized: String, before: String) -> String:
	if not bool(result["said_before"]):
		return "nothing"
	if not bool(result["frame_before"]):
		return "frame_before"
	return "exact" if normalized != expected_past(before) else "ok"


static func _diagnose(result: Dictionary, normalized: String, before: String, after: String, exact: bool) -> String:
	if not bool(result["said_before"]) and not bool(result["said_after"]):
		# Did they say either word at all, in any order?
		if TextNormalizer.find_phrase(normalized, after) >= 0:
			return "swapped"
		return "nothing"
	if bool(result["said_before"]) and not bool(result["said_after"]):
		return "no_after"
	if not bool(result["said_before"]) and bool(result["said_after"]):
		# The adjective is there but the "It was ___" half is missing or came second.
		return "swapped" if TextNormalizer.find_phrase(normalized, before) >= 0 else "no_before"
	if not bool(result["frame_before"]):
		return "frame_before"
	if not bool(result["frame_after"]):
		return "frame_after"
	return "exact" if exact else "frame_after"
