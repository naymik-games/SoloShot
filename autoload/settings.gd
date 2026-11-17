extends Node
## Autoload "Settings". Register it in Project > Project Settings > Globals (Autoload) with the
## name exactly "Settings". It owns every player setting: defaults, validation, saving, loading.
##
## Gameplay code only reads it, e.g.  Settings.object_line_scale()  or  Settings.show_aim_guide.
## Writing a property (Settings.show_aim_guide = false) validates it, emits `changed` and
## schedules a save, so there is never a manual "apply" step.
##
## To add a setting: add a line to DEFAULTS, a property below, and (if it needs clamping)
## a case in _sanitize(). Old save files keep working: missing keys just take the default.

signal changed(key: String)

const SAVE_PATH := "user://solo_shot_settings.cfg"
const SAVE_SECTION := "settings"
const SAVE_DELAY_SEC := 0.5  # Slider drags don't write to disk on every tick.

const TABLE_ART_DIR := "res://art/tables"
## Used when nothing is saved. If this file doesn't exist, the first image in TABLE_ART_DIR is used.
const DEFAULT_TABLE_ART := "res://art/tables/standard.png"
const IMAGE_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp", "svg"]

const BALL_SET_DIR := "res://art/balls"
## Used when nothing is saved (or the saved folder is gone). Falls back to the first folder found.
const DEFAULT_BALL_SET := "alt_0"

## Object-ball line: stops 0..4. 0 = off, DEFAULT_OBJECT_LINE_STOP = the length used today.
const MAX_OBJECT_LINE_STOP := 4
const DEFAULT_OBJECT_LINE_STOP := 2

## Multiplier on how far the fine-aim control moves the aim (1.0 = today's feel).
const MIN_FINE_AIM_SENSITIVITY := 0.25
const MAX_FINE_AIM_SENSITIVITY := 2.0
const FINE_AIM_STEP := 0.05

const DEFAULTS := {
	"table_art_path": DEFAULT_TABLE_ART,
	"object_line_stop": DEFAULT_OBJECT_LINE_STOP,
	"show_aim_guide": true,  # Ghost ball + first-contact line (the cue ball's path to its first hit).
	"fine_aim_sensitivity": 1.0,
	"spin_control_enabled": true,
	"ai_difficulty": AiProfiles.Level.MEDIUM,
	"ball_set": DEFAULT_BALL_SET,
}

var table_art_path: String:
	get:
		return _values["table_art_path"]
	set(value):
		set_value("table_art_path", value)

## Folder name under res://art/balls, e.g. "alt_0".
var ball_set: String:
	get:
		return _values["ball_set"]
	set(value):
		set_value("ball_set", value)

## 0 = no line, 1..4; 2 is the current length. Use object_line_scale() to apply it.
var object_line_stop: int:
	get:
		return _values["object_line_stop"]
	set(value):
		set_value("object_line_stop", value)

var show_aim_guide: bool:
	get:
		return _values["show_aim_guide"]
	set(value):
		set_value("show_aim_guide", value)

var fine_aim_sensitivity: float:
	get:
		return _values["fine_aim_sensitivity"]
	set(value):
		set_value("fine_aim_sensitivity", value)

var spin_control_enabled: bool:
	get:
		return _values["spin_control_enabled"]
	set(value):
		set_value("spin_control_enabled", value)

## An AiProfiles.Level value.
var ai_difficulty: int:
	get:
		return _values["ai_difficulty"]
	set(value):
		set_value("ai_difficulty", value)

var _values: Dictionary = DEFAULTS.duplicate()
var _dirty := false
var _save_timer: Timer


func _ready() -> void:
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY_SEC
	_save_timer.timeout.connect(save_now)
	add_child(_save_timer)
	load_settings()


func _notification(what: int) -> void:
	# Don't lose a change made just before the app is closed or sent to the background.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_now()


# ---------------------------------------------------------------- reading helpers

## Multiply AimConfig.object_line_length by this. 0 = hide the line, 1 = today's length.
func object_line_scale() -> float:
	return float(object_line_stop) / float(DEFAULT_OBJECT_LINE_STOP)


## A fresh AiConfig for the chosen difficulty (see ai_profiles.gd).
func make_ai_config() -> AiConfig:
	return AiProfiles.make(ai_difficulty)


## Every image in res://art/tables, sorted. Also works in exported builds, where the project
## lists imported images as "name.png.import" instead of "name.png".
func list_table_art() -> Array[String]:
	var found: Array[String] = []
	for file_name in DirAccess.get_files_at(TABLE_ART_DIR):
		var clean := file_name
		for suffix in [".import", ".remap"]:
			clean = clean.trim_suffix(suffix)
		if not IMAGE_EXTENSIONS.has(clean.get_extension().to_lower()):
			continue
		var path := TABLE_ART_DIR.path_join(clean)
		if not found.has(path):
			found.append(path)
	found.sort()
	return found


## The chosen table art, or null if it can't be loaded.
func table_art_texture() -> Texture2D:
	return load(table_art_path) as Texture2D

## Every folder in res://art/balls, sorted. Each one is a ball set.
func list_ball_sets() -> Array[String]:
	var found: Array[String] = []
	for dir_name in DirAccess.get_directories_at(BALL_SET_DIR):
		found.append(dir_name)
	found.sort()
	return found


## Texture path for one ball (0 = cue ball) in the chosen set.
func ball_texture_path(ball_id: int) -> String:
	return "%s/%s/ball_%d.png" % [BALL_SET_DIR, ball_set, ball_id]
# ---------------------------------------------------------------- writing

func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("Settings: unknown setting '%s'" % key)
		return
	var clean: Variant = _sanitize(key, value)
	if _values[key] == clean:
		return
	_values[key] = clean
	changed.emit(key)
	_dirty = true
	_save_timer.start()


func reset_to_defaults() -> void:
	for key: String in DEFAULTS:
		set_value(key, DEFAULTS[key])
	save_now()


func save_now() -> void:
	if not _dirty:
		return
	var cfg := ConfigFile.new()
	for key: String in _values:
		cfg.set_value(SAVE_SECTION, key, _values[key])
	var err := cfg.save(SAVE_PATH)
	if err == OK:
		_dirty = false
	else:
		push_warning("Settings: could not save '%s' (error %d)" % [SAVE_PATH, err])


func load_settings() -> void:
	var cfg := ConfigFile.new()
	var loaded := cfg.load(SAVE_PATH) == OK
	for key: String in DEFAULTS:
		var raw: Variant = DEFAULTS[key]
		if loaded:
			raw = cfg.get_value(SAVE_SECTION, key, DEFAULTS[key])
		_values[key] = _sanitize(key, raw)
	_dirty = false


# ---------------------------------------------------------------- validation

## Turns whatever was passed (or read from a hand-edited file) into a legal value.
func _sanitize(key: String, value: Variant) -> Variant:
	match key:
		"table_art_path":
			var path := String(value)
			return path if ResourceLoader.exists(path) else _fallback_table_art()
		"object_line_stop":
			return clampi(int(value), 0, MAX_OBJECT_LINE_STOP)
		"fine_aim_sensitivity":
			return clampf(snappedf(float(value), FINE_AIM_STEP),
					MIN_FINE_AIM_SENSITIVITY, MAX_FINE_AIM_SENSITIVITY)
		"ai_difficulty":
			return clampi(int(value), 0, AiProfiles.LEVEL_NAMES.size() - 1)
		"ball_set":
			var set_name := String(value)
			return set_name if list_ball_sets().has(set_name) else _fallback_ball_set()
		_:
			return bool(value)  # The remaining settings are on/off switches.


func _fallback_table_art() -> String:
	if ResourceLoader.exists(DEFAULT_TABLE_ART):
		return DEFAULT_TABLE_ART
	var all := list_table_art()
	return all[0] if not all.is_empty() else ""


func _fallback_ball_set() -> String:
	var all := list_ball_sets()
	if all.has(DEFAULT_BALL_SET):
		return DEFAULT_BALL_SET
	return all[0] if not all.is_empty() else DEFAULT_BALL_SET
