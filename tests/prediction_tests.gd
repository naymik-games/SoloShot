extends Node
## Prediction tests. Attach to a bare Node scene and run with F6. Needs TableBuilder + simulator.
## (Replaces the earlier version: geometry checks are now exact because contacts are exact.)

const SEED: int = 12345
# Godot's Vector2 is 32-bit float, so use tolerances above ~1e-7 m.
const POS_TOL: float = 1e-5
const SHOT_COUNT: int = 50

var table: TableDef
var params: PhysicsParams
var sim: PoolSimulator
var predictor: ShotPredictor
var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	table = TableDef.new()
	params = PhysicsParams.new()
	TableBuilder.build(table)
	sim = PoolSimulator.new(table, params)

	var cfg := AimConfig.new()
	cfg.max_bounces = 99  # Follow bounces until the first ball contact.
	predictor = ShotPredictor.new(sim, cfg)

	_test_matches_real_full_power_shot()
	_test_straight_shot_geometry()
	_test_no_side_effects()
	print("Prediction tests: %d checks, %d failures" % [_checks, _failures])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


## The first ball the cue touches in a REAL full-power run must be the one the predictor reports.
func _test_matches_real_full_power_shot() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in SHOT_COUNT:
		var state := _random_state(rng, 6)
		var angle := rng.randf_range(-PI, PI)
		var pred := predictor.predict(state, angle)

		var expected := _real_first_contact(state, angle)  # id, -1 = none, -2 = scratch
		var got := -1
		match pred.outcome:
			PredictionResult.Outcome.HITS_BALL:
				got = pred.hit_ball_id
			PredictionResult.Outcome.POCKETS_CUE:
				got = -2
		_check(got == expected, "shot %d angle %.3f: predicted %d, real %d" % [i, angle, got, expected])


func _test_straight_shot_geometry() -> void:
	var r := table.ball_radius
	var state := SimState.new()
	state.balls.append(_ball(0, Vector2(0.5, table.size.y * 0.5)))
	state.balls.append(_ball(1, Vector2(1.2, table.size.y * 0.5)))
	var pred := predictor.predict(state, 0.0)

	_check(pred.outcome == PredictionResult.Outcome.HITS_BALL, "straight shot hits a ball")
	_check(pred.hit_ball_id == 1, "straight shot hits ball 1")
	_check(absf(pred.ghost_pos.x - (1.2 - 2.0 * r)) < POS_TOL, "ghost ball exactly 2R from object ball")
	_check(absf(pred.ghost_pos.distance_to(pred.object_start) - 2.0 * r) < POS_TOL, "ghost-to-object distance is 2R")
	_check(pred.object_dir.dot(Vector2.RIGHT) > 0.99999, "object ball leaves straight ahead")


func _test_no_side_effects() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	var state := _random_state(rng, 8)
	var before := _snapshot(state)
	for i in 10:
		predictor.predict(state, rng.randf_range(-PI, PI))
	_check(before == _snapshot(state), "predict() leaves live state unchanged")


# --------------------------------------------------------------------- helpers

func _real_first_contact(state: SimState, angle: float) -> int:
	var real_sim := PoolSimulator.new(table, params)
	var s := state.clone()
	real_sim.apply_shot(s, Shot.new(Vector2.RIGHT.rotated(angle), 1.0))
	var events: Array[SimEvent] = []
	real_sim.run_to_rest(s, predictor.config.prediction_time_cap, events)
	for e in events:
		if e.type == SimEvent.Type.BALL_BALL and (e.ball_a == 0 or e.ball_b == 0):
			return e.ball_b if e.ball_a == 0 else e.ball_a
		if e.type == SimEvent.Type.BALL_POCKETED and e.ball_a == 0:
			return -2
	return -1


func _ball(id: int, pos: Vector2) -> BallState:
	var b := BallState.new()
	b.id = id
	b.pos = pos
	return b


func _random_state(rng: RandomNumberGenerator, object_balls: int) -> SimState:
	var s := SimState.new()
	var r := table.ball_radius
	var margin := r * 3.0
	var placed: Array[Vector2] = []
	var attempts := 0
	while placed.size() < object_balls + 1 and attempts < 2000:
		attempts += 1
		var p := Vector2(
			rng.randf_range(margin, table.size.x - margin),
			rng.randf_range(margin, table.size.y - margin))
		var ok := true
		for q in placed:
			if p.distance_to(q) < r * 2.5:
				ok = false
				break
		if not ok:
			continue
		s.balls.append(_ball(placed.size(), p))
		placed.append(p)
	return s


func _snapshot(state: SimState) -> Array:
	var out: Array = [state.time]
	for b in state.balls:
		out.append([b.id, b.pos, b.vel, b.status, b.rolling, b.slide_remaining])
	return out
