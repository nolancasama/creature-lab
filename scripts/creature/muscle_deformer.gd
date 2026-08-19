class_name MuscleDeformer
extends RefCounted
## STRONG / WEAK use opposite treatments on the animal's two existing forelimbs. STRONG
## swells the animal's own upper forelegs into huge muscles; WEAK swaps those same limbs
## for skinny drooping arms. Chest, torso and overall body are never resized.
##
## The original front-leg or wing shoulder roots shrink only while their one-for-one
## replacements are visible. Returning to neutral restores them to authored scale.

const GROUPS: Array[String] = ["chest", "shoulder", "front_limb", "rear_limb", "neck"]
const STRONG_OVERSHOOT := 1.16

## Retained as the public scalar state used by TraitVisuals. The individual groups no
## longer drive body regions; all hold the same Strong/Neutral/Weak level.
var bulk := {}
var posture := 0.0 ## Strong's proud stillness; Weak and neutral remain relaxed.
var shake := Vector3.ZERO ## Brief Strong charge vibration only.
var squash := Vector3.ONE ## Always neutral: this pair never scales the body.
var pitch := 0.0
var yaw := 0.0 ## Tiny Strong presentation turn, never a shape change.
var lift := 0.0 ## Always zero so the supporting feet remain on the platform.

var morph_amount := 0.0
var limb_morph: ForelimbMorph = null

var _rig: CreatureRig = null
var _def: AnimalDefinition = null
var _tweens: Array[Tween] = []
var _target := 1.0


func _init(rig: CreatureRig) -> void:
	_rig = rig
	_def = rig.definition
	for group in GROUPS:
		bulk[group] = 1.0
	limb_morph = ForelimbMorph.create(rig)
	rig.body.add_child(limb_morph)


func set_state(level: float) -> void:
	kill_tweens()
	_target = level
	for group in GROUPS:
		bulk[group] = level
	var target_mode := _mode_for(level)
	morph_amount = 0.0 if target_mode == ForelimbMorph.Mode.NEUTRAL else 1.0
	posture = 0.0 # Both opposites preserve the animal's authored stance.
	shake = Vector3.ZERO
	squash = Vector3.ONE
	pitch = 0.0
	yaw = 0.0
	lift = 0.0
	_rig.set_weak_mesh({})
	limb_morph.set_state(target_mode, morph_amount)
	limb_morph.set_flex(0.0)


func reset() -> void:
	set_state(1.0)


func animate_to(level: float) -> void:
	if _rig == null or not _rig.is_inside_tree():
		set_state(level)
		return
	if is_equal_approx(level, _target):
		return
	kill_tweens()
	shake = Vector3.ZERO
	yaw = 0.0
	for group in GROUPS:
		bulk[group] = level
	match _mode_for(level):
		ForelimbMorph.Mode.STRONG:
			_animate_strong()
		ForelimbMorph.Mode.WEAK:
			_animate_weak()
		_:
			_animate_neutral()
	_target = level


func replaces_front_limbs() -> bool:
	return limb_morph != null and limb_morph.replaces_front_limbs()


func _mode_for(level: float) -> int:
	if level > 1.001:
		return ForelimbMorph.Mode.STRONG
	if level < 0.999:
		return ForelimbMorph.Mode.WEAK
	return ForelimbMorph.Mode.NEUTRAL


## The animal's own upper forelegs swell into muscle. There is no pose change, flex, fist,
## limb collapse or body motion: paws and wings stay exactly where they were authored.
func _animate_strong() -> void:
	Audio.play("charge", 0.9)
	_set_flex(0.0)
	var switching := limb_morph.mode != ForelimbMorph.Mode.NEUTRAL \
		and limb_morph.mode != ForelimbMorph.Mode.STRONG and morph_amount > 0.002
	var delay := 0.22 if switching else 0.0
	var reveal := _rig.create_tween()
	_tweens.append(reveal)
	if switching:
		reveal.tween_method(_set_morph_amount, morph_amount, 0.0, delay) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		reveal.tween_callback(_set_mode.bind(ForelimbMorph.Mode.STRONG))
	else:
		_set_mode(ForelimbMorph.Mode.STRONG)
	reveal.tween_interval(0.14)
	reveal.tween_callback(func() -> void: Audio.play("pop", 0.82))
	reveal.tween_method(_set_morph_amount, 0.0 if switching else morph_amount,
		STRONG_OVERSHOOT, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reveal.tween_method(_set_morph_amount, STRONG_OVERSHOOT, 1.0, 0.24) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	posture = 0.0
	yaw = 0.0


## WEAK swaps the same two limbs for skinny noodle arms. Only those arms attempt to flex,
## barely bulge, wobble, and droop; the animal itself never shakes or slumps.
func _animate_weak() -> void:
	Audio.play("weak", _def.voice_pitch)
	var switching := limb_morph.mode != ForelimbMorph.Mode.NEUTRAL \
		and limb_morph.mode != ForelimbMorph.Mode.WEAK and morph_amount > 0.002
	var delay := 0.22 if switching else 0.0
	var reveal := _rig.create_tween()
	_tweens.append(reveal)
	if switching:
		reveal.tween_method(_set_morph_amount, morph_amount, 0.0, delay) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		reveal.tween_callback(_set_mode.bind(ForelimbMorph.Mode.WEAK))
	else:
		_set_mode(ForelimbMorph.Mode.WEAK)
	reveal.tween_interval(0.18)
	reveal.tween_method(_set_morph_amount, 0.0 if switching else morph_amount, 1.0, 0.38) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var failed_flex := _rig.create_tween()
	_tweens.append(failed_flex)
	failed_flex.tween_interval(delay + 0.62)
	failed_flex.tween_method(_set_flex, 0.0, 0.72, 0.18).set_trans(Tween.TRANS_SINE)
	failed_flex.tween_callback(func() -> void: Audio.play("weak", _def.voice_pitch * 1.08))
	failed_flex.tween_method(_set_flex, 0.72, 0.0, 0.38) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	posture = 0.0


## Undoing either word retracts only its replacement and restores the original front
## legs/wings. No opposite animation or opposite arm form is played.
func _animate_neutral() -> void:
	Audio.play("zip", 0.82)
	var retract := _rig.create_tween()
	_tweens.append(retract)
	retract.tween_method(_set_flex, limb_morph.flex, 0.0, 0.10)
	retract.tween_method(_set_morph_amount, morph_amount, 0.0, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	retract.tween_callback(_set_mode.bind(ForelimbMorph.Mode.NEUTRAL))
	posture = 0.0


func kill_tweens() -> void:
	for tween in _tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_tweens.clear()


func is_animating() -> bool:
	for tween in _tweens:
		if tween != null and tween.is_valid() and tween.is_running():
			return true
	return false


func _set_mode(value: int) -> void:
	limb_morph.set_mode(value)


func _set_morph_amount(value: float) -> void:
	morph_amount = value
	limb_morph.set_amount(value)


func _set_flex(value: float) -> void:
	limb_morph.set_flex(value)


func _set_posture(value: float) -> void:
	posture = value


func _set_shake(value: Vector3) -> void:
	shake = value


func _set_yaw(value: float) -> void:
	yaw = value


func lift_total() -> float:
	return 0.0
