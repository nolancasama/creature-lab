class_name TextNormalizer
extends RefCounted
## Cleans recogniser text and owns the known-alias and fuzzy token policies. Grammar
## remains in GrammarValidator; the browser backend remains recognition-only.

const CONTRACTIONS := {
	"it's": "it is", "its": "it is", "twas": "it was", "'twas": "it was",
	"wasnt": "was not", "isnt": "is not",
}

## Recogniser aliases must never turn one real game answer into another.
const HOMOPHONES := {
	"wus": "was",
	"blew": "blue", "bloo": "blue", "read": "red", "reed": "red", "grey": "gray",
	"wight": "white", "wide": "white", "waite": "white", "block": "black", "blak": "black",
	"gold": "cold", "called": "cold", "colt": "cold", "kold": "cold",
	"hott": "hot", "hoot": "hot", "bigg": "big", "beg": "big",
	"smal": "small", "smoll": "small", "tal": "tall", "toll": "tall",
	"shot": "short", "sort": "short", "shorte": "short", "wrong": "long", "lang": "long",
	"knew": "new", "gnu": "new", "nu": "new", "yung": "young",
	"heart": "hard", "hardt": "hard", "sofft": "soft", "week": "weak", "wek": "weak",
	"strang": "strong", "fasst": "fast", "sloe": "slow", "slo": "slow",
	"purpel": "purple", "perple": "purple", "pinck": "pink", "orang": "orange",
	"yello": "yellow", "jello": "yellow", "grean": "green", "grin": "green", "braun": "brown",
}

const FILLER := ["um", "uh", "erm", "okay", "ok", "so", "and", "then", "eh"]
const GRAMMAR_TOKENS := ["it", "was", "now", "is"]


static func normalize(raw: String) -> String:
	var text := raw.to_lower().strip_edges()
	for symbol in [".", ",", "!", "?", ";", ":", "\"", "-"]:
		text = text.replace(symbol, " ")
	var words := PackedStringArray()
	for token in text.split(" ", false):
		var word := str(token).strip_edges()
		if word.is_empty():
			continue
		if CONTRACTIONS.has(word):
			for expanded in str(CONTRACTIONS[word]).split(" "):
				words.append(str(expanded))
		else:
			words.append(word)
	return " ".join(words)


static func strip_edge_filler(normalized: String) -> String:
	var words := Array(normalized.split(" ", false))
	while not words.is_empty() and FILLER.has(str(words[0])):
		words.pop_front()
	while not words.is_empty() and FILLER.has(str(words[-1])):
		words.pop_back()
	return " ".join(PackedStringArray(words))


## Actual vocabulary, including hidden/legacy pairs: disabling a card must not weaken the
## safety rule that another valid game word is a wrong answer.
static func protected_vocabulary() -> Dictionary:
	var protected := {}
	for pair in Content.pairs:
		protected[pair.word_a] = true
		protected[pair.word_b] = true
	for color in Content.colors:
		protected[color.word] = true
	var violations := protected_alias_violations(protected)
	assert(violations.is_empty(), "Protected speech aliases collide: %s" % violations)
	return protected


static func protected_alias_violations(protected := {}) -> PackedStringArray:
	if protected.is_empty():
		for pair in Content.pairs:
			protected[pair.word_a] = true
			protected[pair.word_b] = true
		for color in Content.colors:
			protected[color.word] = true
	var violations := PackedStringArray()
	for heard in HOMOPHONES:
		var expected := str(HOMOPHONES[heard])
		if protected.has(str(heard)) and protected.has(expected) and str(heard) != expected:
			violations.append("%s->%s" % [heard, expected])
	return violations


static func token_match(heard: String, expected: String, tolerance: int,
		protected: Dictionary) -> Dictionary:
	if heard == expected:
		return {"ok": true, "quality": "exact", "near_fuzzy": false}
	if tolerance <= GrammarValidator.HEAR_NORMAL and str(HOMOPHONES.get(heard, "")) == expected:
		return {"ok": true, "quality": "alias", "near_fuzzy": false}
	# A clearly recognised game word is never reinterpreted as a different game word.
	if protected.has(heard) and heard != expected:
		return {"ok": false, "quality": "protected-conflict", "near_fuzzy": false}
	# Do not let the optional `it` become the required `is` through one-edit fuzziness, or
	# one grammar token become another and collapse the past/present distinction.
	if GRAMMAR_TOKENS.has(heard) or GRAMMAR_TOKENS.has(expected):
		return {"ok": false, "quality": "grammar-conflict", "near_fuzzy": false}
	var distance := edit_distance(heard, expected)
	var limit := 1 if expected.length() <= 4 else 2
	if tolerance <= GrammarValidator.HEAR_LENIENT and distance <= limit:
		return {"ok": true, "quality": "fuzzy-%d" % distance, "near_fuzzy": false}
	return {"ok": false, "quality": "", "near_fuzzy": tolerance <= GrammarValidator.HEAR_LENIENT \
		and not protected.has(heard) and distance == limit + 1}


static func find_token(words: PackedStringArray, expected: String, from_word: int,
		tolerance: int, protected: Dictionary) -> Dictionary:
	for index in range(maxi(from_word, 0), words.size()):
		var heard := str(words[index])
		var match := token_match(heard, expected, tolerance, protected)
		if bool(match["ok"]):
			return {"index": index, "quality": match["quality"], "heard": heard}
	return {"index": -1, "quality": "", "heard": ""}


static func edit_distance(left: String, right: String) -> int:
	var previous: Array[int] = []
	for j in right.length() + 1:
		previous.append(j)
	for i in range(1, left.length() + 1):
		var current: Array[int] = [i]
		for j in range(1, right.length() + 1):
			var substitution := previous[j - 1] + (0 if left[i - 1] == right[j - 1] else 1)
			current.append(mini(mini(previous[j] + 1, current[j - 1] + 1), substitution))
		previous = current
	return previous[-1]
