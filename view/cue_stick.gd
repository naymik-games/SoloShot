class_name CueStick
extends Sprite2D
## Purely visual cue stick. Sits behind the cue ball (opposite the aim direction), rotates with
## the aim angle, and pulls back as power increases. Never takes input.
##
## Sprite origin is placed on the cue TIP, so positioning is just "tip = a point behind the ball".
## The art (res://art/cue.png) is horizontal with the tip on the LEFT.

## Real-world-ish cue length in meters; sets the on-screen size relative to the table.
@export var cue_length_m: float = 1.45
## Pixel position of the tip inside the texture (the image has soft shadow padding around it).
@export var tip_px: Vector2 = Vector2(15.0, 23.5)
## Gap between tip and ball surface, in ball radii, at power 0 and power 1.
@export var min_gap_radii: float = 0.4
@export var max_gap_radii: float = 4.0

var mapper: CoordinateMapper
var aim: AimState
var ball_radius: float = 0.028575  ## Meters. Set by PoolGame from table_def.


func _ready() -> void:
	if texture == null:
		texture = load("res://art/cue.png")
	centered = false
	offset = -tip_px  # Puts the tip pixel on this node's origin.
	visible = false
	z_index = 1

## Recompute position / rotation / scale from the current aim. Cheap; call on any aim change
## or when the table is rescaled.
func refresh() -> void:
	if mapper == null or aim == null or texture == null:
		return

	var origin := mapper.to_screen(Vector2.ZERO)
	var px_per_m := mapper.to_screen(Vector2.RIGHT).distance_to(origin)
	var radius_px := ball_radius * px_per_m

	# Use the raw power-bar value so the cue matches what the slider shows.
	var gap_px := lerpf(min_gap_radii, max_gap_radii, aim.power_input) * radius_px
	var dir := Vector2.RIGHT.rotated(aim.angle)

	position = mapper.to_screen(aim.cue_ball_pos) - dir * (radius_px + gap_px)
	# Texture's +X runs tip -> butt, and the butt must point away from the aim direction.
	rotation = aim.angle + PI

	var length_px := texture.get_width() - tip_px.x
	var s := (cue_length_m * px_per_m) / length_px
	scale = Vector2(s, s)
