class_name BodyPartSpec
extends Resource
## One primitive shape inside a procedurally assembled creature.
##
## A part is a pivot (positioned by `pivot`, oriented by `rotation_deg`) holding a mesh
## pushed away from that pivot by `offset`. Trait modifiers scale the *pivot*, so a trunk
## or an ear grows away from where it is attached instead of ballooning around its middle.

@export var id: String = ""
@export var shape: String = "box" ## box | sphere | capsule | cylinder | cone
@export var size: Vector3 = Vector3.ONE ## Mesh dimensions in metres.
@export var pivot: Vector3 = Vector3.ZERO ## Attachment point, animal-local.
@export var offset: Vector3 = Vector3.ZERO ## Mesh position relative to the pivot.
@export var rotation_deg: Vector3 = Vector3.ZERO
@export var role: String = "skin" ## Which shared material this part uses.
@export var stretch_axis: String = "y" ## Local axis the LENGTH modifier scales.


static func from_dict(d: Dictionary) -> BodyPartSpec:
	var p := BodyPartSpec.new()
	p.id = str(d.get("id", ""))
	p.shape = str(d.get("shape", "box"))
	p.size = to_v3(d.get("size", null), Vector3.ONE)
	p.pivot = to_v3(d.get("pos", null), Vector3.ZERO)
	p.offset = to_v3(d.get("off", null), Vector3.ZERO)
	p.rotation_deg = to_v3(d.get("rot", null), Vector3.ZERO)
	p.role = str(d.get("role", "skin"))
	p.stretch_axis = str(d.get("axis", "y"))
	return p


static func to_v3(value, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


## Index of the axis this part stretches along (0 = x, 1 = y, 2 = z).
func axis_index() -> int:
	match stretch_axis:
		"x": return 0
		"z": return 2
		_: return 1
