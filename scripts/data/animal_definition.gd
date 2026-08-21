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

## Historical body-region map retained for compatibility and neutral measurements. The
## Strong/Weak pair no longer deforms any of these chest or body regions.
@export var bulk: Dictionary = {}

## Forelimb data shared by STRONG's bone-following muscle shells and WEAK's one-for-one
## replacement arms. Keys per side: bone, original_root, chain, kind, offset, rotation,
## scale. STRONG leaves the chain intact; WEAK collapses original_root while replacing it.
@export var forelimbs: Dictionary = {}

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

## YOUNG tuning. Everything here has a default derived from this animal's own stand height
## and face socket, so a new animal reads as a baby without authoring any of it - the
## entries exist to correct species whose muzzle is unusually long or whose head sits at an
## odd angle, not to be filled in seven times. Keys, all optional:
##   head_scale   float  - how much larger the head bone gets.
##   cheek        {size, spacing, forward, down}
##   pacifier     {size, forward, down, tilt, tip} - surface-relative corrections; positive
##                                                   down lowers it; tip mounts at a beak tip
##
##   tint         "#rrggbb" - the young coat colour; defaults to a lightened skin colour.
##
## Every distance is a multiple of the measured face depth (or usable head span for
## vertical offsets), so an override reads on the same scale as its built-in fallback.
@export var young: Dictionary = {}

## OLD tuning, same shape and same unit as `young`. Keys, all optional:
##   grey     {muzzle_size, muzzle_forward, muzzle_down, temple_size, temple_forward,
##             temple_up, temple_spacing}
##   beard    {size, forward, down, length, tip, normal/small/big/long/short/tall overrides}
##            `tip` is opt-in; birds normally use the middle/base mouth surface instead.
##   specs    {size, spacing, forward, up, wire}
##   brow     {length, thickness, spacing, forward, up, angle}  - angle in degrees
##   tint     "#rrggbb" - the colour of the aging markings.
@export var old: Dictionary = {}


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
	var forelimb_cfg = d.get("forelimbs", {})
	if forelimb_cfg is Dictionary:
		a.forelimbs = (forelimb_cfg as Dictionary).duplicate(true)
	var ribs = d.get("ribs", {})
	if ribs is Dictionary:
		a.rib_profile = ribs.duplicate(true)
	for leg_id in d.get("foot_contacts", {}):
		a.foot_contacts[str(leg_id)] = BodyPartSpec.to_v3(
			d["foot_contacts"][leg_id], Vector3.ZERO)
	a.ground_neutral = bool(d.get("ground_neutral", false))
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
	var young_cfg = d.get("young", {})
	if young_cfg is Dictionary:
		a.young = (young_cfg as Dictionary).duplicate(true)
	var old_cfg = d.get("old", {})
	if old_cfg is Dictionary:
		a.old = (old_cfg as Dictionary).duplicate(true)
	return a


func bulk_bones_for(group: String) -> PackedStringArray:
	if bulk.has(group):
		return bulk[group].get("bones", PackedStringArray())
	return PackedStringArray()


## Resolve one existing front leg/wing without naming species in code. Explicit animal
## data is preferred; the shoulder map remains a safe fallback for imported animals.
func forelimb_config(side: String) -> Dictionary:
	var side_cfg: Dictionary = {}
	var raw_side = forelimbs.get(side, {})
	if raw_side is Dictionary:
		side_cfg = (raw_side as Dictionary).duplicate(true)
	var suffix := ".L" if side == "left" else ".R"
	var fallback_bone := ""
	for bone in bulk_bones_for("shoulder"):
		if str(bone).ends_with(suffix):
			fallback_bone = str(bone)
			break
	if fallback_bone.is_empty() and not bulk_bones_for("shoulder").is_empty():
		fallback_bone = str(bulk_bones_for("shoulder")[0])
	return {
		"bone": str(side_cfg.get("bone", fallback_bone)),
		"original_root": str(side_cfg.get("original_root", side_cfg.get("bone", fallback_bone))),
		"chain": PackedStringArray(side_cfg.get("chain", [side_cfg.get("bone", fallback_bone)])),
		"kind": str(side_cfg.get("kind", "leg")),
		"offset": BodyPartSpec.to_v3(side_cfg.get("offset", null), Vector3.ZERO),
		"rotation": BodyPartSpec.to_v3(side_cfg.get("rotation", null), Vector3.ZERO),
		"scale": float(side_cfg.get("scale", forelimbs.get("scale", 1.0))),
	}


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


# --- YOUNG tuning ------------------------------------------------------------
#
# Read through these accessors so TraitVisuals never branches on species. Distances fall
# back to fractions of the muzzle length the rig measures off the model itself, so a
# species only needs an entry in `young` when that measurement is not enough - a head
# carried at an angle, or a coat that should not simply be its adult colour lightened.

func young_head_scale() -> float:
	return float(young.get("head_scale", 1.30))


## `group` is cheek | pacifier; `key` a field inside it. Both the override and `fallback`
## are multiples of the measured muzzle length, which the caller applies - so the two are
## always in the same unit and an override can be read against the default it replaces.
func young_value(group: String, key: String, fallback: float) -> float:
	var cfg = young.get(group, {})
	if cfg is Dictionary and (cfg as Dictionary).has(key):
		return float((cfg as Dictionary)[key])
	return fallback


## The coat a young animal wears. Most species just lighten toward their adult colour, but
## that is wrong for a chick (yellow down, not a pale hen) and for a penguin chick (grey-
## white fluff, not a washed-out tuxedo), so it is overridable.
func young_tint() -> Color:
	if young.has("tint"):
		return Color.html(str(young["tint"]))
	return skin_color.lightened(0.45)


## The OLD counterpart of young_value(): same unit (multiples of the measured muzzle
## length), same fallback contract.
func old_value(group: String, key: String, fallback: float) -> float:
	var cfg = old.get(group, {})
	if cfg is Dictionary and (cfg as Dictionary).has(key):
		return float((cfg as Dictionary)[key])
	return fallback


## The colour of the aging markings. Grey by default; overridable for a species whose own
## colouring would swallow it.
func old_tint() -> Color:
	if old.has("tint"):
		return Color.html(str(old["tint"]))
	return Color("#b9bec6")
