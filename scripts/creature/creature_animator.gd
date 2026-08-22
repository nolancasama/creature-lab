class_name CreatureAnimator
extends RefCounted
## Plays the authored walk and idle clips, ground-locked to how far the animal travels.
##
## The models came from a pack that ships real animation for these exact skeletons; the GLB
## in this project was exported without it. --extractanims lifted the clips out into
## res://animations, and this drives them.
##
## WHY IT IS NOT JUST play("walk"):
##
## An authored cycle has a stride baked into it - one loop of the dog's walk carries it some
## fixed distance. The zoo moves creatures at their own walk_speed, which has nothing to do
## with that. Play the clip at its authored rate and the feet skate exactly as badly as a
## hand-written gait with the wrong numbers; the difference is only that it is harder to
## see why. So the clip's stride is measured once per species, and playback speed is set
## from the speed the body is actually travelling.
##
## WHAT STILL BELONGS TO THE OLD SYSTEM:
##
## The clips write rotations. The trait system writes bone POSITIONS - that is how LONG and
## TALL stretch an animal - and the two do not collide, which is why a walking dog can still
## be long. Position tracks that DID land on trait-owned bones were dropped at extraction.
##
## Root motion is dropped for the same reason in reverse: the brain moves the creature
## through the yard, so a clip that also translates the root would fight it and double the
## speed. The cycle plays on the spot and the node does the travelling.

const CLIP_DIR := "res://animations"
## Game animal id -> the name the source pack gave it. Two disagree: the cat is "Kitty" and
## the penguin is "Pinguin".
const SPECIES := {
	"dog": "Dog", "cat": "Kitty", "tiger": "Tiger", "horse": "Horse",
	"deer": "Deer", "penguin": "Pinguin", "chicken": "Chicken",
}
const LIBRARY := "creature"
## Below this the animal is standing, not walking, whatever `moving` claims - a creature
## easing to a halt should settle into idle rather than crawl through its walk cycle.
const MIN_TRAVEL_SPEED := 0.05
const SPEED_RANGE := Vector2(0.35, 3.0) ## Playback limits; past these it reads as comedy.
const BLEND := 0.25
## How much further a run reaches per stride than a walk. Not measured like the walk stride
## is - a run clip's feet leave the ground entirely, so the excursion trick that measures a
## walk does not describe it - so this is a plain multiplier, tuned to keep a running animal
## from moonwalking.
const RUN_STRIDE := 1.9

## Built once per species and shared: the clips are read-only once loaded, and every dog in
## the zoo can play the same resource.
static var _libraries := {}
static var _strides := {}
## animal id -> how far the walk clip's root moved per loop, in the clip's own units.
static var _root_travel := {}

var _rig: Node = null
var _player: AnimationPlayer = null
var _names := {} ## "idle" / "walk" -> clip name inside the library.
var _stride := 0.0 ## World units covered by one loop of the walk.
var _last_origin := Vector3.ZERO
var _tracking := false
var _playing := ""


func _init(rig: Node, definition: AnimalDefinition) -> void:
	if rig == null or definition == null or rig.skeleton == null:
		return
	var library := _library_for(definition.id)
	if library == null:
		return ## No clips for this animal; CreatureRig falls back to the procedural gait.
	_rig = rig
	var host: Node = rig.skeleton.get_parent()
	_player = AnimationPlayer.new()
	_player.name = "ClipPlayer"
	# Tracks are stored as "Skeleton3D:<bone>", so the player has to sit beside the skeleton
	# and treat that shared parent as its root.
	_player.root_node = NodePath("..")
	# Earlier than the rig, so everything the rig poses afterwards - a trait, a shiver, the
	# selection reaction - lands on top of the clip instead of underneath it.
	_player.process_priority = -10
	host.add_child(_player)
	_player.add_animation_library(LIBRARY, library)
	for motion in ["idle", "walk", "run"]:
		var full := "%s/%s" % [LIBRARY, _clip_name(definition.id, motion)]
		if _player.has_animation(full):
			_names[motion] = full
	_stride = _measure_stride(definition)


## Stride and playback, for --gaittest. The clip's measured stride is what decides whether
## the feet skate, and it is invisible from outside.
func describe() -> String:
	var length := 0.0
	if _names.has("walk"):
		length = _player.get_animation(_names["walk"]).length
	return "stride=%.3f walk_len=%.2fs natural_speed=%.2f/s" % [
		_stride, length, _stride / maxf(length, 0.001)]


## How fast this animal travels when its walk plays at the rate it was authored at.
##
## The clips turned out to be considerably more sedate than the walk_speed numbers this game
## had been using - about 0.4 to 0.6 units per second against 0.9 to 1.8. Something has to
## give, and it is the speed rather than the animation: play a cycle at three times its
## authored rate and it both skates and looks frantic, while walking an animal at the pace
## its own animation implies looks right and locks the feet for free. A zoo that ambles is
## also what the behaviour brief asked for.
func natural_speed() -> float:
	if not _names.has("walk") or _player == null:
		return 0.0
	var clip := _player.get_animation(_names["walk"])
	return _stride / maxf(clip.length, 0.001)


func active() -> bool:
	return _player != null and _names.has("walk")


## Called every frame by CreatureRig, in place of the procedural gait.
func tick(_delta: float, origin: Vector3, motion: String) -> void:
	if _player == null:
		return
	var travelled := 0.0
	if _tracking:
		travelled = Vector2(origin.x - _last_origin.x, origin.z - _last_origin.z).length()
	_last_origin = origin
	_tracking = true

	var frame_time := maxf(_delta, 0.0001)
	var speed := travelled / frame_time
	var wanted_motion := motion
	if not _names.has(wanted_motion):
		# Fall back down the chain rather than freezing: a species with no run clip should
		# run using its walk, played faster, not stand still while it travels.
		wanted_motion = "walk" if _names.has("walk") else ("idle" if _names.has("idle") else "")
	if wanted_motion.is_empty():
		return
	motion = wanted_motion

	if motion != "idle":
		# The clip's own pace is stride-per-length. Ask it to cover the ground the body is
		# actually covering and the planted foot stays planted.
		var clip := _player.get_animation(_names[motion])
		# A run clip covers more ground per loop than a walk. Scaling the measured walk
		# stride by the ratio of their lengths is a rough stand-in, and close enough that
		# the feet stay under the animal at both speeds.
		var reference: float = _stride
		if motion == "run" and _names.has("walk"):
			var walk_clip := _player.get_animation(_names["walk"])
			reference = _stride * (clip.length / maxf(walk_clip.length, 0.001)) * RUN_STRIDE
		var natural: float = reference / maxf(clip.length, 0.001)
		var wanted: float = speed / maxf(natural, 0.0001) if natural > 0.0 else 1.0
		# A creature "moving" on the spot - the lab platform - still has to walk, so an
		# unmeasurable speed falls back to the clip's authored rate.
		if speed < MIN_TRAVEL_SPEED:
			wanted = 1.0
		_player.speed_scale = clampf(wanted, SPEED_RANGE.x, SPEED_RANGE.y)
	else:
		_player.speed_scale = 1.0

	if _playing != motion:
		_playing = motion
		_player.play(_names[motion], BLEND)


func stop() -> void:
	if _player != null:
		_player.stop()
	_playing = ""


## How far one loop of the walk carries the animal, in world units.
##
## Measured, not authored: the clip does not say, and the number decides whether the feet
## skate. Seeks through the cycle sampling a foot bone, and takes how far it swings along
## the line of travel - a foot's excursion across one loop IS the stride, because it lands,
## stays put while the body passes over it, and lifts to do it again.
func _measure_stride(definition: AnimalDefinition) -> float:
	# The root's own travel, where the clip has it - the authored stride, straight from the
	# source. Only fall back to watching the feet when a clip carries no root motion.
	if _root_travel.has(definition.id) and float(_root_travel[definition.id]) > 0.0001:
		return float(_root_travel[definition.id]) * _world_scale()
	if _strides.has(definition.id):
		return float(_strides[definition.id])
	if not _names.has("walk") or definition.legs.is_empty():
		return 0.0
	var bones: PackedStringArray = definition.legs[0].get("bones", PackedStringArray())
	if bones.is_empty():
		return 0.0
	var skeleton: Skeleton3D = _rig.skeleton
	var foot := skeleton.find_bone(bones[bones.size() - 1])
	if foot == -1:
		return 0.0
	var clip := _player.get_animation(_names["walk"])
	var lowest := INF
	var highest := -INF
	var samples := 32
	_player.play(_names["walk"])
	for i in samples:
		_player.seek(clip.length * float(i) / float(samples), true)
		# Seeking writes the bone POSES; it does not recompute the global transforms derived
		# from them. Without this the sampler reads the same stale pose 32 times, measures a
		# stride of zero, and the clip is then played as fast as the clamp allows - which
		# looks exactly like the skating this measurement exists to prevent.
		skeleton.force_update_all_bone_transforms()
		# World space, not skeleton space. The models are rescaled to a common stand height
		# on import and the trait system rescales them again, so a stride measured in the
		# skeleton's own units is not the distance the animal covers on the grass.
		var point: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(foot).origin
		var z: float = point.z
		lowest = minf(lowest, z)
		highest = maxf(highest, z)
	_player.stop()
	_playing = ""
	var span := maxf(highest - lowest, 0.0)
	_strides[definition.id] = span
	return span


func _world_scale() -> float:
	if _rig == null or _rig.skeleton == null:
		return 1.0
	return maxf(_rig.skeleton.global_transform.basis.get_scale().y, 0.001)


static func _clip_name(animal_id: String, motion: String) -> String:
	var species := str(SPECIES.get(animal_id, ""))
	if species.is_empty():
		return ""
	# The chicken's clips are numbered 001/002/003 rather than all 001, so the file is found
	# by its ending rather than by an assumed number.
	for file in _clip_files():
		if file.begins_with(species + "_") and file.ends_with("_%s.res" % motion):
			return file.get_basename()
	return ""


static func _clip_files() -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(CLIP_DIR)
	if dir == null:
		return found
	for file in dir.get_files():
		# Exported projects rename resources to .remap; the real name is underneath.
		found.append(file.trim_suffix(".remap"))
	return found


static func _library_for(animal_id: String) -> AnimationLibrary:
	if _libraries.has(animal_id):
		return _libraries[animal_id]
	var library := AnimationLibrary.new()
	var any := false
	for motion in ["idle", "walk", "run"]:
		var clip_name := _clip_name(animal_id, motion)
		if clip_name.is_empty():
			continue
		var path := "%s/%s.res" % [CLIP_DIR, clip_name]
		if not ResourceLoader.exists(path):
			continue
		var clip: Animation = load(path)
		if clip == null:
			continue
		clip = clip.duplicate(true)
		var travel := _strip_root_motion(clip)
		if motion == "walk":
			_root_travel[animal_id] = travel
		library.add_animation(clip_name, clip)
		any = true
	if not any:
		return null
	_libraries[animal_id] = library
	return library


## Remove translation of the root bone, and return how far it travelled first.
##
## The brain walks the creature across the yard by moving its node, so a clip that ALSO slid
## its root would add its travel to that and the animal would outrun its own feet. But that
## root track is also the only honest record of the stride: in the source clip the feet stay
## planted while the root carries the body forward over them, so how far the root moves in
## one loop IS how far one loop should carry the animal.
##
## Measuring it here, before removing it, is the difference between a locked foot and a
## skating one. Measuring the FEET instead - the obvious thing, and what this did first -
## reads only whatever excursion is left after the root has been taken away, which came out
## about three times too small on every animal and had the clips playing at triple speed to
## compensate.
static func _strip_root_motion(clip: Animation) -> float:
	var travel := 0.0
	for track in range(clip.get_track_count() - 1, -1, -1):
		if str(clip.track_get_path(track)).get_slice(":", 1) != "Root":
			continue
		if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			# The root's ORIENTATION belongs to the game, not to the clip. Every screen here
			# decides which way an animal faces - the picker turns it to profile, the zoo
			# turns it toward wherever it is walking - and a clip that also yaws the root
			# fights all of them. It was turning the picker's dog to face left.
			clip.remove_track(track)
			continue
		if clip.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var lowest := Vector3(INF, INF, INF)
		var highest := Vector3(-INF, -INF, -INF)
		for key in clip.track_get_key_count(track):
			var value: Vector3 = clip.track_get_key_value(track, key)
			lowest = lowest.min(value)
			highest = highest.max(value)
		var span := highest - lowest
		# Whichever horizontal axis the animator built the cycle along.
		travel = maxf(absf(span.x), absf(span.z))
		clip.remove_track(track)
	return travel
