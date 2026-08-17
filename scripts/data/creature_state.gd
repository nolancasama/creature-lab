class_name CreatureState
extends RefCounted
## The single source of truth for one creature. Every other system reads from this
## rather than keeping its own copy: the lab animal renders `before_traits()`, the
## chamber renders `after_traits()`, the zoo card reads `sentences()`.

const SLOTS := 3

var animal_id: String = ""
var entries: Array[Dictionary] = [] ## {category, before, after, sentence, assisted}
var generated_name: String = ""
var custom_name: String = ""
var created_unix: int = 0


static func create(new_animal_id: String) -> CreatureState:
	var s := CreatureState.new()
	s.animal_id = new_animal_id
	s.created_unix = int(Time.get_unix_time_from_system())
	return s


static func sentence_for(before: String, after: String) -> String:
	return "It was %s. Now it is %s." % [before, after]


## What the student is asked to say in Settings.SAY_PAST. The recorded entry still keeps
## the full sentence: the creature transforms either way, only the speaking is halved.
static func past_sentence_for(before: String) -> String:
	return "It was %s." % before


func add_entry(category: String, before: String, after: String, assisted := false) -> void:
	entries.append({
		"category": category,
		"before": before,
		"after": after,
		"sentence": sentence_for(before, after),
		"assisted": assisted,
	})


func slots_filled() -> int:
	return entries.size()


func is_complete() -> bool:
	return entries.size() >= SLOTS


func used_categories() -> PackedStringArray:
	var out := PackedStringArray()
	for e in entries:
		out.append(str(e["category"]))
	return out


## category -> word, describing the animal standing on the platform right now.
func before_traits() -> Dictionary:
	var out := {}
	for e in entries:
		out[str(e["category"])] = str(e["before"])
	return out


## category -> word, the DNA instructions the chamber will execute.
func after_traits() -> Dictionary:
	var out := {}
	for e in entries:
		out[str(e["category"])] = str(e["after"])
	return out


func sentences() -> PackedStringArray:
	var out := PackedStringArray()
	for e in entries:
		out.append(str(e["sentence"]))
	return out


func needed_help() -> bool:
	for e in entries:
		if bool(e.get("assisted", false)):
			return true
	return false


func display_name() -> String:
	if not custom_name.strip_edges().is_empty():
		return custom_name.strip_edges()
	return generated_name


## Stable across runs: the same animal + the same three sentences always yields the
## same seed, so a creature is reproducible rather than randomly rolled.
func fingerprint() -> int:
	var key := animal_id
	var cats := after_traits().keys()
	cats.sort()
	for c in cats:
		key += "|%s=%s" % [c, after_traits()[c]]
	return abs(key.hash())


func to_dict() -> Dictionary:
	return {
		"animal_id": animal_id,
		"entries": entries.duplicate(true),
		"generated_name": generated_name,
		"custom_name": custom_name,
		"created_unix": created_unix,
	}


static func from_dict(d: Dictionary) -> CreatureState:
	var s := CreatureState.new()
	s.animal_id = str(d.get("animal_id", ""))
	s.generated_name = str(d.get("generated_name", ""))
	s.custom_name = str(d.get("custom_name", ""))
	s.created_unix = int(d.get("created_unix", 0))
	for e in d.get("entries", []):
		if e is Dictionary:
			s.entries.append(e)
	return s
