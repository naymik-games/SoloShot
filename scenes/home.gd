extends Node2D

## Home / main menu. Attach to the root node of home.tscn (any node type works;
## the UI is built in code, same style as the rest of the project).

## Scene to load when a mode is picked.
@export_file("*.tscn") var pool_game_scene_path: String = "res://scenes/pool_game.tscn"

const BUTTON_SIZE := Vector2(360.0, 72.0)
const BG_COLOR := Color(0.07, 0.17, 0.12)

## Values for GameSession.computer_opponent (-1 = leave it to PoolGame's inspector value).
const OPPONENT_DEFAULT := -1
const OPPONENT_HUMAN := 0
const OPPONENT_COMPUTER := 1

## label, subtitle, mode (matches ModeCatalog.Type).
## "choose_opponent" entries open the opponent picker instead of starting right away.
const MODES: Array[Dictionary] = [
	{"label": "Free Practice", "sub": "Standard rack, no rules, no clock", "mode": ModeCatalog.Type.FREE_PRACTICE},
	{"label": "9-Ball", "sub": "Pocket in order, fewest shots wins", "mode": ModeCatalog.Type.NINE_BALL},
	{"label": "Time Trial", "sub": "Clear racks before time runs out", "mode": ModeCatalog.Type.TIME_TRIAL},
	{"label": "8-Ball", "sub": "Standard rules, pick your opponent", "mode": ModeCatalog.Type.EIGHT_BALL, "choose_opponent": true},
]

## label, subtitle, GameSession.computer_opponent value.
const EIGHT_BALL_OPPONENTS: Array[Dictionary] = [
	{"label": "Human vs Human", "sub": "Pass and play on this device", "opponent": OPPONENT_HUMAN},
	{"label": "Human vs Computer", "sub": "Play against the computer", "opponent": OPPONENT_COMPUTER},
]

var _main_menu: VBoxContainer
var _opponent_menu: VBoxContainer


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

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 16)
	center.add_child(stack)

	var title := Label.new()
	title.text = "SoloShot"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	stack.add_child(title)

	_main_menu = _make_menu("Select a game mode")
	for entry in MODES:
		_main_menu.add_child(_make_entry(entry["label"], entry["sub"], _on_mode_pressed.bind(entry)))
	stack.add_child(_main_menu)

	_opponent_menu = _make_menu("8-Ball: choose your opponent")
	for entry in EIGHT_BALL_OPPONENTS:
		_opponent_menu.add_child(_make_entry(entry["label"], entry["sub"], _on_opponent_chosen.bind(entry["opponent"])))
	_opponent_menu.add_child(_make_entry("Back", "", _show_main_menu))
	_opponent_menu.visible = false
	stack.add_child(_opponent_menu)


## A column with a prompt label at the top; entries get added by the caller.
func _make_menu(prompt_text: String) -> VBoxContainer:
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 16)

	var prompt := Label.new()
	prompt.text = prompt_text
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 22)
	prompt.modulate = Color(1, 1, 1, 0.7)
	menu.add_child(prompt)
	return menu


func _make_entry(label: String, subtitle: String, on_pressed: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var button := Button.new()
	button.text = label
	button.custom_minimum_size = BUTTON_SIZE
	button.add_theme_font_size_override("font_size", 28)
	button.pressed.connect(on_pressed)
	box.add_child(button)

	if subtitle != "":
		var sub := Label.new()
		sub.text = subtitle
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_font_size_override("font_size", 14)
		sub.modulate = Color(1, 1, 1, 0.6)
		box.add_child(sub)
	return box


func _show_main_menu() -> void:
	_opponent_menu.visible = false
	_main_menu.visible = true


func _on_mode_pressed(entry: Dictionary) -> void:
	if entry.get("choose_opponent", false):
		GameSession.selected_mode = entry["mode"]  # Remembered while the opponent picker is open.
		_main_menu.visible = false
		_opponent_menu.visible = true
	else:
		_start_game(entry["mode"], OPPONENT_DEFAULT)


func _on_opponent_chosen(opponent: int) -> void:
	_start_game(ModeCatalog.Type.EIGHT_BALL, opponent)


func _start_game(mode: int, opponent: int) -> void:
	GameSession.selected_mode = mode
	GameSession.computer_opponent = opponent
	var err := get_tree().change_scene_to_file(pool_game_scene_path)
	if err != OK:
		push_error("Could not load '%s' (error %d). Check pool_game_scene_path on the home root node." % [pool_game_scene_path, err])
