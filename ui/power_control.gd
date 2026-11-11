class_name PowerControl
extends Control
## Pull-down power control. The handle rests at the TOP (zero power); drag it down to add power.
##
##   - Release with the handle pulled down  -> emits `released`; the owner fires the shot
##                                             (see AimController.release_power).
##   - Drag back up into the dead zone at the top and release -> value is 0, so the owner cancels.
##     You can also grab the handle again without letting go of the idea: nothing was fired.
##
## Only the handle can be grabbed, so tapping the track can never fire a shot by accident.
## Give the node a tall, narrow custom_minimum_size (e.g. 80 x 420) and keep mouse_filter = Stop.

## Emitted while dragging whenever the power changes (0..1). Not emitted by set_value().
signal power_changed(value: float)
## Emitted once when the player lets go of the handle (after the final power_changed).
signal released

@export_group("Behavior")
## Fraction of the travel, measured from the top, that snaps to zero power ("cancel zone").
@export_range(0.0, 0.2, 0.005) var dead_zone: float = 0.04
## Extra pixels around the handle that still grab it (fingers are imprecise).
@export var grab_margin: float = 14.0
## How quickly the handle eases to values set from outside (higher = snappier).
@export var ease_speed: float = 18.0

@export_group("Look")
@export var knob_height: float = 56.0
@export var track_width: float = 22.0
@export var track_color: Color = Color(0.06, 0.07, 0.08, 0.75)
@export var track_border_color: Color = Color(1, 1, 1, 0.18)
@export var tick_color: Color = Color(1, 1, 1, 0.28)
@export var knob_color: Color = Color(0.96, 0.96, 0.94)
@export var low_color: Color = Color(0.30, 0.80, 0.40)
@export var mid_color: Color = Color(0.97, 0.80, 0.20)
@export var high_color: Color = Color(0.92, 0.25, 0.20)

## Target power 0..1 (what the game uses).
var value: float = 0.0
## While false the control ignores input and is drawn dimmed (set by PoolGame per phase).
var enabled: bool = true:
	set = set_enabled

var _shown: float = 0.0  ## What is drawn; eases toward `value` unless the player is dragging.
var _dragging: bool = false
var _grab_offset: float = 0.0
var _box: StyleBoxFlat = StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)


## Silent update (does not emit). Use to sync the bar from AimState. Ignored mid-drag, because
## the player's finger owns the value then. The handle eases to the new value.
func set_value(v: float) -> void:
	if _dragging:
		return
	value = clampf(v, 0.0, 1.0)
	set_process(true)


func set_enabled(v: bool) -> void:
	enabled = v
	if not v:
		_dragging = false  # Drag is dropped silently: nothing fires when input is disabled.
	queue_redraw()


# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# Always swallow left clicks over the bar so they can't start an aim drag on the table.
		accept_event()
		if not enabled:
			return
		if event.pressed:
			if _knob_rect(_shown).grow(grab_margin).has_point(event.position):
				_dragging = true
				value = _shown
				_grab_offset = event.position.y - _knob_center_y(_shown)
				queue_redraw()
		elif _dragging:
			_dragging = false
			queue_redraw()
			released.emit()
	elif event is InputEventMouseMotion and _dragging:
		_set_from_knob_center(event.position.y - _grab_offset)
		accept_event()


func _set_from_knob_center(center_y: float) -> void:
	var raw := clampf((center_y - knob_height * 0.5) / _travel(), 0.0, 1.0)
	var v := 0.0 if raw <= dead_zone else raw  # Inside the dead zone the handle snaps to the top.
	if is_equal_approx(v, value):
		return
	value = v
	_shown = v
	power_changed.emit(v)
	queue_redraw()


func _process(delta: float) -> void:
	_shown = lerpf(_shown, value, 1.0 - exp(-ease_speed * delta))
	if absf(_shown - value) < 0.002:
		_shown = value
		set_process(false)
	queue_redraw()


# ---------------------------------------------------------------- geometry

func _travel() -> float:
	return maxf(size.y - knob_height, 1.0)


func _knob_center_y(v: float) -> float:
	return knob_height * 0.5 + v * _travel()


func _knob_rect(v: float) -> Rect2:
	return Rect2(2.0, _knob_center_y(v) - knob_height * 0.5, size.x - 4.0, knob_height)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var a := 1.0 if enabled else 0.45
	var pad := knob_height * 0.5
	var tx := (size.x - track_width) * 0.5
	var groove := Rect2(tx, pad - 4.0, track_width, size.y - 2.0 * pad + 8.0)

	# Groove.
	_panel(groove, _fade(track_color, a), track_width * 0.5, _fade(track_border_color, a), 1)

	# Power fill, from the top down to the handle.
	var cy := _knob_center_y(_shown)
	var fill_h := cy - groove.position.y
	if _shown > 0.001 and fill_h > 1.0:
		_panel(Rect2(tx, groove.position.y, track_width, fill_h),
				_fade(_power_color(_shown), a), track_width * 0.5)

	# Ticks every 10%, longer at 50% and 100%.
	for i in range(1, 11):
		var y := _knob_center_y(i * 0.1)
		var tick_len := 9.0 if i == 5 or i == 10 else 6.0
		draw_line(Vector2(tx - 2.0 - tick_len, y), Vector2(tx - 2.0, y), _fade(tick_color, a), 1.5)
		draw_line(Vector2(tx + track_width + 2.0, y),
				Vector2(tx + track_width + 2.0 + tick_len, y), _fade(tick_color, a), 1.5)

	# Cancel line: pull the handle back above this and release to cancel.
	var cancel_y := _knob_center_y(dead_zone)
	draw_line(Vector2(tx - 4.0, cancel_y), Vector2(tx + track_width + 4.0, cancel_y),
			_fade(Color(1, 1, 1, 0.55), a), 2.0)

	# Handle.
	var armed := value > 0.0
	var kr := _knob_rect(_shown)
	_panel(Rect2(kr.position + Vector2(0.0, 3.0), kr.size), Color(0, 0, 0, 0.30 * a), 12.0)
	var border := _power_color(_shown) if armed else Color(1, 1, 1, 0.9)
	_panel(kr, _fade(knob_color, a), 12.0, _fade(border, a), 3)
	var c := kr.get_center()
	for i in range(-1, 2):
		var gy := c.y + i * 7.0
		draw_line(Vector2(c.x - 12.0, gy), Vector2(c.x + 12.0, gy),
				Color(0.25, 0.25, 0.25, 0.55 * a), 2.0, true)

	# "Pull down" hint, only while resting at the top.
	if enabled and not _dragging and _shown <= 0.001:
		for i in 2:
			var hy := kr.end.y + 12.0 + i * 10.0
			draw_polyline(PackedVector2Array([
				Vector2(c.x - 8.0, hy), Vector2(c.x, hy + 7.0), Vector2(c.x + 8.0, hy)]),
				Color(1, 1, 1, 0.55 - 0.25 * i), 2.5, true)


func _power_color(v: float) -> Color:
	if v < 0.5:
		return low_color.lerp(mid_color, v / 0.5)
	return mid_color.lerp(high_color, (v - 0.5) / 0.5)


func _fade(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


func _panel(rect: Rect2, color: Color, radius: float,
		border: Color = Color(0, 0, 0, 0), border_w: int = 0) -> void:
	_box.bg_color = color
	_box.set_corner_radius_all(int(radius))
	_box.border_color = border
	_box.set_border_width_all(border_w)
	draw_style_box(_box, rect)
