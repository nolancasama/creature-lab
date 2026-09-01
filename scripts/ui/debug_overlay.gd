class_name DebugOverlay
extends Control
## Debug tools from the spec: typed transcript, skip transformation, instant creature,
## spawn any creature, reset zoo, view CreatureState, view transcript, toggle mic.
##
## Toggled with F3 and gated on Settings.debug_mode, which defaults to OS.is_debug_build()
## so it never appears in an exported classroom build.

var _state_view: RichTextLabel = null
var _transcript_view: Label = null
var _mic_button: Button = null
var _refresh_clock := 0.0


func _ready() -> void:
	name = "DebugOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()
	Game.creature_updated.connect(func(_s: CreatureState) -> void: _refresh())
	Game.phase_changed.connect(func(_a: int, _b: int) -> void: _refresh())
	Speech.heard.connect(_on_heard)
	visibility_changed.connect(func() -> void:
		set_process(visible)
		if visible:
			_refresh())
	set_process(visible)
	_refresh()


func _process(delta: float) -> void:
	_refresh_clock += delta
	if _refresh_clock >= 0.5:
		_refresh_clock = 0.0
		_refresh()


func _build() -> void:
	var panel := UiKit.panel(Color(0.03, 0.06, 0.1, 0.94), 12, 2, UiKit.ACCENT)
	panel.position = Vector2(-430, 12)
	panel.custom_minimum_size = Vector2(410, 0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -430
	panel.offset_top = 12
	panel.offset_right = -12
	panel.offset_bottom = 12
	add_child(panel)

	var column := UiKit.vbox(6)
	panel.add_child(column)
	column.add_child(UiKit.label("DEBUG  (F3)", UiKit.H3, UiKit.ACCENT))

	_state_view = UiKit.rich("", UiKit.SMALL)
	column.add_child(_state_view)

	_transcript_view = UiKit.label("transcript: -", UiKit.SMALL, UiKit.MUTED)
	_transcript_view.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_transcript_view)

	var typed_row := UiKit.hbox(6)
	column.add_child(typed_row)
	var entry := UiKit.line_edit("type a transcript...")
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	typed_row.add_child(entry)
	var send := UiKit.button("Send", UiKit.SMALL)
	typed_row.add_child(send)
	send.pressed.connect(func() -> void:
		Speech.submit_typed(entry.text)
		entry.clear())
	entry.text_submitted.connect(func(text: String) -> void:
		Speech.submit_typed(text)
		entry.clear())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	column.add_child(grid)

	_add_action(grid, "Skip transform", "skip_transform")
	_add_action(grid, "Auto-answer", "auto_answer")
	_add_action(grid, "Spawn creature", "spawn")
	_add_action(grid, "Reset zoo", "reset_zoo")
	_add_action(grid, "Go to Zoo", "goto_zoo")
	_add_action(grid, "Go to Title", "goto_title")

	_mic_button = UiKit.button("", UiKit.SMALL)
	_mic_button.pressed.connect(func() -> void:
		Settings.stt_enabled = not Settings.stt_enabled
		Speech.select_backend()
		_refresh())
	grid.add_child(_mic_button)
	grid.add_child(UiKit.spacer(1))


func _add_action(grid: GridContainer, text: String, action: String) -> void:
	var b := UiKit.button(text, UiKit.SMALL)
	grid.add_child(b)
	b.pressed.connect(func() -> void: _run(action))


func _run(action: String) -> void:
	match action:
		"spawn":
			Game.spawn_debug_creature()
		"reset_zoo":
			Game.reset_zoo()
		"goto_zoo":
			Game.set_phase(Game.Phase.ZOO)
		"goto_title":
			Game.set_phase(Game.Phase.TITLE)
		_:
			Game.debug_action.emit(action)
	_refresh()


func _on_heard(alternatives: PackedStringArray, _confidences: PackedFloat32Array,
		is_final: bool) -> void:
	var tag := "final" if is_final else "interim"
	_transcript_view.text = "%s: %s" % [tag, ", ".join(alternatives)]


func _refresh() -> void:
	if _mic_button != null:
		_mic_button.text = "Mic: %s (%s)" % ["on" if Settings.stt_enabled else "off", Speech.mode()]
	if _state_view == null:
		return
	var lines := PackedStringArray()
	var fps := float(Performance.get_monitor(Performance.TIME_FPS))
	var frame_ms := 1000.0 / fps if fps > 0.0 else 0.0
	lines.append("[b]performance[/b] %.0f FPS / %.1f ms" % [fps, frame_ms])
	lines.append("[b]renderer[/b] %s / %s" % [
		RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name()])
	lines.append("[b]graphics[/b] %s, scale %.3f, shadows %s, MSAA %s" % [
		GraphicsQuality.profile_label(), GraphicsQuality.render_scale(),
		"on" if GraphicsQuality.shadows_enabled() else "off", GraphicsQuality.msaa_label()])
	lines.append("[b]zoo FX[/b] %s  [b]draws[/b] %d  [b]primitives[/b] %d" % [
		GraphicsQuality.effect_quality_label(),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
	lines.append("[b]phase[/b] %s" % Game.Phase.keys()[Game.phase])
	lines.append("[b]zoo[/b] %d creature(s)" % Game.zoo.size())
	if Game.current == null:
		lines.append("[b]current[/b] none")
	else:
		lines.append("[b]animal[/b] %s" % Game.current.animal_id)
		lines.append("[b]slots[/b] %d/%d" % [Game.current.slots_filled(), CreatureState.SLOTS])
		for entry in Game.current.entries:
			lines.append("  %s - %s" % [str(entry["category"]), str(entry["sentence"])])
	_state_view.text = "\n".join(lines)
