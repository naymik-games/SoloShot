class_name PlayersPanel
extends Node2D
## Player section at the top of the screen for multi-player games: for each player an avatar
## placeholder, their name, their group (solids / stripes) and the balls of that group they have
## pocketed so far. The player whose turn it is gets a bright frame and the others are dimmed.
## Reuses BallView, like the pocketed tray. Created and owned by PoolGame; keep at (0,0) so
## positions are screen pixels.


## What the panel shows for one player. PoolGame fills these from the Players and the mode.
class Seat:
	var display_name: String = ""
	## "Solids", "Stripes", ... or "" while the player has no group.
	var group_name: String = ""
	## Ids of the balls in this player's group (empty until the group is known).
	var group_balls: Array[int] = []


## Everything computed for one drawn panel (rebuilt by _rebuild).
class PanelLayout:
	var index: int = 0
	var active: bool = false
	var display_name: String = ""
	var group_name: String = ""
	var rect: Rect2
	var avatar_rect: Rect2
	var corner: float = 8.0
	var text_x: float = 0.0
	var text_w: float = 0.0
	var name_size: int = 16
	var name_baseline: float = 0.0
	var slot_centers: PackedVector2Array = PackedVector2Array()
	var slot_r: float = 10.0


## Slots shown per player (a group is seven balls).
const SLOT_COUNT: int = 7

## Pocketed-ball size relative to the balls on the table.
var ball_scale: float = 1.0
## Distance between slot centers, in ball radii (2.0 = touching).
var spacing_radii: float = 2.4
## Gap between the two player panels.
var panel_gap_px: float = 14.0
var panel_color: Color = Color(0.05, 0.08, 0.15, 0.85)
## Frame, name and glow of the player whose turn it is.
var active_color: Color = Color(1.0, 0.8, 0.25)
var idle_border_color: Color = Color(1.0, 1.0, 1.0, 0.12)
## How strongly the player who is not shooting is faded (1 = not at all).
var inactive_alpha: float = 0.55
## Placeholder avatar backgrounds, one per player (wraps around).
var avatar_colors: Array[Color] = [Color(0.16, 0.55, 0.95), Color(0.93, 0.45, 0.25)]
var avatar_silhouette_color: Color = Color(0.05, 0.1, 0.22)

var _log: PocketedLog
var _state: SimState
var _mapper: CoordinateMapper
var _ball_radius_m: float = 0.02858
var _strip: Rect2 = Rect2()
var _seats: Array = []
var _current: int = 0
var _views: Array[BallView] = []
var _panels: Array[PanelLayout] = []


func setup(log: PocketedLog, state: SimState, ball_radius_m: float, mapper: CoordinateMapper) -> void:
	_log = log
	_state = state
	_ball_radius_m = ball_radius_m
	_mapper = mapper
	_rebuild()


## `strip` is the screen-space band the whole section may use; the panels share it equally.
func layout(strip: Rect2) -> void:
	_strip = strip
	_rebuild()


## `seats` holds one PlayersPanel.Seat per player, `current_index` is whose turn it is.
func refresh(seats: Array, current_index: int) -> void:
	_seats = seats
	_current = current_index
	_rebuild()


func _rebuild() -> void:
	for v in _views:
		remove_child(v)
		v.queue_free()
	_views.clear()
	_panels.clear()
	if _log == null or _state == null or _mapper == null or _seats.is_empty() \
			or _strip.size.x <= 0.0 or _strip.size.y <= 0.0:
		queue_redraw()
		return

	var font := ThemeDB.fallback_font
	var n := _seats.size()
	var panel_w := (_strip.size.x - panel_gap_px * (n - 1)) / float(n)
	var h := _strip.size.y
	var pad := maxf(4.0, h * 0.09)
	var avatar := maxf(h - 2.0 * pad, 1.0)
	var pocketed := _log.visible_ids(_state)  # Every pocketed ball, in the order they dropped.

	for i in n:
		var seat: Seat = _seats[i]
		var p := PanelLayout.new()
		p.index = i
		p.active = (i == _current)
		p.display_name = seat.display_name
		p.group_name = seat.group_name
		p.rect = Rect2(_strip.position.x + i * (panel_w + panel_gap_px), _strip.position.y, panel_w, h)
		p.corner = minf(10.0, h * 0.18)
		p.avatar_rect = Rect2(p.rect.position + Vector2(pad, pad), Vector2(avatar, avatar))
		p.text_x = p.avatar_rect.end.x + pad * 1.5
		p.text_w = maxf(p.rect.end.x - pad - p.text_x, 1.0)

		# Name row on top, ball slots underneath.
		p.name_size = int(clampf(h * 0.24, 11.0, 20.0))
		p.name_baseline = p.rect.position.y + pad + font.get_ascent(p.name_size)
		var row_top := p.rect.position.y + pad + font.get_height(p.name_size) + 2.0
		var row_h := maxf(p.rect.end.y - pad - row_top, 4.0)
		var r := minf(_mapper.length_to_screen(_ball_radius_m) * ball_scale, row_h * 0.5)
		r = minf(r, p.text_w / (float(SLOT_COUNT) * spacing_radii))
		r = maxf(r, 1.0)
		p.slot_r = r
		var step := minf(r * spacing_radii, (p.text_w - 2.0 * r) / float(SLOT_COUNT - 1))
		step = maxf(step, 0.0)
		var cy := row_top + row_h * 0.5
		for s in SLOT_COUNT:
			p.slot_centers.append(Vector2(p.text_x + r + s * step, cy))

		# This player's pocketed balls fill the slots left to right, in drop order.
		var mine: Array[int] = []
		for id in pocketed:
			if seat.group_balls.has(id):
				mine.append(id)
		for s in mini(mine.size(), SLOT_COUNT):
			var view := _create_view(mine[s])
			view.show_static(p.slot_centers[s], r)
			view.modulate = Color(1.0, 1.0, 1.0, 1.0 if p.active else inactive_alpha)
		_panels.append(p)
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for p in _panels:
		var a := 1.0 if p.active else inactive_alpha

		# Glow behind the active player's frame.
		if p.active:
			var glow := StyleBoxFlat.new()
			glow.bg_color = Color(0.0, 0.0, 0.0, 0.0)
			glow.border_color = Color(active_color, 0.3)
			glow.set_border_width_all(6)
			glow.set_corner_radius_all(int(p.corner) + 3)
			glow.anti_aliasing = true
			draw_style_box(glow, p.rect.grow(3.0))

		var body := StyleBoxFlat.new()
		body.bg_color = Color(panel_color, panel_color.a * (1.0 if p.active else 0.8))
		body.border_color = active_color if p.active else idle_border_color
		body.set_border_width_all(3 if p.active else 1)
		body.set_corner_radius_all(int(p.corner))
		body.anti_aliasing = true
		draw_style_box(body, p.rect)

		# Avatar placeholder: coloured tile with a head-and-shoulders silhouette.
		var av_box := StyleBoxFlat.new()
		av_box.bg_color = Color(avatar_colors[p.index % avatar_colors.size()], a)
		av_box.set_corner_radius_all(int(p.avatar_rect.size.x * 0.12))
		av_box.anti_aliasing = true
		draw_style_box(av_box, p.avatar_rect)
		_draw_silhouette(p.avatar_rect, Color(avatar_silhouette_color, a))

		# Name (left) and group (right) on the top row.
		var name_color := active_color if p.active else Color(1.0, 1.0, 1.0, a)
		draw_string(font, Vector2(p.text_x, p.name_baseline), p.display_name,
				HORIZONTAL_ALIGNMENT_LEFT, p.text_w * 0.6, p.name_size, name_color)
		if not p.group_name.is_empty():
			draw_string(font, Vector2(p.text_x, p.name_baseline), p.group_name,
					HORIZONTAL_ALIGNMENT_RIGHT, p.text_w, p.name_size - 3, Color(1.0, 1.0, 1.0, 0.7 * a))

		# Empty slots; pocketed balls (BallViews) are drawn over them as children.
		for c in p.slot_centers:
			draw_circle(c, p.slot_r, Color(0.0, 0.0, 0.0, 0.45))
			draw_arc(c, p.slot_r, 0.0, TAU, 24, Color(1.0, 1.0, 1.0, 0.12 * a), 1.0, true)


func _draw_silhouette(box: Rect2, color: Color) -> void:
	var s := box.size.x
	var cx := box.get_center().x
	draw_circle(Vector2(cx, box.position.y + s * 0.36), s * 0.19, color)
	# Shoulders: the top half of an ellipse standing on the bottom edge of the tile.
	var base_y := box.end.y - 1.0
	var rx := s * 0.36
	var ry := s * 0.30
	var pts := PackedVector2Array()
	var steps := 16
	for k in steps + 1:
		var ang := PI + PI * float(k) / float(steps)
		pts.append(Vector2(cx + rx * cos(ang), base_y + ry * sin(ang)))
	draw_colored_polygon(pts, color)


func _create_view(id: int) -> BallView:
	var view := BallView.new()
	view.ball_id = id
	view.radius_m = _ball_radius_m
	view.randomize_rest_orientation = false  # Upright numbers, like the tray.
	add_child(view)
	_views.append(view)
	return view
