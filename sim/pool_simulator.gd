class_name PoolSimulator
extends RefCounted
## Deterministic 2D pool physics (no spin yet). Stateless apart from table + params + a rest flag,
## so it works the same on the live state or a clone (use a separate instance for prediction).
##
## One substep:
##   1. friction          velocities decay (sliding phase, then rolling phase)
##   2. advance           move balls over the substep, resolving every ball-ball and ball-cushion
##                        contact at its EXACT time (solve, move to the contact, apply impulse,
##                        continue with the remaining time)
##   3. penetrations      tiny float-drift cleanup for ball-ball overlap
##   4. pockets           capture radius, plus a backstop for balls that left the playfield
##   5. rest              emit BALLS_AT_REST once everything has stopped
##
## Friction model (no spin): a ball starts SLIDING after a shot, collision, or cushion hit.
## Sliding friction removes 2/7 of its speed (the physics of a plain-sliding sphere reaching
## rolling), then the ball is ROLLING and only the small rolling friction applies.

const SLIDE_LOSS_FRACTION: float = 2.0 / 7.0
const MAX_EVENTS_PER_SUBSTEP: int = 64
const EPS_TIME: float = 1e-12
const EPS_DIST2: float = 1e-12
# Vector2 is 32-bit float (~1e-7 m resolution at table scale), so only clean up overlaps above 1 micron.
const PENETRATION_EPS: float = 1e-6

var table: TableDef
var params: PhysicsParams

var _rest_emitted: bool = false
# Scratch output of _cushion_contact_time (avoids allocating a result object per call).
var _hit_normal: Vector2 = Vector2.ZERO


func _init(p_table: TableDef = null, p_params: PhysicsParams = null) -> void:
	table = p_table
	params = p_params


## Sets the cue ball velocity from a shot.
func apply_shot(state: SimState, shot: Shot) -> void:
	var cue := state.get_cue_ball()
	if cue == null or not cue.is_on_table():
		return
	cue.vel = shot.direction.normalized() * shot.power * params.max_shot_speed
	_enter_sliding(cue)
	_rest_emitted = false


## Advances by one substep (params.substep), appending any events.
func step(state: SimState, events: Array[SimEvent]) -> void:
	var dt := params.substep
	_apply_friction(state, dt)
	_advance(state, dt, events)
	_resolve_penetrations(state)
	_check_pockets(state, events)
	state.time += dt
	_check_rest(state, events)


## Runs until all balls rest or max_time elapses. Used for prediction and tests.
func run_to_rest(state: SimState, max_time: float, events: Array[SimEvent]) -> void:
	var start := state.time
	while state.any_moving() and (state.time - start) < max_time:
		step(state, events)


# ------------------------------------------------------------------ friction

func _apply_friction(state: SimState, dt: float) -> void:
	var a_slide := params.sliding_friction * params.gravity
	var a_roll := params.rolling_friction * params.gravity
	for b in state.balls:
		if not b.is_on_table() or not b.is_moving():
			continue
		var speed := b.vel.length()
		if not b.rolling:
			var loss := a_slide * dt
			if loss >= b.slide_remaining:
				# Sliding ends inside this substep: slide for part of it, roll for the rest.
				var t_slide := b.slide_remaining / a_slide if a_slide > 0.0 else dt
				speed -= b.slide_remaining
				b.slide_remaining = 0.0
				b.rolling = true
				speed -= a_roll * maxf(dt - t_slide, 0.0)
			else:
				speed -= loss
				b.slide_remaining -= loss
		else:
			speed -= a_roll * dt

		if speed <= params.stop_speed:
			b.vel = Vector2.ZERO
			b.slide_remaining = 0.0
		else:
			b.vel = b.vel.normalized() * speed


func _enter_sliding(b: BallState) -> void:
	b.rolling = false
	b.slide_remaining = SLIDE_LOSS_FRACTION * b.vel.length()


# ------------------------------------------------------------------ advance + exact contacts

func _advance(state: SimState, dt: float, events: Array[SimEvent]) -> void:
	var balls := state.balls
	var count := balls.size()
	var radius := table.ball_radius
	var diameter := radius * 2.0
	var remaining := dt
	var guard := 0

	while remaining > EPS_TIME and guard < MAX_EVENTS_PER_SUBSTEP:
		guard += 1
		var t_hit := remaining
		var kind := 0  # 0 = none, 1 = ball-ball, 2 = ball-cushion
		var hit_i := -1
		var hit_j := -1
		var hit_normal := Vector2.ZERO

		# Find the earliest contact in the remaining time.
		for i in count:
			var a := balls[i]
			if not a.is_on_table():
				continue
			var a_moving := a.is_moving()

			if a_moving:
				for seg in table.cushions:
					var t_c := _cushion_contact_time(a.pos, a.vel, seg, radius, t_hit)
					if t_c < t_hit:
						t_hit = t_c
						kind = 2
						hit_i = i
						hit_normal = _hit_normal

			for j in range(i + 1, count):
				var b := balls[j]
				if not b.is_on_table():
					continue
				if not (a_moving or b.is_moving()):
					continue
				var d := b.pos - a.pos
				var w := b.vel - a.vel
				var reach := diameter + w.length() * t_hit
				if d.length_squared() > reach * reach:
					continue  # Too far to touch within the remaining time.
				var t_b := _circle_contact_time(d, w, diameter, t_hit)
				if t_b < t_hit:
					t_hit = t_b
					kind = 1
					hit_i = i
					hit_j = j

		# Move everything up to the contact (or the end of the substep).
		for b in balls:
			if b.is_on_table() and b.is_moving():
				b.pos += b.vel * t_hit
		remaining -= t_hit

		var event_time := state.time + (dt - remaining)
		if kind == 1:
			_collide_balls(balls[hit_i], balls[hit_j], event_time, events)
		elif kind == 2:
			_bounce_off_cushion(balls[hit_i], hit_normal, event_time, events)
		else:
			break

	# Event budget exhausted (e.g. a dense cluster): finish the move without more contacts.
	if remaining > EPS_TIME:
		for b in balls:
			if b.is_on_table() and b.is_moving():
				b.pos += b.vel * remaining


## Earliest t in [0, max_t] where |d + w*t| == dist, for approaching circles; INF if none.
## Already touching/overlapping counts as t = 0 only if the circles are approaching.
func _circle_contact_time(d: Vector2, w: Vector2, dist: float, max_t: float) -> float:
	var b := d.dot(w)
	var c := d.dot(d) - dist * dist
	if c <= EPS_DIST2:
		return 0.0 if b < 0.0 else INF
	var a := w.dot(w)
	if a < 1e-18 or b >= 0.0:
		return INF
	var disc := b * b - a * c
	if disc < 0.0:
		return INF
	var t := (-b - sqrt(disc)) / a
	return t if t <= max_t else INF


## Earliest contact of a ball (center p, velocity v) with a cushion segment, INF if none within max_t.
## Checks the flat face and both rounded endpoint caps. Sets _hit_normal (pointing at the ball).
func _cushion_contact_time(p: Vector2, v: Vector2, seg: CushionSegment, radius: float, max_t: float) -> float:
	var best := INF
	var best_normal := Vector2.ZERO
	var n := seg.normal

	# Flat face: center reaches the line offset by `radius`, and the contact lies within the segment.
	var vn := v.dot(n)
	if vn < -1e-9:
		var s0 := (p - seg.a).dot(n)
		if s0 > -radius:  # Ignore balls whose center is already behind the wall.
			var t_face := maxf((radius - s0) / vn, 0.0)
			if t_face <= max_t:
				var ab := seg.b - seg.a
				var u := ((p + v * t_face) - seg.a).dot(ab) / ab.dot(ab)
				if u >= 0.0 and u <= 1.0:
					best = t_face
					best_normal = n

	# Rounded jaw tips at both endpoints.
	var limit := minf(max_t, best)
	var t_a := _circle_contact_time(p - seg.a, v, radius, limit)
	if t_a < limit:
		best = t_a
		best_normal = _cap_normal(p + v * t_a - seg.a, n)
		limit = t_a
	var t_b := _circle_contact_time(p - seg.b, v, radius, limit)
	if t_b < limit:
		best = t_b
		best_normal = _cap_normal(p + v * t_b - seg.b, n)

	_hit_normal = best_normal
	return best


func _cap_normal(offset: Vector2, fallback: Vector2) -> Vector2:
	if offset.length_squared() < 1e-18:
		return fallback
	return offset.normalized()


func _collide_balls(a: BallState, b: BallState, time: float, events: Array[SimEvent]) -> void:
	var n := (b.pos - a.pos).normalized()
	var approach := (a.vel - b.vel).dot(n)
	if approach <= 0.0:
		return
	# Equal masses: exchange the normal component, scaled by restitution. Tangential parts untouched.
	var j := approach * (1.0 + params.ball_restitution) * 0.5
	a.vel -= n * j
	b.vel += n * j
	_enter_sliding(a)
	_enter_sliding(b)

	var e := SimEvent.make(SimEvent.Type.BALL_BALL, time)
	e.ball_a = a.id
	e.ball_b = b.id
	e.impact_speed = approach
	e.position = (a.pos + b.pos) * 0.5
	e.pos_a = a.pos
	e.pos_b = b.pos
	e.vel_a_after = a.vel
	e.vel_b_after = b.vel
	events.append(e)


func _bounce_off_cushion(b: BallState, n: Vector2, time: float, events: Array[SimEvent]) -> void:
	var vn := b.vel.dot(n)
	if vn >= 0.0:
		return
	var vt := (b.vel - n * vn) * (1.0 - params.cushion_tangent_loss)
	b.vel = n * (-vn * params.cushion_restitution) + vt
	_enter_sliding(b)

	var e := SimEvent.make(SimEvent.Type.BALL_CUSHION, time)
	e.ball_a = b.id
	e.impact_speed = -vn
	e.position = b.pos - n * table.ball_radius
	e.pos_a = b.pos
	e.vel_a_after = b.vel
	events.append(e)


# ------------------------------------------------------------------ cleanup, pockets, rest

## Float-drift cleanup only: exact contacts already prevent real overlaps.
func _resolve_penetrations(state: SimState) -> void:
	var balls := state.balls
	var count := balls.size()
	var diameter := table.ball_radius * 2.0
	for i in count:
		var a := balls[i]
		if not a.is_on_table():
			continue
		for j in range(i + 1, count):
			var b := balls[j]
			if not b.is_on_table() or not (a.is_moving() or b.is_moving()):
				continue
			var d := b.pos - a.pos
			var dist := d.length()
			if dist < diameter - PENETRATION_EPS and dist > 0.0:
				var push := (d / dist) * ((diameter - dist) * 0.5)
				a.pos -= push
				b.pos += push


func _check_pockets(state: SimState, events: Array[SimEvent]) -> void:
	if table.pockets.is_empty():
		return
	for b in state.balls:
		if not b.is_on_table():
			continue
		var hit := -1
		for k in table.pockets.size():
			var p := table.pockets[k]
			if b.pos.distance_to(p.center) < p.capture_radius:
				hit = k
				break
		# Backstop: cushions block everything except pocket mouths, so a ball center outside the
		# playfield must have gone through a mouth. The nearest pocket takes it.
		if hit < 0 and (b.pos.x < 0.0 or b.pos.x > table.size.x or b.pos.y < 0.0 or b.pos.y > table.size.y):
			var best := INF
			for k in table.pockets.size():
				var dist := b.pos.distance_to(table.pockets[k].center)
				if dist < best:
					best = dist
					hit = k
		if hit >= 0:
			var e := SimEvent.make(SimEvent.Type.BALL_POCKETED, state.time)
			e.ball_a = b.id
			e.pocket_index = hit
			e.impact_speed = b.vel.length()
			e.position = table.pockets[hit].center
			e.pos_a = b.pos
			events.append(e)
			b.status = BallState.Status.POCKETED
			b.vel = Vector2.ZERO
			b.slide_remaining = 0.0


func _check_rest(state: SimState, events: Array[SimEvent]) -> void:
	if _rest_emitted or state.any_moving():
		return
	_rest_emitted = true
	events.append(SimEvent.make(SimEvent.Type.BALLS_AT_REST, state.time))
