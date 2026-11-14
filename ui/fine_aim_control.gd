class_name FineAimControl
extends Control
## Vertical fine-tune strip. Drag up/down = tiny relative angle changes.
## Dragging down rotates the aim clockwise (flip with invert_direction).
## Ticks scroll with the finger for feedback.
##
## Mouse input behaves exactly as before. Touch input (Godot's emulated mouse events) gets extra
## care, because a finger is far less precise than a mouse:
##   - touch_sensitivity_scale  fingers sweep much farther than a mouse for the same intent
##   - touch_slop               the wobble of a finger landing never nudges the aim
##   - max_touch_step           a single spiky event can't swing the aim
##   - lift_guard               the movement that arrives together with the lift is discarded

signal nudge(delta_radians: float)

const STRIP_SIZE: Vector2 = Vector2(56, 300)  # Was 30 wide; too narrow to land a thumb on.
const TICK_SPACING: float = 16.0

@export var config: AimConfig
@export var strip_color: Color = Color(0.1, 0.1, 0.1, 0.6)
@export var tick_color: Color = Color(1, 1, 1, 0.45)
## Flip if dragging down feels like it should rotate the aim the other way.
@export var invert_direction: bool = false

@export_group("Touch")
## Multiplies fine_strip_sensitivity for finger input only. Lower = finer control on the phone.
@export_range(0.05, 1.0, 0.05) var touch_sensitivity_scale: float = 0.35
## Pixels the finger must travel after landing before the strip reacts.
@export var touch_slop: float = 6.0
## Largest movement (in strip pixels) accepted from one touch event. Clips sudden spikes.
@export var max_touch_step: float = 24.0
## Holds the newest touch movement back until the next one arrives and drops it if the finger
## lifts first. Costs one frame of latency; removes the "jump when I let go" flick.
@export var lift_guard: bool = true

var _dragging: bool = false
var _is_touch: bool = false
var _slop_passed: bool = false
var _press_y: float = 0.0
var _last_y: float = 0.0
var _held_px: float = 0.0  ## Newest touch movement, waiting for lift_guard to release it.
var _scroll: float = 0.0


func _ready() -> void:
	if config == null:
		config = AimConfig.new()
	custom_minimum_size = STRIP_SIZE
	size = STRIP_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP


func _notification(what: int) -> void:
	# If the strip is hidden mid-drag the release never arrives; don't stay "dragging".
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_end_drag()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if event.pressed:
			_dragging = true
			# Mouse events synthesized from a touch carry DEVICE_ID_EMULATION.
			_is_touch = event.device == InputEvent.DEVICE_ID_EMULATION
			_slop_passed = not _is_touch
			_press_y = event.position.y
			_last_y = event.position.y
			_held_px = 0.0
		else:
			_end_drag()  # Lifting never nudges: anything still held back is dropped.
	elif event is InputEventMouseMotion and _dragging:
		accept_event()
		# Use the pointer position rather than event.relative: it is in the strip's own pixels
		# and can't carry a stray jump from the touch-to-mouse emulation.
		var y: float = event.position.y
		if not _slop_passed:
			if absf(y - _press_y) < touch_slop:
				return
			_slop_passed = true
			_last_y = y  # Start counting from here so leaving the slop doesn't jump.
			return
		var d: float = y - _last_y
		_last_y = y
		if _is_touch:
			d = clampf(d, -max_touch_step, max_touch_step)
			if lift_guard:
				var ready_px := _held_px
				_held_px = d
				d = ready_px
		_apply(d)


func _apply(d: float) -> void:
	if is_zero_approx(d):
		return
	if invert_direction:
		d = -d
	_scroll += d  # Ticks follow the finger 1:1, whatever the sensitivity.
	var scale_factor := touch_sensitivity_scale if _is_touch else 1.0
	nudge.emit(d * config.fine_strip_sensitivity * scale_factor)
	queue_redraw()


func _end_drag() -> void:
	_dragging = false
	_held_px = 0.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), strip_color)
	var y := fposmod(_scroll, TICK_SPACING)
	while y < size.y:
		draw_line(Vector2(size.x * 0.25, y), Vector2(size.x * 0.75, y), tick_color, 1.0)
		y += TICK_SPACING
