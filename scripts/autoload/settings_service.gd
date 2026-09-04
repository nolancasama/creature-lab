extends Node
## Teacher-owned configuration. Gameplay reads these and never writes them.
##
## The spec left "Easy Mode is the default" dangling with no other mode defined, so the
## idea is split into three independent dials a teacher can actually reason about:
## how much choice the student gets, how tolerant recognition is, and how much of the
## sentence is printed on screen. Grammar frames are fixed at every tolerance.

signal changed

const PATH := "user://teacher_settings.cfg"

const TARGET_ENGLISH := "en"
const TARGET_JAPANESE := "ja"

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

const PROMPT_FULL := "full" ## "It was small. Now it is big."
const PROMPT_GAPPED := "gapped" ## "It was ____ . Now it is ____ ."
const PROMPT_HIDDEN := "hidden" ## Picture cards only - the student produces the frame.

## Pronunciation / recognition tolerance. The persisted `strictness` key keeps its old
## numeric values so existing teacher configuration remains compatible.
const HEAR_LENIENT := 0
const HEAR_NORMAL := 1
const HEAR_EXACT := 2

## How many counted EFFORTFUL_WRONG attempts before the scaffold grants an assisted pass.
##
## Tolerance and patience move together: a recogniser that is harder to satisfy owes the
## student more tries before the game steps in and hands them the sentence. One flat
## threshold of three meant the strictest mode gave the fewest real chances, which is
## backwards.
##
## From classroom use: students enjoyed the challenge and several retried past three of
## their own accord, and because other students were passing normally the recogniser never
## read as broken. An assisted pass arriving too early takes that away, so the number is
## now the mode's own.
const ASSIST_AFTER := {HEAR_LENIENT: 3, HEAR_NORMAL: 4, HEAR_EXACT: 5}

var choice_mode: String = CHOICE_FREE
var prompt_mode: String = PROMPT_FULL
var target_language := TARGET_ENGLISH
## Standard is the recommended classroom mode, so it is what a machine with no saved
## teacher configuration starts on. Only fresh installs are affected - load_settings()
## reads whatever an existing config already holds.
var strictness: int = HEAR_NORMAL
var graphics_quality := GraphicsQuality.STANDARD
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
var _pending_target_language := ""


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	choice_mode = str(cfg.get_value("game", "choice_mode", choice_mode))
	prompt_mode = str(cfg.get_value("game", "prompt_mode", prompt_mode))
	var stored_language := str(cfg.get_value("game", "target_language", TARGET_ENGLISH))
	target_language = stored_language if stored_language in [TARGET_ENGLISH, TARGET_JAPANESE] \
		else TARGET_ENGLISH
	_pending_target_language = ""
	strictness = int(cfg.get_value("game", "strictness", strictness))
	graphics_quality = str(cfg.get_value("display", "graphics_quality", graphics_quality))
	if not GraphicsQuality.is_valid_profile(graphics_quality):
		graphics_quality = GraphicsQuality.STANDARD
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
	GraphicsQuality.set_profile(graphics_quality)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "choice_mode", choice_mode)
	cfg.set_value("game", "prompt_mode", prompt_mode)
	cfg.set_value("game", "target_language", target_language_choice())
	cfg.set_value("game", "strictness", strictness)
	cfg.set_value("game", "persist_zoo", persist_zoo)
	cfg.set_value("game", "speech_log", speech_log)
	cfg.set_value("content", "pairs", enabled_pairs)
	cfg.set_value("content", "colors", enabled_colors)
	cfg.set_value("io", "tts", tts_enabled)
	cfg.set_value("io", "stt", stt_enabled)
	cfg.set_value("io", "typed", typed_input)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "graphics_quality", graphics_quality)
	cfg.save(PATH)
	_apply_display()
	GraphicsQuality.set_profile(graphics_quality)
	changed.emit()


## Counted effortful failures the current mode allows before an assisted pass. Read through
## here rather than copied into the scene, so the three modes stay one table.
func assist_after_failures() -> int:
	return int(ASSIST_AFTER.get(strictness, ASSIST_AFTER[HEAR_NORMAL]))


func set_graphics_quality(value: String) -> void:
	graphics_quality = value if GraphicsQuality.is_valid_profile(value) else GraphicsQuality.STANDARD
	save_settings()


## A recogniser keeps the locale it started with. Cancel before changing the shared target,
## then rebuild input and voice selection so the next tap changes language without a reload.
func set_target_language(value: String) -> void:
	var requested := value if value in [TARGET_ENGLISH, TARGET_JAPANESE] else TARGET_ENGLISH
	if requested == target_language and _pending_target_language.is_empty():
		return
	_pending_target_language = requested
	if not Speech.session_state_changed.is_connected(_on_speech_state_for_language_change):
		Speech.session_state_changed.connect(_on_speech_state_for_language_change)
	Speech.cancel() # Safe before any session exists, including typed-only classrooms.
	# CHECKING and FINISHING deliberately refuse cancellation. Keep the old language active
	# until Chrome closes that recogniser rather than classifying its answer under a locale
	# that did not produce it or detaching the onend the session still needs.
	if Speech.is_active():
		return
	_apply_pending_target_language()


func target_language_choice() -> String:
	return _pending_target_language if not _pending_target_language.is_empty() \
		else target_language


func _on_speech_state_for_language_change(_session_id: int, state: int,
		_restart_queued: bool) -> void:
	if not _pending_target_language.is_empty() and state in [
			SpeechSession.State.COMPLETE, SpeechSession.State.CANCELLED]:
		call_deferred("_apply_pending_target_language")


func _apply_pending_target_language() -> void:
	if _pending_target_language.is_empty() or Speech.is_active():
		return
	target_language = _pending_target_language
	_pending_target_language = ""
	Speech.select_backend()
	Tts.reconfigure_language()
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
