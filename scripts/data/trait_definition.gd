class_name TraitDefinition
extends Resource
## One opposite pair (big/small, hot/cold...). The student picks the direction, so a pair
## stores a value per *word* rather than per "before"/"after" slot.

@export var id: String = ""
@export var category: String = "" ## SIZE, TEMPERATURE, ... Gameplay switches on this, never on the word.
@export var word_a: String = ""
@export var word_b: String = ""
@export var modifier: String = "" ## Which visual effect in TraitVisuals this pair drives.
@export var value_a: float = 1.0
@export var value_b: float = 1.0


static func from_dict(d: Dictionary) -> TraitDefinition:
	var t := TraitDefinition.new()
	t.id = str(d.get("id", ""))
	t.category = str(d.get("category", "")).to_upper()
	t.word_a = str(d.get("word_a", ""))
	t.word_b = str(d.get("word_b", ""))
	t.modifier = str(d.get("modifier", "")).to_upper()
	t.value_a = float(d.get("value_a", 1.0))
	t.value_b = float(d.get("value_b", 1.0))
	return t


func has_word(word: String) -> bool:
	return word == word_a or word == word_b


func opposite_of(word: String) -> String:
	return word_b if word == word_a else word_a


func value_for(word: String) -> float:
	return value_a if word == word_a else value_b


func words() -> PackedStringArray:
	return PackedStringArray([word_a, word_b])
