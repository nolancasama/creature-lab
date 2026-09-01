class_name GrammarValidator
extends RefCounted
## Matches the required grammar frame after TextNormalizer has cleaned recogniser output.
## Tolerance changes only token recognition; `was` / `is` and adjective order never do.

const BEFORE_FRAME := "it was"
const AFTER_FRAME := "now it is"

## Kept local so this class remains testable without reading Settings.
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


## Validates every ranked recognition alternative. The first passing candidate wins;
## otherwise the failure with the most useful frame evidence is selected for feedback.
static func validate_alternatives(alternatives: PackedStringArray, before: String,
		after: String, tolerance: int, clause := CLAUSE_BOTH) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var best := {}
	var best_index := -1
	var passing_index := -1
	for index in alternatives.size():
		var transcript := str(alternatives[index])
		var result := validate(transcript, before, after, tolerance, clause)
		candidates.append({"transcript": transcript, "result": result})
		if passing_index < 0 and bool(result["ok"]):
			passing_index = index
		if best.is_empty() or _score(result) > _score(best):
			best = result
			best_index = index

	if passing_index >= 0:
		return {
			"ok": true, "selected_index": passing_index,
			"selected_transcript": str(alternatives[passing_index]),
			"result": candidates[passing_index]["result"], "candidates": candidates,
			"uncertain": false,
		}
	if best.is_empty():
		best = validate("", before, after, tolerance, clause)
	var all_uncertain := true
	for candidate in candidates:
		if not bool(candidate["result"].get("uncertain", false)):
			all_uncertain = false
			break
	return {
		"ok": false,
		"selected_index": best_index,
		"selected_transcript": "" if best_index < 0 else str(alternatives[best_index]),
		"result": best,
		"candidates": candidates,
		"uncertain": candidates.is_empty() or all_uncertain,
	}


static func validate(transcript: String, before: String, after: String, tolerance: int,
		clause := CLAUSE_BOTH) -> Dictionary:
	var normalized := TextNormalizer.strip_edge_filler(TextNormalizer.normalize(transcript))
	var result := {
		"ok": false,
		"reason": "empty",
		"normalized": normalized,
		"said_before": false,
		"said_after": false,
		"frame_before": false,
		"frame_after": false,
		"protected_conflict": false,
		"match_evidence": PackedStringArray(),
		"uncertain": normalized.is_empty(),
	}
	if normalized.is_empty():
		return result

	var words := PackedStringArray(normalized.split(" ", false))
	var protected := TextNormalizer.protected_vocabulary()
	var before_any := _find_adjective(words, before, 0, tolerance, protected)
	var after_any := _find_adjective(words, after, 0, tolerance, protected)
	result["said_before"] = int(before_any["index"]) >= 0
	result["said_after"] = int(after_any["index"]) >= 0

	var past := _match_clause(words, "was", before, 0, tolerance, protected)
	var present_from := int(past["adjective_index"]) + 1 if bool(past["ok"]) else 0
	var present := _match_clause(words, "is", after, present_from, tolerance, protected)
	result["frame_before"] = bool(past["ok"])
	result["frame_after"] = bool(present["ok"])
	result["protected_conflict"] = bool(past["protected_conflict"]) or bool(present["protected_conflict"])
	result["match_evidence"] = _evidence(past, present, clause)

	match clause:
		CLAUSE_PAST:
			result["ok"] = bool(past["ok"])
			result["reason"] = "ok" if result["ok"] else _diagnose_clause(
				past, bool(result["said_before"]), "frame_before")
			result["uncertain"] = _is_uncertain_failure(past, bool(result["said_before"]))
		CLAUSE_PRESENT:
			present = _match_clause(words, "is", after, 0, tolerance, protected)
			result["frame_after"] = bool(present["ok"])
			result["protected_conflict"] = bool(present["protected_conflict"])
			result["match_evidence"] = _evidence({}, present, clause)
			result["ok"] = bool(present["ok"])
			result["reason"] = "ok" if result["ok"] else _diagnose_clause(
				present, bool(result["said_after"]), "frame_after")
			result["uncertain"] = _is_uncertain_failure(present, bool(result["said_after"]))
		_:
			result["ok"] = bool(past["ok"]) and bool(present["ok"])
			result["reason"] = "ok" if result["ok"] else _diagnose_both(result, past, present)
			result["uncertain"] = not bool(result["ok"]) \
				and not bool(result["protected_conflict"]) \
				and (bool(past["weak_fuzzy"]) or bool(present["weak_fuzzy"])) \
				and not _has_clear_frame_miss(result)
	return result


## Finds the required frame word, then the expected adjective after it. `it` and `now`
## are intentionally absent because browsers often drop those unstressed words.
static func _match_clause(words: PackedStringArray, frame_word: String, adjective: String,
		from_word: int, tolerance: int, protected: Dictionary) -> Dictionary:
	var frame := TextNormalizer.find_token(words, frame_word, from_word, tolerance, protected)
	var out := {
		"ok": false, "frame_index": int(frame["index"]), "adjective_index": -1,
		"frame_quality": str(frame["quality"]), "adjective_quality": "",
		"frame_heard": str(frame["heard"]), "adjective_heard": "",
		"protected_conflict": false, "weak_fuzzy": false,
	}
	if int(frame["index"]) < 0:
		return out
	var adjective_match := _find_adjective(words, adjective, int(frame["index"]) + 1,
		tolerance, protected)
	out["adjective_index"] = int(adjective_match["index"])
	out["adjective_quality"] = str(adjective_match["quality"])
	out["adjective_heard"] = str(adjective_match["heard"])
	out["protected_conflict"] = bool(adjective_match["protected_conflict"])
	out["weak_fuzzy"] = bool(adjective_match["weak_fuzzy"])
	out["ok"] = int(adjective_match["index"]) >= 0 and not bool(out["protected_conflict"])
	return out


## The first protected adjective after the frame is decisive. It may never be reinterpreted
## as another protected game word, even when edit distance would otherwise allow it.
static func _find_adjective(words: PackedStringArray, expected: String, from_word: int,
		tolerance: int, protected: Dictionary) -> Dictionary:
	var weak_fuzzy := false
	for index in range(maxi(from_word, 0), words.size()):
		var heard := str(words[index])
		if protected.has(heard) and heard != expected:
			return {"index": -1, "quality": "protected-conflict", "heard": heard,
				"protected_conflict": true, "weak_fuzzy": false}
		var match := TextNormalizer.token_match(heard, expected, tolerance, protected)
		if bool(match["ok"]):
			return {"index": index, "quality": match["quality"], "heard": heard,
				"protected_conflict": false, "weak_fuzzy": weak_fuzzy}
		weak_fuzzy = weak_fuzzy or bool(match["near_fuzzy"])
	return {"index": -1, "quality": "", "heard": "",
		"protected_conflict": false, "weak_fuzzy": weak_fuzzy}


static func _diagnose_clause(match: Dictionary, said_adjective: bool, frame_reason: String) -> String:
	if bool(match["protected_conflict"]):
		return "wrong_word"
	if int(match["frame_index"]) < 0 and said_adjective:
		return frame_reason
	if bool(match["weak_fuzzy"]):
		return "uncertain"
	return "nothing"


static func _diagnose_both(result: Dictionary, past: Dictionary, present: Dictionary) -> String:
	if bool(result["protected_conflict"]):
		return "wrong_word"
	if not bool(past["ok"]):
		if bool(past["weak_fuzzy"]):
			return "uncertain"
		return "frame_before" if bool(result["said_before"]) else "no_before"
	if not bool(present["ok"]):
		if bool(present["weak_fuzzy"]):
			return "uncertain"
		return "frame_after" if bool(result["said_after"]) else "no_after"
	return "nothing"


static func _is_uncertain_failure(match: Dictionary, said_adjective: bool) -> bool:
	return not bool(match["protected_conflict"]) and bool(match["weak_fuzzy"]) \
		and int(match["frame_index"]) >= 0 and not said_adjective


static func _has_clear_frame_miss(result: Dictionary) -> bool:
	return (bool(result["said_before"]) and not bool(result["frame_before"])) \
		or (bool(result["said_after"]) and not bool(result["frame_after"]))


static func _evidence(past: Dictionary, present: Dictionary, clause: int) -> PackedStringArray:
	var evidence := PackedStringArray()
	if clause != CLAUSE_PRESENT and not past.is_empty():
		if int(past.get("frame_index", -1)) >= 0:
			evidence.append("was:%s" % past.get("frame_quality", ""))
		if int(past.get("adjective_index", -1)) >= 0:
			evidence.append("before:%s" % past.get("adjective_quality", ""))
	if clause != CLAUSE_PAST and not present.is_empty():
		if int(present.get("frame_index", -1)) >= 0:
			evidence.append("is:%s" % present.get("frame_quality", ""))
		if int(present.get("adjective_index", -1)) >= 0:
			evidence.append("after:%s" % present.get("adjective_quality", ""))
	return evidence


static func _score(result: Dictionary) -> int:
	var value := 0
	if bool(result.get("said_before", false)):
		value += 1
	if bool(result.get("said_after", false)):
		value += 1
	if bool(result.get("frame_before", false)):
		value += 2
	if bool(result.get("frame_after", false)):
		value += 2
	if bool(result.get("protected_conflict", false)):
		value += 1
	return value
