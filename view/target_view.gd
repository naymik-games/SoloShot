class_name TargetView
extends Node2D
## Draws a TargetSpec on the table: concentric translucent rings with their point values.
## Also plays a short celebration when the player scores (play_score_effect).
## Visual only. Lives between TableView and BallsLayer so balls roll over it. Keep at (0,0).

## Fill per ring, bullseye first. Translucent so the cloth shows through.
const FILL_COLORS: Array[Color] = [
	Color(1.00, 0.80, 0.25, 0.55),  # bullseye: gold
	Color(0.85, 0.20, 0.20, 0.45),  # middle: red
	Color(1.00, 1.00, 1.00, 0.30),  # outer: white
]
const LINE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.8)
const TEXT_COLOR: Color = Color(1.0, 1.0, 1.0, 0.95)
const TEXT_OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.55)

## Score effect: how long it lasts (keep it a bit shorter than the delay between rounds), and its
## color per ring, bullseye first.
const EFFECT_TIME: float = 1.6
const EFFECT_COLORS: Array[Color] = [
	Color(1.00, 0.85, 0.30),  # bullseye
	Color(1.00, 0.45, 0.35),  # middle
	Color(1.00, 1.00, 1.00),  # outer
]
const EFFECT_SPARKS: Array[int] = [28, 16, 9]

var mapper: CoordinateMapper
var spec: TargetSpec

var _fx_time: float = -1.0  ## < 0 = no effect playing.
var _fx_points: int = 0
var _fx_ring: int = 0
var _fx_sparks: Array[Vector2] = []  ## Unit-ish direction vectors, one per spark.


func _ready() -> void:
	set_process(false)


## Pass null to hide the target. Also stops any effect that is still playing.
func set_spec(new_spec: TargetSpec) -> void:
	spec = new_spec
	stop_effect()
	queue_redraw()


## Plays the celebration on the current target. `points` picks the ring style (100/50/25);
## anything else (0 or no match) plays nothing.
func play_score_effect(points: int) -> void:
	if spec == null or points <= 0:
		return
	var ring := spec.points.find(points)
	if ring < 0:
		ring = spec.points.size() - 1
	_fx_ring = ring
	_fx_points = points
	_fx_time = 0.0
	_fx_sparks.clear()
	var count: int = EFFECT_SPARKS[mini(ring, EFFECT_SPARKS.size() - 1)]
	for i in count:
		var angle := TAU * float(i) / float(count) + randf_range(-0.2, 0.2)
		_fx_sparks.append(Vector2.from_angle(angle) * randf_range(0.7, 1.0))
	set_process(true)
	queue_redraw()


func stop_effect() -> void:
	_fx_time = -1.0
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_fx_time += delta
	if _fx_time >= EFFECT_TIME:
		stop_effect()
	else:
		queue_redraw()


func _draw() -> void:
	if spec == null or mapper == null or spec.radii.is_empty():
		return
	var center := mapper.to_screen(spec.center)
	var font := ThemeDB.fallback_font

	# Outermost first so the smaller rings paint on top.
	for i in range(spec.radii.size() - 1, -1, -1):
		var radius := mapper.length_to_screen(spec.radii[i])
		draw_circle(center, radius, FILL_COLORS[mini(i, FILL_COLORS.size() - 1)])
		draw_arc(center, radius, 0.0, TAU, 64, LINE_COLOR, maxf(1.5, radius * 0.02), true)

	# Point values, straight above the middle of each ring band.
	var font_size := int(clampf(mapper.length_to_screen(0.04), 10.0, 24.0))
	for i in spec.radii.size():
		var inner := 0.0 if i == 0 else spec.radii[i - 1]
		var mid_px := mapper.length_to_screen((inner + spec.radii[i]) * 0.5)
		if i == 0:
			mid_px = 0.0
		var baseline := center.y - mid_px + font.get_ascent(font_size) - font.get_height(font_size) * 0.5
		var origin := Vector2(center.x - 50.0, baseline)
		var text := str(spec.points[i])
		draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, 100.0, font_size, 3, TEXT_OUTLINE_COLOR)
		draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, 100.0, font_size, TEXT_COLOR)

	if _fx_time >= 0.0:
		_draw_score_effect(center, font)


func _draw_score_effect(center: Vector2, font: Font) -> void:
	var t := clampf(_fx_time / EFFECT_TIME, 0.0, 1.0)
	var color: Color = EFFECT_COLORS[mini(_fx_ring, EFFECT_COLORS.size() - 1)]
	var outer_px := mapper.length_to_screen(spec.radii[spec.radii.size() - 1])
	var burst := 1.0 - pow(1.0 - t, 3.0)  # ease-out: fast at first, then settles

	# Quick flash over the whole target.
	var flash := maxf(0.0, 1.0 - t * 3.5)
	if flash > 0.0:
		draw_circle(center, outer_px, Color(color, 0.45 * flash))

	# Two shock-wave rings expanding past the outer ring.
	for k in 2:
		var tk := clampf(t * 1.5 - float(k) * 0.22, 0.0, 1.0)
		if tk <= 0.0 or tk >= 1.0:
			continue
		var e := 1.0 - pow(1.0 - tk, 3.0)
		var r := lerpf(outer_px * 0.25, outer_px * 1.5, e)
		draw_arc(center, r, 0.0, TAU, 64, Color(color, 1.0 - tk), lerpf(6.0, 1.5, tk), true)

	# Sparks flying outward and fading.
	for dir in _fx_sparks:
		var p := center + dir * outer_px * (0.2 + burst * 1.2)
		draw_circle(p, lerpf(4.5, 1.0, t), Color(color, 1.0 - t))

	# Floating "+points" that rises and fades out.
	var big := _fx_points >= 100
	var fx_size := int(clampf(mapper.length_to_screen(0.075 if big else 0.06), 20.0, 48.0))
	var alpha := 1.0 - smoothstep(0.6, 1.0, t)
	var rise := mapper.length_to_screen(0.12) * burst
	var label := "+%d" % _fx_points
	var base_y := center.y - outer_px * 0.15 - rise + font.get_ascent(fx_size) * 0.5
	var pos := Vector2(center.x - 100.0, base_y)
	draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 200.0, fx_size, 6, Color(0, 0, 0, 0.7 * alpha))
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 200.0, fx_size, Color(color, alpha))
