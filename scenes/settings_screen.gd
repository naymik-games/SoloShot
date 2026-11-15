extends Node2D
## Settings screen, opened from the home screen. Attach to the root node of settings_screen.tscn.
## The UI is built in code, same style as home.gd. Every control writes straight to the
## Settings autoload (which autosaves), so there is no Apply button.

@export_file("*.tscn") var home_scene_path: String = "res://scenes/home.tscn"

const BG_COLOR := Color(0.07, 0.17, 0.12)  # Same as home.gd.
const PANEL_WIDTH := 560.0
const SCREEN_MARGIN := 16
const BAR_BUTTON_SIZE := Vector2(300.0, 72.0)
const ARROW_BUTTON_SIZE := Vector2(72.0, 72.0)
const PREVIEW_SIZE := Vector2(320.0, 184.0)
const DIFFICULTY_BUTTON_SIZE := Vector2(170.0, 64.0)
const RESET_TEXT := "Reset to Defaults"
const RESET_CONFIRM_TEXT := "Tap again to confirm"
const RESET_CONFIRM_SECONDS := 3.0

var _margin: MarginContainer
var _stack: VBoxContainer

var _table_art: Array[String] = []
var _table_index := 0
var _table_preview: TextureRect
var _table_name: Label
var _table_prev: Button
var _table_next: Button

var _prediction_slider: HSlider
var _prediction_value: Label
var _aim_guide_toggle: CheckButton
var _fine_aim_slider: HSlider
var _fine_aim_value: Label
var _spin_toggle: CheckButton

var _difficulty_buttons: Array[Button] = []
var _difficulty_desc: Label

var _reset_button: Button
var _reset_armed := false
var _reset_ticket := 0


func _ready() -> void:
	_build_ui()
	_sync_from_settings()
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_home()


# ---------------------------------------------------------------- building

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)

	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	_margin.add_child(page)

	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	page.add_child(title)

	# The options scroll; the Reset / Back bar below stays put (handy on a phone).
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	_stack = VBoxContainer.new()
	_stack.custom_minimum_size.x = PANEL_WIDTH
	_stack.add_theme_constant_override("separation", 20)
	center.add_child(_stack)

	_add_section("Player preferences")
	_build_table_art_row()
	_build_prediction_row()
	_aim_guide_toggle = _add_toggle_row("Aim guide", "Ghost ball and the line to the first ball hit",
			_on_aim_guide_toggled)
	_build_fine_aim_row()
	_spin_toggle = _add_toggle_row("Spin control", "Show the cue ball spin control while aiming",
			_on_spin_toggled)

	_add_section("AI difficulty")
	_build_difficulty_row()

	page.add_child(_make_bottom_bar())


func _add_section(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 32)
	_stack.add_child(label)
	_stack.add_child(HSeparator.new())


## A title with a small grey hint under it (same look as the subtitles on the home buttons).
## Returns the column so the caller can add the control.
func _make_row(title: String, hint: String = "") -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_make_title_label(title, hint))
	_stack.add_child(row)
	return row


func _make_title_label(title: String, hint: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 24)
	box.add_child(label)

	if hint != "":
		var sub := Label.new()
		sub.text = hint
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.add_theme_font_size_override("font_size", 14)
		sub.modulate = Color(1, 1, 1, 0.6)
		box.add_child(sub)
	return box


func _add_toggle_row(title: String, hint: String, on_toggled: Callable) -> CheckButton:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.add_child(_make_title_label(title, hint))

	var toggle := CheckButton.new()
	toggle.custom_minimum_size = Vector2(96.0, 56.0)
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.toggled.connect(on_toggled)
	line.add_child(toggle)

	_stack.add_child(line)
	return toggle


func _make_slider(min_value: float, max_value: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size = Vector2(0.0, 44.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return slider


func _make_value_label() -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(90.0, 0.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 22)
	return label


func _build_table_art_row() -> void:
	var row := _make_row("Table art", "Choose the look of the table")
	_table_art = Settings.list_table_art()

	var carousel := HBoxContainer.new()
	carousel.alignment = BoxContainer.ALIGNMENT_CENTER
	carousel.add_theme_constant_override("separation", 12)
	row.add_child(carousel)

	_table_prev = _make_arrow_button("<", -1)
	carousel.add_child(_table_prev)

	var middle := VBoxContainer.new()
	middle.add_theme_constant_override("separation", 4)
	carousel.add_child(middle)

	_table_preview = TextureRect.new()
	_table_preview.custom_minimum_size = PREVIEW_SIZE
	_table_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_table_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	middle.add_child(_table_preview)

	_table_name = Label.new()
	_table_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_table_name.add_theme_font_size_override("font_size", 18)
	middle.add_child(_table_name)

	_table_next = _make_arrow_button(">", 1)
	carousel.add_child(_table_next)


func _make_arrow_button(text: String, direction: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = ARROW_BUTTON_SIZE
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 28)
	button.pressed.connect(_step_table.bind(direction))
	return button


func _build_prediction_row() -> void:
	var row := _make_row("Object ball line",
			"How far the line shows the object ball travelling. 0 hides it, 2 is the standard length")
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	row.add_child(line)

	_prediction_slider = _make_slider(0.0, Settings.MAX_OBJECT_LINE_STOP, 1.0)
	_prediction_slider.tick_count = Settings.MAX_OBJECT_LINE_STOP + 1
	_prediction_slider.ticks_on_borders = true
	_prediction_slider.value_changed.connect(_on_prediction_changed)
	line.add_child(_prediction_slider)

	_prediction_value = _make_value_label()
	line.add_child(_prediction_value)


func _build_fine_aim_row() -> void:
	var row := _make_row("Fine aim sensitivity", "Lower = slower, steadier fine aim")
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	row.add_child(line)

	_fine_aim_slider = _make_slider(Settings.MIN_FINE_AIM_SENSITIVITY,
			Settings.MAX_FINE_AIM_SENSITIVITY, Settings.FINE_AIM_STEP)
	_fine_aim_slider.value_changed.connect(_on_fine_aim_changed)
	line.add_child(_fine_aim_slider)

	_fine_aim_value = _make_value_label()
	line.add_child(_fine_aim_value)


func _build_difficulty_row() -> void:
	var row := _make_row("Computer opponent", "How well the computer plays 8-ball")

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	row.add_child(buttons)

	var group := ButtonGroup.new()
	for level in range(AiProfiles.LEVEL_NAMES.size()):
		var button := Button.new()
		button.text = AiProfiles.LEVEL_NAMES[level]
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = DIFFICULTY_BUTTON_SIZE
		button.add_theme_font_size_override("font_size", 28)
		button.pressed.connect(_on_difficulty_pressed.bind(level))
		buttons.add_child(button)
		_difficulty_buttons.append(button)

	_difficulty_desc = Label.new()
	_difficulty_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_difficulty_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_difficulty_desc.add_theme_font_size_override("font_size", 14)
	_difficulty_desc.modulate = Color(1, 1, 1, 0.6)
	row.add_child(_difficulty_desc)


func _make_bottom_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 16)

	_reset_button = Button.new()
	_reset_button.text = RESET_TEXT
	_reset_button.custom_minimum_size = BAR_BUTTON_SIZE
	_reset_button.add_theme_font_size_override("font_size", 24)
	_reset_button.pressed.connect(_on_reset_pressed)
	bar.add_child(_reset_button)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = BAR_BUTTON_SIZE
	back.add_theme_font_size_override("font_size", 28)
	back.pressed.connect(_go_home)
	bar.add_child(back)
	return bar


## Keeps the page clear of notches and the home bar, same SafeArea the game screen uses.
func _apply_safe_area() -> void:
	var viewport := get_viewport()
	var visible := viewport.get_visible_rect()
	var safe := SafeArea.get_rect(viewport)
	_margin.add_theme_constant_override("margin_left", int(safe.position.x - visible.position.x) + SCREEN_MARGIN)
	_margin.add_theme_constant_override("margin_right", int(visible.end.x - safe.end.x) + SCREEN_MARGIN)
	_margin.add_theme_constant_override("margin_top", int(safe.position.y - visible.position.y) + SCREEN_MARGIN)
	_margin.add_theme_constant_override("margin_bottom", int(visible.end.y - safe.end.y) + SCREEN_MARGIN)
	_stack.custom_minimum_size.x = minf(PANEL_WIDTH, safe.size.x - 2.0 * SCREEN_MARGIN)


# ---------------------------------------------------------------- showing the current values

## Puts every control on the Settings value without firing their signals (also used after a reset).
func _sync_from_settings() -> void:
	_table_index = maxi(_table_art.find(Settings.table_art_path), 0)
	_refresh_table_art()

	_prediction_slider.set_value_no_signal(Settings.object_line_stop)
	_update_prediction_label()
	_aim_guide_toggle.set_pressed_no_signal(Settings.show_aim_guide)
	_fine_aim_slider.set_value_no_signal(Settings.fine_aim_sensitivity)
	_update_fine_aim_label()
	_spin_toggle.set_pressed_no_signal(Settings.spin_control_enabled)

	for i in range(_difficulty_buttons.size()):
		_difficulty_buttons[i].set_pressed_no_signal(i == Settings.ai_difficulty)
	_difficulty_desc.text = AiProfiles.describe(Settings.ai_difficulty)


func _refresh_table_art() -> void:
	var several := _table_art.size() > 1
	_table_prev.disabled = not several
	_table_next.disabled = not several
	if _table_art.is_empty():
		_table_preview.texture = null
		_table_name.text = "No table art found in %s" % Settings.TABLE_ART_DIR
		return
	var path := _table_art[_table_index]
	_table_preview.texture = load(path) as Texture2D
	_table_name.text = "%s  (%d / %d)" % [path.get_file().get_basename(), _table_index + 1, _table_art.size()]


func _update_prediction_label() -> void:
	var stop := int(_prediction_slider.value)
	_prediction_value.text = "Off" if stop == 0 else str(stop)


func _update_fine_aim_label() -> void:
	_fine_aim_value.text = "%.2fx" % _fine_aim_slider.value


# ---------------------------------------------------------------- handlers

func _step_table(direction: int) -> void:
	if _table_art.is_empty():
		return
	_table_index = posmod(_table_index + direction, _table_art.size())
	Settings.table_art_path = _table_art[_table_index]
	_refresh_table_art()


func _on_prediction_changed(value: float) -> void:
	Settings.object_line_stop = int(value)
	_update_prediction_label()


func _on_aim_guide_toggled(pressed: bool) -> void:
	Settings.show_aim_guide = pressed


func _on_fine_aim_changed(value: float) -> void:
	Settings.fine_aim_sensitivity = value
	_update_fine_aim_label()


func _on_spin_toggled(pressed: bool) -> void:
	Settings.spin_control_enabled = pressed


func _on_difficulty_pressed(level: int) -> void:
	Settings.ai_difficulty = level
	_difficulty_desc.text = AiProfiles.describe(level)


## Two taps (within a few seconds) so a stray touch can't wipe everything.
func _on_reset_pressed() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_button.text = RESET_CONFIRM_TEXT
		_reset_ticket += 1
		var ticket := _reset_ticket
		await get_tree().create_timer(RESET_CONFIRM_SECONDS).timeout
		if ticket == _reset_ticket:
			_disarm_reset()
		return
	_disarm_reset()
	Settings.reset_to_defaults()
	_sync_from_settings()


func _disarm_reset() -> void:
	_reset_armed = false
	_reset_ticket += 1  # Cancels any pending "revert the button text" timer.
	_reset_button.text = RESET_TEXT


func _go_home() -> void:
	Settings.save_now()
	var err := get_tree().change_scene_to_file(home_scene_path)
	if err != OK:
		push_error("Could not load '%s' (error %d). Check home_scene_path on the settings root node." % [home_scene_path, err])
