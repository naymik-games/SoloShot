class_name CoinFlipOverlay
extends Control
## Full-screen coin toss that decides which seat breaks. PoolGame decides the winner up front
## (so the result is fair and testable); this node only plays the animation and then emits
## `finished(starter_index)`. It covers everything while it plays, then fades out to reveal the table.
##
## Tap/click: first tap skips to the landed coin, second tap ends the overlay.
## Two seats only (a coin has two faces).

signal finished(starter_index: int)

@export var background_color: Color = Color("#1d263b")  # Same as TableView.background_color.
@export var rim_color: Color = Color(0.95, 0.78, 0.25)
@export var highlight_color: Color = Color(1.0, 0.8, 0.25)
@export var title: String = "Coin toss"
## Seconds the coin sits still before it is tossed.
@export var lead_in: float = 0.4
@export var toss_time: float = 1.7
## Seconds the result stays up after the coin lands.
@export var hold_time: float = 1.1
@export var fade_time: float = 0.4
## Half-turns the coin makes. Even number; one more is added when seat 2 wins so the
## coin lands on that player's face.
@export var half_turns: int = 8

var _names: Array[String] = []
var _colors: Array[Color] = []
var _winner: int = 0
var _elapsed: float = 0.0
var _fade_elapsed: float = 0.0
var _fading: bool = false


## `names` and `colors` hold one entry per seat (face 0 = seat 1, face 1 = seat 2).
func setup(names: Array[String], colors: Array[Color], winner: int) -> void:
	_names = names
	_colors = colors
	_winner = clampi(winner, 0, 1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP  # Nothing underneath reacts while the coin is up.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)


## Anchors would resolve against the parent, and the "UI" node can be a zero-size Control, which
## put the coin at (0, 0). Size the overlay from the viewport instead.
func _fit_to_viewport() -> void:
	global_position = Vector2.ZERO
	size = get_viewport_rect().size
	queue_redraw()


func _process(delta: float) -> void:
	if _fading:
		_fade_elapsed += delta
		modulate.a = clampf(1.0 - _fade_elapsed / maxf(fade_time, 0.01), 0.0, 1.0)
		if _fade_elapsed >= fade_time:
			queue_free()
		return
	_elapsed += delta
	if _elapsed >= lead_in + toss_time + hold_time:
		_begin_fade()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Mouse only: touches arrive as emulated mouse clicks, so handling both would double-fire.
	if not (event is InputEventMouseButton and event.pressed):
		return
	if _fading:
		return
	var landed_at := lead_in + toss_time
	if _elapsed < landed_at:
		_elapsed = landed_at
	else:
		_begin_fade()


func _begin_fade() -> void:
	if _fading:
		return
	_fading = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	finished.emit(_winner)  # The game starts while the overlay fades away.


func _draw() -> void:
	if _names.size() < 2 or _colors.size() < 2:
		return
	var font := ThemeDB.fallback_font
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), background_color)

	var r := clampf(minf(sz.x, sz.y) * 0.11, 36.0, 80.0)
	var ground := Vector2(sz.x * 0.5, sz.y * 0.52)
	var rise := sz.y * 0.22

	var t := clampf((_elapsed - lead_in) / toss_time, 0.0, 1.0)
	var lift := sin(PI * t) * rise
	var spin_t := 1.0 - pow(1.0 - t, 2.0)  # Spin slows down as the coin comes down.
	var angle := PI * float(half_turns + _winner) * spin_t
	var squash_x := absf(cos(angle))
	var face := 0 if cos(angle) >= 0.0 else 1
	var land_t := _elapsed - lead_in - toss_time
	var landed := land_t >= 0.0
	var pulse := 1.0
	if landed and land_t < 0.25:
		pulse = 1.0 + 0.1 * sin(land_t / 0.25 * PI)

	# Title.
	var title_size := int(clampf(r * 0.55, 18.0, 34.0))
	draw_string(font, Vector2(0.0, sz.y * 0.14), title, HORIZONTAL_ALIGNMENT_CENTER,
			sz.x, title_size, Color(1, 1, 1, 0.85))

	# Shadow on the "table": shrinks and fades as the coin rises.
	var sh := 1.0 - 0.4 * (lift / rise)
	draw_set_transform(ground + Vector2(0.0, r * 1.05), 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, r * sh, Color(0, 0, 0, 0.35 * sh))

	# The coin: flattened horizontally by the flip (never fully to 0, so the edge stays visible).
	var center := ground - Vector2(0.0, lift)
	draw_set_transform(center, 0.0, Vector2(maxf(squash_x, 0.05) * pulse, pulse))
	var face_color := _colors[face]
	draw_circle(Vector2.ZERO, r, rim_color)
	draw_circle(Vector2.ZERO, r * 0.86, face_color)
	draw_arc(Vector2.ZERO, r * 0.86, 0.0, TAU, 40, Color(0, 0, 0, 0.25), 2.0, true)
	_draw_silhouette(r * 1.2, Color(0.05, 0.1, 0.22))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Which face is which: a chip and the name on either side of the coin.
	var name_size := int(clampf(r * 0.3, 14.0, 26.0))
	for i in 2:
		var x := ground.x + (-1.0 if i == 0 else 1.0) * r * 3.0
		var is_winner := landed and i == _winner
		var dim := 1.0 if (not landed or is_winner) else 0.4
		var chip_y := ground.y + r * 2.1
		draw_circle(Vector2(x, chip_y), r * 0.3, Color(_colors[i], dim))
		if is_winner:
			draw_arc(Vector2(x, chip_y), r * 0.3 + 4.0, 0.0, TAU, 32, highlight_color, 3.0, true)
		var name_color := highlight_color if is_winner else Color(1, 1, 1, 0.85 * dim)
		draw_string(font, Vector2(x - r * 1.4, chip_y + r * 0.3 + name_size + 6.0), _names[i],
				HORIZONTAL_ALIGNMENT_CENTER, r * 2.8, name_size, name_color)

	# Result line.
	if landed:
		var a := clampf(land_t / 0.25, 0.0, 1.0)
		var res_size := int(clampf(r * 0.6, 22.0, 44.0))
		draw_string(font, Vector2(0.0, ground.y + r * 3.8), "%s breaks!" % _names[_winner],
				HORIZONTAL_ALIGNMENT_CENTER, sz.x, res_size, Color(highlight_color, a))


## Head and shoulders, centred on the current draw transform. `s` is the tile size.
func _draw_silhouette(s: float, color: Color) -> void:
	draw_circle(Vector2(0.0, -s * 0.14), s * 0.19, color)
	var base_y := s * 0.5
	var rx := s * 0.36
	var ry := s * 0.30
	var pts := PackedVector2Array()
	var steps := 16
	for k in steps + 1:
		var ang := PI + PI * float(k) / float(steps)
		pts.append(Vector2(rx * cos(ang), base_y + ry * sin(ang)))
	draw_colored_polygon(pts, color)
