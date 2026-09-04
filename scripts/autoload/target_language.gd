extends Node
## Student-facing target-language data. CreatureState remains English semantic IDs; this
## layer is the only place those IDs become displayed or recognised language.

const JAPANESE_PATH := "res://content/language_ja.json"
const ENGLISH := "en"
const JAPANESE := "ja"

var _japanese := {}


func _ready() -> void:
	_japanese = _read_pack(JAPANESE_PATH)


func current() -> String:
	return Settings.target_language


func is_japanese() -> bool:
	return current() == JAPANESE


func stt_locale() -> String:
	if not is_japanese():
		return "en-US"
	return japanese_locale("stt")


func tts_locale() -> String:
	if not is_japanese():
		return "en-US"
	return japanese_locale("tts")


func japanese_locale(kind: String) -> String:
	var locale: Dictionary = _japanese.get("locale", {})
	return str(locale.get(kind, "ja-JP"))


## Godot's voice query uses language tags inconsistently across platforms. Preserve the
## exact English query order already used in classrooms, and derive the equivalent pair
## from the authored Japanese locale before falling back to any installed voice.
func tts_voice_languages() -> PackedStringArray:
	if not is_japanese():
		return PackedStringArray(["en", "en_US"])
	var locale := tts_locale()
	return PackedStringArray([locale.get_slice("-", 0), locale.replace("-", "_")])


func word_key(category: String, word: String) -> String:
	return "%s/%s" % [category, word]


func japanese_entry(category: String, word: String) -> Dictionary:
	var words: Dictionary = _japanese.get("words", {})
	var entry: Variant = words.get(word_key(category, word), {})
	return entry if entry is Dictionary else {}


func japanese_word_keys() -> PackedStringArray:
	var words: Dictionary = _japanese.get("words", {})
	return PackedStringArray(words.keys())


func display_word(category: String, word: String) -> String:
	if not is_japanese():
		return word
	return str(japanese_entry(category, word).get("display", word))


func accepted_forms(category: String, word: String, tense: String) -> PackedStringArray:
	var field := "past_forms" if tense == "past" else "present_forms"
	return PackedStringArray(japanese_entry(category, word).get(field, []))


func frame_accept(tense: String) -> PackedStringArray:
	var frames: Dictionary = _japanese.get("frames", {})
	var frame: Dictionary = frames.get(tense, {})
	return PackedStringArray(frame.get("accept", []))


func frame_display(tense: String) -> String:
	if not is_japanese():
		return GrammarValidator.BEFORE_FRAME if tense == "past" \
			else GrammarValidator.AFTER_FRAME
	return japanese_frame_display(tense)


func japanese_frame_display(tense: String) -> String:
	var frames: Dictionary = _japanese.get("frames", {})
	var frame: Dictionary = frames.get(tense, {})
	return str(frame.get("display", ""))


func sentence(category: String, before: String, after: String,
		clause := GrammarValidator.CLAUSE_BOTH) -> String:
	if not is_japanese():
		match clause:
			GrammarValidator.CLAUSE_PAST:
				return CreatureState.past_sentence_for(before)
			GrammarValidator.CLAUSE_PRESENT:
				return CreatureState.present_sentence_for(after)
		return CreatureState.sentence_for(before, after)
	match clause:
		GrammarValidator.CLAUSE_PAST:
			return _japanese_clause(category, before, "past")
		GrammarValidator.CLAUSE_PRESENT:
			return _japanese_clause(category, after, "present")
	return "%s %s" % [
		_japanese_clause(category, before, "past"),
		_japanese_clause(category, after, "present"),
	]


func gapped_sentence(clause := GrammarValidator.CLAUSE_BOTH) -> String:
	if not is_japanese():
		match clause:
			GrammarValidator.CLAUSE_PAST:
				return "It was ____ ."
			GrammarValidator.CLAUSE_PRESENT:
				return "Now it is ____ ."
		return "It was ____ . Now it is ____ ."
	match clause:
		GrammarValidator.CLAUSE_PAST:
			return "%s ____。" % frame_display("past")
		GrammarValidator.CLAUSE_PRESENT:
			return "%s ____。" % frame_display("present")
	return "%s ____。 %s ____。" % [frame_display("past"), frame_display("present")]


func input_placeholder() -> String:
	# Kana for the same reason every student-facing word in the pack is kana: 日 and 本 are
	# not in the bundled font subset, so the literal would draw as boxes in the web build.
	return "にほんごの文を入力" if is_japanese() else "英語の文を入力"


## Only these strings are display data. Recognition forms deliberately include kanji and
## must not be swept into the web-font fixture merely because they share the same JSON.
func japanese_display_strings() -> PackedStringArray:
	var out := PackedStringArray()
	var frames: Dictionary = _japanese.get("frames", {})
	for tense in ["past", "present"]:
		var frame: Dictionary = frames.get(tense, {})
		out.append(str(frame.get("display", "")))
	var words: Dictionary = _japanese.get("words", {})
	for key in words:
		var entry: Dictionary = words[key]
		out.append(str(entry.get("display", "")))
	return out


## Sentence surfaces are also rendered, but only after selecting the pack's kana polite
## variant. Keep them separate from the explicit `display` fixture so recognition kanji
## never become a font requirement.
func japanese_sentence_display_forms() -> PackedStringArray:
	var out := PackedStringArray()
	for raw_key in japanese_word_keys():
		var parts := str(raw_key).split("/", true, 1)
		if parts.size() != 2:
			continue
		for tense in ["past", "present"]:
			out.append(_kana_polite_form(str(parts[0]), str(parts[1]), tense))
	return out


func _japanese_clause(category: String, word: String, tense: String) -> String:
	if word.is_empty():
		return ""
	var form := _kana_polite_form(category, word, tense)
	return "%s %s。" % [frame_display(tense), form]


## The pack owns every irregular inflection. Select its authored kana polite surface form
## instead of conjugating `display` in code; generating endings here would turn AGE and
## noun colours into plausible-looking but wrong classroom Japanese.
## The four polite classroom endings the pack uses. です/でした carry adjectives and noun
## predicates; ます/ました carry the one verb phrase (としをとっています).
static func _is_polite(text: String) -> bool:
	return text.ends_with("です") or text.ends_with("でした") \
		or text.ends_with("ます") or text.ends_with("ました")


func _kana_polite_form(category: String, word: String, tense: String) -> String:
	for form in accepted_forms(category, word, tense):
		var text := str(form)
		# ます/ました count as polite too. AGE/old is a verb phrase - としをとっています - not an
		# adjective or a noun predicate, so a です-only test would skip the canonical form and
		# quietly show the simpler 年寄り alternate instead.
		if _is_polite(text) and not _contains_kanji(text):
			return _apply_display_spacing(text, str(japanese_entry(category, word).get(
				"display", "")))
	push_error("No kana polite %s form for %s" % [tense, word_key(category, word)])
	return str(japanese_entry(category, word).get("display", word))


## HEIGHT deliberately names the body part as two beginner-readable chunks. The authored
## inflected form is contiguous for recognition, so put back only spacing already present
## in `display`; no Japanese ending is generated here.
func _apply_display_spacing(form: String, display: String) -> String:
	var pieces := display.split(" ", false)
	if pieces.size() < 2:
		return form
	var prefix := ""
	for index in pieces.size() - 1:
		prefix += str(pieces[index])
	if not form.begins_with(prefix):
		return form
	return " ".join(PackedStringArray(pieces.slice(0, pieces.size() - 1))) \
		+ " " + form.substr(prefix.length())


func _contains_kanji(text: String) -> bool:
	for index in text.length():
		var code := text.unicode_at(index)
		if (code >= 0x3400 and code <= 0x4dbf) or (code >= 0x4e00 and code <= 0x9fff) \
				or (code >= 0xf900 and code <= 0xfaff):
			return true
	return false


func _read_pack(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing target-language pack: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Target-language pack is not a JSON object: %s" % path)
		return {}
	return parsed
