class_name TextNormalizer
extends RefCounted
## Turns whatever the recogniser produced into something the grammar validator can match.
##
## Speech APIs return no punctuation, expand nothing, and cheerfully hand back a
## homophone. Fixing that here - rather than inside the validator or the speech backend -
## keeps each stage replaceable.

const CONTRACTIONS := {
	"it's": "it is",
	"its": "it is",
	"twas": "it was",
	"'twas": "it was",
	"wasnt": "was not",
	"isnt": "is not",
}

## Words a recogniser commonly returns instead of our vocabulary. Only mappings that
## cannot collide with another word in the game are listed.
const HOMOPHONES := {
	"blew": "blue", "bloo": "blue",
	"read": "red", "reed": "red",
	"grey": "gray",
	"wight": "white", "wide": "white", "waite": "white",
	"block": "black", "blak": "black",
	"gold": "cold", "called": "cold", "colt": "cold", "kold": "cold",
	"hott": "hot", "hoot": "hot",
	"bigg": "big", "beg": "big",
	"smal": "small", "smoll": "small",
	"tal": "tall", "toll": "tall",
	"shot": "short", "sort": "short", "shorte": "short",
	"wrong": "long", "lang": "long",
	"knew": "new", "gnu": "new", "nu": "new",
	"yung": "young",
	"heart": "hard", "hardt": "hard",
	"sofft": "soft",
	"week": "weak", "wek": "weak",
	"strang": "strong",
	"fasst": "fast",
	"sloe": "slow", "slo": "slow",
	"purpel": "purple", "perple": "purple",
	"pinck": "pink",
	"orang": "orange",
	"yello": "yellow", "jello": "yellow",
	"grean": "green", "grin": "green",
	"braun": "brown",
}

## Filler a student or the recogniser may add around the target sentence.
const FILLER := ["um", "uh", "erm", "okay", "ok", "so", "and", "then", "eh"]


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
			continue
		words.append(str(HOMOPHONES.get(word, word)))
	return " ".join(words)


## The same normalisation with leading/trailing filler removed. Filler is only stripped
## from the ends - "and" in the middle of a sentence is left alone so exact mode can
## still tell "It was small now it is big" from something rambling.
static func strip_edge_filler(normalized: String) -> String:
	var words := Array(normalized.split(" ", false))
	while not words.is_empty() and FILLER.has(str(words[0])):
		words.pop_front()
	while not words.is_empty() and FILLER.has(str(words[-1])):
		words.pop_back()
	return " ".join(PackedStringArray(words))


## True when `phrase` appears as a run of whole words starting at or after `from_word`.
## Returns the word index of the match, or -1.
static func find_phrase(normalized: String, phrase: String, from_word := 0) -> int:
	var haystack := normalized.split(" ", false)
	var needle := phrase.split(" ", false)
	if needle.is_empty() or haystack.size() < needle.size():
		return -1
	for start in range(from_word, haystack.size() - needle.size() + 1):
		var matched := true
		for i in needle.size():
			if haystack[start + i] != needle[i]:
				matched = false
				break
		if matched:
			return start
	return -1
