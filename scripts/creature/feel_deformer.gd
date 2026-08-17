class_name FeelDeformer
extends RefCounted
## HARD / SOFT: what the animal is made of, and the transformation into it.
##
## One signed control, `feel`: +1 fully hard, -1 fully soft, 0 natural. Everything the
## student sees is derived from it, so the two adjectives can never disagree with each
## other:
##   hardness  = max(feel, 0)  -> shine, polish, rigidity
##   softness  = max(-feel, 0) -> puff, squash, jiggle, floppy appendages
##
## Deliberately touches no bones. Bone scale already belongs to MuscleDeformer and bone
## position to CreatureDeformer, so this works at the body-transform and material level
## instead - which is also the cheap way to do it. Nothing here simulates anything: a
## few tweened numbers, one extra shader branch, and a sine wave for the jiggle. That
## keeps it viable on a school Chromebook, where soft-body physics would not be.
##
## Softness is not "less shiny". A soft animal visibly puffs, squashes when it lands,
## and keeps a small wobble forever after; hardness takes the wobble away entirely.

const SQUASH_HOLD := 0.09
const JIGGLE_RATE := 8.5

var feel := 0.0 ## -1 soft .. +1 hard.

## Read by CreatureRig each frame and folded into the body transform.
var scale_multiplier := Vector3.ONE
var offset := Vector3.ZERO

var _rig: CreatureRig = null
var _def: AnimalDefinition = null
var _anim_scale := Vector3.ONE ## Transient squash/stretch from the transformation.
var _jiggle := 0.0 ## Amplitude of the persistent wobble.
var _clock := 0.0
var _tweens: Array[Tween] = []
var _min_y := 0.0
var _max_y := 1.0
var _sweep_edge := 0.0
var _sweep_glow := 0.0


func _init(rig: CreatureRig) -> void:
	_rig = rig
	_def = rig.definition
	if rig.mesh_instance != null:
		var box := rig.mesh_instance.get_aabb()
		_min_y = box.position.y
		_max_y = box.position.y + box.size.y


func hardness() -> float:
	return maxf(feel, 0.0)


func softness() -> float:
	return maxf(-feel, 0.0)


## How much idle sway, walk swing and secondary motion survives. A hard animal barely
## moves; a soft one moves more than normal.
func motion_scale() -> float:
	return 1.0 - hardness() * 0.75 + softness() * 0.35


func floppiness() -> float:
	return softness()


# --- State --------------------------------------------------------------------

## Snap straight to a state. Used for zoo residents, ghosts and finished creatures,
## which are all born already transformed.
func set_state(value: float) -> void:
	kill_tweens()
	feel = value
	_anim_scale = Vector3.ONE
	_jiggle = softness() * 0.5
	offset = Vector3.ZERO
	_apply_material(hardness(), _max_y + 1.0, 0.0)
	_recompute()


func reset() -> void:
	set_state(0.0)


## Persistent puff: a soft animal is wider than it is tall, which reads as a cushion
## rather than simply a bigger animal - the big/small trait already owns "bigger".
func _base_scale() -> Vector3:
	var puff := softness() * _def.soft_puff
	# Hard pulls very slightly the other way: tighter, more defined silhouette.
	var tighten := hardness() * 0.04
	return Vector3(1.0 + puff - tighten, 1.0 + puff * 0.45 - tighten, 1.0 + puff - tighten)


func _recompute() -> void:
	scale_multiplier = _base_scale() * _anim_scale


## Called by the rig every frame: the small wobble a soft animal never quite loses, and
## a little extra when it is walking.
func tick(delta: float, moving: bool) -> void:
	if _jiggle <= 0.0001:
		if not offset.is_zero_approx():
			offset = Vector3.ZERO
		_recompute()
		return
	_clock += delta * JIGGLE_RATE
	var amount: float = _jiggle * _def.soft_jiggle * 0.03 * (1.4 if moving else 1.0)
	var wobble := sin(_clock)
	var wobble_late := sin(_clock - 0.9) # belly lags behind the body
	_recompute()
	scale_multiplier *= Vector3(1.0 - wobble * amount, 1.0 + wobble * amount * 1.5, 1.0 - wobble_late * amount)
	offset = Vector3(0.0, wobble_late * amount * 0.35 * _def.stand_height, 0.0)


# --- Transitions --------------------------------------------------------------

func animate_to(value: float) -> void:
	if _rig == null or not _rig.is_inside_tree():
		set_state(value)
		return
	if is_equal_approx(value, feel):
		return
	kill_tweens()
	# Removing HARD or SOFT returns to the natural material. It must not be treated as
	# crossing into the opposite adjective (soft -> hard or hard -> soft).
	if is_zero_approx(value):
		_return_to_neutral()
		return
	if value > feel:
		_harden(value)
	else:
		_soften(value)


func _return_to_neutral() -> void:
	var from := feel
	var tween := _rig.create_tween()
	_tweens.append(tween)
	tween.tween_method(_set_neutral_feel, from, 0.0, 0.32) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## SOLIDIFY -> SHINE -> CLANG -> RIGID. The hardening travels up from the feet, so the
## change is something you watch happen rather than a material that simply swaps.
func _harden(value: float) -> void:
	feel = value
	_jiggle = 0.0

	# 1. Brace.
	var brace := _rig.create_tween()
	_tweens.append(brace)
	brace.tween_method(_set_anim_scale, Vector3.ONE, Vector3(1.05, 0.93, 1.05), 0.18) \
		.set_trans(Tween.TRANS_SINE)
	brace.tween_method(_set_anim_scale, Vector3(1.05, 0.93, 1.05), Vector3.ONE, 0.22) \
		.set_trans(Tween.TRANS_SINE)

	# 2-5. The hard surface climbs the body, and the sweep band rides with it.
	var span := _max_y - _min_y
	var sweep := _rig.create_tween()
	_tweens.append(sweep)
	sweep.tween_interval(0.20)
	sweep.tween_callback(func() -> void: Audio.play("charge", 1.5))
	sweep.tween_method(_set_sweep, _min_y - span * 0.15, _max_y + span * 0.15, 0.85) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	var glow := _rig.create_tween()
	_tweens.append(glow)
	glow.tween_interval(0.20)
	glow.tween_method(_set_glow, 0.0, 2.2, 0.18).set_trans(Tween.TRANS_SINE)
	glow.tween_interval(0.5)
	glow.tween_method(_set_glow, 2.2, 0.0, 0.28).set_trans(Tween.TRANS_SINE)

	# 6-9. Overshoot the shine, CLANG, and a short rigid vibration from the impact.
	var impact := _rig.create_tween()
	_tweens.append(impact)
	impact.tween_interval(1.05)
	impact.tween_callback(func() -> void: Audio.play("clang"))
	impact.tween_method(_set_anim_scale, Vector3.ONE, Vector3(1.09, 0.90, 1.09), 0.07) \
		.set_trans(Tween.TRANS_SINE)
	impact.tween_method(_set_anim_scale, Vector3(1.09, 0.90, 1.09), Vector3.ONE, 0.26) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	var shudder := _rig.create_tween()
	_tweens.append(shudder)
	shudder.tween_interval(1.05)
	var kick: float = _def.stand_height * 0.012
	for i in 6:
		var direction := 1.0 if i % 2 == 0 else -1.0
		var decay: float = 1.0 - float(i) / 6.0
		shudder.tween_method(_set_offset, offset, Vector3(kick * direction * decay, 0.0, 0.0), 0.035)
	shudder.tween_method(_set_offset, offset, Vector3.ZERO, 0.06)

	# Fireworks are not needed; a couple of sparks at the moment of impact are.
	var spark := _rig.create_tween()
	_tweens.append(spark)
	spark.tween_interval(1.05)
	spark.tween_callback(func() -> void:
		Fx.burst(_rig.fx_root, Vector3(0.0, _def.stand_height * 0.45, 0.0), "sparkle",
			Color("#dfefff"), _def.stand_height * 0.35))


## PUFF -> SQUISH -> BOING -> JIGGLE. The biggest, silliest physical move in the game.
func _soften(value: float) -> void:
	var from_feel := feel
	feel = value
	var depth: float = _def.soft_squash
	var wide: float = 1.0 + depth * 0.62

	# 1-3. Puff outward first, so the squash has something to squash.
	var puff := _rig.create_tween()
	_tweens.append(puff)
	puff.tween_callback(func() -> void: Audio.play("puff"))
	puff.tween_method(_set_feel_only, from_feel, value, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	var body := _rig.create_tween()
	_tweens.append(body)
	body.tween_interval(0.45)

	# 4-6. An invisible weight drops it: squash hard, hold a beat.
	body.tween_callback(func() -> void: Audio.play("squish", 0.85))
	body.tween_method(_set_anim_scale, Vector3.ONE, Vector3(wide, 1.0 - depth, wide), 0.20) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	body.tween_interval(SQUASH_HOLD)

	# 7-9. Release, boing past its own height.
	body.tween_callback(func() -> void: Audio.play("boing"))
	body.tween_method(_set_anim_scale, Vector3(wide, 1.0 - depth, wide),
		Vector3(1.0 - depth * 0.34, 1.0 + depth * 0.52, 1.0 - depth * 0.34), 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 10-11. Two or three diminishing wobbles, then settle.
	var amplitude := depth * 0.30
	for i in 3:
		var high := Vector3(1.0 - amplitude * 0.6, 1.0 + amplitude, 1.0 - amplitude * 0.6)
		var low := Vector3(1.0 + amplitude * 0.7, 1.0 - amplitude * 0.75, 1.0 + amplitude * 0.7)
		body.tween_method(_set_anim_scale, high, low, 0.16).set_trans(Tween.TRANS_SINE)
		amplitude *= 0.45
		body.tween_method(_set_anim_scale, low,
			Vector3(1.0 - amplitude * 0.5, 1.0 + amplitude, 1.0 - amplitude * 0.5), 0.16) \
			.set_trans(Tween.TRANS_SINE)
	body.tween_method(_set_anim_scale, _anim_scale, Vector3.ONE, 0.22) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	# The wobble it keeps for good.
	var settle := _rig.create_tween()
	_tweens.append(settle)
	settle.tween_interval(0.65)
	settle.tween_method(_set_jiggle, 0.0, softness() * 0.5, 0.9).set_trans(Tween.TRANS_SINE)

	# Softening also unwinds any hardness that was there.
	_apply_material(0.0, _max_y + 1.0, 0.0)


func kill_tweens() -> void:
	for t in _tweens:
		if t != null and t.is_valid():
			t.kill()
	_tweens.clear()


func is_animating() -> bool:
	for t in _tweens:
		if t != null and t.is_valid() and t.is_running():
			return true
	return false


func _apply_material(hard: float, edge: float, glow: float) -> void:
	_sweep_edge = edge
	_sweep_glow = glow
	_push_material(hard)


func _push_material(hard: float) -> void:
	if _rig.material == null:
		return
	_rig.material.set_shader_parameter("hardness", clampf(hard, 0.0, 1.0))
	_rig.material.set_shader_parameter("harden_edge", _sweep_edge)
	_rig.material.set_shader_parameter("harden_width", (_max_y - _min_y) * 0.14)
	_rig.material.set_shader_parameter("sweep_glow", _sweep_glow)


# --- Tween setters ------------------------------------------------------------

func _set_anim_scale(value: Vector3) -> void:
	_anim_scale = value
	_recompute()


## Hardening rises from the feet: everything below the edge has already turned.
func _set_sweep(edge: float) -> void:
	_sweep_edge = edge
	_push_material(hardness())


func _set_glow(value: float) -> void:
	_sweep_glow = value
	_push_material(hardness())


func _set_feel_only(value: float) -> void:
	feel = value
	_recompute()


## A plain fade back to the natural state, without any HARD or SOFT transformation beats.
func _set_neutral_feel(value: float) -> void:
	feel = value
	_jiggle = softness() * 0.5
	offset = Vector3.ZERO
	_apply_material(hardness(), _max_y + 1.0, 0.0)
	_recompute()


func _set_offset(value: Vector3) -> void:
	offset = value


func _set_jiggle(value: float) -> void:
	_jiggle = value
