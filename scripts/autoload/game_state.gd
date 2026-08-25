extends Node
## The finite state machine and the one CreatureState everything else reads from.
##
## Game owns *what* is true; Router owns *which scene shows it*. They talk through the
## phase_changed signal, so no scene ever reaches into another scene.

signal phase_changed(phase: int, previous: int)
signal creature_updated(state: CreatureState)
signal zoo_changed
## Debug tools talk to whichever scene is listening rather than reaching into it.
signal debug_action(action: String)

enum Phase { TITLE, ANIMAL_SELECTION, CREATURE_LAB, TRANSFORMATION, NAMING, ZOO, TEACHER_SETTINGS }

const ZOO_CAPACITY := 30

## Legal transitions. Anything else is a bug and gets rejected loudly rather than
## quietly leaving the game in an impossible state.
const ALLOWED := {
	Phase.TITLE: [Phase.ANIMAL_SELECTION, Phase.ZOO, Phase.TEACHER_SETTINGS],
	Phase.ANIMAL_SELECTION: [Phase.CREATURE_LAB, Phase.TITLE, Phase.ZOO, Phase.TEACHER_SETTINGS],
	Phase.CREATURE_LAB: [Phase.TRANSFORMATION, Phase.ANIMAL_SELECTION, Phase.TITLE, Phase.TEACHER_SETTINGS],
	Phase.TRANSFORMATION: [Phase.NAMING, Phase.TITLE],
	Phase.NAMING: [Phase.ZOO, Phase.TITLE, Phase.ANIMAL_SELECTION],
	Phase.ZOO: [Phase.ANIMAL_SELECTION, Phase.TITLE, Phase.TEACHER_SETTINGS],
	Phase.TEACHER_SETTINGS: [Phase.TITLE, Phase.ANIMAL_SELECTION, Phase.ZOO],
}

var phase: Phase = Phase.TITLE
var current: CreatureState = null
var zoo: Array[CreatureState] = []
## A one-scene visual handoff, never saved with the creature. The recording screen writes
## its final subject-relative camera and animal angle; the chamber consumes it once.
var _transformation_handoff := {}

var _return_phase: Phase = Phase.TITLE


func _ready() -> void:
	zoo.assign(SaveService.load_zoo())


func set_phase(next: Phase) -> bool:
	if next == phase:
		return true
	var legal: Array = ALLOWED.get(phase, [])
	if not legal.has(next):
		push_error("Illegal phase transition: %s -> %s" % [Phase.keys()[phase], Phase.keys()[next]])
		return false
	var previous := phase
	phase = next
	phase_changed.emit(next, previous)
	return true


## Teacher Settings can be opened from several places; remember where to go back to.
func open_settings() -> void:
	_return_phase = phase
	set_phase(Phase.TEACHER_SETTINGS)


func close_settings() -> void:
	set_phase(_return_phase if ALLOWED[Phase.TEACHER_SETTINGS].has(_return_phase) else Phase.TITLE)


# --- Creature lifecycle ------------------------------------------------------

## Cleared when a round starts, so kept_slots describes this creature only.
func _clear_voice_log() -> void:
	Voice.kept_slots.clear()


func begin_creature(animal_id: String) -> void:
	_clear_voice_log()
	current = CreatureState.create(animal_id)
	_transformation_handoff = {}
	# One child's recorded voice must never surface in the next child's transformation.
	Voice.clear()
	creature_updated.emit(current)


func record_sentence(category: String, before: String, after: String, assisted := false) -> void:
	if current == null:
		return
	current.add_entry(category, before, after, assisted)
	creature_updated.emit(current)


func finish_creature(final_name: String) -> void:
	if current == null:
		return
	current.custom_name = final_name
	zoo.append(current)
	while zoo.size() > ZOO_CAPACITY:
		zoo.pop_front()
	SaveService.save_zoo(zoo)
	current = null
	_transformation_handoff = {}
	zoo_changed.emit()


func abandon_creature() -> void:
	current = null
	_transformation_handoff = {}
	Voice.clear()


func set_transformation_handoff(camera_offset: Vector3, aim_offset: Vector3,
		camera_fov: float, creature_rotation_y: float) -> void:
	_transformation_handoff = {
		"camera_offset": camera_offset,
		"aim_offset": aim_offset,
		"camera_fov": camera_fov,
		"creature_rotation_y": creature_rotation_y,
	}


func take_transformation_handoff() -> Dictionary:
	var handoff := _transformation_handoff.duplicate(true)
	_transformation_handoff = {}
	return handoff


## Take one creature out of the zoo, because the student asked.
##
## Until now a creature could only leave two ways: reset_zoo() threw away all of them, or
## the capacity cap silently dropped the OLDEST once there were more than thirty - which in
## a classroom is very likely the one a child was proudest of. Neither was a decision the
## person who made it got to make.
func release_from_zoo(state: CreatureState) -> bool:
	var index := zoo.find(state)
	if index == -1:
		return false
	zoo.remove_at(index)
	SaveService.save_zoo(zoo)
	zoo_changed.emit()
	return true


func reset_zoo() -> void:
	zoo.clear()
	SaveService.clear_zoo()
	zoo_changed.emit()


## Used by the debug overlay to fill the zoo without speaking thirty sentences.
func spawn_debug_creature() -> void:
	var ids := Content.animal_ids()
	if ids.is_empty() or Content.pairs.size() < 2:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var state := CreatureState.create(ids[rng.randi() % ids.size()])
	var picks := Content.pairs.duplicate()
	picks.shuffle()
	for i in mini(2, picks.size()):
		var p: TraitDefinition = picks[i]
		var flip := rng.randf() < 0.5
		state.add_entry(p.category, p.word_b if flip else p.word_a, p.word_a if flip else p.word_b)
	var swatches := Content.colors.duplicate()
	swatches.shuffle()
	if swatches.size() >= 2:
		state.add_entry(Content.COLOR_CATEGORY, swatches[0].word, swatches[1].word)
	state.generated_name = NameGenerator.candidates(state)[0]
	zoo.append(state)
	while zoo.size() > ZOO_CAPACITY:
		zoo.pop_front()
	zoo_changed.emit()
