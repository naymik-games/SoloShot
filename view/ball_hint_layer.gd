class_name BallHintLayer
extends Node2D
## Briefly rings the balls the player should aim at (visual only). Keep at (0,0), above BallsLayer
## and below the aim overlay. Drawn here rather than in BallView, because BallView's sphere shader
## would apply to anything drawn inside it.
##
## Rings follow the ball's live position, so they stay correct if the layout changes size.

@export var duration: float = 1.5
@export var fade_in: float = 0.15
@export var fade_out: float = 0.45
@export var ring_color: Color = Color(1.0, 0.9, 0.35)
@export var ring_width: float = 3.0
## Pulses per second.
@export var pulse_hz: float = 1.6

## Set by PoolGame.
var state: SimState
var mapper: CoordinateMapper
var ball_radius: float = 0.02858  ## Meters.

var _ids: Array[int] = []
var _elapsed: float = 0.0


func _ready() -> void:
	set_process(false)


func show_hint(ids: Array[int]) -> void:
	if ids.is_empty():
		clear()
		return
	_ids.assign(ids)
	_elapsed = 0.0
	set_process(true)
	queue_redraw()


func clear() -> void:
	_ids.clear()
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		clear()
		return
	queue_redraw()


func _alpha() -> float:
	var a_in := clampf(_elapsed / maxf(fade_in, 0.001), 0.0, 1.0)
	var a_out := clampf((duration - _elapsed) / maxf(fade_out, 0.001), 0.0, 1.0)
	return a_in * a_out


func _draw() -> void:
	if _ids.is_empty() or state == null or mapper == null:
		return
	var alpha := _alpha()
	var pulse := 0.5 + 0.5 * sin(_elapsed * TAU * pulse_hz)
	var r := mapper.length_to_screen(ball_radius)
	for id in _ids:
		var ball := state.get_ball(id)
		if ball == null or not ball.is_on_table():
			continue
		var c := mapper.to_screen(ball.pos)
		var ring_r := r * (1.3 + 0.25 * pulse)
		var glow := ring_color
		glow.a = alpha * 0.18
		draw_circle(c, ring_r, glow)
		var ring := ring_color
		ring.a = alpha
		draw_arc(c, ring_r, 0.0, TAU, 48, ring, ring_width, true)
