class_name BallView
extends Node2D
## Draws one ball as a lit, rolling sphere with a soft drop shadow. Updated from a BallState; never writes to it.
##
## Rolling is purely visual: each frame the ball's on-screen movement is converted into a rotation
## (angle = distance / radius, about the axis perpendicular to the travel direction), accumulated in
## `_orient`, and handed to the shader. The simulation knows nothing about it.
##
## Art: res://art/balls/ball_<id>.png (0 = cue ball), 2:1 wrapped texture, number spots at
## u = 0.25 and 0.75. Balls without a texture fall back to a flat color with spots so rolling is
## still visible while the art is being made.

const BALL_SHADER: Shader = preload("res://shaders/ball_sphere.gdshader")
const TEXTURE_PATH: String = "res://art/balls/ball_%d.png"

const PALETTE: Array[Color] = [
	Color(0.96, 0.77, 0.09),  # 1 yellow
	Color(0.12, 0.31, 0.85),  # 2 blue
	Color(0.84, 0.16, 0.16),  # 3 red
	Color(0.42, 0.11, 0.60),  # 4 purple
	Color(0.97, 0.50, 0.00),  # 5 orange
	Color(0.18, 0.49, 0.20),  # 6 green
	Color(0.48, 0.12, 0.12),  # 7 maroon
	Color(0.07, 0.07, 0.07),  # 8 black
]
const BALL_WHITE: Color = Color(0.97, 0.97, 0.94)

## The quad is drawn this many times larger than the ball: room for the antialiased edge and the
## drop shadow, which the shader draws into the same quad. Keep in sync with the shader's `pad`.
const QUAD_PAD: float = 1.7
## Ignore on-screen jumps larger than this many radii in one update (respots, teleports).
const MAX_ROLL_STEP_RADII: float = 30.0

var ball_id: int = 0
var radius_m: float = 0.02858

## Longitude (degrees from the texture's center) shown facing the viewer when a ball is first set up.
## 90 = the number spot at u = 0.75.
var rest_longitude_deg: float = 90.0
## Give each ball a random (but repeatable) turn and tilt at spawn so the numbers aren't all upright.
var randomize_rest_orientation: bool = true

var _radius_px: float = 0.0
var _material: ShaderMaterial
var _quad_tex: ImageTexture
var _loaded_id: int = -1

## Ball-local -> view-space rotation. The shader gets its inverse.
var _orient: Basis = Basis.IDENTITY
var _last_pos: Vector2 = Vector2.ZERO
var _has_last: bool = false
var _was_moving: bool = false


func update_from(ball: BallState, mapper: CoordinateMapper) -> void:
	_ensure_assets()

	var on_table := ball.is_on_table()
	visible = on_table

	var r := mapper.length_to_screen(radius_m)
	if not is_equal_approx(r, _radius_px):
		_radius_px = r
		_material.set_shader_parameter("outline_width", 1.0 / maxf(r, 1.0))
		queue_redraw()

	var new_pos := mapper.to_screen(ball.pos)
	if on_table:
		# Only roll while the sim says the ball is moving (plus the frame it stops), so respots
		# and ball-in-hand placement slide instead of spinning the ball.
		var moving := ball.is_moving()
		if _has_last and (moving or _was_moving):
			_roll(new_pos - _last_pos)
		_last_pos = new_pos
		_has_last = true
		_was_moving = moving
	else:
		_has_last = false
		_was_moving = false
	position = new_pos


## Display-only use (e.g. the pocketed-ball tray): draw at a fixed screen position and radius,
## no rolling, no BallState needed.
func show_static(screen_pos: Vector2, radius_px: float) -> void:
	_ensure_assets()
	visible = true
	position = screen_pos
	if not is_equal_approx(radius_px, _radius_px):
		_radius_px = radius_px
		_material.set_shader_parameter("outline_width", 1.0 / maxf(radius_px, 1.0))
		queue_redraw()


func _draw() -> void:
	if _radius_px <= 0.0:
		return
	var half := _radius_px * QUAD_PAD
	draw_texture_rect(_quad_tex, Rect2(-half, -half, half * 2.0, half * 2.0), false)


# ---------------------------------------------------------------- rolling

## `delta_px` is the ball's on-screen movement since the last update (screen y points down).
func _roll(delta_px: Vector2) -> void:
	var dist := delta_px.length()
	if dist < 0.001 or _radius_px <= 0.0:
		return
	if dist > _radius_px * MAX_ROLL_STEP_RADII:
		return
	# View space has y up, so moving right (+x) rotates about +y, moving down on screen about +x.
	# If a ball ever appears to roll backwards, negate this axis.
	var axis := Vector3(delta_px.y, delta_px.x, 0.0) / dist
	_orient = (Basis(axis, dist / _radius_px) * _orient).orthonormalized()
	_push_orientation()


func _push_orientation() -> void:
	_material.set_shader_parameter("to_local", _orient.transposed())


func _reset_orientation() -> void:
	# Bring the chosen longitude to the front.
	_orient = Basis(Vector3.UP, -deg_to_rad(rest_longitude_deg))
	if randomize_rest_orientation:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(ball_id + 1)
		var turn := rng.randf_range(0.0, TAU)  # In-plane turn (about the view axis).
		var tilt := rng.randf_range(-0.5, 0.5)  # Radians, leans the number toward/away from view.
		_orient = Basis(Vector3(0, 0, 1), turn) * Basis(Vector3.RIGHT, tilt) * _orient
	_push_orientation()


# ---------------------------------------------------------------- assets

## Lazy so BallsLayer can set ball_id after construction (or after add_child).
func _ensure_assets() -> void:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = BALL_SHADER
		_material.set_shader_parameter("pad", QUAD_PAD)
		material = _material
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_quad_tex = ImageTexture.create_from_image(img)
	if _loaded_id == ball_id:
		return
	_loaded_id = ball_id

	var tex: Texture2D = null
	var path := TEXTURE_PATH % ball_id
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_material.set_shader_parameter("use_texture", tex != null)
	if tex != null:
		_material.set_shader_parameter("ball_tex", tex)
	else:
		var color := BALL_WHITE if ball_id == 0 else PALETTE[(ball_id - 1) % 8]
		_material.set_shader_parameter("fallback_color", color)
		_material.set_shader_parameter("fallback_stripe", ball_id >= 9)
	_reset_orientation()
	queue_redraw()
