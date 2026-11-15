class_name SoloPanel
extends Node2D
## Stat bar at the top of the screen for solo modes (the counterpart of PlayersPanel): a row of
## dark rounded panels, each with a gold label and a big value, a ball icon or a row of pips.
## Looks and colors are copied from PlayersPanel. Reuses BallView for the ball icons.
## Created and owned by PoolGame; keep at (0,0) so positions are screen pixels.
##
## PoolGame calls refresh() every frame with the mode's SoloStats. Cheap when nothing changed:
## panels are only rebuilt when the set of panels changes, and redrawn when a value changes or
## something animates (value pulse on change, score count-up, flashing low time).


## Everything computed for one drawn panel.
class Cell:
	var stat: SoloStat
	var rect: Rect2 = Rect2()
	var corner: float = 8.0
	var pad: float = 6.0
	var label_size: int = 12
	var label_baseline: float = 0.0
	var row_center: Vector2 = Vector2.ZERO
	var row_h: float = 0.0
	var value_size: int = 24
	var ball_r: float = 10.0
	var shown: float = 0.0  # Displayed value of a count-up number.
	var pulse: float = 0.0  # 1 right after a change, fades to 0.
	var last_key: Variant = null
	var view: BallView = null


## Panels never get wider than this (they are centered when the strip is wider).
var max_cell_width_px: float = 200.0
var panel_gap_px: float = 10.0

# Style: same values as PlayersPanel.
var panel_color: Color = Color(0.05, 0.08, 0.15, 0.85)
var accent_color: Color = Color(1.0, 0.8, 0.25)
var idle_border_color: Color = Color(1.0, 1.0, 1.0, 0.12)
var label_color: Color = Color(1.0, 0.8, 0.25)
var value_color: Color = Color(1.0, 1.0, 1.0)
var warn_color: Color = Color(1.0, 0.3, 0.25)
var slot_color: Color = Color(0.0, 0.0, 0.0, 0.45)
var slot_ring_color: Color = Color(1.0, 1.0, 1.0, 0.12)

## Seconds the "just changed" highlight lasts, and how much the value grows during it.
var pulse_seconds: float = 0.35
var pulse_scale: float = 0.25
## How fast a count-up number catches up (higher = faster).
var count_up_speed: float = 6.0

var _ball_radius_m: float = 0.02858
var _strip: Rect2 = Rect2()
var _cells: Array[Cell] = []
var _time: float = 0.0


func setup(ball_radius_m: float) -> void:
	_ball_radius_m = ball_radius_m
	set_process(false)


## `strip` is the screen-space band the whole bar may use.
func layout(strip: Rect2) -> void:
	_strip = strip
	_layout_cells()
	queue_redraw()


## Call every frame with the mode's current stats (Array of SoloStat).
func refresh(stats: Array) -> void:
	if not _same_structure(stats):
		_rebuild(stats)
		return
	var changed := false
	for i in stats.size():
		if _update_cell(_cells[i], stats[i]):
			changed = true
	if changed:
		queue_redraw()


# ---------------------------------------------------------------- build / update

func _same_structure(stats: Array) -> bool:
	if stats.size() != _cells.size():
		return false
	for i in stats.size():
		var a: SoloStat = stats[i]
		var b: SoloStat = _cells[i].stat
		if a.kind != b.kind or a.label != b.label or not is_equal_approx(a.weight, b.weight):
			return false
	return true


func _rebuild(stats: Array) -> void:
	for c in _cells:
		if c.view != null:
			remove_child(c.view)
			c.view.queue_free()
	_cells.clear()
	for item in stats:
		var s: SoloStat = item
		var c := Cell.new()
		c.stat = s
		c.last_key = _key_of(s)
		c.shown = float(s.number)
		if s.kind == SoloStat.Kind.BALL:
			var v := BallView.new()
			v.radius_m = _ball_radius_m
			v.randomize_rest_orientation = false  # Upright numbers, like the tray.
			v.ball_id = maxi(s.ball_id, 0)
			add_child(v)
			c.view = v
		_cells.append(c)
	_layout_cells()
	set_process(not _cells.is_empty())
	queue_redraw()


## Returns true if the shown value changed.
func _update_cell(c: Cell, s: SoloStat) -> bool:
	c.stat = s
	var key: Variant = _key_of(s)
	var changed: bool = key != c.last_key
	if changed:
		c.last_key = key
		c.pulse = 1.0
		_place_ball(c)
	return changed


func _key_of(s: SoloStat) -> Variant:
	match s.kind:
		SoloStat.Kind.BALL:
			return s.ball_id
		SoloStat.Kind.PIPS:
			return s.pips_steps
	return s.number if s.count_up else s.text


func _layout_cells() -> void:
	if _cells.is_empty() or _strip.size.x <= 0.0 or _strip.size.y <= 0.0:
		return
	var font := ThemeDB.fallback_font
	var n := _cells.size()
	var weights := 0.0
	for c in _cells:
		weights += maxf(c.stat.weight, 0.01)
	var gaps := panel_gap_px * float(n - 1)
	var unit := minf((_strip.size.x - gaps) / weights, max_cell_width_px)
	var x := _strip.get_center().x - (unit * weights + gaps) * 0.5
	var h := _strip.size.y
	var pad := maxf(4.0, h * 0.09)

	for c in _cells:
		var w := unit * maxf(c.stat.weight, 0.01)
		c.rect = Rect2(x, _strip.position.y, w, h)
		x += w + panel_gap_px
		c.pad = pad
		c.corner = minf(10.0, h * 0.18)

		# Label row on top (if any), the value / ball / pips underneath.
		var row_top := c.rect.position.y + pad
		if not c.stat.label.is_empty():
			c.label_size = int(clampf(h * 0.2, 10.0, 15.0))
			c.label_baseline = row_top + font.get_ascent(c.label_size)
			row_top += font.get_height(c.label_size) + 2.0
		c.row_h = maxf(c.rect.end.y - pad - row_top, 4.0)
		c.row_center = Vector2(c.rect.get_center().x, row_top + c.row_h * 0.5)
		c.value_size = int(clampf(c.row_h * 0.8, 12.0, 34.0))
		c.ball_r = maxf(minf(c.row_h * 0.5, w * 0.4), 1.0)
		_place_ball(c)


func _place_ball(c: Cell) -> void:
	if c.view == null:
		return
	if c.stat.ball_id < 0 or c.rect.size.x <= 0.0:
		c.view.visible = false
		return
	c.view.ball_id = c.stat.ball_id
	c.view.show_static(c.row_center, c.ball_r)


# ---------------------------------------------------------------- animation

func _process(delta: float) -> void:
	_time += delta
	var dirty := false
	for c in _cells:
		if c.pulse > 0.0:
			c.pulse = maxf(c.pulse - delta / pulse_seconds, 0.0)
			dirty = true
		if c.stat.count_up:
			var target := float(c.stat.number)
			var diff := target - c.shown
			if absf(diff) > 0.0:
				if absf(diff) < 1.0:
					c.shown = target
				else:
					c.shown += diff * minf(delta * count_up_speed, 1.0)
				dirty = true
		if c.stat.warn:
			dirty = true
	if dirty:
		queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var font := ThemeDB.fallback_font
	for c in _cells:
		var s := c.stat
		var p := c.pulse

		if s.accent:
			var glow := StyleBoxFlat.new()
			glow.bg_color = Color(0.0, 0.0, 0.0, 0.0)
			glow.border_color = Color(accent_color, 0.3)
			glow.set_border_width_all(6)
			glow.set_corner_radius_all(int(c.corner) + 3)
			glow.anti_aliasing = true
			draw_style_box(glow, c.rect.grow(3.0))

		var body := StyleBoxFlat.new()
		body.bg_color = panel_color
		if s.accent:
			body.border_color = accent_color
			body.set_border_width_all(3)
		else:
			body.border_color = idle_border_color.lerp(accent_color, p)
			body.set_border_width_all(1 + roundi(2.0 * p))
		body.set_corner_radius_all(int(c.corner))
		body.anti_aliasing = true
		draw_style_box(body, c.rect)

		if not s.label.is_empty():
			draw_string(font, Vector2(c.rect.position.x, c.label_baseline), s.label,
					HORIZONTAL_ALIGNMENT_CENTER, c.rect.size.x, c.label_size, label_color)

		match s.kind:
			SoloStat.Kind.TEXT:
				_draw_value(c, font)
			SoloStat.Kind.BALL:
				_draw_ball_slot(c)
			SoloStat.Kind.PIPS:
				_draw_pips(c)


func _draw_value(c: Cell, font: Font) -> void:
	var s := c.stat
	var text := str(roundi(c.shown)) if s.count_up else s.text
	var size := roundi(float(c.value_size) * (1.0 + pulse_scale * c.pulse))
	var col := value_color
	if s.tint.a > 0.0:
		col = s.tint
	col = col.lerp(accent_color, c.pulse * 0.6)
	if s.warn:
		col = col.lerp(warn_color, 0.5 + 0.5 * sin(_time * 10.0))
	var baseline := c.row_center.y + font.get_ascent(size) - font.get_height(size) * 0.5
	draw_string(font, Vector2(c.rect.position.x, baseline), text,
			HORIZONTAL_ALIGNMENT_CENTER, c.rect.size.x, size, col)


## Dark socket behind the ball (the BallView child draws the ball over it).
func _draw_ball_slot(c: Cell) -> void:
	var r := c.ball_r * (1.0 + 0.12 * c.pulse)
	draw_circle(c.row_center, r * 1.12, slot_color)
	draw_arc(c.row_center, r * 1.12, 0.0, TAU, 32, slot_ring_color, 1.0, true)


## Circles that fill in half steps: half, full, then the next circle starts as a half, ...
func _draw_pips(c: Cell) -> void:
	var n := c.stat.pips_total
	if n <= 0:
		return
	var r := minf(c.row_h * 0.4, (c.rect.size.x - 2.0 * c.pad) / (float(n) * 2.6))
	r = maxf(r, 2.0)
	var step := r * 2.6
	var x0 := c.row_center.x - step * float(n - 1) * 0.5
	for i in n:
		var ctr := Vector2(x0 + float(i) * step, c.row_center.y)
		draw_circle(ctr, r, slot_color)
		var fill := clampf((float(c.stat.pips_steps) - 2.0 * float(i)) / 2.0, 0.0, 1.0)
		if fill >= 1.0:
			draw_circle(ctr, r - 1.0, accent_color)
		elif fill > 0.0:
			# Left half of the circle.
			var pts := PackedVector2Array()
			for k in 13:
				var ang := PI * 0.5 + PI * float(k) / 12.0
				pts.append(ctr + Vector2(cos(ang), sin(ang)) * (r - 1.0))
			draw_colored_polygon(pts, accent_color)
		draw_arc(ctr, r, 0.0, TAU, 24, slot_ring_color, 1.0, true)
