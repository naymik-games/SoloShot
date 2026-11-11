class_name AimOverlay
extends Node2D
## Draws the aim line, ghost ball, and short object-ball line from a PredictionResult.
## Pure rendering: reads the result, never touches the simulator.
## Replaces the earlier stub: update_overlay() now takes only the PredictionResult.

@export var config: AimConfig
@export var aim_line_color: Color = Color(1, 1, 1, 0.75)
@export var scratch_color: Color = Color(1.0, 0.3, 0.3, 0.9)
@export var ghost_outline_color: Color = Color(1, 1, 1, 0.6)
@export var ghost_fill_color: Color = Color(1, 1, 1, 0.12)
@export var object_line_color: Color = Color(1.0, 0.85, 0.3, 0.9)
@export var line_width: float = 1.5

var mapper: CoordinateMapper
var ball_radius: float = 0.02858  ## Meters. Set from TableDef.ball_radius.
var prediction: PredictionResult


func _ready() -> void:
	if config == null:
		config = AimConfig.new()


func update_overlay(p_prediction: PredictionResult) -> void:
	prediction = p_prediction
	queue_redraw()


func clear() -> void:
	prediction = null
	queue_redraw()


func _draw() -> void:
	if prediction == null or mapper == null:
		return
	var p := prediction
	var scratch := p.outcome == PredictionResult.Outcome.POCKETS_CUE

	# 1. Aim line (cue ball path).
	if config.show_aim_line and p.cue_path.size() >= 2:
		var pts := PackedVector2Array()
		for m in p.cue_path:
			pts.append(mapper.to_screen(m))
		draw_polyline(pts, scratch_color if scratch else aim_line_color, line_width, true)

	if p.outcome != PredictionResult.Outcome.HITS_BALL:
		return

	var r_px := mapper.length_to_screen(ball_radius)

	# 2. Ghost ball at the contact position.
	if config.show_ghost_ball:
		var c := mapper.to_screen(p.ghost_pos)
		draw_circle(c, r_px, ghost_fill_color)
		draw_arc(c, r_px, 0.0, TAU, 48, ghost_outline_color, line_width, true)

	# 3. Short object-ball line, starting at the ball's edge.
	if config.show_object_line and p.object_dir != Vector2.ZERO:
		var a := p.object_start + p.object_dir * ball_radius
		var b := p.object_start + p.object_dir * (ball_radius + config.object_line_length)
		draw_line(mapper.to_screen(a), mapper.to_screen(b), object_line_color, line_width, true)
