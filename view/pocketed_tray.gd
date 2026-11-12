class_name PocketedTray
extends Node2D
## Row of mini balls in the band above the table showing which balls are pocketed, in the order
## they dropped. Built from PocketedLog + the live SimState. Reuses BallView, so the balls match
## the table art. Created and owned by PoolGame; keep at (0,0) so positions are screen pixels.

## Tray ball size relative to the balls on the table.
var ball_scale: float = 1.0
## Distance between ball centers, in ball radii (2.0 = touching).
var spacing_radii: float = 2.4
## Show the numbers upright instead of the random resting tilt used on the table.
var upright_numbers: bool = true
## Backing pill drawn behind the balls.
var panel_color: Color = Color(0.35, 0.35, 0.35, 0.624)
var panel_padding_radii: float = .5

var _log: PocketedLog
var _state: SimState
var _mapper: CoordinateMapper
var _ball_radius_m: float = 0.02858
var _strip: Rect2 = Rect2()
var _views: Dictionary = {}  # ball id -> BallView
var _panel_rect: Rect2 = Rect2()
var _panel_corner: float = 0.0


func setup(log: PocketedLog, state: SimState, ball_radius_m: float, mapper: CoordinateMapper) -> void:
	_log = log
	_state = state
	_ball_radius_m = ball_radius_m
	_mapper = mapper
	refresh()


## `strip` is the screen-space band the tray may use (balls are centered inside it).
func layout(strip: Rect2) -> void:
	_strip = strip
	refresh()


## Rebuild the row from the log and the current ball states.
func refresh() -> void:
	if _log == null or _state == null or _mapper == null or _strip.size.x <= 0.0:
		return

	var ids := _log.visible_ids(_state)

	# Drop views for balls that are no longer shown (e.g. respotted).
	for id in _views.keys():
		if not ids.has(id):
			_views[id].queue_free()
			_views.erase(id)

	var n := ids.size()
	if n == 0:
		_panel_rect = Rect2()
		queue_redraw()
		return

	var r := minf(_mapper.length_to_screen(_ball_radius_m) * ball_scale, _strip.size.y * 0.4)
	r = maxf(r, 1.0)
	var step := r * spacing_radii
	var max_width := _strip.size.x * 0.95
	if n > 1 and step * (n - 1) + 2.0 * r > max_width:
		step = (max_width - 2.0 * r) / float(n - 1)  # Squeeze (overlap) rather than overflow.

	var total := step * (n - 1)
	var center := _strip.get_center()
	for i in n:
		var id := ids[i]
		var view: BallView = _views.get(id)
		if view == null:
			view = _create_view(id)
		view.show_static(Vector2(center.x - total * 0.5 + i * step, center.y), r)

	var pad := r * panel_padding_radii
	_panel_rect = Rect2(
		center.x - total * 0.5 - r - pad,
		center.y - r - pad,
		total + 2.0 * r + 2.0 * pad,
		2.0 * (r + pad))
	_panel_corner = r + pad
	queue_redraw()


func _draw() -> void:
	if _panel_rect.size.x <= 0.0:
		return
	var box := StyleBoxFlat.new()
	box.bg_color = panel_color
	box.set_corner_radius_all(int(_panel_corner))
	box.anti_aliasing = true
	draw_style_box(box, _panel_rect)


func _create_view(id: int) -> BallView:
	var view := BallView.new()
	view.ball_id = id
	view.radius_m = _ball_radius_m
	view.randomize_rest_orientation = not upright_numbers
	add_child(view)
	_views[id] = view
	return view
