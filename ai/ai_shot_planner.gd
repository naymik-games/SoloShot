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
	## Where the cue tip hits the cue ball (ball radii from the center, x right, y up = follow, down = draw).
	var tip: Vector2 = Vector2.ZERO
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


# ---------------------------------------------------------------- position play

const EIGHT_ID: int = 8
## Codes returned by _simulate_shot for a run that did not work out (real scores are never negative).
const FAIL_MISS: float = -1.0
const FAIL_FOUL: float = -2.0  # Scratch, early 8, or the cue ball hit an illegal ball first.


## Like best_candidate, but each of the best few pocketing shots is played out in the simulator
## (at several powers and cue tip offsets) and judged by where the cue ball stops:
##   total = shot score + position_weight * score of the best shot available from there.
## Runs where the target does not drop, the cue ball scratches, or a foul happens are discarded, so
## this also filters out shots the geometric model got wrong. Returns null if nothing survives.
##
## A coroutine: it yields to the renderer when it has used cfg.position_frame_budget_ms, so
## call it with `await`. `state` must not change while it runs (pass a clone).
static func best_position_candidate(cue_pos: Vector2, state: SimState, table: TableDef,
		params: PhysicsParams, cfg: AiConfig, targets: Array[int],
		rng: RandomNumberGenerator) -> Candidate:
	var found := find_candidates(cue_pos, state, table, params, cfg, targets)
	if found.is_empty():
		return null
	found.sort_custom(func(a, b): return (a as Candidate).score < (b as Candidate).score)

	var shooting_eight := targets.size() == 1 and targets[0] == EIGHT_ID
	var sim_params := params.duplicate() as PhysicsParams
	sim_params.substep = cfg.position_substep
	var sim := PoolSimulator.new(table, sim_params)
	var tree := Engine.get_main_loop() as SceneTree
	var budget_us := int(cfg.position_frame_budget_ms * 1000.0)
	var slice_start := Time.get_ticks_usec()

	var tips: Array[Vector2] = cfg.position_tips
	if tips.is_empty():
		tips = [Vector2.ZERO]
	var scales := cfg.position_power_scales
	if scales.is_empty():
		scales = PackedFloat32Array([1.0])

	var best: Candidate = null
	var best_total := INF
	for i in mini(cfg.position_candidates, found.size()):
		var base := found[i] as Candidate
		var tried_powers: Array[float] = []
		for scale in scales:
			var power := clampf(base.power * scale, cfg.min_power, 1.0)
			var duplicate := false
			for p in tried_powers:
				if is_equal_approx(p, power):
					duplicate = true  # Two scales clamped to the same power.
			if duplicate:
				continue
			tried_powers.append(power)
			for tip in tips:
				if tree != null and Time.get_ticks_usec() - slice_start > budget_us:
					await tree.process_frame
					slice_start = Time.get_ticks_usec()
				var total := _evaluate_option(sim, state, base, power, tip, table, params, cfg,
						targets, shooting_eight, rng)
				if total < best_total:
					best_total = total
					best = Candidate.new()
					best.target_id = base.target_id
					best.pocket_index = base.pocket_index
					best.direction = base.direction
					best.cut_deg = base.cut_deg
					best.power = power
					best.tip = tip
					best.score = total
	return best


## Score of one (shot, power, tip) option: INF if the clean run fails, else the average over
## cfg.position_samples runs (run 0 is clean, later runs add the AI's own noise).
static func _evaluate_option(sim: PoolSimulator, state: SimState, base: Candidate, power: float,
		tip: Vector2, table: TableDef, params: PhysicsParams, cfg: AiConfig, targets: Array[int],
		shooting_eight: bool, rng: RandomNumberGenerator) -> float:
	var samples := maxi(cfg.position_samples, 1)
	var sum := 0.0
	for s in samples:
		var dir := base.direction
		var pw := power
		if s > 0:
			var sigma := cfg.aim_sigma_deg
			dir = dir.rotated(deg_to_rad(clampf(rng.randfn(0.0, sigma), -2.5 * sigma, 2.5 * sigma)))
			var power_error := clampf(rng.randfn(0.0, cfg.power_sigma), -0.15, 0.15)
			pw = clampf(power * (1.0 + power_error), cfg.min_power, 1.0)
		var result := _simulate_shot(sim, state, base, dir, pw, tip, table, params, cfg, targets,
				shooting_eight)
		if result < 0.0:
			if s == 0:
				return INF  # Even the clean shot fails: not an option.
			sum += cfg.foul_penalty if result == FAIL_FOUL else cfg.miss_penalty
		else:
			sum += result
	return sum / float(samples)


## Plays the shot on a copy of the state. Returns FAIL_MISS / FAIL_FOUL, or the total score:
## shot score + opponent-ball penalty + position_weight * next-shot score.
static func _simulate_shot(sim: PoolSimulator, state: SimState, base: Candidate, dir: Vector2,
		power: float, tip: Vector2, table: TableDef, params: PhysicsParams, cfg: AiConfig,
		targets: Array[int], shooting_eight: bool) -> float:
	var after := state.clone()
	var events: Array[SimEvent] = []
	sim.apply_shot(after, Shot.new(dir, power), false, null, tip)
	sim.run_to_rest(after, cfg.position_sim_max_time, events)
	var report := ShotReport.new()
	report.add_events(events)

	if report.cue_pocketed:
		return FAIL_FOUL
	var pocketed := report.object_balls_pocketed()
	if pocketed.has(EIGHT_ID) and not shooting_eight:
		return FAIL_FOUL
	if not report.detect_fouls(targets, false).is_empty():
		return FAIL_FOUL
	if not pocketed.has(base.target_id):
		return FAIL_MISS

	var score := base.score
	var group := _ball_group(base.target_id)
	for id in pocketed:
		if id != base.target_id and id != EIGHT_ID and _ball_group(id) != group:
			score += cfg.opponent_ball_penalty
	if shooting_eight:
		return score  # Pocketing the 8 ends the game: nothing to set up.

	var cue_end := after.get_cue_ball()
	var next_targets := _targets_after(after, base.target_id)
	return score + cfg.position_weight * _next_shot_score(cue_end.pos, after, table, params, cfg,
			next_targets)


## How good the position is: the score of the best pocketing shot from `cue_pos` (same scale as
## shot scores, lower = better), or a penalty when only a safe hit or a blocked line remains.
static func _next_shot_score(cue_pos: Vector2, state: SimState, table: TableDef, params: PhysicsParams,
		cfg: AiConfig, next_targets: Array[int]) -> float:
	if next_targets.is_empty():
		return 0.0
	var next := best_candidate(cue_pos, state, table, params, cfg, next_targets)
	if next != null:
		return next.score
	var safe := safe_hit(cue_pos, state, table, cfg, next_targets)
	if safe != null and safe.clear:
		return cfg.no_shot_penalty
	return cfg.blocked_penalty


## Balls the shooter may hit first on the next turn (if it keeps the turn): the rest of the group
## of the ball just pocketed, or the 8 once that group is gone.
## Mirrors EightBallMode's ids (solids 1-7, stripes 9-15). For a ball in no group, every ball counts.
static func _targets_after(state: SimState, pocketed_target_id: int) -> Array[int]:
	var group := _ball_group(pocketed_target_id)
	var ids: Array[int] = []
	var eight_on_table := false
	for b in state.balls:
		if b.id == ShotReport.CUE_ID or not b.is_on_table():
			continue
		if b.id == EIGHT_ID:
			eight_on_table = true
		if group == 0 or _ball_group(b.id) == group:
			ids.append(b.id)
	if ids.is_empty() and eight_on_table:
		ids.append(EIGHT_ID)
	return ids


## 1 = solids, 2 = stripes, 0 = the 8 / anything else.
static func _ball_group(id: int) -> int:
	if id >= 1 and id <= 7:
		return 1
	if id >= 9 and id <= 15:
		return 2
	return 0


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


# ---------------------------------------------------------------- break by simulation

## Candidate cue ball positions along the head string, as fractions of the table width
## added to the placement spot's y (0 = the spot itself, i.e. the center).
const BREAK_SPOT_FRACTIONS := [-0.3, 0.0, 0.15]
## Cue tip offsets tried on the break (ball radii; y negative = draw / low).
const BREAK_TIPS := [Vector2.ZERO, Vector2(0.0, -0.35)]
## Simulated breaks per (spot, tip). Each adds the AI's aim noise and the simulator's break error.
const BREAK_SAMPLES: int = 2
## The break aim noise is this fraction of the normal aim noise (a break is a straight shot at the head ball).
const BREAK_AIM_SIGMA_SCALE: float = 0.5
const BREAK_SIM_MAX_TIME: float = 25.0
const NINE_ID: int = 9
const BREAK_SCRATCH_PENALTY: float = 80.0
const BREAK_FOUL_PENALTY: float = 60.0
const BREAK_ILLEGAL_PENALTY: float = 60.0
const BREAK_POCKET_BONUS: float = 10.0
const BREAK_EIGHT_PENALTY: float = 50.0  # 8-ball: the 8 on the break means a re-rack.
const BREAK_NINE_BONUS: float = 40.0  # 9-ball: the 9 on a legal break wins.
const BREAK_CENTER_WEIGHT: float = 3.0  # Slight preference for a cue ball left away from the rails.
const BREAK_CUSHION_BALLS: int = 4  # Same number the modes use for a legal break.


class BreakPlan extends RefCounted:
	var spot: Vector2 = Vector2.ZERO
	var tip: Vector2 = Vector2.ZERO
	## Average simulated score (lower is better).
	var score: float = INF


## Plays the break from several spots on the head string with a few tip offsets and picks the best:
## pocketed balls are rewarded; scratches, fouls and illegal breaks (no ball pocketed and fewer than
## 4 object balls reaching a cushion) are punished. `nine_ball` switches the rules about the 8 and the 9.
## A coroutine like best_position_candidate: call it with `await`, and pass a clone of the state.
static func choose_break(state: SimState, table: TableDef, params: PhysicsParams, cfg: AiConfig,
		placement: CuePlacement, targets: Array[int], nine_ball: bool,
		rng: RandomNumberGenerator) -> BreakPlan:
	var sim_params := params.duplicate() as PhysicsParams
	sim_params.substep = cfg.position_substep
	var sim := PoolSimulator.new(table, sim_params)
	var tree := Engine.get_main_loop() as SceneTree
	var budget_us := int(cfg.position_frame_budget_ms * 1000.0)
	var slice_start := Time.get_ticks_usec()

	var best: BreakPlan = null
	for frac in BREAK_SPOT_FRACTIONS:
		var wish := CuePlacer.constrain(
				Vector2(placement.spot.x, placement.spot.y + frac * table.size.y), state, table, placement)
		if not CuePlacer.is_valid(wish, state, table, placement):
			continue
		var head_pos := _nearest_target_pos(wish, state, targets)
		if head_pos == Vector2.INF:
			continue
		var dir := (head_pos - wish).normalized()
		for tip in BREAK_TIPS:
			if tree != null and Time.get_ticks_usec() - slice_start > budget_us:
				await tree.process_frame
				slice_start = Time.get_ticks_usec()
			var total := 0.0
			for s in BREAK_SAMPLES:
				total += _simulate_break(sim, state, table, cfg, wish, dir, tip, targets, nine_ball, rng)
			var avg := total / float(BREAK_SAMPLES) + rng.randf() * 0.5  # Tiny jitter: ties vary.
			if best == null or avg < best.score:
				best = BreakPlan.new()
				best.spot = wish
				best.tip = tip
				best.score = avg
	return best


static func _nearest_target_pos(from: Vector2, state: SimState, targets: Array[int]) -> Vector2:
	var best := Vector2.INF
	var best_dist := INF
	for id in targets:
		var ball := state.get_ball(id)
		if ball == null or not ball.is_on_table():
			continue
		var d := ball.pos.distance_to(from)
		if d < best_dist and d > 1e-4:
			best_dist = d
			best = ball.pos
	return best


static func _simulate_break(sim: PoolSimulator, state: SimState, table: TableDef, cfg: AiConfig,
		spot: Vector2, dir: Vector2, tip: Vector2, targets: Array[int], nine_ball: bool,
		rng: RandomNumberGenerator) -> float:
	var after := state.clone()
	CuePlacer.set_cue_ball(after.get_cue_ball(), spot)
	var sigma := cfg.aim_sigma_deg * BREAK_AIM_SIGMA_SCALE
	var d := dir.rotated(deg_to_rad(clampf(rng.randfn(0.0, sigma), -2.5 * sigma, 2.5 * sigma)))
	var events: Array[SimEvent] = []
	sim.apply_shot(after, Shot.new(d, cfg.break_power), true, rng, tip)
	sim.run_to_rest(after, BREAK_SIM_MAX_TIME, events)
	var report := ShotReport.new()
	report.add_events(events)

	var cushion_balls := {}
	for e in events:
		if e.type == SimEvent.Type.BALL_CUSHION and e.ball_a != ShotReport.CUE_ID:
			cushion_balls[e.ball_a] = true
	var pocketed := report.object_balls_pocketed()

	var score := 0.0
	var foul := false
	if report.cue_pocketed:
		score += BREAK_SCRATCH_PENALTY
		foul = true
	elif not report.detect_fouls(targets, false).is_empty():
		score += BREAK_FOUL_PENALTY
		foul = true
	if pocketed.is_empty() and cushion_balls.size() < BREAK_CUSHION_BALLS:
		score += BREAK_ILLEGAL_PENALTY
		foul = true
	if not foul:
		for id in pocketed:
			if not nine_ball and id == EIGHT_ID:
				score += BREAK_EIGHT_PENALTY
			elif nine_ball and id == NINE_ID:
				score -= BREAK_NINE_BONUS
			else:
				score -= BREAK_POCKET_BONUS
	var cue := after.get_cue_ball()
	if cue != null and cue.is_on_table():
		score += BREAK_CENTER_WEIGHT * cue.pos.distance_to(table.size * 0.5) / table.size.x
	return score


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
