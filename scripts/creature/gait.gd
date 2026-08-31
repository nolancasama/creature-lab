class_name Gait
extends RefCounted
## The walk cycle, one per species.
##
## No walk animations ship with these models, so the legs are posed in code. What was here
## before rotated a single bone per leg by sin(clock * 5) with the sign flipped on every
## other leg: four rods pivoting at the shoulder, both sides of the animal in lockstep, and
## the same motion on a chicken as on a horse.
##
## Three things are different here.
##
## FOUR BEATS, NOT TWO. A quadruped's feet land one at a time in the order rear-left,
## front-left, rear-right, front-right. Phase offsets of a quarter cycle produce that
## directly; the old parity flip produced a two-beat pace no walking mammal uses.
##
## THE WHOLE CHAIN MOVES. Every rig here carries four joints per leg - thigh, shin, foot,
## toe - and only the first was being touched. The joint between front_shin and front_foot
## IS the carpus, so the stiff straight foreleg was never a rigging limit, just an unused
## bone. Elbow, carpus, stifle and hock each get their own curve and their own timing.
##
## THE STRIDE IS MEASURED, NOT TIMED. Phase advances with distance actually travelled, not
## with the clock, so one stride covers exactly one stride's worth of ground. This is what
## stops the skating: a planted foot rotates backward at precisely the speed the body moves
## forward, because both are driven by the same number.
##
## Species differ by the numbers in DEFAULTS, not by separate code paths, and animals.json
## may override any of them per animal via a "gait" block.

## Footfall order for a four-beat walk, as a fraction of the cycle after the rear-left foot
## lands. Lateral sequence: the two legs of one side never swing together, which is what
## keeps a walk from reading as a pace.
const QUADRUPED_PHASE := {
	"rear_left": 0.0,
	"front_left": 0.25,
	"rear_right": 0.5,
	"front_right": 0.75,
}
const BIPED_PHASE := {"rear_left": 0.0, "rear_right": 0.5}

## Fallback cadence for a creature that is "moving" but not translating - the lab platform,
## where the animal walks on the spot. Radians per second of phase, not of bone angle.
const IN_PLACE_CADENCE := 0.85
## How much the knee gives as weight comes onto it, during stance. Trades directly against
## foot planting - measured with --gaittest, 0.12 cost about a fifth of the stance to slide
## and 0.04 reads as weight while leaving the plant intact.
const STANCE_YIELD := 0.04
const MIN_STRIDE := 0.05 ## Guards the divide; a zero-length leg must not spin the phase.

## Every tunable, with the values used when animals.json says nothing. Angles are radians.
##
## duty       fraction of the cycle a foot spends on the ground (a walk is over half)
## stride     ground distance per cycle, as a multiple of the leg's own length
## knee       stifle flex on the rear leg during swing
## elbow      elbow flex on the front leg during swing
## carpus     wrist flex on the front leg during swing - the stiff-foreleg fix
## hock       ankle flex on the rear leg during swing
## toe        toe roll at push-off and touchdown
## bob        vertical travel of the body, twice per cycle
## roll       side-to-side body lean, once per cycle - the penguin's waddle
## pitch      fore-aft body tilt, twice per cycle
## pelvis     pelvis yaw counter-rotation
## chest      chest yaw, opposing the pelvis - a flexible spine, felt through the shoulders
## spine      vertical spine undulation across the back
## neck       neck pitch across the stride
## head_bob   forward head thrust-and-hold; the chicken's defining move
## tail       tail sway
const DEFAULTS := {
	"duty": 0.62, "stride": 1.15,
	"knee": 0.55, "elbow": 0.50, "carpus": 0.60, "hock": 0.45, "toe": 0.30,
	"bob": 0.020, "roll": 0.020, "pitch": 0.012,
	"pelvis": 0.05, "chest": 0.04, "spine": 0.03,
	"neck": 0.04, "head_bob": 0.0, "tail": 0.10,
}

## Where the species character lives. Each entry is a delta from DEFAULTS, so an animal only
## names what makes it itself and the shared walk carries the rest.
const SPECIES := {
	# Energetic but relaxed. Quicker steps than the big animals, a real bob, a loose tail.
	"dog": {
		"duty": 0.60, "stride": 1.05,
		"elbow": 0.62, "carpus": 0.72, "knee": 0.60, "hock": 0.52, "toe": 0.34,
		"bob": 0.026, "pelvis": 0.07, "chest": 0.05, "tail": 0.22, "neck": 0.05,
	},
	# Quiet and deliberate: longer, lower steps, almost no bob, and the spine doing more of
	# the work than the legs. The tail is a slow counterweight rather than a wag.
	"cat": {
		"duty": 0.66, "stride": 1.30,
		"elbow": 0.58, "carpus": 0.66, "knee": 0.52, "hock": 0.46, "toe": 0.22,
		"bob": 0.010, "roll": 0.026, "pitch": 0.008,
		"pelvis": 0.09, "chest": 0.08, "spine": 0.06, "neck": 0.03, "tail": 0.16,
	},
	# A prowl. Slowest cadence and the longest stance of any of them, heavy roll through the
	# shoulders, and the head carried low and steady.
	"tiger": {
		# Shorter than the cat's despite being the larger animal: this rig's hind legs measure
		# 1.6x its front, so a stride sized off the hind pair had the forelegs swinging 52
		# degrees to keep up with it. 1.10 brings that back to about 30, like everyone else.
		"duty": 0.70, "stride": 1.10,
		"elbow": 0.52, "carpus": 0.58, "knee": 0.46, "hock": 0.42, "toe": 0.20,
		"bob": 0.014, "roll": 0.034, "pitch": 0.010,
		"pelvis": 0.10, "chest": 0.09, "spine": 0.05, "neck": 0.02, "tail": 0.20,
	},
	# Light and alert. Long legs, small angles: the reach comes from the length of the limb
	# rather than from swinging it hard, which is what separates it from the horse.
	"deer": {
		"duty": 0.62, "stride": 1.35,
		"elbow": 0.44, "carpus": 0.62, "knee": 0.40, "hock": 0.50, "toe": 0.16,
		"bob": 0.016, "roll": 0.012, "pitch": 0.010,
		"pelvis": 0.05, "chest": 0.04, "spine": 0.02, "neck": 0.06, "tail": 0.08,
	},
	# Grounded and rhythmic. Least flex of all - a horse's knee stays comparatively straight,
	# and over-bending it is exactly what makes a horse walk look like a big dog.
	"horse": {
		"duty": 0.66, "stride": 1.45,
		"elbow": 0.34, "carpus": 0.46, "knee": 0.30, "hock": 0.38, "toe": 0.14,
		"bob": 0.018, "roll": 0.014, "pitch": 0.014,
		"pelvis": 0.05, "chest": 0.03, "spine": 0.02, "neck": 0.09, "tail": 0.12,
	},
	# Quick, small, upright, and defined entirely by the head. head_bob carries it.
	"chicken": {
		"duty": 0.54, "stride": 0.80,
		"knee": 0.70, "hock": 0.60, "toe": 0.40,
		"bob": 0.022, "roll": 0.010, "pitch": 0.020,
		"pelvis": 0.06, "chest": 0.0, "spine": 0.0, "neck": 0.10, "head_bob": 0.16,
		"tail": 0.06,
	},
	# The waddle. Roll is an order of magnitude above everyone else's and the steps are tiny:
	# the body rocks over each foot rather than striding past it.
	"penguin": {
		"duty": 0.70, "stride": 0.55,
		"knee": 0.30, "hock": 0.26, "toe": 0.0,
		"bob": 0.018, "roll": 0.165, "pitch": 0.010,
		"pelvis": 0.05, "chest": 0.0, "spine": 0.0, "neck": 0.02, "head_bob": 0.03,
		"tail": 0.0,
	},
}

var _rig: Node = null
var _skeleton: Skeleton3D = null
var _legs: Array[Dictionary] = []
var _trunk := {}
var _p := {}
var _phase := 0.0
var _leg_length := 0.0 ## In skeleton space. Scaled to world in _stride(); see there.
var _last_origin := Vector3.ZERO
var _tracking := false
var _blend := 0.0 ## Eases the cycle in and out so stopping does not freeze mid-stride.
var _hinges := {} ## bone + world axis -> that axis in the bone's rest frame. See _hinge().


func _init(rig: Node, definition: AnimalDefinition) -> void:
	_rig = rig
	_skeleton = rig.skeleton
	if _skeleton == null or definition == null:
		return
	_p = DEFAULTS.duplicate()
	for key in SPECIES.get(definition.id, {}):
		_p[key] = SPECIES[definition.id][key]
	# animals.json wins over both, so a single animal can be tuned without touching code.
	var overrides: Dictionary = definition.gait
	for key in overrides:
		if _p.has(key):
			_p[key] = float(overrides[key])
	_resolve_legs(definition)
	_resolve_trunk()


## One entry per leg: the bone chain from the top down, plus where in the cycle it lands.
## The chain is read out of the skeleton rather than listed in data - every rig here runs
## thigh -> shin -> foot -> toe with a single child at each step, so following the hierarchy
## finds the real joints and stays correct if a model is re-exported with different names.
func _resolve_legs(definition: AnimalDefinition) -> void:
	var quadruped := definition.leg_bones.size() >= 4
	var table: Dictionary = QUADRUPED_PHASE if quadruped else BIPED_PHASE
	for bone_name in definition.leg_bones:
		var idx := _skeleton.find_bone(bone_name)
		if idx == -1:
			continue
		var front := bone_name.begins_with("front")
		var right := bone_name.ends_with(".R")
		var key := "%s_%s" % ["front" if front else "rear", "right" if right else "left"]
		if not table.has(key):
			continue
		var chain := _descend(idx)
		_legs.append({
			"upper": idx,
			"lower": chain[0] if chain.size() > 0 else -1,
			"foot": chain[1] if chain.size() > 1 else -1,
			"toe": chain[2] if chain.size() > 2 else -1,
			"contact": int(chain[chain.size() - 1]) if not chain.is_empty() else idx,
			"rest": _rest_offset(idx, chain),
			"front": front,
			"side": 1.0 if right else -1.0,
			"offset": float(table[key]),
			"length": _radius(idx, chain),
		})
	# Stride is set by the longest leg: a horse covering a dog's stride would mince, and a
	# dog covering a horse's would do the splits. Sizing it off the SHORTEST leg instead is
	# the tempting alternative - no limb then has to over-swing - but it was measurably worse
	# on five of the seven, because it shortens everyone's step to suit one limb and the
	# resulting high cadence costs more planting than the over-swing did. Where one animal's
	# legs are genuinely mismatched, its own stride number is the place to fix it.
	for leg in _legs:
		_leg_length = maxf(_leg_length, float(leg["length"]))


## Pelvis, chest, neck, head and tail, found by walking the hierarchy rather than by name.
## The rigs disagree about which numbered spine bone is which - the dog's tail is spine.003
## down to spine, the tiger's back runs to spine.012 - but they agree on the shape: the
## pelvis parents the rear legs, one chain off it reaches the skull and the other is tail.
func _resolve_trunk() -> void:
	var rear := -1
	for leg in _legs:
		if not bool(leg["front"]):
			rear = int(leg["upper"])
			break
	if rear == -1:
		return
	var shoulder := _skeleton.get_bone_parent(rear)
	var pelvis := _skeleton.get_bone_parent(shoulder) if shoulder != -1 else -1
	if pelvis == -1:
		return
	_trunk["pelvis"] = pelvis

	var front := -1
	for leg in _legs:
		if bool(leg["front"]):
			front = int(leg["upper"])
			break
	# The chest is whatever parents the forelegs; on a biped there is none, and the spine
	# above the pelvis stands in.
	var chest := -1
	if front != -1:
		var front_shoulder := _skeleton.get_bone_parent(front)
		chest = _skeleton.get_bone_parent(front_shoulder) if front_shoulder != -1 else -1
	var head := _find_head()
	for child in _skeleton.get_bone_children(pelvis):
		if child == shoulder or _is_leg_root(child):
			continue
		if head != -1 and _reaches(child, head):
			var back := _path_between(child, head)
			_trunk["back"] = back
			# Only the part of the back that is not holding a leg up may undulate. A spine
			# bone between the pelvis and the shoulders is an ancestor of the forelegs, so
			# bending it swings the whole limb from above - and because the wave runs at
			# twice the stride frequency, that swing is fast. Measured, it was moving a
			# dog's front feet at more than body speed throughout their stance: the legs
			# were planting correctly and the back was dragging them along anyway. The neck
			# carries the undulation instead, where it is visible and load-bearing on
			# nothing.
			var free: Array = []
			for bone in back:
				if not _carries_leg(int(bone)):
					free.append(bone)
			_trunk["flex"] = free
			if chest != -1:
				_trunk["chest"] = chest
		else:
			_trunk["tail"] = _descend(child, true)
	if head != -1:
		_trunk["head"] = head


func _find_head() -> int:
	for b in _skeleton.get_bone_count():
		var name := _skeleton.get_bone_name(b).to_lower()
		if name == "scull" or name == "skull" or name == "head":
			return b
	return -1


## Whether any leg hangs off this bone, directly or through the hierarchy. Rotating one of
## these moves a foot that may be standing on the ground.
func _carries_leg(idx: int) -> bool:
	for leg in _legs:
		if _reaches(idx, int(leg["upper"])):
			return true
	return false


func _is_leg_root(idx: int) -> bool:
	for leg in _legs:
		if _skeleton.get_bone_parent(int(leg["upper"])) == idx or int(leg["upper"]) == idx:
			return true
	return false


func _reaches(from: int, target: int) -> bool:
	var walk := target
	while walk != -1:
		if walk == from:
			return true
		walk = _skeleton.get_bone_parent(walk)
	return false


## Every bone from `from` down to `target`, target excluded - the neck, in practice.
func _path_between(from: int, target: int) -> Array:
	var reversed: Array = []
	var walk := _skeleton.get_bone_parent(target)
	while walk != -1 and walk != _skeleton.get_bone_parent(from):
		reversed.append(walk)
		walk = _skeleton.get_bone_parent(walk)
	reversed.reverse()
	return reversed


## Follow single-child descent. `keep_all` continues through forks for tails, which on some
## rigs pick up a stray child near the base.
func _descend(idx: int, keep_all := false) -> Array:
	var chain: Array = []
	var walk := idx
	while true:
		var children := _skeleton.get_bone_children(walk)
		if children.is_empty():
			break
		if children.size() > 1 and not keep_all:
			break
		walk = children[0]
		chain.append(walk)
	return chain


## The radius the foot actually swings on: hip joint to ground contact, straight line,
## taken from the rest pose.
##
## Not the sum of the segment lengths, which is what a fully extended leg would measure. No
## animal here stands with a straight leg - a dog's hock and a horse's stifle are folded even
## at rest - so summing segments overstates the radius, and a stride sized from it comes out
## too long. That overstatement is why the rear legs kept skating after the front ones had
## settled: the rear chains are the more folded of the two.
## How far the foot rests fore-or-aft of the joint that swings it, as a fraction of the
## leg's radius.
##
## A leg is not a pendulum hanging straight down. A dog's forefoot rests well ahead of its
## own shoulder joint, so the swing is not symmetric about the rest pose and the arc has to
## be inverted about where the foot actually IS. Ignoring this left every quadruped's front
## feet skating while the rear feet - which happen to rest much closer to under their hips -
## planted correctly, which is a confusing thing to look at and an easy thing to misread as
## a problem with the front legs themselves.
func _rest_offset(upper: int, chain: Array) -> float:
	if chain.is_empty():
		return 0.0
	var hip := _skeleton.get_bone_global_rest(upper).origin
	var foot := _skeleton.get_bone_global_rest(int(chain[chain.size() - 1])).origin
	var radius := hip.distance_to(foot)
	if radius <= 0.0001:
		return 0.0
	# Along the line of travel, which for these models is the skeleton's Z.
	return clampf((foot.z - hip.z) / radius, -0.9, 0.9)


func _radius(upper: int, chain: Array) -> float:
	if chain.is_empty():
		return 0.0
	var hip := _skeleton.get_bone_global_rest(upper).origin
	var foot := _skeleton.get_bone_global_rest(int(chain[chain.size() - 1])).origin
	return hip.distance_to(foot)


## Cycle position, 0-1, for the harness to bucket foot speed against.
func phase() -> float:
	return _phase


## Where each leg sits in the cycle relative to the shared phase.
func leg_offsets() -> Dictionary:
	var out := {}
	for leg in _legs:
		out["%s_%s" % ["front" if bool(leg["front"]) else "rear",
			"right" if float(leg["side"]) > 0.0 else "left"]] = float(leg["offset"])
	return out


## Geometry summary, for --gaittest. The stride and the swing angles are derived rather
## than authored, so when a foot slides the question is always which derived number is
## wrong, and this is the only way to see them.
func describe() -> String:
	var out := "stride %.3f (radius %.3f x %.2f x scale %.3f)" % [_stride(), _leg_length,
		float(_p["stride"]), _skeleton.global_transform.basis.get_scale().y]
	for leg in _legs:
		out += "
[gaittest]     %-12s radius %.3f span %.3f reach %.1f deg rest %.2f" % [
			"front" if bool(leg["front"]) else "rear", float(leg["length"]), _span(leg),
			rad_to_deg(asin(clampf(_span(leg) * 0.5, 0.0, 0.95))), float(leg["rest"])]
	return out


## Bone indices the gait treats as ground contacts, for the harness to measure. Exposed
## because a slide measurement has to watch the same point the gait plants, and the leg
## data in animals.json names a different bone - it stops at the ankle, above the toe.
func contact_bones() -> Dictionary:
	var out := {}
	for leg in _legs:
		out["%s_%s" % ["front" if bool(leg["front"]) else "rear",
			"right" if float(leg["side"]) > 0.0 else "left"]] = int(leg["contact"])
	return out


## Called every frame from CreatureRig._process. `origin` is the rig's own world position,
## which is what makes the stride ground-locked: the phase is a function of how far the
## animal has actually gone, so the foot on the floor tracks the floor.
func tick(delta: float, origin: Vector3, moving: bool, motion: float) -> void:
	if _skeleton == null or _legs.is_empty():
		return
	var target := 1.0 if moving else 0.0
	_blend = move_toward(_blend, target, delta * 3.0)
	if not _tracking:
		_last_origin = origin
		_tracking = true
	var travelled := Vector2(origin.x - _last_origin.x, origin.z - _last_origin.z).length()
	_last_origin = origin
	var strength := _blend * motion
	if moving:
		# Distance first, clock second. A creature walking on the spot still has to move its
		# legs, so a stationary walker falls back to a fixed cadence - but anything that is
		# actually travelling gets its phase from the ground it covered.
		#
		# Divided by the stride the legs are ACTUALLY covering, not the full-amplitude one.
		# Anything that shrinks the swing - easing in from standing, a stiff HARD animal -
		# shortens the step, and a short step has to come round more often or the foot cannot
		# keep up with the body and skates. Cadence rising as stride falls is also simply what
		# a real animal does when it moves stiffly.
		if travelled > 0.00001:
			_phase += travelled / maxf(_stride() * _amplitude(strength), MIN_STRIDE)
		else:
			_phase += delta * IN_PLACE_CADENCE
	_phase = fposmod(_phase, 1.0)
	if _blend <= 0.001:
		return
	for leg in _legs:
		_pose_leg(leg, strength)
	_pose_trunk(strength)


## Ground distance covered per cycle, in world units.
##
## The leg length is measured in skeleton space but the distance travelled is measured in
## the world, and the two are not the same number: every model is rescaled to a common
## stand height on import, and BIG or TALL rescales it again at runtime. Converting here
## rather than once at build time is what keeps a transformed creature's stride honest -
## a big dog takes big steps because its legs got longer, with nothing to tune.
func _stride() -> float:
	var scale: float = _skeleton.global_transform.basis.get_scale().y
	return maxf(_leg_length * scale * float(_p["stride"]), MIN_STRIDE)


## Ground covered during one stance, as a multiple of THIS leg's own length.
##
## Per leg, not per animal, because the front and rear legs are not the same length and both
## have to cover the same ground in the same time. Sharing one angle between them is what
## left the rear legs of every quadruped skating while the front ones planted: the short pair
## has to swing through a wider angle to keep up, and the ratio is exactly how much wider.
## The world scale cancels - both lengths carry it - so this is pure geometry.
func _span(leg: Dictionary) -> float:
	var length := maxf(float(leg["length"]), 0.0001)
	return float(_p["duty"]) * float(_p["stride"]) * (_leg_length / length)


## How much of the full stride the legs are covering at this strength, as a fraction.
##
## Not simply `strength`: the foot's reach along the ground goes as the sine of the swing
## angle, so half the angle is not half the step. Getting this wrong is invisible at rest and
## obvious the moment an animal starts walking - the legs ease in while the body is already
## at full speed, and it moonwalks out of the blend.
func _amplitude(strength: float) -> float:
	var full := asin(clampf(float(_p["duty"]) * float(_p["stride"]) * 0.5, 0.0, 0.95))
	if full <= 0.0001:
		return 1.0
	return maxf(sin(full * clampf(strength, 0.0, 1.0)) / sin(full), 0.05)


func _pose_leg(leg: Dictionary, strength: float) -> void:
	var t := fposmod(_phase + float(leg["offset"]), 1.0)
	var duty := float(_p["duty"])
	var front: bool = leg["front"]
	var span := _span(leg)
	var reach := asin(clampf(span * 0.5, 0.0, 0.95)) * strength
	# The ground the foot covers at this reduced reach, which is what the stance profile
	# below has to invert. Recomputed from the angle rather than scaled from `span`, for the
	# same reason _amplitude() exists: the relationship is a sine, not a ratio.
	span = 2.0 * sin(reach)
	# Where this foot sits at rest, and therefore what the swing is symmetric about.
	var rest_ratio := float(leg["rest"])
	var rest_angle := asin(rest_ratio)

	var swing := 0.0 ## Upper-leg angle: + forward, - back.
	var flex := 0.0  ## 0 at touchdown, 1 at peak swing flexion.
	var lift := 0.0  ## Distal flex, peaking later than the knee.
	if t < duty:
		# Stance. The foot is down and the body travels over it, so what has to be constant is
		# the foot's speed ALONG THE GROUND - not the joint's angular speed. A leg is a radius,
		# and a radius turning at a constant rate sweeps its tip fastest at the bottom of the
		# arc and slowest at the ends. Turning the angle linearly therefore still skates,
		# just less obviously: fast under the body, dragging at both ends of the step.
		#
		# Inverting the arc fixes it exactly. The foot's horizontal offset from the hip is
		# L*sin(angle), so asking that offset to move linearly gives the angle directly, and
		# the foot then tracks the ground at a genuinely constant rate.
		var s := t / maxf(duty, 0.001)
		# Offset by the rest pose, then subtracted again: the rotation applied to the bone is
		# relative to rest, but the arc being inverted is absolute.
		swing = asin(clampf(rest_ratio + (0.5 - s) * span, -0.95, 0.95)) - rest_angle
		# A little yield as weight comes onto the limb: without it the leg reads as a prop
		# rather than something carrying an animal. Kept small on purpose - bending the knee
		# during stance moves the foot that is supposed to be standing still, so every
		# degree of it is bought with a degree of slide. See STANCE_YIELD.
		flex = sin(s * PI) * STANCE_YIELD
	else:
		# Swing. Eased at both ends so the foot settles onto the floor instead of arriving at
		# stance speed, which is the other half of not looking like skating.
		var s := (t - duty) / maxf(1.0 - duty, 0.001)
		swing = lerpf(-reach, reach, s - sin(s * TAU) / TAU)
		# Peaks early: the limb folds up right after it leaves the ground, then opens out to
		# reach for the next contact.
		flex = sin(clampf(s, 0.0, 1.0) * PI) * (0.35 + 0.65 * (1.0 - s))
		lift = sin(clampf(s * 1.15, 0.0, 1.0) * PI)

	_rotate(int(leg["upper"]), swing)
	# Elbow and stifle fold in opposite directions - a foreleg's elbow points back, a hind
	# leg's stifle points forward. Using one sign for both is what makes procedural
	# quadrupeds look like they have four identical legs on backwards.
	var joint := float(_p["elbow"] if front else _p["knee"]) * strength
	_rotate(int(leg["lower"]), (-flex if front else flex) * joint)
	# The carpus. Flexes hard as the paw leaves the ground, then extends to plant flat -
	# this is the joint that was doing nothing, and the reason the forelegs looked like rods.
	var distal := float(_p["carpus"] if front else _p["hock"]) * strength
	_rotate(int(leg["foot"]), (lift * 0.75 + flex * 0.25) * distal * (1.0 if front else -1.0))
	# Toe rolls the other way to keep the sole flat as the ankle flexes over it.
	_rotate(int(leg["toe"]), -lift * float(_p["toe"]) * strength * (1.0 if front else -1.0))


## The body above the legs. Everything here is at a multiple of the leg cycle, so it stays
## locked to the footfalls rather than drifting against them.
func _pose_trunk(strength: float) -> void:
	var body: Node3D = _rig.body
	if body == null:
		return
	var cycle := _phase * TAU
	# Twice per cycle: the body rises over each supporting pair and drops between them.
	var bob := sin(cycle * 2.0) * float(_p["bob"]) * strength
	# Once per cycle, and a quarter turn out of step with the footfalls, so the animal leans
	# onto the foot that is carrying it rather than away from it.
	var roll := sin(cycle - PI * 0.5) * float(_p["roll"]) * strength
	var pitch := sin(cycle * 2.0 + PI * 0.5) * float(_p["pitch"]) * strength
	_rig.gait_body_offset = Vector3(0.0, bob, 0.0)
	_rig.gait_body_roll = roll
	_rig.gait_body_pitch = pitch

	# Pelvis and chest counter-rotate: the hips lead, the shoulders answer. On a cat or a
	# tiger this is most of what reads as a flexible spine.
	if _trunk.has("pelvis"):
		var pelvis := int(_trunk["pelvis"])
		_rotate_axis(pelvis, _hinge(pelvis, Vector3.UP),
			sin(cycle) * float(_p["pelvis"]) * strength)
	if _trunk.has("chest"):
		var chest := int(_trunk["chest"])
		_rotate_axis(chest, _hinge(chest, Vector3.UP),
			-sin(cycle) * float(_p["chest"]) * strength)
	var flex: Array = _trunk.get("flex", [])
	for i in flex.size():
		# A travelling wave, not a single hinge: each bone lags the one behind it, so the
		# undulation runs up the spine the way a walking cat's does.
		var wave := sin(cycle * 2.0 - float(i) * 0.55)
		_rotate(int(flex[i]), wave * float(_p["spine"]) * strength)

	_pose_head(cycle, strength)

	var tail: Array = _trunk.get("tail", [])
	for i in tail.size():
		var wave := sin(cycle - float(i) * 0.7)
		var bone := int(tail[i])
		_rotate_axis(bone, _hinge(bone, Vector3.UP), wave * float(_p["tail"]) * strength)


## The head, and the chicken.
##
## A real head-bob is not an oscillation. The bird thrusts its head forward, then holds it
## still in space while the body walks underneath it, then thrusts again - so the profile is
## a fast rise and a long hold, and that shape is the whole effect. A sine wave here reads as
## a head waving back and forth, which is the thing the brief specifically rules out.
func _pose_head(cycle: float, strength: float) -> void:
	if not _trunk.has("head"):
		return
	var head := int(_trunk["head"])
	var neck := sin(cycle * 2.0) * float(_p["neck"]) * strength
	var thrust := float(_p["head_bob"])
	if thrust > 0.0:
		# Two bobs per cycle, one per step. `hold` is 1 while the head waits for the body and
		# runs to 0 across the thrust; the head angle follows it, so the head stays put in
		# world space for most of the step and catches up quickly.
		var beat := fposmod(_phase * 2.0, 1.0)
		var hold := 1.0 - smoothstep(0.0, 0.28, beat)
		_rotate(head, (hold - 0.5) * thrust * 2.0 * strength)
		# The neck leans the opposite way, so the hold happens in space rather than the whole
		# bird nodding.
		var back: Array = _trunk.get("back", [])
		if not back.is_empty():
			_rotate(int(back[back.size() - 1]), -(hold - 0.5) * thrust * strength)
		return
	_rotate(head, -neck)
	var back: Array = _trunk.get("back", [])
	if not back.is_empty():
		_rotate(int(back[back.size() - 1]), neck)


## Flexion: fore-and-aft, about the animal's own left-right axis.
##
## NOT about the bone's local X, which is the obvious thing to write and is wrong. These
## bones are oriented along the limb, and a limb that splays or angles even slightly carries
## its local X away from true left-right - so hinging on it swings the foot partly sideways.
## That sideways component is invisible in a still frame and shows up in the numbers as a
## foot that never quite stops: --gaittest measured a dog's front foot still travelling at
## 60% of body speed through the middle of its own stance, because more than half its swing
## was going across the line of travel rather than along it.
##
## Resolving the axis per bone costs one inverse at build time and makes the left and right
## sides agree for free: both derive from the same skeleton-space direction, so mirrored
## bones hinge the same way round without a hand-written sign for each side.
func _rotate(idx: int, angle: float) -> void:
	# Optional joints are -1 for species that do not have that part. Guard before asking
	# _hinge() for the bone's rest transform; _rotate_axis()'s later guard is too late.
	if idx < 0 or is_zero_approx(angle):
		return
	_rotate_axis(idx, _hinge(idx, Vector3.RIGHT), angle)


## A skeleton-space direction expressed in one bone's rest frame, cached. Rotations are
## applied as rest * Quaternion(axis, angle), which turns the bone about its OWN axes, so
## anything that should be world-aligned has to be converted into that frame first.
func _hinge(idx: int, world_axis: Vector3) -> Vector3:
	var key := "%d:%.0f%.0f%.0f" % [idx, world_axis.x, world_axis.y, world_axis.z]
	if _hinges.has(key):
		return _hinges[key]
	var basis := _skeleton.get_bone_global_rest(idx).basis.orthonormalized()
	var local := (basis.inverse() * world_axis).normalized()
	if local.length_squared() < 0.5:
		local = world_axis ## Degenerate rest basis; the raw axis is the best guess left.
	_hinges[key] = local
	return local


func _rotate_axis(idx: int, axis: Vector3, angle: float) -> void:
	if idx < 0 or is_zero_approx(angle):
		return
	var rest := _skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()
	_skeleton.set_bone_pose_rotation(idx, rest * Quaternion(axis, angle))
	_rig.mark_posed(idx)
