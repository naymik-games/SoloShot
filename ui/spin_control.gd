class_name SpinControl
extends Control
## The cue ball face. Tap or drag to choose where the cue tip strikes; double-tap to recentre.
## value is a point in the unit disc: x = right (+) / left (-), y = top (+, follow) / bottom (-, draw).
## (0, 0) is a centre-ball hit with no spin. AimController resets it after every shot.

signal spin_changed(value: Vector2)

@export var ball_color: Color = Color(0.96, 0.96, 0.91)
@export var line_color: Color = Color(0.0, 0.0, 0.0, 0.35)
@export var dot_color: Color = Color(0.85, 0.12, 0.12)

var value: Vector2 = Vector2.ZERO
var enabled: bool = true:
	set(v):
		enabled = v
		if not enabled:
			_dragging = false
		modulate.a = 1.0 if enabled else 0.45

var _dragging: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP  # Consumes the touch so it never aims the table.
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(96.0, 96.0)


## Programmatic update (from AimState). Does not emit spin_changed.
func set_value(v: Vector2) -> void:
	v = v.limit_length(1.0)
	if v.is_equal_approx(value):
		return
	value = v
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.double_click:
				_dragging = false
				_apply(Vector2.ZERO)
			else:
				_dragging = true
				_apply(_value_at(event.position))
		else:
			_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_apply(_value_at(event.position))
		accept_event()


func _apply(v: Vector2) -> void:
	v = v.limit_length(1.0)
	if v.is_equal_approx(value):
		return
	value = v
	queue_redraw()
	spin_changed.emit(value)


func _radius() -> float:
	return minf(size.x, size.y) * 0.5 - 3.0


func _dot_radius() -> float:
	return _radius() * 0.13


## Local point -> unit-disc value (screen y points down, spin y points up).
func _value_at(p: Vector2) -> Vector2:
	var reach := _radius() - _dot_radius()
	if reach <= 0.0:
		return Vector2.ZERO
	var rel := (p - size * 0.5) / reach
	return Vector2(rel.x, -rel.y).limit_length(1.0)


func _draw() -> void:
	var c := size * 0.5
	var r := _radius()
	var dr := _dot_radius()
	draw_circle(c, r + 3.0, Color(0.0, 0.0, 0.0, 0.35))  # Backing so it reads on any table colour.
	draw_circle(c, r, ball_color)
	draw_arc(c, r, 0.0, TAU, 48, Color(0.0, 0.0, 0.0, 0.8), 2.0, true)
	draw_line(c - Vector2(r, 0.0), c + Vector2(r, 0.0), line_color, 1.0, true)
	draw_line(c - Vector2(0.0, r), c + Vector2(0.0, r), line_color, 1.0, true)
	draw_arc(c, (r - dr) * 0.5, 0.0, TAU, 32, line_color, 1.0, true)  # Half-way ring.
	var dot_pos := c + Vector2(value.x, -value.y) * (r - dr)
	draw_circle(dot_pos, dr, dot_color)
	draw_arc(dot_pos, dr, 0.0, TAU, 20, Color(0.0, 0.0, 0.0, 0.9), 1.5, true)
