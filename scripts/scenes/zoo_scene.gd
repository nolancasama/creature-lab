extends Node3D

const AGAIN_SIZE := Vector2(180, 52)
## Centred on the gear's band so the two top controls read as one row across the screen.
const AGAIN_TOP := UiKit.GEAR_INSET_TOP + (UiKit.GEAR_SIZE - 52) / 2
const INFO_CLOSE_SIZE := 52.0
const INFO_NAME_GAP := 16.0
const INFO_MIN_HEAD_WIDTH := 220.0
const INFO_PANEL_MARGIN := 28.0
const INFO_VIEWPORT_MARGIN := 48.0
## The reward. Every creature here gets a quiet close-up when selected.

## Half-extents of the yard, X by Z. A rectangle rather than a disc: a zoo enclosure is a
## fenced field, and a round one with no corners read as an arena.
## Half-extents, so the yard is twice these across. Doubled in AREA from 13x9: each side
## carries a factor of root two, which is what doubling an area costs. Doubling each side
## instead would have quadrupled it, and seven animals in four times the grass reads as an
## empty field rather than a bigger zoo.
const YARD := Vector2(18.4, 12.7)
const FENCE_MARGIN := 1.0 ## How far the fence stands outside the grass.
const POST_SPACING := 1.7
const RAIL_HEIGHTS := [0.42, 0.82]
const ORBIT_SPEED := 0.006
const ZOOM_LIMITS := Vector2(9.0, 26.0)
const FOCUS_DISTANCE := 8.0
const YARD_CAMERA_TARGET := Vector3(0.0, 1.2, 0.0)
const TITLE_COLOR := Color("#17324d") ## Deep enough to stay legible against the pale sky.
const PINCH_ZOOM_SCALE := 0.018

var _camera: Camera3D = null
var _yaw := 0.4
var _pitch := 0.42
var _distance := 34.0 ## Far enough back that the whole rectangle is in frame at rest.
var _camera_target := YARD_CAMERA_TARGET
var _dragging := false
var _info: PanelContainer = null
var _info_body: VBoxContainer = null
var _hint: Label = null
var _creatures: Node3D = null
var _focused_brain: CreatureBrain = null
var _distance_before_focus := 34.0
var _touch_points := {}
var _pinching := false
var _pinch_distance := 0.0
var _overlap_clock := 0.0


func _ready() -> void:
	# Creature brains use the default priority. Run the yard-wide collision pass after all
	# of them have advanced for this physics frame.
	process_physics_priority = 100
	# Clicking a creature relies on Area3D picking, which the viewport does not do by
	# default.
	get_viewport().physics_object_picking = true
	_build_stage()
	_build_ui()
	_populate()
	Game.zoo_changed.connect(_populate)
	Audio.play_ambience(true)


func _physics_process(delta: float) -> void:
	if _creatures == null:
		return
	_overlap_clock += delta
	if _overlap_clock < GraphicsQuality.zoo_overlap_interval():
		return
	_overlap_clock = 0.0
	CreatureBrain.resolve_group_overlaps(_creatures, 8)


func _build_stage() -> void:
	add_child(StageKit.environment(Color("#2c5a92"), Color("#8fc2d8"), 0.9))
	add_child(StageKit.key_light(Vector3(-45, -40, 0), 1.2))
	_build_grass()
	_build_fence()

	_creatures = Node3D.new()
	_creatures.name = "Creatures"
	add_child(_creatures)

	_camera = StageKit.camera(Vector3(0, 11, 24), Vector3.ZERO, 55.0)
	add_child(_camera)
	_update_camera()


## A rectangular field rather than StageKit's disc, which is built for the lab platform.
func _build_grass() -> void:
	var grass := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(YARD.x * 2.0 + FENCE_MARGIN * 2.4, 0.2, YARD.y * 2.0 + FENCE_MARGIN * 2.4)
	grass.mesh = mesh
	grass.position.y = -0.1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#4b7a45")
	mat.roughness = 0.95
	grass.material_override = mat
	add_child(grass)


## Posts with rails between them. Posts alone read as a row of sticks in a field; it is the
## horizontals that make it a fence.
func _build_fence() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#8a6a44")
	wood.roughness = 0.85
	var x: float = YARD.x + FENCE_MARGIN
	var z: float = YARD.y + FENCE_MARGIN
	var corners := [Vector3(-x, 0, -z), Vector3(x, 0, -z), Vector3(x, 0, z), Vector3(-x, 0, z)]
	for i in corners.size():
		var from: Vector3 = corners[i]
		var to: Vector3 = corners[(i + 1) % corners.size()]
		_fence_run(from, to, wood)


func _fence_run(from: Vector3, to: Vector3, wood: StandardMaterial3D) -> void:
	var span := to - from
	var length := span.length()
	var count := maxi(int(round(length / POST_SPACING)), 1)
	# The last post of one run is the first of the next, so runs stop one short of their
	# end and the corners are not built twice.
	for i in count:
		var post := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.09
		mesh.bottom_radius = 0.11
		mesh.height = 1.1
		post.mesh = mesh
		post.position = from + span * (float(i) / float(count))
		post.position.y = 0.55
		post.material_override = wood
		add_child(post)

	for height in RAIL_HEIGHTS:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(length, 0.09, 0.05)
		rail.mesh = rail_mesh
		rail.position = (from + to) * 0.5
		rail.position.y = float(height)
		rail.rotation.y = atan2(-span.z, span.x)
		rail.material_override = wood
		add_child(rail)


func _build_ui() -> void:
	var layer := StageKit.ui_layer()
	add_child(layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# No bar across the top. It was a strip of chrome carrying a count, a line of controls
	# and an instruction, sitting over the one thing the screen is for - the zoo itself.
	# The name and one button do the same work without covering the yard.
	var title := UiKit.label("Matsubara Zoo", UiKit.H1, TITLE_COLOR)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 26
	title.offset_bottom = 26 + UiKit.H1 + 8
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	_hint = UiKit.label("どうぶつをタップすると名前が見られます", UiKit.SMALL, TITLE_COLOR)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hint.offset_top = 84
	_hint.offset_bottom = 112
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_hint)

	# Top-left, opposite the gear. Both used to sit in the right corner, which put the one
	# control a student presses next to the one only a teacher should touch.
	var again := UiKit.button("もう一度つくる", UiKit.BODY, true)
	UiKit.style_primary(again)
	again.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	again.custom_minimum_size = AGAIN_SIZE
	again.offset_left = UiKit.GEAR_INSET_RIGHT ## Inset to match the gear's, mirrored.
	again.offset_right = UiKit.GEAR_INSET_RIGHT + AGAIN_SIZE.x
	again.offset_top = AGAIN_TOP
	again.offset_bottom = AGAIN_TOP + AGAIN_SIZE.y
	again.pressed.connect(func() -> void:
		Audio.play("select")
		Game.set_phase(Game.Phase.ANIMAL_SELECTION))
	root.add_child(again)

	# The shared size and corner, so the gear is in the same place on every screen that has
	# one. It was previously sized to the button beside it, which made it a different
	# control in a different position from the picker's.
	var gear := UiKit.gear_button(UiKit.GEAR_SIZE)
	# Repainted for this screen only. The shared gear is near-white because every other
	# screen that carries one sits on a dark stage; the zoo is a pale sky, where the same
	# icon washes out beside a title already darkened for exactly that reason.
	gear.add_theme_color_override("icon_normal_color", TITLE_COLOR)
	gear.add_theme_color_override("icon_hover_color", UiKit.ACCENT.darkened(0.45))
	gear.add_theme_color_override("icon_pressed_color", UiKit.ACCENT.darkened(0.45))
	gear.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	gear.offset_right = -UiKit.GEAR_INSET_RIGHT
	gear.offset_left = gear.offset_right - UiKit.GEAR_SIZE
	gear.offset_top = UiKit.GEAR_INSET_TOP
	gear.offset_bottom = UiKit.GEAR_INSET_TOP + UiKit.GEAR_SIZE
	gear.pressed.connect(func() -> void: Game.open_settings())
	root.add_child(gear)

	_info = UiKit.panel(Color(0.05, 0.09, 0.15, 0.95), 16, 2, UiKit.GOLD)
	_info.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_info.offset_left = -230
	_info.offset_right = 230
	_info.offset_top = -150
	_info.offset_bottom = -28
	_info.visible = false
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_info)

	_info_body = UiKit.vbox(8)
	_info_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_child(_info_body)


func _populate() -> void:
	for child in _creatures.get_children():
		# Detach immediately so the collision pass below cannot include residents already
		# queued for deletion when the zoo is repopulated in-place.
		_creatures.remove_child(child)
		child.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717
	var occupied: Array[Dictionary] = []
	for state in Game.zoo:
		var estimated_radius := CreatureBrain.spacing_radius_for(state)
		var spot := _find_open_spot(rng, estimated_radius, occupied)
		var brain := CreatureBrain.create(state, spot)
		brain.clicked.connect(_show_info)
		_creatures.add_child(brain)
		# add_child() runs the brain's _ready(), where its transformed mesh is available for
		# an exact footprint. Re-place if that measured circle exceeds the data-only estimate,
		# then use the measured value for every later resident.
		var radius := brain.spacing_radius()
		if radius > estimated_radius + 0.001:
			spot = _find_open_spot(rng, radius, occupied)
			brain.position.x = spot.x
			brain.position.z = spot.z
		occupied.append({"position": spot, "radius": radius})
	# Fallback placement can be approximate at maximum capacity. Settle the full group
	# before the first rendered frame so no initial pile is ever visible.
	CreatureBrain.resolve_group_overlaps(_creatures, 64)

	if Game.zoo.is_empty():
		_show_empty_hint()


func _find_open_spot(rng: RandomNumberGenerator, radius: float,
		occupied: Array[Dictionary]) -> Vector3:
	# Try many candidates so the initial frame is already separated; the brains' live
	# separation pass remains as a safeguard once they start walking.
	var x_limit := maxf(YARD.x - radius - 0.7, 1.0)
	var z_limit := maxf(YARD.y - radius - 0.7, 1.0)
	for _attempt in 80:
		var candidate := Vector3(rng.randf_range(-x_limit, x_limit), 0.0,
			rng.randf_range(-z_limit, z_limit))
		var clear := true
		for entry in occupied:
			var other: Vector3 = entry["position"]
			var required: float = radius + float(entry["radius"]) + CreatureBrain.NEIGHBOUR_GAP
			if candidate.distance_to(other) < required:
				clear = false
				break
		if clear:
			return candidate
	# At high zoo capacity, return the best-effort candidate and let live steering finish the
	# separation instead of stacking every late resident at one fixed fallback point.
	return Vector3(rng.randf_range(-x_limit, x_limit), 0.0,
		rng.randf_range(-z_limit, z_limit))


func _show_empty_hint() -> void:
	_info_body_reset()
	_info.offset_left = -230
	_info.offset_right = 230
	_info.offset_top = -150
	_info_body.add_child(UiKit.label("どうぶつえんはまだ空です", UiKit.H3, UiKit.GOLD))
	_info_body.add_child(UiKit.label(
		"クリーチャーをつくると、このレッスンのあいだここでくらします。",
		UiKit.BODY, UiKit.MUTED))
	_info.visible = true


func _info_body_reset() -> void:
	for child in _info_body.get_children():
		# A queued Control still contributes its minimum size until the end of the frame.
		# Detach it now so rapidly choosing another resident cannot size the new name card
		# from both the old and new labels at once.
		_info_body.remove_child(child)
		child.queue_free()


func _show_info(brain: CreatureBrain) -> void:
	var state := brain.state_data
	if _focused_brain == brain:
		return
	Audio.play("pop")
	if _hint != null:
		_hint.visible = false
	if _focused_brain == null:
		_distance_before_focus = _distance
	else:
		_focused_brain.dismiss_focus()
	_focused_brain = brain
	_camera_target = brain.global_position + Vector3(0.0, 1.0, 0.0)
	_distance = FOCUS_DISTANCE
	_update_camera()
	brain.focus_on(_camera)
	_info_body_reset()

	var head := Control.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := UiKit.label(state.display_name(), UiKit.H2, UiKit.GOLD)
	name_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Keep a close-button-sized clear zone on BOTH sides. The previous one-sided reserve
	# let the centered text extend under the close button even when the outer panel width
	# was mathematically larger than the name.
	var side_reserve := INFO_CLOSE_SIZE + INFO_NAME_GAP
	name_label.offset_left = side_reserve
	name_label.offset_right = -side_reserve
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(name_label)
	var close := UiKit.button("×", UiKit.SMALL)
	UiKit.style_navigation(close)
	close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close.offset_left = -INFO_CLOSE_SIZE
	close.offset_right = 0
	close.offset_top = 6
	close.offset_bottom = 6 + INFO_CLOSE_SIZE
	close.custom_minimum_size = Vector2.ONE * INFO_CLOSE_SIZE
	close.pressed.connect(_dismiss_info)
	head.add_child(close)
	_info_body.add_child(head)

	# Measure only after the label has entered the live scene tree and inherited its actual
	# theme font. Measuring it beforehand returned the fallback minimum, so Japanese names
	# could extend through the close button and beyond the panel border.
	var font := name_label.get_theme_font("font")
	var name_width := ceilf(font.get_string_size(name_label.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.H2).x)
	var desired_head_width := maxf(name_width + side_reserve * 2.0, INFO_MIN_HEAD_WIDTH)
	var max_box_width := maxf(get_viewport().get_visible_rect().size.x - INFO_VIEWPORT_MARGIN,
		INFO_MIN_HEAD_WIDTH + INFO_PANEL_MARGIN)
	var box_width := minf(desired_head_width + INFO_PANEL_MARGIN, max_box_width)
	var head_width := box_width - INFO_PANEL_MARGIN
	head.custom_minimum_size = Vector2(head_width, 56)
	_build_release_row(state, head_width)
	_info.offset_left = -box_width * 0.5
	_info.offset_right = box_width * 0.5
	# Tall enough for the name row AND the release row beneath it. This was -112, sized for
	# a card that held nothing but a name, and the new row was being cut off by the panel's
	# own bottom edge.
	_info.offset_top = -168
	_info.visible = true


## Letting a student take a creature back out of the zoo.
##
## Two taps, never one. This is the only destructive thing in the game and the people using
## it are six; a single mis-tap on a card they opened to read a name should not be able to
## delete the animal they made. The first tap only asks.
##
## Worded as sending it home rather than as deleting it. Same outcome, and for this audience
## the difference between "your creature is gone" and "your creature went home" is the
## difference between a mistake and an ending.
func _build_release_row(state: CreatureState, width: float) -> void:
	var ask := UiKit.button("おうちにかえす", UiKit.SMALL)
	ask.custom_minimum_size = Vector2(width, 40)
	ask.focus_mode = Control.FOCUS_NONE
	UiKit.style_navigation(ask)
	_info_body.add_child(ask)

	var confirm := UiKit.hbox(8)
	confirm.alignment = BoxContainer.ALIGNMENT_CENTER
	confirm.visible = false
	confirm.custom_minimum_size = Vector2(width, 40)
	_info_body.add_child(confirm)

	var question := UiKit.label("ほんとうに?", UiKit.SMALL, UiKit.TEXT)
	question.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	confirm.add_child(question)
	var yes := UiKit.button("はい", UiKit.SMALL)
	yes.custom_minimum_size = Vector2(76, 40)
	yes.focus_mode = Control.FOCUS_NONE
	UiKit.style_navigation(yes)
	confirm.add_child(yes)
	var no := UiKit.button("いいえ", UiKit.SMALL)
	no.custom_minimum_size = Vector2(76, 40)
	no.focus_mode = Control.FOCUS_NONE
	UiKit.style_navigation(no)
	confirm.add_child(no)

	ask.pressed.connect(func() -> void:
		Audio.play("click")
		ask.visible = false
		confirm.visible = true)
	no.pressed.connect(func() -> void:
		Audio.play("click")
		confirm.visible = false
		ask.visible = true)
	yes.pressed.connect(_release.bind(state))


func _release(state: CreatureState) -> void:
	Audio.play("pop")
	# Close the card FIRST. Releasing repopulates the yard, which frees every brain including
	# the focused one, and the card holds a reference to it.
	_dismiss_info()
	Game.release_from_zoo(state)


func _dismiss_info() -> void:
	Audio.play("click")
	if _focused_brain != null:
		_focused_brain.dismiss_focus()
	_focused_brain = null
	_camera_target = YARD_CAMERA_TARGET
	_distance = _distance_before_focus
	_update_camera()
	_info.visible = false


# --- Camera ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _focused_brain != null:
		if event is InputEventScreenTouch and event.pressed:
			if _creature_at(event.position) != _focused_brain:
				_dismiss_info()
			return
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			if _creature_at(event.position) != _focused_brain:
				_dismiss_info()
			return
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_pick_creature_at(event.position)
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_pick_creature_at(button.position)
			_dragging = button.pressed
		elif button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_distance = clampf(_distance - 1.4, ZOOM_LIMITS.x, ZOOM_LIMITS.y)
			_update_camera()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_distance = clampf(_distance + 1.4, ZOOM_LIMITS.x, ZOOM_LIMITS.y)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		var motion: InputEventMouseMotion = event
		_yaw -= motion.relative.x * ORBIT_SPEED
		_pitch = clampf(_pitch - motion.relative.y * ORBIT_SPEED, 0.12, 1.25)
		_update_camera()


func _pick_creature_at(screen_position: Vector2) -> void:
	var creature := _creature_at(screen_position)
	if creature != null:
		_show_info(creature)


func _creature_at(screen_position: Vector2) -> CreatureBrain:
	if _camera == null or _creatures == null:
		return null
	var origin := _camera.project_ray_origin(screen_position)
	var endpoint := origin + _camera.project_ray_normal(screen_position) * 100.0
	var query := PhysicsRayQueryParameters3D.create(origin, endpoint)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var node: Node = hit.get("collider")
	while node != null and node != _creatures:
		if node is CreatureBrain:
			return node as CreatureBrain
		node = node.get_parent()
	return null


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touch_points[event.index] = event.position
		if _touch_points.size() == 2:
			_pinching = true
			_pinch_distance = _touch_distance()
	else:
		_touch_points.erase(event.index)
		if _touch_points.size() < 2:
			_pinching = false
			_pinch_distance = 0.0


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if not _pinching or not _touch_points.has(event.index):
		return
	_touch_points[event.index] = event.position
	var distance := _touch_distance()
	if _pinch_distance > 0.0 and distance > 0.0:
		_distance = clampf(_distance - (distance - _pinch_distance) * PINCH_ZOOM_SCALE,
			ZOOM_LIMITS.x, ZOOM_LIMITS.y)
		_update_camera()
	_pinch_distance = distance


func _touch_distance() -> float:
	if _touch_points.size() < 2:
		return 0.0
	var ids := _touch_points.keys()
	var first: Vector2 = _touch_points[ids[0]]
	var second: Vector2 = _touch_points[ids[1]]
	return first.distance_to(second)


func _update_camera() -> void:
	var offset := Vector3(
		cos(_pitch) * sin(_yaw),
		sin(_pitch),
		cos(_pitch) * cos(_yaw)
	) * _distance
	var target_shift := _camera_target - YARD_CAMERA_TARGET
	_camera.position = offset + Vector3(0, 0.8, 0) + target_shift
	_camera.look_at(_camera_target, Vector3.UP)
