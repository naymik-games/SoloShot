extends Node
## Headless physics tests. Attach to a bare Node scene (tests/sim_test_runner.tscn) and run with F6.
## Output: "Sim tests: N checks, M failures". Failures also go to the Errors tab.

const SEED: int = 4242
# Godot's Vector2 is 32-bit float (~1e-7 m resolution at table scale), so exact-looking checks need
# tolerances well above 1e-9. These are still far tighter than anything visible in play.
const POS_TOL: float = 1e-5  # meters
const VEL_TOL: float = 1e-5  # m/s
const DIR_TOL: float = 1e-4  # unit-vector distance
const ENERGY_TOL: float = 1e-4  # sum of v^2; a real energy bug adds far more than this

var table: TableDef
var params: PhysicsParams
var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	table = TableDef.new()
	params = PhysicsParams.new()
	TableBuilder.build(table)

	_test_head_on()
	_test_cut_shot()
	_test_contact_is_speed_independent()
	_test_bank_shot()
	_test_comes_to_rest()
	_test_pockets()
	_test_rack_break()
	_test_random_shots_energy_and_bounds()
	_test_determinism()
	print("Sim tests: %d checks, %d failures" % [_checks, _failures])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


# ------------------------------------------------------------------ tests

func _test_head_on() -> void:
	var r := table.ball_radius
	var s := _state(Vector2(0.5, table.size.y * 0.5), [Vector2(1.2, table.size.y * 0.5)])
	var sim := _new_sim()
	sim.apply_shot(s, Shot.new(Vector2.RIGHT, 1.0))
	var e := _first_event(sim, s, SimEvent.Type.BALL_BALL, 5.0)
	_check(e != null, "head-on: contact happens")
	if e == null:
		return
	var restitution := params.ball_restitution
	_check(_near(e.pos_a.x, 1.2 - 2.0 * r, POS_TOL), "head-on: contact at exactly 2R from object ball")
	_check(_near(e.vel_b_after.x, e.impact_speed * (1.0 + restitution) * 0.5, VEL_TOL), "head-on: object ball speed")
	_check(_near(e.vel_a_after.x, e.impact_speed * (1.0 - restitution) * 0.5, VEL_TOL), "head-on: cue nearly stops")
	_check(absf(e.vel_b_after.y) < VEL_TOL, "head-on: object ball leaves straight")


func _test_cut_shot() -> void:
	var r := table.ball_radius
	var offset := 2.0 * r * sin(deg_to_rad(30.0))
	var s := _state(Vector2(0.5, table.size.y * 0.5), [Vector2(1.2, table.size.y * 0.5 + offset)])
	var sim := _new_sim()
	sim.apply_shot(s, Shot.new(Vector2.RIGHT, 1.0))
	var e := _first_event(sim, s, SimEvent.Type.BALL_BALL, 5.0)
	_check(e != null, "cut: contact happens")
	if e == null:
		return
	var obj_angle := rad_to_deg(e.vel_b_after.angle())
	_check(_near(obj_angle, 30.0, 0.01), "cut: object ball leaves along line of centers (30 deg), got %.3f" % obj_angle)
	var between := rad_to_deg(e.vel_a_after.normalized().angle_to(e.vel_b_after.normalized()))
	_check(absf(between) > 85.0 and absf(between) <= 90.0, "cut: cue/object ~90 deg apart, got %.2f" % between)


## The point of exact contact timing: contact geometry must not depend on shot power.
func _test_contact_is_speed_independent() -> void:
	var r := table.ball_radius
	var first_dir := Vector2.ZERO
	for power in [1.0, 0.6, 0.25]:
		var s := _state(Vector2(0.5, table.size.y * 0.5), [Vector2(1.2, table.size.y * 0.5 + 0.02)])
		var sim := _new_sim()
		sim.apply_shot(s, Shot.new(Vector2.RIGHT, power))
		var e := _first_event(sim, s, SimEvent.Type.BALL_BALL, 8.0)
		_check(e != null, "speed-independence: contact at power %.2f" % power)
		if e == null:
			continue
		_check(_near(e.pos_a.distance_to(e.pos_b), 2.0 * r, POS_TOL), "speed-independence: center distance == 2R at power %.2f" % power)
		var dir := e.vel_b_after.normalized()
		if first_dir == Vector2.ZERO:
			first_dir = dir
		_check(dir.distance_to(first_dir) < DIR_TOL, "speed-independence: same object direction at power %.2f" % power)


func _test_bank_shot() -> void:
	var s := _state(Vector2(1.0, 0.6), [])
	var sim := _new_sim()
	sim.apply_shot(s, Shot.new(Vector2.RIGHT.rotated(deg_to_rad(-45.0)), 0.8))
	var e := _first_event(sim, s, SimEvent.Type.BALL_CUSHION, 5.0)
	_check(e != null, "bank: hits the top rail")
	if e == null:
		return
	_check(_near(e.pos_a.y, table.ball_radius, POS_TOL), "bank: ball center is one radius from the rail at contact")
	_check(_near(e.vel_a_after.y, e.impact_speed * params.cushion_restitution, VEL_TOL), "bank: normal speed scaled by restitution")
	_check(e.vel_a_after.x > 0.0 and e.vel_a_after.y > 0.0, "bank: keeps going right, now heading down")


func _test_comes_to_rest() -> void:
	var s := _state(Vector2(0.5, 0.6), [])
	var sim := _new_sim()
	sim.apply_shot(s, Shot.new(Vector2.RIGHT, 0.1))
	var events: Array[SimEvent] = []
	sim.run_to_rest(s, 120.0, events)
	_check(not s.any_moving(), "rest: slow ball stops completely (no creeping)")
	var rest_events := 0
	for e in events:
		if e.type == SimEvent.Type.BALLS_AT_REST:
			rest_events += 1
	_check(rest_events == 1, "rest: BALLS_AT_REST emitted exactly once, got %d" % rest_events)


func _test_pockets() -> void:
	# Corner pocket (index 0): straight at the top-left corner.
	var s := _state(Vector2(0.3, 0.3), [])
	var sim := _new_sim()
	sim.apply_shot(s, Shot.new(Vector2(-1, -1).normalized(), 0.5))
	var e := _first_event(sim, s, SimEvent.Type.BALL_POCKETED, 5.0)
	_check(e != null and e.pocket_index == 0, "pockets: corner pocket 0")

	# Side pocket (index 1): straight up the middle.
	s = _state(Vector2(table.size.x * 0.5, 0.4), [])
	sim = _new_sim()
	sim.apply_shot(s, Shot.new(Vector2.UP, 0.5))
	e = _first_event(sim, s, SimEvent.Type.BALL_POCKETED, 5.0)
	_check(e != null and e.pocket_index == 1, "pockets: side pocket 1")


func _test_rack_break() -> void:
	var s := _rack_state()
	var sim := _new_sim()
	sim.apply_shot(s, Shot.new(Vector2.RIGHT, 1.0))
	var audit := _run_audited(sim, s, 60.0)
	_check(audit["max_increase"] <= ENERGY_TOL, "break: kinetic energy never increases (max +%s)" % str(audit["max_increase"]))
	_check(not audit["escaped"], "break: no ball leaves the table without being pocketed")
	_check(audit["ball_ball_events"] >= 5, "break: balls actually collide (%d events)" % audit["ball_ball_events"])
	_check(not s.any_moving(), "break: everything comes to rest")


func _test_random_shots_energy_and_bounds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var worst := 0.0
	var escaped := false
	var still_moving := false
	for i in 40:
		var s := _random_state(rng, rng.randi_range(1, 10))
		var sim := _new_sim()
		sim.apply_shot(s, Shot.new(Vector2.RIGHT.rotated(rng.randf_range(-PI, PI)), rng.randf_range(0.2, 1.0)))
		var audit := _run_audited(sim, s, 60.0)
		worst = maxf(worst, audit["max_increase"])
		escaped = escaped or audit["escaped"]
		still_moving = still_moving or s.any_moving()
	_check(worst <= ENERGY_TOL, "random shots: energy never increases (max +%s)" % str(worst))
	_check(not escaped, "random shots: no ball escapes the table")
	_check(not still_moving, "random shots: all shots come to rest within 60 s")


func _test_determinism() -> void:
	var a := _run_fixed_shot()
	var b := _run_fixed_shot()
	_check(a == b, "determinism: identical shots give identical final positions")


# ------------------------------------------------------------------ helpers

func _new_sim() -> PoolSimulator:
	return PoolSimulator.new(table, params)


func _ball(id: int, pos: Vector2) -> BallState:
	var b := BallState.new()
	b.id = id
	b.pos = pos
	return b


## Cue ball (id 0) plus object balls (ids 1..n).
func _state(cue: Vector2, others: Array) -> SimState:
	var s := SimState.new()
	s.balls.append(_ball(0, cue))
	for i in others.size():
		s.balls.append(_ball(i + 1, others[i]))
	return s


func _rack_state() -> SimState:
	var s := SimState.new()
	s.balls.append(_ball(0, Vector2(table.size.x * 0.25, table.size.y * 0.5)))
	var rows: Array = [[1], [2, 3], [4, 5, 6], [7, 8, 9, 10], [11, 12, 13, 14, 15]]
	var d := 2.0 * table.ball_radius + 0.0004
	var foot := Vector2(table.size.x * 0.75, table.size.y * 0.5)
	for row in rows.size():
		var ids: Array = rows[row]
		for k in ids.size():
			s.balls.append(_ball(int(ids[k]), Vector2(
				foot.x + row * d * sqrt(3.0) * 0.5,
				foot.y + (k - (ids.size() - 1) * 0.5) * d)))
	return s


func _random_state(rng: RandomNumberGenerator, object_balls: int) -> SimState:
	var s := SimState.new()
	var r := table.ball_radius
	var placed: Array[Vector2] = []
	var attempts := 0
	while placed.size() < object_balls + 1 and attempts < 2000:
		attempts += 1
		var p := Vector2(
			rng.randf_range(0.1, table.size.x - 0.1),
			rng.randf_range(0.1, table.size.y - 0.1))
		var ok := true
		for q in placed:
			if p.distance_to(q) < r * 2.2:
				ok = false
				break
		if ok:
			s.balls.append(_ball(placed.size(), p))
			placed.append(p)
	return s


func _first_event(sim: PoolSimulator, state: SimState, type: SimEvent.Type, max_time: float) -> SimEvent:
	var events: Array[SimEvent] = []
	var start := state.time
	while state.time - start < max_time:
		events.clear()
		sim.step(state, events)
		for e in events:
			if e.type == type:
				return e
	return null


func _kinetic(state: SimState) -> float:
	var total := 0.0
	for b in state.balls:
		if b.is_on_table():
			total += b.vel.length_squared()
	return total


## Steps until rest (or max_time), tracking worst energy increase, escapes, and collision count.
func _run_audited(sim: PoolSimulator, state: SimState, max_time: float) -> Dictionary:
	var events: Array[SimEvent] = []
	var previous := _kinetic(state)
	var max_increase := 0.0
	var escaped := false
	var ball_ball := 0
	var start := state.time
	while state.any_moving() and state.time - start < max_time:
		events.clear()
		sim.step(state, events)
		for e in events:
			if e.type == SimEvent.Type.BALL_BALL:
				ball_ball += 1
		var energy := _kinetic(state)
		max_increase = maxf(max_increase, energy - previous)
		previous = energy
		for b in state.balls:
			if b.is_on_table() and (b.pos.x < -0.12 or b.pos.x > table.size.x + 0.12 \
					or b.pos.y < -0.12 or b.pos.y > table.size.y + 0.12 \
					or is_nan(b.pos.x) or is_nan(b.pos.y)):
				escaped = true
	return {"max_increase": max_increase, "escaped": escaped, "ball_ball_events": ball_ball}


func _run_fixed_shot() -> Array:
	var s := _state(Vector2(0.5, 0.6), [Vector2(1.1, 0.62), Vector2(1.15, 0.7)])
	var sim := _new_sim()
	sim.apply_shot(s, Shot.new(Vector2.RIGHT.rotated(0.05), 1.0))
	var events: Array[SimEvent] = []
	sim.run_to_rest(s, 60.0, events)
	var out: Array = []
	for b in s.balls:
		out.append([b.pos, b.status])
	return out
