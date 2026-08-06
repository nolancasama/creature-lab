extends Node
## Session persistence only - no accounts, no cloud.
##
## The two spec documents disagreed here: the gameplay doc says the zoo lives only for
## the session, the architecture doc says SaveManager stores it. Resolved in favour of
## the classroom: the zoo is a session concept, but it is mirrored to disk so a crash or
## an accidental Alt+F4 does not delete a child's morning of work. A teacher can wipe it
## from Teacher Settings, and turning persistence off makes it purely in-memory.

const ZOO_PATH := "user://zoo_session.json"


func save_zoo(zoo: Array) -> void:
	if not Settings.persist_zoo:
		return
	var payload := {"version": 1, "saved_unix": int(Time.get_unix_time_from_system()), "creatures": []}
	for creature in zoo:
		var state: CreatureState = creature
		payload["creatures"].append(state.to_dict())
	var f := FileAccess.open(ZOO_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write %s" % ZOO_PATH)
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()


func load_zoo() -> Array[CreatureState]:
	var out: Array[CreatureState] = []
	if not Settings.persist_zoo or not FileAccess.file_exists(ZOO_PATH):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ZOO_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var data: Dictionary = parsed
	for entry in data.get("creatures", []):
		if not (entry is Dictionary):
			continue
		var state := CreatureState.from_dict(entry)
		# A creature whose animal was removed from content can no longer be rendered.
		if Content.animal(state.animal_id) != null:
			out.append(state)
	return out


func clear_zoo() -> void:
	if FileAccess.file_exists(ZOO_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ZOO_PATH))
