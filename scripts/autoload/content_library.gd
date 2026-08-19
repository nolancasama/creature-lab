extends Node
## Loads every piece of game content from res://content/*.json.
##
## Deliberate deviation from the spec's "Resources/*.tres": ten animals of a dozen
## primitives each is unmaintainable as hand-authored .tres, and a teacher can edit JSON
## in Notepad. The typed data classes are still Resources, so .tres authoring remains
## possible later. Adding vocabulary, colours, animals or fantasy parts needs no code.

const TRAITS_PATH := "res://content/traits.json"
const COLORS_PATH := "res://content/colors.json"
const ANIMALS_PATH := "res://content/animals.json"
const FANTASY_PATH := "res://content/fantasy_parts.json"

const COLOR_CATEGORY := "COLOR"

var pairs: Array[TraitDefinition] = []
var colors: Array[ColorDefinition] = []
var animals: Array[AnimalDefinition] = []
var fantasy_parts: Array[FantasyPartDefinition] = []
var role_colors := {}

var _pair_by_category := {}
var _color_by_word := {}
var _animal_by_id := {}


func _ready() -> void:
	var animal_file := _read(ANIMALS_PATH)

	for entry in _read(TRAITS_PATH).get("pairs", []):
		var t := TraitDefinition.from_dict(entry)
		pairs.append(t)
		_pair_by_category[t.category] = t

	for entry in _read(COLORS_PATH).get("colors", []):
		var c := ColorDefinition.from_dict(entry)
		colors.append(c)
		_color_by_word[c.word] = c

	for entry in animal_file.get("animals", []):
		var a := AnimalDefinition.from_dict(entry)
		animals.append(a)
		_animal_by_id[a.id] = a

	for entry in _read(FANTASY_PATH).get("parts", []):
		fantasy_parts.append(FantasyPartDefinition.from_dict(entry))

	for key in animal_file.get("roles", {}):
		var hex := str(animal_file["roles"][key])
		if hex.begins_with("#"):
			role_colors[str(key)] = Color.html(hex)

	if animals.is_empty() or pairs.is_empty():
		push_error("Creature Lab: content failed to load; check res://content/*.json")


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing content file: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Content file is not a JSON object: %s" % path)
		return {}
	return parsed


# --- Lookups -----------------------------------------------------------------

func pair_for_category(category: String) -> TraitDefinition:
	return _pair_by_category.get(category, null)


func color_def(word: String) -> ColorDefinition:
	return _color_by_word.get(word, null)


func color_of(word: String, fallback := Color.WHITE) -> Color:
	var c: ColorDefinition = _color_by_word.get(word, null)
	return c.color if c != null else fallback


func is_color_word(word: String) -> bool:
	return _color_by_word.has(word)


func animal(id: String) -> AnimalDefinition:
	return _animal_by_id.get(id, null)


func animal_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for a in animals:
		out.append(a.id)
	return out


func role_color(role: String, fallback := Color.WHITE) -> Color:
	return role_colors.get(role, fallback)


## Fantasy parts grown by a set of "Now it is ___" words, in content order so the
## result is deterministic for a given creature.
func fantasy_parts_for(words: PackedStringArray) -> Array[FantasyPartDefinition]:
	var out: Array[FantasyPartDefinition] = []
	for f in fantasy_parts:
		if words.has(f.trigger):
			out.append(f)
	return out


## Selectable pairs a teacher has left switched on, in content order. Non-selectable
## legacy pairs remain in `pairs` and category lookup so old saved creatures still load,
## but they can never leak back into the student choice grid.
func enabled_pairs() -> Array[TraitDefinition]:
	var out: Array[TraitDefinition] = []
	for p in pairs:
		if p.selectable and (Settings.enabled_pairs.is_empty() or Settings.enabled_pairs.has(p.id)):
			out.append(p)
	return out


func enabled_colors() -> Array[ColorDefinition]:
	var out: Array[ColorDefinition] = []
	for c in colors:
		if Settings.enabled_colors.is_empty() or Settings.enabled_colors.has(c.word):
			out.append(c)
	return out
