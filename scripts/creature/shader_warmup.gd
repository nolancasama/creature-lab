class_name ShaderWarmup
extends Node
## Draws one of every particle and material variant the traits use, once, into a tiny
## offscreen viewport - so the graphics driver compiles them here instead of in the
## middle of a lesson.
##
## Why this is needed at all: the web export runs the Compatibility (WebGL) renderer,
## not Forward+ - Vulkan is desktop-only. Under Compatibility the FIRST draw of a
## material variant blocks the main thread while the driver compiles it, and the cost
## is enormous. Measured against a cleared driver shader cache:
##
##     first HOT pick    9819 ms        second HOT pick    33 ms
##     first COLD pick   3224 ms        second COLD pick   41 ms
##     LENGTH / STRENGTH   17 ms
##
## HOT and COLD are far worse than the other adjectives because they introduce by far
## the most new variants at once: turbulence, alpha-blended billboards, proximity fade,
## scale curves, colour ramps, emissive billboards and an extra omni light. That is why
## only those two ever felt like they took seconds to start.
##
## The work is spread one item per frame rather than done in a single burst. The total
## compile cost is the same, but the title screen appears immediately and the stalls are
## small and staggered while the student is still reading it, instead of one long freeze.

## Emitted once every variant has been drawn and the driver has had its settling frames.
## The loading screen waits on this rather than on a timer: the compile cost is whatever
## the machine's driver makes it, and a classroom's Chromebooks do not agree on that.
signal finished()

## Warmed in this order; each entry is drawn on its own frame.
const KINDS := [
	"flame", "embers", "snow", "cold_mist", "breath", "frost_cling",
	"sparkle", "dust", "glow", "motion",
]

## Fx.spread_along swaps a preset's emission shape from sphere to box, and that is a
## SEPARATE program to compile - warming only the sphere form of these left COLD still
## stalling for 3.2s, because ColdEffect spreads its snow and mist over a volume.
const BOXED_KINDS := ["flame", "snow", "cold_mist"]

var _viewport: SubViewport = null
var _queue: Array = []
var _idle_frames := 0


## Call once, as early as there is a tree to attach to. Does nothing when there is no
## renderer (headless selftests) since there is nothing to compile.
##
## Returns the running instance so a caller can wait on `finished`, or null when there was
## nothing to warm - a caller waiting on that must treat null as "already done".
static func run(host: Node) -> ShaderWarmup:
	if host == null or not host.is_inside_tree():
		return null
	if DisplayServer.get_name() == "headless":
		return null
	var warmup := ShaderWarmup.new()
	host.add_child(warmup)
	return warmup


func _ready() -> void:
	name = "ShaderWarmup"
	_viewport = SubViewport.new()
	# Small, but not 1x1: a degenerate target can get culled before anything is drawn.
	_viewport.size = Vector2i(64, 64)
	# Its own world, so none of this can leak into whatever scene is on screen.
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var camera := Camera3D.new()
	camera.position = Vector3(0, 0.4, 2.4)
	camera.current = true
	_viewport.add_child(camera)

	# Both light types, so lit variants are compiled too - HOT adds an omni light at the
	# moment it is picked, which would otherwise be its own stall.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, -30, 0)
	_viewport.add_child(key)
	var omni := OmniLight3D.new()
	omni.omni_range = 6.0
	omni.position = Vector3(0, 0.5, 0.6)
	_viewport.add_child(omni)

	for kind in KINDS:
		_queue.append(kind)
	for kind in BOXED_KINDS:
		_queue.append("box:%s" % kind)
	_queue.append("_frost_patch")


func _process(_delta: float) -> void:
	if not _queue.is_empty():
		_warm(_queue.pop_front())
		return
	# Give the driver a few more drawn frames to finish before tearing the viewport down.
	_idle_frames += 1
	if _idle_frames > 3:
		# Emitted before the free so a listener still has a live object to hear it from.
		finished.emit()
		queue_free()


func _warm(item: String) -> void:
	var node: Node3D = null
	if item == "_frost_patch":
		node = Fx.frost_patch(0.35, Color(0.86, 0.95, 1.0, 0.55))
	elif item.begins_with("box:"):
		var boxed := Fx.make(item.substr(4), Color.WHITE, 0.3)
		Fx.spread_along(boxed, Vector3(0.12, 0.06, 0.12))
		node = boxed
	else:
		node = Fx.make(item, Color.WHITE, 0.3)
	if node == null:
		return
	_viewport.add_child(node)
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = true
