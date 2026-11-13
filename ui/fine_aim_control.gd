class_name FineAimControl
extends Control
## Vertical fine-tune strip. Drag up/down = tiny relative angle changes.
## Dragging down rotates the aim clockwise (flip with invert_direction).
## Ticks scroll with the finger for feedback.

signal nudge(delta_radians: float)

const STRIP_SIZE: Vector2 = Vector2(30, 300)
const TICK_SPACING: float = 16.0

@export var config: AimConfig
@export var strip_color: Color = Color(0.1, 0.1, 0.1, 0.6)
@export var tick_color: Color = Color(1, 1, 1, 0.45)
## Flip if dragging down feels like it should rotate the aim the other way.
@export var invert_direction: bool = false

var _dragging: bool = false
var _scroll: float = 0.0


func _ready() -> void:
	if config == null:
		config = AimConfig.new()
	custom_minimum_size = STRIP_SIZE
	size = STRIP_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var d: float = event.relative.y
		if invert_direction:
			d = -d
		_scroll += d
		nudge.emit(d * config.fine_strip_sensitivity)
		queue_redraw()
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), strip_color)
	var y := fposmod(_scroll, TICK_SPACING)
	while y < size.y:
		draw_line(Vector2(size.x * 0.25, y), Vector2(size.x * 0.75, y), tick_color, 1.0)
		y += TICK_SPACING
