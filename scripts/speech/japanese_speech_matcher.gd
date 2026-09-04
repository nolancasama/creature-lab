class_name JapaneseSpeechMatcher
extends RefCounted
## Japanese matching is structural and exact against the authored pack. It never shares
## English tokenisation or edit-distance rules: Chrome normally returns one contiguous
## clause, and one substituted Japanese character is another word rather than a near miss.


static func assess(transcript: String, category: String, before: String, after: String,
		tolerance: int, clause: int) -> Dictionary:
	var normalized := normalize(transcript)
	if normalized.is_empty():
		return {"normalized": normalized, "pass": false, "relevant": false}

	var form_matches := _maximal_form_matches(normalized)
	var allowed := _expected_keys(category, before, after, clause)
	var conflict := _has_protected_conflict(form_matches, allowed)
	var passed := not conflict and _matches(normalized, category, before, after,
		tolerance, clause, form_matches)
	return {
		"normalized": normalized,
		"pass": passed,
		"relevant": _is_relevant(normalized, category, before, after, form_matches),
	}


static func normalize(raw: String) -> String:
	var out := ""
	for index in raw.length():
		var code := raw.unicode_at(index)
		if _is_whitespace(code) or code in [0x3001, 0x3002, 0xff01, 0xff1f, 0x30fb]:
			continue
		# Chrome occasionally mixes fullwidth Latin characters into hypotheses. Fold only
		# ASCII width; kana and kanji must remain exact.
		if code >= 0xff01 and code <= 0xff5e:
			code -= 0xfee0
		out += String.chr(code)
	return out


static func _matches(normalized: String, category: String, before: String, after: String,
		tolerance: int, clause: int, form_matches: Array[Dictionary]) -> bool:
	match clause:
		GrammarValidator.CLAUSE_PAST:
			return bool(_match_clause(normalized, category, before, "past", tolerance, 0,
				form_matches)["ok"])
		GrammarValidator.CLAUSE_PRESENT:
			return bool(_match_clause(normalized, category, after, "present", tolerance, 0,
				form_matches)["ok"])
		_:
			var past := _match_clause(normalized, category, before, "past", tolerance, 0,
				form_matches)
			if not bool(past["ok"]):
				return false
			var present := _match_clause(normalized, category, after, "present", tolerance,
				int(past["end"]), form_matches)
			return bool(present["ok"])


static func _match_clause(normalized: String, category: String, word: String, tense: String,
		tolerance: int, from_index: int, form_matches: Array[Dictionary]) -> Dictionary:
	if word.is_empty():
		return {"ok": false, "end": -1}
	var form_start := from_index
	if tolerance == GrammarValidator.HEAR_EXACT:
		var frame := _find_first(normalized, TargetLanguage.frame_accept(tense), from_index)
		if int(frame["index"]) < 0:
			return {"ok": false, "end": -1}
		form_start = int(frame["end"])
	var form := _find_form(category, word, tense, tolerance, form_start, form_matches)
	return {"ok": int(form["index"]) >= 0, "end": int(form["end"])}


static func _find_form(category: String, word: String, tense: String, tolerance: int,
		from_index: int, form_matches: Array[Dictionary]) -> Dictionary:
	var best_index := -1
	var best_end := -1
	var key := TargetLanguage.word_key(category, word)
	for match_data in form_matches:
		if str(match_data["key"]) != key or str(match_data["tense"]) != tense:
			continue
		var form := str(match_data["form"])
		if not _form_allowed(form, tense, tolerance):
			continue
		var index := int(match_data["index"])
		if index >= from_index and (best_index < 0 or index < best_index):
			best_index = index
			best_end = int(match_data["end"])
	return {"index": best_index, "end": best_end}


## Challenge demands the complete polite classroom form. Standard accepts inflection with
## optional です; Easy additionally admits pack-listed bare nouns such as 緑 or ピンク.
static func _form_allowed(form: String, tense: String, tolerance: int) -> bool:
	if tolerance == GrammarValidator.HEAR_LENIENT:
		return true
	if tolerance == GrammarValidator.HEAR_EXACT:
		# ます/ました are polite endings too. AGE/old is a verb phrase - としをとっています -
		# so a です-only test would have failed the canonical answer in the strictest mode
		# while accepting the simpler alternate, which is precisely backwards.
		return form.ends_with("です") or form.ends_with("でした") \
			or form.ends_with("ます") or form.ends_with("ました")
	if tense == "past":
		return true # Every pack-listed past surface carries its authored inflection.
	return form.ends_with("です") or form.ends_with("い") or form.ends_with("います")


static func _find_first(normalized: String, raw_forms: PackedStringArray,
		from_index: int) -> Dictionary:
	var best_index := -1
	var best_end := -1
	for raw_form in raw_forms:
		var form := normalize(str(raw_form))
		var index := normalized.find(form, from_index)
		if not form.is_empty() and index >= 0 and (best_index < 0 or index < best_index):
			best_index = index
			best_end = index + form.length()
	return {"index": best_index, "end": best_end}


## A correct word cannot rescue a clause that also clearly contains another game's word.
## Keys, not English word IDs, keep HEIGHT/short separate from LENGTH/short.
static func _has_protected_conflict(form_matches: Array[Dictionary], allowed: Dictionary) -> bool:
	for match_data in form_matches:
		if not allowed.has(str(match_data["key"])):
			return true
	return false


static func _expected_keys(category: String, before: String, after: String,
		clause: int) -> Dictionary:
	var allowed := {}
	if clause != GrammarValidator.CLAUSE_PRESENT and not before.is_empty():
		allowed[TargetLanguage.word_key(category, before)] = true
	if clause != GrammarValidator.CLAUSE_PAST and not after.is_empty():
		allowed[TargetLanguage.word_key(category, after)] = true
	return allowed


static func _is_relevant(normalized: String, category: String, before: String,
		after: String, form_matches: Array[Dictionary]) -> bool:
	for tense in ["past", "present"]:
		for frame in TargetLanguage.frame_accept(tense):
			if normalized.contains(normalize(str(frame))):
				return true

	var relevant_words := PackedStringArray()
	if not before.is_empty():
		relevant_words.append(before)
	if not after.is_empty() and not relevant_words.has(after):
		relevant_words.append(after)
	if after.is_empty():
		var pair := Content.pair_for_category(category)
		if pair != null:
			var opposite := pair.opposite_of(before)
			if not opposite.is_empty() and not relevant_words.has(opposite):
				relevant_words.append(opposite)
	var relevant_keys := {}
	for word in relevant_words:
		relevant_keys[TargetLanguage.word_key(category, word)] = true
	for match_data in form_matches:
		if relevant_keys.has(str(match_data["key"])):
			return true
	return false


## Containment is required because Japanese arrives without word boundaries, but shorter
## forms can themselves be pieces of longer authored words (`きいろ` inside `むらさきいろ`).
## Give each span to its longest pack form before applying protected-vocabulary rules.
static func _maximal_form_matches(normalized: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for raw_key in TargetLanguage.japanese_word_keys():
		var key := str(raw_key)
		var parts := key.split("/", true, 1)
		if parts.size() != 2:
			continue
		for tense in ["past", "present"]:
			for raw_form in TargetLanguage.accepted_forms(str(parts[0]), str(parts[1]), tense):
				var form := normalize(str(raw_form))
				if form.is_empty():
					continue
				var from_index := 0
				while from_index < normalized.length():
					var index := normalized.find(form, from_index)
					if index < 0:
						break
					found.append({
						"key": key,
						"tense": tense,
						"form": form,
						"index": index,
						"end": index + form.length(),
					})
					from_index = index + 1

	var maximal: Array[Dictionary] = []
	for candidate in found:
		var shadowed := false
		for other in found:
			var candidate_length := int(candidate["end"]) - int(candidate["index"])
			var other_length := int(other["end"]) - int(other["index"])
			if other_length > candidate_length and int(other["index"]) <= int(candidate["index"]) \
					and int(other["end"]) >= int(candidate["end"]):
				shadowed = true
				break
		if not shadowed:
			maximal.append(candidate)
	return maximal


static func _is_whitespace(code: int) -> bool:
	return code in [0x0009, 0x000a, 0x000b, 0x000c, 0x000d, 0x0020, 0x0085,
		0x00a0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000] \
		or (code >= 0x2000 and code <= 0x200a)
