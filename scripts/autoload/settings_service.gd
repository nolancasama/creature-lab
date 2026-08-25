extends Node
## Teacher-owned configuration. Gameplay reads these and never writes them.
##
## The spec left "Easy Mode is the default" dangling with no other mode defined, so the
## idea is split into three independent dials a teacher can actually reason about:
## how much choice the student gets, how strictly speech is judged, and how much of the
## sentence is printed on screen.

signal changed

const PATH := "user://teacher_settings.cfg"

## How pairs are chosen. "free" is the spec's Easy Mode.
const CHOICE_FREE := "free"
const CHOICE_GUIDED := "guided"

## How much of the target sentence is printed above the mic.
## How much of the transformation the student has to say out loud. Split is the default:
## the student says "It was small." card by card, then meets all three "Now it is ___"
## sentences together in a pass of their own once the past tense is done.
##
## It keeps what past-only was for - every utterance is still one short clause, which a
## beginner can produce and a recogniser handles far more reliably than the full compound
## sentence - while still asking for the present tense, which is half the grammar the game
## exists to teach and which past-only never asks a student to say at all.
const SAY_PAST := "past" ## "It was small."
const SAY_SPLIT := "split" ## Past for each card, then all three "Now it is ___" together.
const SAY_FULL := "full" ## "It was small. Now it is big."

const PROMPT_FULL := "full" ## "It was small. Now it is big."
const PROMPT_GAPPED := "gapped" ## "It was ____ . Now it is ____ ."
const PROMPT_HIDDEN := "hidden" ## Picture cards only - the student produces the frame.

## Speech judging. 0 = keywords in order, 1 = both halves present, 2 = whole sentence.
const STRICT_LENIENT := 0
const STRICT_NORMAL := 1
const STRICT_EXACT := 2

var choice_mode: String = CHOICE_FREE
var say_mode: String = SAY_SPLIT
var prompt_mode: String = PROMPT_FULL
var strictness: int = STRICT_NORMAL
var enabled_pairs := PackedStringArray() ## Empty = all.
var enabled_colors := PackedStringArray() ## Empty = all.
var tts_enabled := true
var stt_enabled := true
var typed_input := true
var music_volume := 0.45
var sfx_volume := 0.85
var fullscreen := false
var persist_zoo := true
var debug_mode := OS.is_debug_build()
## Shows the speech diagnostics on screen. Off by default and reachable from Teacher
## Settings, because the browser console is not reachable on the machines this runs on.
var speech_log := false


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	choice_mode = str(cfg.get_value("game", "choice_mode", choice_mode))
	say_mode = str(cfg.get_value("game", "say_mode", say_mode))
	prompt_mode = str(cfg.get_value("game", "prompt_mode", prompt_mode))
	strictness = int(cfg.get_value("game", "strictness", strictness))
	enabled_pairs = PackedStringArray(cfg.get_value("content", "pairs", []))
	enabled_colors = PackedStringArray(cfg.get_value("content", "colors", []))
	tts_enabled = bool(cfg.get_value("io", "tts", tts_enabled))
	stt_enabled = bool(cfg.get_value("io", "stt", stt_enabled))
	typed_input = bool(cfg.get_value("io", "typed", typed_input))
	music_volume = float(cfg.get_value("audio", "music", music_volume))
	sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
	fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
	persist_zoo = bool(cfg.get_value("game", "persist_zoo", persist_zoo))
	speech_log = bool(cfg.get_value("game", "speech_log", speech_log))
	_apply_display()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "choice_mode", choice_mode)
	cfg.set_value("game", "say_mode", say_mode)
	cfg.set_value("game", "prompt_mode", prompt_mode)
	cfg.set_value("game", "strictness", strictness)
	cfg.set_value("game", "persist_zoo", persist_zoo)
	cfg.set_value("content", "pairs", enabled_pairs)
	cfg.set_value("content", "colors", enabled_colors)
	cfg.set_value("io", "tts", tts_enabled)
	cfg.set_value("io", "stt", stt_enabled)
	cfg.set_value("io", "typed", typed_input)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.save(PATH)
	_apply_display()
	changed.emit()


func _apply_display() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


func toggle_pair(pair_id: String, on: bool) -> void:
	var all := PackedStringArray()
	for p in Content.pairs:
		all.append(p.id)
	enabled_pairs = _toggled(enabled_pairs, all, pair_id, on)
	changed.emit()


func toggle_color(word: String, on: bool) -> void:
	var all := PackedStringArray()
	for c in Content.colors:
		all.append(c.word)
	enabled_colors = _toggled(enabled_colors, all, word, on)
	changed.emit()


func is_pair_enabled(pair_id: String) -> bool:
	return enabled_pairs.is_empty() or enabled_pairs.has(pair_id)


func is_color_enabled(word: String) -> bool:
	return enabled_colors.is_empty() or enabled_colors.has(word)


## An empty list means "everything is on", so the first switch-off has to materialise
## the full list, and switching the last one back on collapses it to empty again.
static func _toggled(current: PackedStringArray, all: PackedStringArray, key: String, on: bool) -> PackedStringArray:
	var list := all.duplicate() if current.is_empty() else current.duplicate()
	var idx := list.find(key)
	if on and idx == -1:
		list.append(key)
	elif not on and idx != -1:
		list.remove_at(idx)
	if list.size() >= all.size():
		return PackedStringArray()
	return list


## True when the card-by-card pass only asks for the "It was ___" half. Split mode does
## too - its present half is a separate pass at the end, not part of the same breath.
func past_only() -> bool:
	return say_mode != SAY_FULL


## True when the present tense is collected as its own pass before the transformation.
func split_pass() -> bool:
	return say_mode == SAY_SPLIT


## Typing does not have the recognition problem that makes a one-clause microphone round
## useful, so a typed Past-only round still collects the missing "Now it is ___" half in
## the existing present-tense pass. Full mode already collected both halves and must not
## ask for the present a second time.
func needs_present_pass(uses_microphone: bool) -> bool:
	return split_pass() or (not uses_microphone and say_mode == SAY_PAST)
