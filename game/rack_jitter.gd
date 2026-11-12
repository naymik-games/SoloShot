class_name RackJitter
extends RefCounted
## Call once right after a rack is built (initial rack and every rerack).
## Nudges every object ball by a tiny random offset, then pushes overlapping pairs apart so the
## rack starts with microscopic gaps instead of perfectly flush contacts. That is what makes
## breaks come out differently, and it is physically honest: nobody racks perfectly.

const MAX_RELAX_ITERATIONS: int = 16


static func apply(state: SimState, table: TableDef, params: PhysicsParams, rng: RandomNumberGenerator) -> void:
	if params.rack_jitter <= 0.0:
		return
	var cue := state.get_cue_ball()
	var balls: Array = []
	for b in state.balls:
		if b != cue and b.is_on_table():
			balls.append(b)

	var j = params.rack_jitter
	for b in balls:
		b.pos += Vector2(rng.randf_range(-j, j), rng.randf_range(-j, j))

	# Relax: separate any pair closer than diameter + min gap.
	var min_dist = table.ball_radius * 2.0 + params.rack_min_gap
	for _iter in MAX_RELAX_ITERATIONS:
		var moved := false
		for i in balls.size():
			for k in range(i + 1, balls.size()):
				var d: Vector2 = balls[k].pos - balls[i].pos
				var dist := d.length()
				if dist >= min_dist - 1e-6:  # 1 micron tolerance so the loop can finish
					continue
				var dir := d / dist if dist > 1e-9 else Vector2.RIGHT
				var push = dir * ((min_dist - dist) * 0.5)
				balls[i].pos -= push
				balls[k].pos += push
				moved = true
		if not moved:
			break
