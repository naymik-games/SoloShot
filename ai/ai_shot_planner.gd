class_name AiShotPlanner
extends RefCounted
## Shot selection for the computer opponent: pure functions, no state, no randomness.
## (The controller adds the aim noise afterwards.)
##
## For every legal target ball and every pocket it builds the classic "ghost ball" shot:
##   ghost = the spot the cue ball's center must reach, 2 radii behind the target on the line to the pocket.
## A shot is makeable when the pocket is entered at a sane angle, the cut is not too thin, the ghost
## is on the table, and no ball sits on the cue ball's path or on the target's path to the pocket.
## Power comes from the same friction model as the simulator (sliding, then rolling), so the object
## ball arrives at the pocket with a little speed to spare.
##
## All positions are table meters.

class Candidate extends RefCounted:
	var target_id: int = -1
	var pocket_index: int = -1
	## Unit vector from the cue ball toward the ghost ball (before noise).
	var direction: Vector2 = Vector2.RIGHT
	## 0..1 (before noise).
	var power: float = 0.5
	var cut_deg: float = 0.0
	## Lower is better.
	var score: float = INF
	## Safe hits only: false when every line to every legal ball is blocked (the shot will likely foul).
	var clear: bool = true


# ---------------------------------------------------------------- pocketing shots

## Every makeable shot from `cue_pos` at one of the `targets` (ball ids).
static func find_candidates(cue_pos: Vector2, state: SimState, table: TableDef, params: PhysicsParams,
		cfg: AiConfig, targets: Array[int]) -> Array:
	var found: Array = []
	var r := table.ball_radius
	var diameter := 2.0 * r
	var clearance := diameter * cfg.path_clearance
	var min_cos_cut := cos(deg_to_rad(cfg.max_cut_deg))

	for id in targets:
		var ball := state.get_ball(id)
		if ball == null or not ball.is_on_table():
			continue
		for k in table.pockets.size():
			var pocket = table.pockets[k]
			var pocket_pos: Vector2 = pocket.center
			var to_pocket := pocket_pos - ball.pos
			var pocket_dist := to_pocket.length()
			if pocket_dist < diameter:
				continue
			var pocket_dir := to_pocket / pocket_dist

			# Entering the pocket: the ball's path against the pocket's axis.
			var side := _is_side_pocket(pocket_pos, table)
			var axis := _pocket_axis(pocket_pos, table)
			var entry_deg := rad_to_deg(acos(clampf(pocket_dir.dot(axis), -1.0, 1.0)))
			var max_entry := cfg.max_side_entry_deg if side else cfg.max_corner_entry_deg
			if entry_deg > max_entry:
				continue

			# Ghost ball: must be reachable by the cue ball's center.
			var ghost := ball.pos - pocket_dir * diameter
			if ghost.x < r or ghost.x > table.size.x - r or ghost.y < r or ghost.y > table.size.y - r:
				continue
			var to_ghost := ghost - cue_pos
			var cue_dist := to_ghost.length()
			if cue_dist < 1e-4:
				continue
			var aim := to_ghost / cue_dist
			var cos_cut := aim.dot(pocket_dir)
			if cos_cut < min_cos_cut:
				continue

			# Both paths must be clear (the cue ball is not an obstacle to itself, the target is not
			# an obstacle on its own path).
			if _path_blocked(state, id, cue_pos, ghost, clearance):
				continue
			if _path_blocked(state, id, ball.pos, pocket_pos, clearance):
				continue

			var power := required_power(cue_dist, pocket_dist, cos_cut, params, cfg)
			if power < 0.0:
				continue  # Out of reach even at full power.

			var c := Candidate.new()
			c.target_id = id
			c.pocket_index = k
			c.direction = aim
			c.power = power
			c.cut_deg = rad_to_deg(acos(clampf(cos_cut, -1.0, 1.0)))
			c.score = c.cut_deg * cfg.cut_weight \
					+ entry_deg * cfg.entry_weight \
					+ (cue_dist + pocket_dist) / table.size.x * cfg.distance_weight
			found.append(c)
	return found


## The lowest-scoring makeable shot, or null if there is none.
static func best_candidate(cue_pos: Vector2, state: SimState, table: TableDef, params: PhysicsParams,
		cfg: AiConfig, targets: Array[int]) -> Candidate:
	var best: Candidate = null
	for found in find_candidates(cue_pos, state, table, params, cfg, targets):
		var c := found as Candidate
		if best == null or c.score < best.score:
			best = c
	return best


# ---------------------------------------------------------------- no makeable shot / break

## Nothing can be pocketed: hit a legal ball firmly enough that something reaches a cushion.
## Tries several contact points around each legal ball (full hit first, then up to a 70 degree cut)
## so the cue ball's path is clear of every other ball, e.g. the 8 sitting behind a legal ball.
## If every line is blocked, aims straight at the nearest legal ball and marks the shot `clear = false`.
## Null only if there is no legal ball at all.
static func safe_hit(cue_pos: Vector2, state: SimState, table: TableDef, cfg: AiConfig,
		targets: Array[int]) -> Candidate:
	var r := table.ball_radius
	var diameter := 2.0 * r
	var clearance := diameter * cfg.path_clearance
	var best: Candidate = null
	var best_key := INF
	var blocked_best: Candidate = null
	var blocked_dist := INF

	for id in targets:
		var ball := state.get_ball(id)
		if ball == null or not ball.is_on_table():
			continue
		var to_cue := cue_pos - ball.pos
		var dist := to_cue.length()
		if dist < 1e-4:
			continue
		var base_angle := to_cue.angle()

		# Remember the plain straight line as the last resort.
		if dist < blocked_dist:
			blocked_dist = dist
			blocked_best = Candidate.new()
			blocked_best.target_id = id
			blocked_best.direction = -to_cue / dist
			blocked_best.power = cfg.safe_hit_power
			blocked_best.clear = false

		for step in range(-7, 8):
			var offset := deg_to_rad(10.0 * float(step))
			# Where the cue ball's center is at the moment of contact.
			var contact := ball.pos + Vector2.from_angle(base_angle + offset) * diameter
			if contact.x < r or contact.x > table.size.x - r or contact.y < r or contact.y > table.size.y - r:
				continue
			var to_contact := contact - cue_pos
			var d := to_contact.length()
			if d < 1e-4:
				continue
			if _path_blocked(state, id, cue_pos, contact, clearance):
				continue
			# Prefer a fuller hit and a shorter trip.
			var key := d / table.size.x + absf(float(step)) * 0.05
			if key < best_key:
				best_key = key
				best = Candidate.new()
				best.target_id = id
				best.direction = to_contact / d
				best.power = cfg.safe_hit_power
				best.score = key

	if best != null:
		return best
	if blocked_best != null:
		blocked_best.score = 100.0 + blocked_dist
	return blocked_best


## The break: drive straight at the nearest legal ball (the head ball of the rack), full power.
static func break_shot(cue_pos: Vector2, state: SimState, targets: Array[int], cfg: AiConfig) -> Candidate:
	var best: Candidate = null
	var best_dist := INF
	for id in targets:
		var ball := state.get_ball(id)
		if ball == null or not ball.is_on_table():
			continue
		var dist := ball.pos.distance_to(cue_pos)
		if dist < best_dist and dist > 1e-4:
			best_dist = dist
			best = Candidate.new()
			best.target_id = id
			best.direction = (ball.pos - cue_pos) / dist
			best.power = cfg.break_power
	return best


# ---------------------------------------------------------------- ball in hand

## The best spot for the cue ball inside what `placement` allows: the grid point from which the
## best pocketing shot scores lowest. Falls back to the placement's own spot when no point offers a shot.
static func choose_cue_spot(state: SimState, table: TableDef, params: PhysicsParams, cfg: AiConfig,
		placement: CuePlacement, targets: Array[int]) -> Vector2:
	var fallback := CuePlacer.find_free_position(placement.spot, state, table, placement)
	var rect := CuePlacer.allowed_rect(table, placement)
	var cols := maxi(cfg.placement_grid.x, 1)
	var rows := maxi(cfg.placement_grid.y, 1)
	var best_spot := fallback
	var best_score := INF
	for ix in cols:
		for iy in rows:
			var pos := rect.position + Vector2(
					(float(ix) + 0.5) / float(cols) * rect.size.x,
					(float(iy) + 0.5) / float(rows) * rect.size.y)
			if not CuePlacer.is_valid(pos, state, table, placement):
				continue
			var best := best_candidate(pos, state, table, params, cfg, targets)
			var spot_score := INF
			if best != null:
				spot_score = best.score
			else:
				# No pocketing shot from here: at least make sure a clean legal hit exists, so the
				# cue ball isn't dropped behind another ball (the 8!) and foul again.
				var safe := safe_hit(pos, state, table, cfg, targets)
				if safe != null and safe.clear:
					spot_score = 1000.0 + safe.score
			if spot_score < best_score:
				best_score = spot_score
				best_spot = pos
	return best_spot


# ---------------------------------------------------------------- power model

## Shot power (0..1) for a cue ball that has to travel `cue_dist` to the ghost ball and then send the
## object ball `pocket_dist` to the pocket, hitting it with a cut whose cosine is `cos_cut`.
## Returns -1 when it would take more than full power.
static func required_power(cue_dist: float, pocket_dist: float, cos_cut: float, params: PhysicsParams,
		cfg: AiConfig) -> float:
	var a_slide := maxf(params.sliding_friction * params.gravity, 1e-6)
	var a_roll := maxf(params.rolling_friction * params.gravity, 1e-6)
	# Equal masses: the object ball gets the cue ball's speed along the line of centers, times (1 + e) / 2.
	var transfer := cos_cut * (1.0 + params.ball_restitution) * 0.5
	if transfer < 0.05:
		return -1.0
	var object_launch := _launch_speed(pocket_dist, cfg.pocket_arrival_speed, a_slide, a_roll)
	var cue_at_contact := object_launch / transfer
	var cue_launch := _launch_speed(cue_dist, cue_at_contact, a_slide, a_roll)
	var power := cue_launch / params.max_shot_speed
	if power > 1.0:
		return -1.0
	return clampf(power * cfg.power_margin, cfg.min_power, 1.0)


## Speed of a ball with no spin that started at `v0` and has travelled `distance`. It slides first
## (losing 2/7 of its speed over 12/49 v0^2 / a_slide), then rolls at 5/7 v0.
static func _speed_after(v0: float, distance: float, a_slide: float, a_roll: float) -> float:
	var slide_distance := (12.0 / 49.0) * v0 * v0 / a_slide
	if distance <= slide_distance:
		return sqrt(maxf(v0 * v0 - 2.0 * a_slide * distance, 0.0))
	var v_roll := v0 * 5.0 / 7.0
	return sqrt(maxf(v_roll * v_roll - 2.0 * a_roll * (distance - slide_distance), 0.0))


## Smallest launch speed for which `_speed_after(v0, distance)` is still `final_speed` (bisection).
static func _launch_speed(distance: float, final_speed: float, a_slide: float, a_roll: float) -> float:
	var lo := final_speed
	var hi := 60.0
	for _i in 32:
		var mid := (lo + hi) * 0.5
		if _speed_after(mid, distance, a_slide, a_roll) >= final_speed:
			hi = mid
		else:
			lo = mid
	return hi


# ---------------------------------------------------------------- geometry helpers

## True if a ball other than the cue ball and `ignore_id` comes closer than `min_dist` to the
## segment a-b. Balls behind the start of the segment never block it.
static func _path_blocked(state: SimState, ignore_id: int, a: Vector2, b: Vector2, min_dist: float) -> bool:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 1e-12:
		return false
	for other in state.balls:
		if other.id == ShotReport.CUE_ID or other.id == ignore_id or not other.is_on_table():
			continue
		var t := (other.pos - a).dot(ab) / len2
		if t <= 0.0:
			continue
		var closest := a + ab * minf(t, 1.0)
		if other.pos.distance_to(closest) < min_dist:
			return true
	return false


## Side pockets sit near the middle of the long rails.
static func _is_side_pocket(pocket_pos: Vector2, table: TableDef) -> bool:
	return absf(pocket_pos.x - table.size.x * 0.5) < table.size.x * 0.25


## Direction a ball travels when it drops straight in: across the table for a side pocket,
## along the diagonal for a corner.
static func _pocket_axis(pocket_pos: Vector2, table: TableDef) -> Vector2:
	var sy := 1.0 if pocket_pos.y >= table.size.y * 0.5 else -1.0
	if _is_side_pocket(pocket_pos, table):
		return Vector2(0.0, sy)
	var sx := 1.0 if pocket_pos.x >= table.size.x * 0.5 else -1.0
	return Vector2(sx, sy).normalized()
