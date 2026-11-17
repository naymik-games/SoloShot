extends Node2D

## Home / main menu. Attach to the root node of home.tscn (any node type works;
## the UI is built in code, same style as the rest of the project).

## Scene to load when a mode is picked.
@export_file("*.tscn") var pool_game_scene_path: String = "res://scenes/pool_game.tscn"
const SETTINGS_SCENE_PATH := "res://scenes/settings_screen.tscn"
const BUTTON_SIZE := Vector2(360.0, 72.0)
const BG_COLOR := Color(0.07, 0.17, 0.12)

## Values for GameSession.computer_opponent (-1 = leave it to PoolGame's inspector value).
const OPPONENT_DEFAULT := -1
const OPPONENT_HUMAN := 0
const OPPONENT_COMPUTER := 1

const CORNER_MARGIN := 24
## Second-level menus. Each choice: label, subtitle, mode (ModeCatalog.Type) and opponent
## (GameSession.computer_opponent value).
const EIGHT_BALL_CHOICES: Array[Dictionary] = [
	{"label": "Human vs Human", "sub": "Pass and play on this device", "mode": ModeCatalog.Type.EIGHT_BALL, "opponent": OPPONENT_HUMAN},
	{"label": "Human vs Computer", "sub": "Play against the computer", "mode": ModeCatalog.Type.EIGHT_BALL, "opponent": OPPONENT_COMPUTER},
]

const NINE_BALL_CHOICES: Array[Dictionary] = [
	{"label": "Solo", "sub": "Pocket in order, fewest shots wins", "mode": ModeCatalog.Type.NINE_BALL, "opponent": OPPONENT_DEFAULT},
	{"label": "Human vs Human", "sub": "Pass and play on this device", "mode": ModeCatalog.Type.NINE_BALL_VERSUS, "opponent": OPPONENT_HUMAN},
	{"label": "Human vs Computer", "sub": "Play against the computer", "mode": ModeCatalog.Type.NINE_BALL_VERSUS, "opponent": OPPONENT_COMPUTER},
]

## Main menu entries: label, subtitle, and either
##   "mode"                  - start this mode right away, or
##   "prompt" + "choices"    - open a second menu with those choices.
const MODES: Array[Dictionary] = [
	{"label": "Free Practice", "sub": "Standard rack, no rules, no clock", "mode": ModeCatalog.Type.FREE_PRACTICE},
	{"label": "9-Ball", "sub": "Solo or head to head", "prompt": "9-Ball: choose how to play", "choices": NINE_BALL_CHOICES},
	{"label": "Time Trial", "sub": "Clear racks before time runs out", "mode": ModeCatalog.Type.TIME_TRIAL},
	{"label": "Target Practice", "sub": "Land the ball on the target, 3 rounds", "mode": ModeCatalog.Type.TARGET_PRACTICE},
	{"label": "8-Ball", "sub": "Standard rules, pick your opponent", "prompt": "8-Ball: choose your opponent", "choices": EIGHT_BALL_CHOICES},
]

var _main_menu: VBoxContainer
## Shared by every second-level menu; refilled by _show_choices().
var _choice_menu: VBoxContainer
var _corner_margin: MarginContainer

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

	_choice_menu = _make_menu("")
	_choice_menu.visible = false
	stack.add_child(_choice_menu)

		# Bottom-right corner, kept clear of notches and the home bar (same SafeArea as settings).
	_corner_margin = MarginContainer.new()
	_corner_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_corner_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block the menu buttons.
	layer.add_child(_corner_margin)

	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.custom_minimum_size = Vector2(200.0, 64.0)
	settings_button.add_theme_font_size_override("font_size", 24)
	settings_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	settings_button.size_flags_vertical = Control.SIZE_SHRINK_END
	settings_button.pressed.connect(_open_settings)
	_corner_margin.add_child(settings_button)

	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


## A column with a prompt label at the top (child 0); entries get added by the caller.
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
	_choice_menu.visible = false
	_main_menu.visible = true


## Fills the shared second-level menu with one mode's choices (plus Back) and shows it.
func _show_choices(entry: Dictionary) -> void:
	(_choice_menu.get_child(0) as Label).text = entry["prompt"]
	for i in range(_choice_menu.get_child_count() - 1, 0, -1):  # Keep the prompt label.
		var child := _choice_menu.get_child(i)
		_choice_menu.remove_child(child)
		child.queue_free()
	for choice in entry["choices"]:
		_choice_menu.add_child(_make_entry(choice["label"], choice["sub"],
				_start_game.bind(choice["mode"], choice["opponent"])))
	_choice_menu.add_child(_make_entry("Back", "", _show_main_menu))
	_main_menu.visible = false
	_choice_menu.visible = true


func _on_mode_pressed(entry: Dictionary) -> void:
	if entry.has("choices"):
		_show_choices(entry)
	else:
		_start_game(entry["mode"], OPPONENT_DEFAULT)


func _start_game(mode: int, opponent: int) -> void:
	GameSession.selected_mode = mode
	GameSession.computer_opponent = opponent
	var err := get_tree().change_scene_to_file(pool_game_scene_path)
	if err != OK:
		push_error("Could not load '%s' (error %d). Check pool_game_scene_path on the home root node." % [pool_game_scene_path, err])


func _open_settings() -> void:
	var err := get_tree().change_scene_to_file(SETTINGS_SCENE_PATH)
	if err != OK:
		push_error("Could not load '%s' (error %d)." % [SETTINGS_SCENE_PATH, err])

func _apply_safe_area() -> void:
	var viewport := get_viewport()
	var visible_rect := viewport.get_visible_rect()
	var safe := SafeArea.get_rect(viewport)
	_corner_margin.add_theme_constant_override("margin_right", int(visible_rect.end.x - safe.end.x) + CORNER_MARGIN)
	_corner_margin.add_theme_constant_override("margin_bottom", int(visible_rect.end.y - safe.end.y) + CORNER_MARGIN)
