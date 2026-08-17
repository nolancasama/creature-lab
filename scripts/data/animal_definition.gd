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

## The torso segments LONG/SHORT pushes apart. These are *translated*, not scaled, so
## the torso lengthens while the head, legs and tail keep their own proportions.
@export var body_bones: PackedStringArray = PackedStringArray()

## Trait categories this animal cannot use (for example, a penguin cannot be long/short).
@export var disabled_categories: PackedStringArray = PackedStringArray()

## One entry per leg, in the order they pop out during a TALL transformation:
## {"id": String, "bones": PackedStringArray}. The bones are the telescoping segments
## below the hip, so TALL/SHORT changes leg length without touching the torso.
@export var legs: Array[Dictionary] = []

## STRONG/WEAK muscle groups: name -> {"bones": PackedStringArray}. Nesting between
## groups is resolved by walking the skeleton, not declared here.
@export var bulk: Dictionary = {}

## Optional STRONG/WEAK rib treatment, expressed as fractions of this mesh's local
## AABB: {"center": [x,y,z], "size": [x,y,z], "count": 3..5, "depth": number}.
## Keeping it data-driven lets unusually shaped species tune their chest region without
## hard-coding model names in the shader.
@export var rib_profile: Dictionary = {}

## leg id -> sole/hoof contact offset from that leg's final configured foot bone.
## Values are in normalised creature units and are measured from each neutral mesh,
## rather than inferred from a whole-model bounding box at runtime.
@export var foot_contacts: Dictionary = {}
@export var ground_neutral := false ## Opt-in correction for an authored uneven stance.

## Which species finishing pose closes the power-up: stomp | rear | puff | flex.
@export var flourish: String = "puff"

## HARD/SOFT tuning. How far this species puffs and squashes when it turns soft, how
## much it keeps jiggling afterwards, and which appendages loosen up.
@export var soft_puff := 0.15
@export var soft_squash := 0.55
@export var soft_jiggle := 1.0
@export var floppy_bones: PackedStringArray = PackedStringArray()

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
	a.body_bones = PackedStringArray(d.get("body_bones", []))
	a.disabled_categories = PackedStringArray(d.get("disabled_categories", []))
	for leg in d.get("legs", []):
		a.legs.append({
			"id": str(leg.get("id", "leg")),
			"bones": PackedStringArray(leg.get("bones", [])),
		})
	for group_name in d.get("bulk", {}):
		var group: Dictionary = d["bulk"][group_name]
		a.bulk[str(group_name)] = {"bones": PackedStringArray(group.get("bones", []))}
	var ribs = d.get("ribs", {})
	if ribs is Dictionary:
		a.rib_profile = ribs.duplicate(true)
	for leg_id in d.get("foot_contacts", {}):
		a.foot_contacts[str(leg_id)] = BodyPartSpec.to_v3(
			d["foot_contacts"][leg_id], Vector3.ZERO)
	a.ground_neutral = bool(d.get("ground_neutral", false))
	a.flourish = str(d.get("flourish", "puff"))
	var feel: Dictionary = d.get("feel", {})
	a.soft_puff = float(feel.get("puff", 0.15))
	a.soft_squash = float(feel.get("squash", 0.55))
	a.soft_jiggle = float(feel.get("jiggle", 1.0))
	a.floppy_bones = PackedStringArray(feel.get("floppy_bones", []))
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


func bulk_bones_for(group: String) -> PackedStringArray:
	if bulk.has(group):
		return bulk[group].get("bones", PackedStringArray())
	return PackedStringArray()


func foot_contact_for(leg_id: String) -> Vector3:
	return foot_contacts.get(leg_id, Vector3.ZERO)


func socket_bone(socket_name: String) -> String:
	if sockets.has(socket_name):
		return str(sockets[socket_name].get("bone", ""))
	return ""


func socket_offset(socket_name: String) -> Vector3:
	if sockets.has(socket_name):
		return sockets[socket_name].get("off", Vector3.ZERO)
	return Vector3.ZERO
