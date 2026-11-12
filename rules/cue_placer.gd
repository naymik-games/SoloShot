class_name CuePlacer
extends RefCounted
## Rules for where the cue ball may sit: inside the playfield (and the placement region, if any),
## clear of every other ball, and clear of the pocket mouths. Pure functions, no state.
## Positions are table meters (cue ball center).

## Extra clearance kept between the cue ball and other balls (meters).
const BALL_GAP: float = 0.0003
## Extra clearance kept between the cue ball and a pocket's capture radius (meters).
const POCKET_MARGIN: float = 0.002
## Tolerance for float comparisons.
const EPS: float = 0.00005


## Rectangle the cue ball's center must stay inside.
static func allowed_rect(table: TableDef, placement: CuePlacement) -> Rect2:
	var r := table.ball_radius
	var rect := Rect2(r, r, table.size.x - 2.0 * r, table.size.y - 2.0 * r)
	if placement != null and placement.mode == CuePlacement.Mode.LIMITED:
		rect = rect.intersection(placement.region)
	return rect


static func is_valid(pos: Vector2, state: SimState, table: TableDef, placement: CuePlacement) -> bool:
	var rect := allowed_rect(table, placement)
	if pos.x < rect.position.x - EPS or pos.x > rect.end.x + EPS:
		return false
	if pos.y < rect.position.y - EPS or pos.y > rect.end.y + EPS:
		return false

	var min_ball := 2.0 * table.ball_radius + BALL_GAP
	for b in state.balls:
		if b.id == ShotReport.CUE_ID or not b.is_on_table():
			continue
		if pos.distance_to(b.pos) < min_ball - EPS:
			return false

	for pocket in table.pockets:
		var c: Vector2 = pocket.center
		var capture: float = pocket.capture_radius
		if pos.distance_to(c) < capture + POCKET_MARGIN - EPS:
			return false
	return true


## Nudges `pos` toward a legal spot: clamps into the allowed rectangle and pushes the ball out of
## other balls and pocket mouths. Used while dragging so the cue ball slides around obstacles.
## The result is not guaranteed legal (e.g. a squeezed corner) - check is_valid().
static func constrain(pos: Vector2, state: SimState, table: TableDef, placement: CuePlacement) -> Vector2:
	var rect := allowed_rect(table, placement)
	var min_ball := 2.0 * table.ball_radius + BALL_GAP
	var p := pos
	for _i in 8:
		p = Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
		var moved := false
		for b in state.balls:
			if b.id == ShotReport.CUE_ID or not b.is_on_table():
				continue
			if p.distance_to(b.pos) < min_ball:
				p = b.pos + _direction(p - b.pos) * (min_ball + EPS)
				moved = true
		for pocket in table.pockets:
			var c: Vector2 = pocket.center
			var clear: float = float(pocket.capture_radius) + POCKET_MARGIN
			if p.distance_to(c) < clear:
				p = c + _direction(p - c) * (clear + EPS)
				moved = true
		if not moved:
			break
	return p


## Nearest legal position to `target` (used for FIXED respots when the spot is occupied).
static func find_free_position(target: Vector2, state: SimState, table: TableDef, placement: CuePlacement) -> Vector2:
	var p := constrain(target, state, table, placement)
	if is_valid(p, state, table, placement):
		return p
	var step := table.ball_radius * 0.5
	for ring in range(1, 80):
		var radius := float(ring) * step
		for k in 32:
			var candidate := target + Vector2.from_angle(TAU * float(k) / 32.0) * radius
			if is_valid(candidate, state, table, placement):
				return candidate
	return p


## True if a ball centered at `pos` would touch or overlap another ball on the table.
static func overlaps_other_ball(pos: Vector2, state: SimState, table: TableDef) -> bool:
	var min_ball := 2.0 * table.ball_radius + BALL_GAP
	for b in state.balls:
		if b.id == ShotReport.CUE_ID or not b.is_on_table():
			continue
		if pos.distance_to(b.pos) < min_ball:
			return true
	return false


## Puts the cue ball on the table, at rest, at `pos`.
static func set_cue_ball(cue: BallState, pos: Vector2) -> void:
	cue.pos = pos
	cue.vel = Vector2.ZERO
	cue.status = BallState.Status.ON_TABLE
	cue.rolling = false


static func _direction(v: Vector2) -> Vector2:
	if v.length_squared() < 1e-10:
		return Vector2.RIGHT
	return v.normalized()
