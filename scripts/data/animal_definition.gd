class_name AnimalDefinition
extends Resource
## Everything the game knows about one animal. Adding an animal is a data edit:
## no gameplay code names any animal.
##
## Animals are skinned models inside res://models/animals.glb. Where the old primitive
## build described *shapes*, this describes *bones* - which ones the LENGTH trait
## stretches, which ones STRENGTH thickens, which ones fantasy parts hang off.

@export var id: String = ""
@export var display_name: String = ""
@export var fantasy_noun: String = "" ## Used by the name generator (Horse -> Unicorn).
@export var model: String = "" ## Node name inside animals.glb.
@export var skin_color: Color = Color("#9aa0a8") ## Representative colour, for UI and ghosts.

## The LENGTH trait scales these bones along their own axis. Whatever reads best on
## this animal: ears on a dog, tail on a cat, wings on a chicken.
@export var feature_bones: PackedStringArray = PackedStringArray()
@export var feature_label: String = "" ## "ears" / "tail" / "wings", for teacher-facing text.

@export var bulk_bones: PackedStringArray = PackedStringArray() ## Thickened by STRENGTH.
@export var leg_bones: PackedStringArray = PackedStringArray() ## Swung by the walk cycle.

## socket name -> {"bone": String, "off": Vector3}. Offsets are in normalised units
## (the same scale as stand_height), Y up, so they read the same on every animal.
@export var sockets: Dictionary = {}

@export var stand_height: float = 2.0 ## Every model is scaled to stand this tall.
@export var walk_speed: float = 1.2
@export var voice_pitch: float = 1.0
@export var hover: float = 0.0 ## 1.0 for animals that swim instead of walk.


static func from_dict(d: Dictionary) -> AnimalDefinition:
	var a := AnimalDefinition.new()
	a.id = str(d.get("id", ""))
	a.display_name = str(d.get("display_name", a.id.capitalize()))
	a.fantasy_noun = str(d.get("fantasy_noun", a.display_name))
	a.model = str(d.get("model", ""))
	a.skin_color = Color.html(str(d.get("skin", "#9aa0a8")))
	a.feature_bones = PackedStringArray(d.get("feature_bones", []))
	a.feature_label = str(d.get("feature_label", "tail"))
	a.bulk_bones = PackedStringArray(d.get("bulk_bones", []))
	a.leg_bones = PackedStringArray(d.get("leg_bones", []))
	for socket_name in d.get("sockets", {}):
		var entry: Dictionary = d["sockets"][socket_name]
		a.sockets[str(socket_name)] = {
			"bone": str(entry.get("bone", "")),
			"off": BodyPartSpec.to_v3(entry.get("off", null), Vector3.ZERO),
		}
	a.stand_height = float(d.get("stand_height", 2.0))
	a.walk_speed = float(d.get("walk_speed", 1.2))
	a.voice_pitch = float(d.get("voice_pitch", 1.0))
	a.hover = float(d.get("hover", 0.0))
	return a


func socket_bone(socket_name: String) -> String:
	if sockets.has(socket_name):
		return str(sockets[socket_name].get("bone", ""))
	return ""


func socket_offset(socket_name: String) -> Vector3:
	if sockets.has(socket_name):
		return sockets[socket_name].get("off", Vector3.ZERO)
	return Vector3.ZERO
