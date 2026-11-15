class_name AiController
extends PlayerController
## Computer opponent. Same interface as HumanController: PoolGame asks it to shoot or to place the
## cue ball, and it answers through shot_decided / placement_confirmed.
##
## It plays the best makeable shot it can find (AiShotPlanner), falls back to a firm "safe" hit when
## nothing is makeable, and blurs the aim and power with noise (AiConfig.aim_sigma_deg / power_sigma).
## With AiConfig.position_weight > 0 the pocketing shots are played out in the simulator first, and
## the one that leaves the cue ball best placed for the next shot (and never scratches) wins.
## With ball in hand it picks the spot that gives it the best shot.

var _player_index: int
var _mode: GameMode
var _table: TableDef
var _params: PhysicsParams
var _config: AiConfig
var _rng := RandomNumberGenerator.new()

## Bumped by every new decision and by cancel(): a decision that wakes up from its "thinking"
## pause with an old ticket has been cancelled and does nothing.
var _ticket: int = 0


## What the controller has decided: the shot and where the cue tip hits the cue ball.
class Decision extends RefCounted:
	var shot: Shot
	var tip: Vector2 = Vector2.ZERO

	func _init(p_shot: Shot, p_tip: Vector2 = Vector2.ZERO) -> void:
		shot = p_shot
		tip = p_tip


func _init(p_player_index: int, p_mode: GameMode, p_table: TableDef, p_params: PhysicsParams,
		p_config: AiConfig) -> void:
	_player_index = p_player_index
	_mode = p_mode
	_table = p_table
	_params = p_params
	_config = p_config if p_config != null else AiConfig.new()
	_rng.randomize()


## PoolGame hides the aim line, power bar, fine aim, spin and cue stick during this player's turn.
func uses_touch_controls() -> bool:
	return false


func begin_shot(state: SimState) -> void:
	_ticket += 1
	var ticket := _ticket
	var started_msec := Time.get_ticks_msec()
	var decision: Decision = await _choose_shot(state)
	if ticket != _ticket:
		return  # Cancelled while planning.
	# The look-ahead counts as thinking time: only wait for whatever is left of it.
	var remaining := _config.think_time - float(Time.get_ticks_msec() - started_msec) / 1000.0
	await _think(remaining)
	if ticket != _ticket:
		return  # Cancelled while "thinking".
	shot_decided.emit(decision.shot, decision.tip)


func begin_placement(state: SimState, placement: CuePlacement) -> void:
	_ticket += 1
	var ticket := _ticket
	var spot := _choose_spot(state, placement)
	await _think(_config.placement_think_time)
	if ticket != _ticket:
		return
	var cue := state.get_cue_ball()
	if cue != null:
		CuePlacer.set_cue_ball(cue, spot)
	placement_confirmed.emit()


func cancel() -> void:
	_ticket += 1


# ---------------------------------------------------------------- decisions

func _choose_shot(state: SimState) -> Decision:
	var cue := state.get_cue_ball()
	if cue == null or not cue.is_on_table():
		return Decision.new(Shot.new(Vector2.RIGHT, _config.safe_hit_power))

	var started_usec := Time.get_ticks_usec()
	var targets := _legal_targets(state)  # Ask the mode before any await: it reads the live state.
	var is_break := _mode.is_break_shot()
	var plan: AiShotPlanner.Candidate = null
	if is_break:
		plan = AiShotPlanner.break_shot(cue.pos, state, targets, _config)
	else:
		if _config.position_weight > 0.0:
			# Plan on a copy: the look-ahead yields to the renderer now and then.
			plan = await AiShotPlanner.best_position_candidate(cue.pos, state.clone(), _table, _params,
					_config, targets, _rng)
		else:
			plan = AiShotPlanner.best_candidate(cue.pos, state, _table, _params, _config, targets)
		if plan == null:
			plan = AiShotPlanner.safe_hit(cue.pos, state, _table, _config, targets)

	var direction := Vector2.RIGHT
	var power := _config.safe_hit_power
	var tip := Vector2.ZERO
	if plan != null:
		direction = plan.direction
		power = plan.power
		tip = plan.tip
	else:
		direction = (_table.size * 0.5 - cue.pos).normalized()  # Nothing legal to hit: just shoot somewhere.

	if _config.debug_print:
		var what := "no shot"
		if plan != null:
			what = "ball %d, pocket %d, power %.2f, tip (%.1f, %.1f), cut %.0f, score %.1f, clear %s" % [
					plan.target_id, plan.pocket_index, plan.power, plan.tip.x, plan.tip.y, plan.cut_deg,
					plan.score, str(plan.clear)]
		print("AI (player %d) legal first balls: %s | break: %s | plan: %s | planning %d ms" % [
				_player_index, str(targets), str(is_break), what,
				(Time.get_ticks_usec() - started_usec) / 1000])

	# Noise. Clamped so a rare outlier can't send the ball somewhere absurd.
	var sigma := _config.aim_sigma_deg
	var angle_error := clampf(_rng.randfn(0.0, sigma), -2.5 * sigma, 2.5 * sigma)
	direction = direction.rotated(deg_to_rad(angle_error))
	if not is_break:  # The break always goes at full power.
		var power_error := clampf(_rng.randfn(0.0, _config.power_sigma), -0.15, 0.15)
		power = clampf(power * (1.0 + power_error), _config.min_power, 1.0)
	return Decision.new(Shot.new(direction, power), tip)


func _choose_spot(state: SimState, placement: CuePlacement) -> Vector2:
	if _mode.is_break_shot():
		# Everything is blocked by the rack: just vary the starting spot a little.
		var y := placement.spot.y + _rng.randf_range(-1.0, 1.0) * _config.break_spot_spread * _table.size.y
		var wish := CuePlacer.constrain(Vector2(placement.spot.x, y), state, _table, placement)
		if CuePlacer.is_valid(wish, state, _table, placement):
			return wish
		return CuePlacer.find_free_position(placement.spot, state, _table, placement)
	return AiShotPlanner.choose_cue_spot(state, _table, _params, _config, placement, _legal_targets(state))


## Balls this player may hit first. The mode says (empty = any ball is fine, e.g. the break).
func _legal_targets(state: SimState) -> Array[int]:
	var ids := _mode.legal_first_balls(_player_index)
	if not ids.is_empty():
		return ids
	var all: Array[int] = []
	for b in state.balls:
		if b.id != ShotReport.CUE_ID and b.is_on_table():
			all.append(b.id)
	return all


## A pause so the turn doesn't flash by (and the player sees whose turn it is).
func _think(seconds: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or seconds <= 0.0:
		return
	await tree.create_timer(seconds).timeout
