class_name SpeechAttemptClassifier
extends RefCounted
## Classifies language evidence from one attempt. Browser timing belongs to SpeechSession;
## scaffold counts belong to the scene's attempt controller.

enum Outcome {
	PASS,
	EFFORTFUL_WRONG,
	UNCERTAIN,
	TECHNICAL_ERROR,
}


static func classify(alternatives: PackedStringArray, before: String, after: String,
		tolerance: int, clause := GrammarValidator.CLAUSE_BOTH) -> Dictionary:
	var protected := TextNormalizer.protected_vocabulary()
	var candidates: Array[Dictionary] = []
	var first_relevant := -1
	var first_usable := -1
	for index in alternatives.size():
		var transcript := str(alternatives[index])
		var normalized := TextNormalizer.strip_edge_filler(TextNormalizer.normalize(transcript))
		var words := PackedStringArray(normalized.split(" ", false))
		var passed := _matches(words, before, after, tolerance, clause, protected, false)
		var relevant := _is_relevant(words, before, after, tolerance, clause, protected)
		candidates.append({
			"transcript": transcript,
			"normalized": normalized,
			"pass": passed,
			"relevant": relevant,
		})
		if first_usable < 0 and not normalized.is_empty():
			first_usable = index
		if first_relevant < 0 and relevant:
			first_relevant = index
		if passed:
			return _result(Outcome.PASS, index, candidates, alternatives)
	if first_relevant >= 0:
		return _result(Outcome.EFFORTFUL_WRONG, first_relevant, candidates, alternatives)
	return _result(Outcome.UNCERTAIN, first_usable, candidates, alternatives)


## Interim results may end recognition early only when every required token is exact or a
## known safe alias. Conservative fuzziness is useful feedback on a final, but too weak to
## clip a child's recording on a partial hypothesis.
static func is_strong_pass(alternatives: PackedStringArray, before: String, after: String,
		tolerance: int, clause := GrammarValidator.CLAUSE_BOTH) -> bool:
	var protected := TextNormalizer.protected_vocabulary()
	for transcript in alternatives:
		var normalized := TextNormalizer.strip_edge_filler(TextNormalizer.normalize(str(transcript)))
		var words := PackedStringArray(normalized.split(" ", false))
		if _matches(words, before, after, tolerance, clause, protected, true):
			return true
	return false


static func technical_error(reason: String) -> Dictionary:
	return {
		"outcome": Outcome.TECHNICAL_ERROR,
		"selected_index": -1,
		"selected_transcript": "",
		"normalized": "",
		"candidates": [],
		"error_reason": reason,
	}


static func outcome_name(outcome: int) -> String:
	if outcome >= 0 and outcome < Outcome.keys().size():
		return str(Outcome.keys()[outcome])
	return "UNKNOWN"


static func _result(outcome: int, selected_index: int, candidates: Array[Dictionary],
		alternatives: PackedStringArray) -> Dictionary:
	var transcript := ""
	var normalized := ""
	if selected_index >= 0 and selected_index < candidates.size():
		transcript = str(alternatives[selected_index])
		normalized = str(candidates[selected_index]["normalized"])
	return {
		"outcome": outcome,
		"selected_index": selected_index,
		"selected_transcript": transcript,
		"normalized": normalized,
		"candidates": candidates,
		"error_reason": "",
	}


static func _matches(words: PackedStringArray, before: String, after: String, tolerance: int,
		clause: int, protected: Dictionary, strong_only: bool) -> bool:
	match clause:
		GrammarValidator.CLAUSE_PAST:
			return bool(_match_clause(words, "was", before, 0, tolerance, protected,
				strong_only)["ok"])
		GrammarValidator.CLAUSE_PRESENT:
			return bool(_match_clause(words, "is", after, 0, tolerance, protected,
				strong_only)["ok"])
		_:
			var past := _match_clause(words, "was", before, 0, tolerance, protected,
				strong_only)
			if not bool(past["ok"]):
				return false
			var present := _match_clause(words, "is", after, int(past["adjective_index"]) + 1,
				tolerance, protected, strong_only)
			return bool(present["ok"])


static func _match_clause(words: PackedStringArray, frame_word: String, adjective: String,
		from_word: int, tolerance: int, protected: Dictionary, strong_only: bool) -> Dictionary:
	var frame := _find_match(words, frame_word, from_word, tolerance, protected, strong_only,
		false)
	if int(frame["index"]) < 0:
		return {"ok": false, "adjective_index": -1}
	var adjective_match := _find_match(words, adjective, int(frame["index"]) + 1,
		tolerance, protected, strong_only, true)
	return {
		"ok": int(adjective_match["index"]) >= 0,
		"adjective_index": int(adjective_match["index"]),
	}


## The first protected vocabulary word after a frame is decisive. A later expected word
## cannot rescue "it was weak strong" by reinterpreting the child's clear wrong answer.
static func _find_match(words: PackedStringArray, expected: String, from_word: int,
		tolerance: int, protected: Dictionary, strong_only: bool,
		stop_at_protected_conflict: bool) -> Dictionary:
	for index in range(maxi(from_word, 0), words.size()):
		var heard := str(words[index])
		if stop_at_protected_conflict and protected.has(heard) and heard != expected:
			return {"index": -1, "quality": "protected-conflict"}
		var match := TextNormalizer.token_match(heard, expected, tolerance, protected)
		if bool(match["ok"]) and (not strong_only or str(match["quality"]) in ["exact", "alias"]):
			return {"index": index, "quality": str(match["quality"])}
	return {"index": -1, "quality": ""}


static func _is_relevant(words: PackedStringArray, before: String, after: String,
		tolerance: int, clause: int, protected: Dictionary) -> bool:
	if words.is_empty():
		return false
	var expected_words := PackedStringArray()
	if clause != GrammarValidator.CLAUSE_PRESENT:
		expected_words.append(before)
	if clause != GrammarValidator.CLAUSE_PAST:
		expected_words.append(after)

	# `was`/`is` (and safe near matches) are direct evidence that the child attempted the
	# lesson frame, even when they chose the wrong tense or adjective.
	for heard in words:
		for frame in ["was", "is"]:
			if bool(TextNormalizer.token_match(str(heard), str(frame), tolerance, protected)["ok"]):
				return true

	var has_it := words.has("it")
	var has_now_it := words.has("now") and has_it
	for heard in words:
		var word := str(heard)
		for expected in expected_words:
			# The target adjective, or the opposite the lesson pairs it with, is about this
			# prompt and nothing else. Saying one of them alone is the commonest way a
			# beginner under-answers - "strong" for "It was strong" - and it has to reach the
			# scaffold, because the help waiting at the second failure is a modelled sentence
			# with the frame in it, which is exactly what that child is missing. Ranking a
			# bare adjective below its own opposite would have left the most ordinary
			# under-answer in the room looping on "try again" and never being shown the
			# sentence. A stray word from the next table can trigger the same help; that
			# costs a child nothing, while withholding it costs them the lesson.
			if bool(TextNormalizer.token_match(word, str(expected), tolerance, protected)["ok"]):
				return true
			if word == _paired_opposite(str(expected)):
				return true
		if protected.has(word) and (has_it or has_now_it):
			return true
	return false


static func _paired_opposite(word: String) -> String:
	for pair in Content.pairs:
		if pair.word_a == word:
			return pair.word_b
		if pair.word_b == word:
			return pair.word_a
	return ""
