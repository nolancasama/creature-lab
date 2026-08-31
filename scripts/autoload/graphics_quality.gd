extends Node
## One policy for every graphics-quality decision. Scenes ask this service for the
## current values instead of carrying their own web/desktop branches.

signal changed

const PERFORMANCE := "performance"
const STANDARD := "standard"
const HIGH := "high"

var profile := STANDARD


func _ready() -> void:
	_apply_runtime()


func set_profile(value: String) -> void:
	var next := value if is_valid_profile(value) else STANDARD
	if profile == next:
		_apply_runtime()
		return
	profile = next
	_apply_runtime()
	changed.emit()


func is_valid_profile(value: String) -> bool:
	return value == PERFORMANCE or value == STANDARD or value == HIGH


func render_scale() -> float:
	match profile:
		PERFORMANCE:
			return 0.625
		HIGH:
			return 1.0
		_:
			return 0.75


func shadows_enabled() -> bool:
	return profile == HIGH


func msaa_3d() -> Viewport.MSAA:
	return Viewport.MSAA_2X if profile == HIGH else Viewport.MSAA_DISABLED


## Screen-space glow remains part of every preset. Compatibility uses its lower-cost glow
## implementation, and disabling it without Chromebook measurements would remove a major
## part of the platform and transformation look on a guess.
func glow_enabled() -> bool:
	return true


func glow_intensity() -> float:
	return 0.5


## Transformation effects are intentionally excluded. Only sustained zoo residents are
## reduced, and a selected resident immediately returns to full strength.
func zoo_effect_ratio(focused := false) -> float:
	if focused or profile == HIGH:
		return 1.0
	return 0.35 if profile == PERFORMANCE else 0.65


## The local steering already runs only while a resident is moving. This is the slower,
## yard-wide safety pass that resolves the rare overlap left after steering.
func zoo_overlap_interval() -> float:
	match profile:
		PERFORMANCE:
			return 0.12
		HIGH:
			return 0.05
		_:
			return 0.10


func profile_label() -> String:
	match profile:
		PERFORMANCE:
			return "Performance / 軽い"
		HIGH:
			return "High / 高画質"
		_:
			return "Standard / 標準"


func msaa_label() -> String:
	return "2x" if msaa_3d() == Viewport.MSAA_2X else "off"


func effect_quality_label() -> String:
	return "full" if profile == HIGH else ("reduced distant" if profile == PERFORMANCE else "moderate distant")


func _apply_runtime() -> void:
	if not is_inside_tree():
		return
	var root := get_tree().root
	root.scaling_3d_scale = render_scale()
	root.msaa_3d = msaa_3d()
	_apply_existing_stage_nodes(root)


## Settings normally replaces the current scene, but this also makes programmatic/debug
## profile switches genuinely live for any 3D scene that is already present.
func _apply_existing_stage_nodes(root: Node) -> void:
	for node in root.find_children("*", "DirectionalLight3D", true, false):
		if node.has_meta("graphics_key_light"):
			(node as DirectionalLight3D).shadow_enabled = shadows_enabled()
	for node in root.find_children("*", "WorldEnvironment", true, false):
		if not node.has_meta("graphics_environment"):
			continue
		var environment := (node as WorldEnvironment).environment
		if environment != null:
			environment.glow_enabled = glow_enabled()
			environment.glow_intensity = glow_intensity()
