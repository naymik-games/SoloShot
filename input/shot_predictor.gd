class_name ShotPredictor
extends RefCounted
## (Replaces the earlier version: contact data now comes straight from the simulator's events,
## so ghost position and departure directions are exact and independent of substep timing.)
##
## Clones the state, fires a FULL-POWER shot at the given angle through the real simulator,
## and stops at the first cue-ball ball contact (or scratch / bounce limit / rest / time cap).
## No drawing here.

const CUE_ID: int = 0

var config: AimConfig

# Own simulator instance: prediction must never touch the live game's simulator flags.
var _sim: PoolSimulator


func _init(p_simulator: PoolSimulator = null, p_config: AimConfig = null) -> void:
	config = p_config if p_config != null else AimConfig.new()
	if p_simulator != null:
		_sim = PoolSimulator.new(p_simulator.table, p_simulator.params)


func predict(state: SimState, angle: float) -> PredictionResult:
	var result := PredictionResult.new()
	var live_cue := state.get_cue_ball()
	if _sim == null or live_cue == null or not live_cue.is_on_table():
		return result

	var copy := state.clone()
	var cue := copy.get_cue_ball()
	_sim.apply_shot(copy, Shot.new(Vector2.RIGHT.rotated(angle), 1.0))
	result.cue_path.append(cue.pos)
	result.stop_pos = cue.pos

	var events: Array[SimEvent] = []
	var bounces := 0
	var start_time := copy.time

	while copy.time - start_time < config.prediction_time_cap:
		events.clear()
		_sim.step(copy, events)

		for e in events:
			match e.type:
				SimEvent.Type.BALL_CUSHION:
					if e.ball_a == CUE_ID:
						bounces += 1
						result.cue_path.append(e.pos_a)
						if bounces > config.max_bounces:
							result.stop_pos = e.pos_a
							return result
				SimEvent.Type.BALL_BALL:
					if e.ball_a == CUE_ID or e.ball_b == CUE_ID:
						_fill_contact(result, e, bounces > 0)
						return result
				SimEvent.Type.BALL_POCKETED:
					if e.ball_a == CUE_ID:
						result.outcome = PredictionResult.Outcome.POCKETS_CUE
						result.cue_path.append(e.pos_a)
						result.stop_pos = e.pos_a
						return result

		if not cue.is_moving():
			break

	# Nothing hit: line ends where the cue ball stopped / time ran out.
	result.cue_path.append(cue.pos)
	result.stop_pos = cue.pos
	return result


## Uses the event's exact contact positions and post-impulse velocities.
func _fill_contact(result: PredictionResult, e: SimEvent, cushion_first: bool) -> void:
	var cue_is_a := e.ball_a == CUE_ID
	var cue_pos := e.pos_a if cue_is_a else e.pos_b
	var obj_pos := e.pos_b if cue_is_a else e.pos_a
	var cue_vel := e.vel_a_after if cue_is_a else e.vel_b_after
	var obj_vel := e.vel_b_after if cue_is_a else e.vel_a_after

	result.outcome = PredictionResult.Outcome.HITS_BALL
	result.hit_ball_id = e.ball_b if cue_is_a else e.ball_a
	result.hit_cushion_first = cushion_first
	result.ghost_pos = cue_pos
	result.object_start = obj_pos
	result.cue_path.append(cue_pos)
	result.stop_pos = cue_pos
	if obj_vel.length_squared() > 0.0:
		result.object_dir = obj_vel.normalized()
	if cue_vel.length_squared() > 0.0:
		result.cue_dir_after = cue_vel.normalized()
