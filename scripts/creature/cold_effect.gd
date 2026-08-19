class_name ColdEffect
extends Node3D
## Everything that makes an animal read as COLD, in one self-contained node.
##
## The design constraint that shapes this: COLD must not look like HARD. HARD already
## owns "rigid, glossy, solid material" - a travelling shine sweep and a polished rim -
## so encasing the animal in ice or giving it a crystalline shell would make the two
## adjectives collide, which is fatal when the whole point is teaching opposites. So
## cold is carried almost entirely by ANIMATION and ENVIRONMENT instead of by the
## body's material: the animal shivers, breathes visible puffs, and stands in drifting
## snow and mist over a patch of ground frost. Its own colours stay clearly visible.
##
## Adding this node to the rig's fx_root is all that is needed; clear_fx() frees it on
## the next trait change and _exit_tree() hands the stance back to the rig.

const BREATH_INTERVAL := 2.6 ## Seconds between visible breaths, before jitter.

var _rig: CreatureRig = null
var _height := 1.55
var _shiver_amount := 0.0 ## 0 still, 1 full chatter. Ramped by the intro sequence.
var _clock := 0.0
var _breath_timer := 0.0
var _face: Node3D = null
var _muzzle := Vector3.ZERO
var _breath_direction := Vector3.FORWARD
var _patch: MeshInstance3D = null
var _rng := RandomNumberGenerator.new()


static func create(rig: CreatureRig) -> ColdEffect:
	var effect := ColdEffect.new()
	effect.name = "ColdEffect"
	effect._rig = rig
	effect._height = rig.definition.stand_height
	effect._configure_breath()
	return effect


func _ready() -> void:
	_rng.randomize()
	var h := _height
	var scale_for_species := h / 1.55

	# Parented to body so the measured snout point and its breath move with the shiver.
	_face = _rig.body

	# Snow falls through a box wider and taller than the animal, so flakes are already
	# in mid-air at every height rather than all appearing from one point.
	# The snow volume spans the animal from the ground to well over its head, so flakes
	# are always mid-fall at every height. Emitting from a flat box above the head
	# instead leaves a visible clump of snow hanging in the sky.
	var snow := Fx.make("snow", Color(1, 1, 1, 0.9), h * 0.5, scale_for_species)
	Fx.spread_along(snow, Vector3(h * 0.95, h * 0.85, h * 0.95))
	add_child(snow)
	snow.position = Vector3(0, h * 0.90, 0)
	snow.emitting = true

	# Mist pools around the feet in a flat, wide slab.
	var mist := Fx.make("cold_mist", Color(0.83, 0.93, 1.0, 0.30), h * 0.4, scale_for_species)
	Fx.spread_along(mist, Vector3(h * 0.40, h * 0.02, h * 0.40))
	add_child(mist)
	mist.position = Vector3(0, h * 0.10, 0)
	mist.emitting = true

	# Frost glinting on the fur at the two most readable silhouette points.
	_add_cling(_bone_point("head_top"), scale_for_species)
	_add_cling(_bone_point("rear"), scale_for_species)

	_patch = Fx.frost_patch(h * 0.34, Color(0.86, 0.95, 1.0, 0.55))
	_patch.position = Vector3(0, 0.012, 0)
	add_child(_patch)

	# Steady state by default: the zoo and the finished creature are already cold when
	# they appear and must not replay the arrival every time they are rebuilt.
	_shiver_amount = 1.0
	_breath_timer = _rng.randf_range(0.3, BREATH_INTERVAL)


func _add_cling(at: Vector3, scale_for_species: float) -> void:
	var cling := Fx.make("frost_cling", Color(0.88, 0.96, 1.0), _height * 0.10, scale_for_species)
	add_child(cling)
	cling.position = at
	cling.emitting = true


func _bone_point(socket: String) -> Vector3:
	var node: Node3D = _rig.sockets.get(socket)
	if node == null:
		return Vector3(0, _height * 0.8, 0)
	return node.position - _rig.definition.socket_offset(socket)


## The mesh itself supplies both facts a breath needs: where the snout ends and which way
## it points. This avoids treating an upright penguin beak like a low horse muzzle.
func _configure_breath() -> void:
	if _rig == null:
		return
	var anchors := _rig.face_anchors()
	var pivot: Vector3 = anchors["head_pivot"]
	var tip: Vector3 = anchors["snout_tip"]
	_breath_direction = Vector3(0.0, tip.y - pivot.y, tip.z - pivot.z).normalized()
	if _breath_direction.length_squared() < 0.5 or _breath_direction.z > -0.05:
		_breath_direction = Vector3.FORWARD
	# Start just beyond the skin so the first soft billboard does not bloom inside the face.
	_muzzle = tip + _breath_direction * (_height * 0.012)


func breath_origin() -> Vector3:
	return _muzzle


func breath_direction() -> Vector3:
	return _breath_direction


## The arrival: a gust blows through, the animal flinches and starts shivering, then
## breathes out and the frost spreads. Only played when a student actually picks the
## card - see TraitVisuals.apply_all's `animate`.
func play_intro() -> void:
	_shiver_amount = 0.0
	if _patch != null:
		_patch.scale = Vector3(0.15, 1.0, 0.15)

	var gust := Fx.make("motion", Color(0.86, 0.95, 1.0), _height * 0.45)
	gust.one_shot = true
	gust.explosiveness = 0.85
	# The gust crosses the animal sideways rather than rising, so it reads as weather
	# arriving rather than as anything the animal is emitting.
	var process := gust.process_material as ParticleProcessMaterial
	process.direction = Vector3(1, 0.1, 0)
	process.spread = 18.0
	add_child(gust)
	gust.position = Vector3(-_height * 0.5, _height * 0.5, 0)
	gust.emitting = true
	gust.finished.connect(gust.queue_free)

	var tween := create_tween()
	# Flinch away from the gust, then settle into a steady chatter.
	tween.tween_method(_set_shiver, 0.0, 1.45, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_method(_set_shiver, 1.45, 1.0, 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(_breathe)
	if _patch != null:
		# Frost creeps outward from under the feet while that happens.
		var grow := create_tween()
		grow.tween_property(_patch, "scale", Vector3.ONE, 1.5) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_breath_timer = 0.9


func _set_shiver(value: float) -> void:
	_shiver_amount = value


func _process(delta: float) -> void:
	_clock += delta

	# Two detuned high frequencies: a single sine reads as a smooth wobble, whereas the
	# beat between these reads as teeth chattering.
	var amp := _height * 0.006 * _shiver_amount
	var x := sin(_clock * 38.0) * 0.65 + sin(_clock * 53.0 + 1.1) * 0.35
	var z := sin(_clock * 44.0 + 2.3) * 0.5
	_rig.shiver_offset = Vector3(x * amp, 0.0, z * amp)
	_rig.shiver_roll = sin(_clock * 41.0 + 0.6) * 0.012 * _shiver_amount

	_breath_timer -= delta
	if _breath_timer <= 0.0:
		_breathe()


func _breathe() -> void:
	_breath_timer = BREATH_INTERVAL + _rng.randf_range(-0.5, 0.9)
	if _face == null or not is_instance_valid(_face):
		return
	Fx.burst(_face, _muzzle, "breath", Color(1, 1, 1, 0.5), _height * 0.05,
		_height / 1.55, _breath_direction)


func _exit_tree() -> void:
	# Hand the stance back, or the animal keeps the last frame of the shiver forever.
	if _rig != null and is_instance_valid(_rig):
		_rig.shiver_offset = Vector3.ZERO
		_rig.shiver_roll = 0.0
