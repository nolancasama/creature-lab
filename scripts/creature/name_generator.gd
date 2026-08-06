class_name NameGenerator
extends RefCounted
## Fantasy names built from the traits the student actually spoke, so the name is a
## record of the sentences rather than decoration. Deterministic: the same creature
## always offers the same list of names in the same order.

const CANDIDATES := 5

const PREFIXES := {
	"big": ["Titan", "Giant", "Grand"],
	"small": ["Pocket", "Tiny", "Wee"],
	"tall": ["Sky", "Tower", "Lofty"],
	"short": ["Stubby", "Little", "Nub"],
	"long": ["Ribbon", "Serpent", "Coil"],
	"hot": ["Flame", "Ember", "Cinder"],
	"cold": ["Frost", "Glacier", "Rime"],
	"old": ["Ancient", "Elder", "Rune"],
	"new": ["Aurora", "Nova", "Dawn"],
	"young": ["Sprout", "Cub", "Spring"],
	"hard": ["Crystal", "Iron", "Diamond"],
	"soft": ["Cloud", "Velvet", "Puff"],
	"strong": ["Mighty", "Boulder", "Storm"],
	"weak": ["Whisper", "Feather", "Mist"],
	"fast": ["Swift", "Comet", "Bolt"],
	"slow": ["Moss", "Drift", "Slumber"],
	"red": ["Ruby", "Scarlet", "Coral"],
	"blue": ["Azure", "Sapphire", "Ocean"],
	"green": ["Jade", "Fern", "Emerald"],
	"yellow": ["Sunny", "Amber", "Honey"],
	"black": ["Shadow", "Midnight", "Onyx"],
	"white": ["Snow", "Pearl", "Ivory"],
	"brown": ["Acorn", "Cocoa", "Timber"],
	"pink": ["Blossom", "Rose", "Petal"],
	"purple": ["Violet", "Amethyst", "Twilight"],
	"orange": ["Sunset", "Tiger", "Marmalade"],
}


static func candidates(state: CreatureState) -> PackedStringArray:
	var def := Content.animal(state.animal_id)
	var noun := def.fantasy_noun if def != null else "Creature"

	# Ordered by the sentences the student spoke, so the first name offered leads with
	# the first thing they said.
	var words := PackedStringArray()
	for entry in state.entries:
		words.append(str(entry["after"]))
	if words.is_empty():
		return PackedStringArray([noun])

	var out := PackedStringArray()
	for i in CANDIDATES * 2:
		var lead := str(words[i % words.size()])
		var tier: int = int(i / words.size())
		var candidate := "%s %s" % [_prefix(lead, tier), noun]
		# Later candidates stack a second trait for variety.
		if tier >= 2 and words.size() > 1:
			var second := str(words[(i + 1) % words.size()])
			candidate = "%s %s %s" % [_prefix(lead, tier), _prefix(second, 0), noun]
		if not out.has(candidate):
			out.append(candidate)
		if out.size() >= CANDIDATES:
			break
	return out


static func _prefix(word: String, tier: int) -> String:
	var pool: Array = PREFIXES.get(word, [])
	if pool.is_empty():
		return word.capitalize()
	return str(pool[tier % pool.size()])
