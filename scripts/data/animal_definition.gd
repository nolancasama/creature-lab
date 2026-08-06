class_name AnimalDefinition
extends Resource
## Everything the game knows about one animal. Adding an animal is a data edit:
## no gameplay code names any animal.

@export var id: String = ""
@export var display_name: String = ""
@export var fantasy_noun: String = "" ## Used by the name generator (Elephant -> Mammoth).
@export var skin_color: Color = Color("#9aa0a8")
@export var accent_color: Color = Color("#7d838b")
@export var belly_color: Color = Color("#cfd4da")
@export var parts: Array[BodyPartSpec] = []
@export var sockets: Dictionary = {} ## socket name -> Vector3, where fantasy parts attach.

## The LENGTH modifier stretches these (trunk / ears / tail / neck)...
@export var feature_parts: PackedStringArray = PackedStringArray()
## ...and slides these along `feature_dir` so things attached to the tip keep up.
@export var feature_followers: PackedStringArray = PackedStringArray()
@export var feature_dir: Vector3 = Vector3.DOWN
@export var feature_length: float = 1.0

@export var bulk_parts: PackedStringArray = PackedStringArray() ## Thickened by STRENGTH.
@export var stand_height: float = 2.0 ## Used to frame cameras and place labels.
@export var walk_speed: float = 1.2
@export var voice_pitch: float = 1.0
@export var hover: float = 0.0 ## 1.0 for animals that swim instead of walk.


static func from_dict(d: Dictionary) -> AnimalDefinition:
	var a := AnimalDefinition.new()
	a.id = str(d.get("id", ""))
	a.display_name = str(d.get("display_name", a.id.capitalize()))
	a.fantasy_noun = str(d.get("fantasy_noun", a.display_name))
	a.skin_color = Color.html(str(d.get("skin", "#9aa0a8")))
	a.accent_color = Color.html(str(d.get("accent", "#7d838b")))
	a.belly_color = Color.html(str(d.get("belly", "#cfd4da")))
	for entry in d.get("parts", []):
		a.parts.append(BodyPartSpec.from_dict(entry))
	for socket_name in d.get("sockets", {}):
		a.sockets[str(socket_name)] = BodyPartSpec.to_v3(d["sockets"][socket_name], Vector3.ZERO)
	a.feature_parts = PackedStringArray(d.get("feature_parts", []))
	a.feature_followers = PackedStringArray(d.get("feature_followers", []))
	a.feature_dir = BodyPartSpec.to_v3(d.get("feature_dir", null), Vector3.DOWN)
	a.feature_length = float(d.get("feature_length", 1.0))
	a.bulk_parts = PackedStringArray(d.get("bulk_parts", []))
	a.stand_height = float(d.get("stand_height", 2.0))
	a.walk_speed = float(d.get("walk_speed", 1.2))
	a.voice_pitch = float(d.get("voice_pitch", 1.0))
	a.hover = float(d.get("hover", 0.0))
	return a

