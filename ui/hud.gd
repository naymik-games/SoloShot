class_name Hud
extends Control
## HUD built in code: game stats (bottom-left band) and a fading message panel (over the table).

@export var message_seconds: float = 2.5
## Height of the band below the table (about table_inset_bottom * screen height).
@export var bottom_band_px: float = 64.0
## Left margin and width of the stats block. Keep left + width under the Place button (x ~ 466).
@export var status_left_px: float = 24.0
@export var status_width_px: float = 400.0
@export var message_bg: Color = Color(0.0, 0.0, 0.0, 0.6)
@export_range(0.0, 1.0, 0.01) var message_y_fraction: float = 0.78


var _status: Label
var _message: Label
var _message_panel: PanelContainer
var _tween: Tween


func _ready() -> void:
	# Cover the screen but never swallow touches meant for the aiming controls.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Game stats: bottom-left of the band, up to two lines, vertically centered.
	_status = _make_label(22)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.set_anchor(SIDE_LEFT, 0.0)
	_status.set_anchor(SIDE_RIGHT, 0.0)
	_status.set_anchor(SIDE_TOP, 1.0)
	_status.set_anchor(SIDE_BOTTOM, 1.0)
	_status.offset_left = status_left_px
	_status.offset_right = status_left_px + status_width_px
	_status.offset_top = -bottom_band_px
	_status.offset_bottom = 0.0
	add_child(_status)

	# Messages: semi-transparent panel centered on the screen (over the table).
	_message_panel = PanelContainer.new()
	_message_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = message_bg
	style.set_corner_radius_all(12)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	_message_panel.add_theme_stylebox_override("panel", style)
	_message_panel.set_anchor(SIDE_LEFT, 0.5)
	_message_panel.set_anchor(SIDE_RIGHT, 0.5)
	_message_panel.set_anchor(SIDE_TOP, message_y_fraction)
	_message_panel.set_anchor(SIDE_BOTTOM, message_y_fraction)
	_message_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_message_panel.modulate.a = 0.0
	add_child(_message_panel)

	_message = _make_label(30)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_panel.add_child(_message)

	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)

## Shows a message that fades out, or stays up if `persist` is true (e.g. game over).
func show_message(text: String, persist: bool = false) -> void:
	if _message_panel == null:
		return
	if _tween != null:
		_tween.kill()
	_message.text = text
	_message_panel.modulate.a = 1.0
	if persist:
		return
	_tween = create_tween()
	_tween.tween_interval(message_seconds)
	_tween.tween_property(_message_panel, "modulate:a", 0.0, 0.6)


## Multi-line status text from the game mode (shot counter, next ball). Empty hides it.
func set_status(text: String) -> void:
	if _status == null:
		return
	_status.text = text
	_status.visible = not text.is_empty()


func set_score(value: int) -> void:
	pass  # Unused for now: 9-ball shows its counter through set_status.


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	return label


func _apply_safe_area() -> void:
	var vp := get_viewport_rect()
	var safe := SafeArea.get_rect(get_viewport())
	var inset_l := safe.position.x - vp.position.x
	var inset_b := vp.end.y - safe.end.y

	_status.offset_left = status_left_px + inset_l
	_status.offset_right = status_left_px + status_width_px + inset_l
	_status.offset_top = -bottom_band_px - inset_b
	_status.offset_bottom = -inset_b



func _on_home_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/home.tscn")
