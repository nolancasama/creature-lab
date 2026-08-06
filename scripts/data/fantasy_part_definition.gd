class_name FantasyPartDefinition
extends Resource
## A modular add-on grown by the transformation chamber when an "after" word matches
## `trigger`. Part positions are relative to the named socket on the base animal.

@export var id: String = ""
@export var display_name: String = ""
@export var trigger: String = "" ## The "Now it is ___" word that grows this part.
@export var socket: String = "back"
@export var parts: Array[BodyPartSpec] = []


static func from_dict(d: Dictionary) -> FantasyPartDefinition:
	var f := FantasyPartDefinition.new()
	f.id = str(d.get("id", ""))
	f.display_name = str(d.get("display_name", f.id.capitalize()))
	f.trigger = str(d.get("trigger", ""))
	f.socket = str(d.get("socket", "back"))
	for entry in d.get("parts", []):
		f.parts.append(BodyPartSpec.from_dict(entry))
	return f
