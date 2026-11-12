extends Node2D

## Home / main menu. Attach to the root node of home.tscn (any node type works;
## the UI is built in code, same style as the rest of the project).

## Scene to load when a mode is picked.
@export_file("*.tscn") var pool_game_scene_path: String = "res://scenes/pool_game.tscn"

const BUTTON_SIZE := Vector2(360.0, 72.0)
const BG_COLOR := Color(0.07, 0.17, 0.12)

## label, subtitle, mode (matches PoolGame.ModeType)
const MODES: Array[Dictionary] = [
	{"label": "Free Practice", "sub": "Standard rack, no rules, no clock", "mode": PoolGame.ModeType.FREE_PRACTICE},
	{"label": "9-Ball", "sub": "Pocket in order, fewest shots wins", "mode": PoolGame.ModeType.NINE_BALL},
	{"label": "Time Trial", "sub": "Clear racks before time runs out", "mode": PoolGame.ModeType.TIME_TRIAL},
]


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)

	var title := Label.new()
	title.text = "SoloShot"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	column.add_child(title)

	var prompt := Label.new()
	prompt.text = "Select a game mode"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 22)
	prompt.modulate = Color(1, 1, 1, 0.7)
	column.add_child(prompt)

	for entry in MODES:
		column.add_child(_make_mode_entry(entry))


func _make_mode_entry(entry: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var button := Button.new()
	button.text = entry["label"]
	button.custom_minimum_size = BUTTON_SIZE
	button.add_theme_font_size_override("font_size", 28)
	button.pressed.connect(_on_mode_chosen.bind(entry["mode"]))
	box.add_child(button)

	var sub := Label.new()
	sub.text = entry["sub"]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.modulate = Color(1, 1, 1, 0.6)
	box.add_child(sub)
	return box


func _on_mode_chosen(mode: int) -> void:
	GameSession.selected_mode = mode
	var err := get_tree().change_scene_to_file(pool_game_scene_path)
	if err != OK:
		push_error("Could not load '%s' (error %d). Check pool_game_scene_path on the home root node." % [pool_game_scene_path, err])
