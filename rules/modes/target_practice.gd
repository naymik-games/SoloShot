class_name TargetPracticeMode
extends GameMode
## Solo target practice: hit the cue ball into the special object ball (ball 17) and try to leave
## it resting in the middle of a painted target.
##
## - 3 rounds, one shot each, harder every round (see _make_rounds).
## - Score = where ball 17 comes to rest (its center): 100 bullseye, 50 middle ring, 25 outer ring.
## - 0 points for: a scratch, no contact, hitting the wrong ball first, touching an "avoid" ball,
##   pocketing ball 17, or finishing outside the target.
## - Combo rounds: the cue ball must hit the combo ball first, which carries on into ball 17.
## - The cue ball is placed for you every round (no free placement).
##
## Layouts are built from a few numbers per round (cut angle, distances, extras) using the
## "ghost ball" idea: the cue ball's path ends where it touches the first ball, and that ball
## then leaves along the line toward the target. Each round is mirrored at random so the same
## round does not look identical every game.

const OBJECT_ID: int = 17  ## The ball that has to land on the target.

## Ring radii (meters, ball CENTER distance from the target center) and their points.
const RING_RADII: Array[float] = [0.05, 0.14, 0.28]
const RING_POINTS: Array[int] = [100, 50, 25]

## Seconds to wait before the next round is set up. Longer after a score so the effect can play
## (keep it above TargetView.EFFECT_TIME).
const ROUND_DELAY_SCORED: float = 2.2
const ROUND_DELAY_MISSED: float = 1.5

## An avoid ball that moved more than this (meters) counts as touched.
const MOVED_EPS: float = 0.0005
## Layout points closer than this to a cushion log a warning (a layout that doesn't fit the table).
const EDGE_MARGIN: float = 0.06


## An extra ball that must NOT be touched. Placed relative to a path so it is a real hazard.
class ExtraCfg:
	extends RefCounted
	var ball_id: int = 18
	## true = along the cue ball's path (cue -> first contact), false = along the object ball's path.
	var on_cue_path: bool = false
	## 0..1 position along that path.
	var t: float = 0.5
	## Sideways offset in meters from the path (the sign picks the side). ~0.1 is a tight squeeze.
	var lateral: float = 0.1

	static func make(p_id: int, p_on_cue_path: bool, p_t: float, p_lateral: float) -> ExtraCfg:
		var e := ExtraCfg.new()
		e.ball_id = p_id
		e.on_cue_path = p_on_cue_path
		e.t = p_t
		e.lateral = p_lateral
		return e


## Everything that defines one round.
class RoundCfg:
	extends RefCounted
	## Short name for the stat bar.
	var title: String = ""
	## Target center as a fraction of the table size (before mirroring).
	var target_frac: Vector2 = Vector2(0.78, 0.5)
	## Direction the object ball must travel, in degrees (0 = toward the right end).
	var shot_dir_deg: float = 0.0
	## Cut angle between the cue ball's path and that direction. 0 = straight on.
	var cut_deg: float = 0.0
	## Distance the cue ball travels to reach the first ball.
	var cue_to_contact: float = 0.5
	## Distance from ball 17 to the target center.
	var object_to_target: float = 0.6
	## Combo ball id (placed behind ball 17 on the shot line), or -1 for no combo.
	var combo_id: int = -1
	## Free space between the combo ball and ball 17 (meters).
	var combo_gap: float = 0.12
	var avoid: Array[ExtraCfg] = []


var finished: bool = false
var score: int = 0
## Points from the last finished round, or -1 before the first one.
var last_points: int = -1

var _state: SimState
var _table: TableDef
var _rounds: Array[RoundCfg] = []
var _round_index: int = 0
var _rng := RandomNumberGenerator.new()

# The current round, filled by _begin_round().
var _spec: TargetSpec
var _layout: LayoutDef
var _cue_spot: Vector2 = Vector2.ZERO
var _first_ball_id: int = OBJECT_ID  ## The only ball the cue ball may hit first.
var _avoid_ids: Array[int] = []
var _start_pos: Dictionary = {}  ## avoid ball id -> start position


# ---------------------------------------------------------------- GameMode

func setup(state: SimState, table: TableDef) -> void:
	_state = state
	_table = table
	_rounds = _make_rounds()
	_round_index = 0
	score = 0
	last_points = -1
	finished = false
	_rng.randomize()
	_begin_round(0)
	RackBuilder.new_game(state, table, _layout)


## The cue ball is put on its round spot automatically (no free placement).
func initial_cue_placement() -> CuePlacement:
	return CuePlacement.fixed(_cue_spot)


func target_spec() -> TargetSpec:
	return _spec


## Layouts must stay exact: no rack jitter, and no break rules for the first shot.
func randomize_racks() -> bool:
	return false


func legal_first_balls(_player_index: int) -> Array[int]:
	var ids: Array[int] = [_first_ball_id]
	return ids


func status_text() -> String:
	return "Round %d/%d   Score %d" % [_display_round(), _rounds.size(), score]


func solo_stats() -> Array[SoloStat]:
	var stats: Array[SoloStat] = []
	stats.append(SoloStat.make_text("ROUND", "%d / %d" % [_display_round(), _rounds.size()]))
	var shot := SoloStat.make_text("SHOT", _rounds[mini(_round_index, _rounds.size() - 1)].title)
	shot.weight = 1.4
	stats.append(shot)
	stats.append(SoloStat.make_text("LAST", "-" if last_points < 0 else str(last_points)))
	stats.append(SoloStat.make_number("SCORE", score, true))
	return stats


func on_shot_ended(state: SimState, report: ShotReport) -> ShotResult:
	var result := ShotResult.new()
	var round_no := _round_index + 1

	# --- Judge the shot ---
	var points := 0
	var note := ""
	var foul_reason := _foul_reason(state, report, result)
	if not foul_reason.is_empty():
		result.foul = true
		note = "%s - no score" % foul_reason
	else:
		var ball := state.get_ball(OBJECT_ID)
		if ball == null or not ball.is_on_table():
			note = "Ball pocketed - no score"
		else:
			points = _spec.points_at(ball.pos)
			note = _ring_text(points)

	score += points
	last_points = points
	result.score_delta = points
	var round_message := "Round %d: %s" % [round_no, note]

	result.celebrate_points = points  # PoolGame plays the target effect when this is > 0.

	# --- Finished, or a pause and then the next round ---
	if _round_index + 1 >= _rounds.size():
		_round_index += 1
		finished = true
		result.game_over = true
		result.message = "%s\nTarget Practice complete!  Final score %d" % [round_message, score]
		return result

	# The old target and the resting balls stay on screen during the delay; the next round is only
	# built when PoolGame calls _start_next_round afterwards.
	result.message = round_message
	result.followup_delay = ROUND_DELAY_SCORED if points > 0 else ROUND_DELAY_MISSED
	result.followup = _start_next_round.bind(state)
	return result


## Called by PoolGame after the delay: sets up the next round and hands back the rerack.
func _start_next_round(state: SimState) -> ShotResult:
	_round_index += 1
	_begin_round(_round_index)
	_clear_stale_balls(state)
	var result := ShotResult.new()
	result.rerack = _layout  # PoolGame places ball 17 and the extras (and clears the tray).
	result.cue_placement = CuePlacement.fixed(_cue_spot)
	result.message = "Next: %s" % _rounds[_round_index].title.capitalize()
	return result


# ---------------------------------------------------------------- rounds

## Three rounds, each building on the last:
##   1. straight-on, short.      2. cut angle, longer, one avoid ball.
##   3. bigger cut, combo ball, two avoid balls.
## Tweak the numbers freely. Ball ids 18-21 are the extras (21 is spare).
func _make_rounds() -> Array[RoundCfg]:
	var rounds: Array[RoundCfg] = []

	var r1 := RoundCfg.new()
	r1.title = "STRAIGHT"
	r1.target_frac = Vector2(0.78, 0.50)
	r1.cut_deg = 0.0
	r1.cue_to_contact = 0.50
	r1.object_to_target = 0.55
	rounds.append(r1)

	var r2 := RoundCfg.new()
	r2.title = "CUT"
	r2.target_frac = Vector2(0.78, 0.38)
	r2.cut_deg = 20.0
	r2.cue_to_contact = 0.70
	r2.object_to_target = 0.80
	r2.avoid.append(ExtraCfg.make(18, false, 0.55, 0.11))
	rounds.append(r2)

	var r3 := RoundCfg.new()
	r3.title = "COMBO"
	r3.target_frac = Vector2(0.82, 0.45)
	r3.cut_deg = 30.0
	r3.cue_to_contact = 0.70
	r3.object_to_target = 0.70
	r3.combo_id = 19
	r3.avoid.append(ExtraCfg.make(18, false, 0.50, -0.10))  # beside ball 17's path
	r3.avoid.append(ExtraCfg.make(20, true, 0.50, 0.10))  # beside the cue ball's path
	rounds.append(r3)

	return rounds


## Works out where everything goes for round `index` and stores it in _layout, _cue_spot, _spec,
## _first_ball_id and the avoid-ball bookkeeping.
func _begin_round(index: int) -> void:
	var rc: RoundCfg = _rounds[index]
	var size := _table.size
	var contact := 2.0 * _table.ball_radius + RackBuilder.BALL_GAP  # center-to-center when touching

	var along := Vector2.RIGHT.rotated(deg_to_rad(rc.shot_dir_deg))  # direction ball 17 travels
	var target := Vector2(size.x * rc.target_frac.x, size.y * rc.target_frac.y)
	var object_pos := target - along * rc.object_to_target

	# The ball the cue ball hits first: ball 17, or the combo ball sitting behind it on the line.
	var first_pos := object_pos
	if rc.combo_id >= 0:
		first_pos = object_pos - along * (contact + rc.combo_gap)

	# Ghost ball: where the cue ball's center is when it touches the first ball. The first ball
	# leaves along `along`, the cue ball arrives at the cut angle.
	var ghost := first_pos - along * contact
	var travel := along.rotated(deg_to_rad(rc.cut_deg))
	var cue_pos := ghost - travel * rc.cue_to_contact

	var ids: Array[int] = [OBJECT_ID]
	var positions: Array[Vector2] = [object_pos]
	if rc.combo_id >= 0:
		ids.append(rc.combo_id)
		positions.append(first_pos)
	var avoid_ids: Array[int] = []
	for extra in rc.avoid:
		var p: Vector2
		if extra.on_cue_path:
			p = cue_pos + (ghost - cue_pos) * extra.t + _perp(travel) * extra.lateral
		else:
			p = object_pos + (target - object_pos) * extra.t + _perp(along) * extra.lateral
		ids.append(extra.ball_id)
		positions.append(p)
		avoid_ids.append(extra.ball_id)

	# Random mirror so rounds vary between games. The table is symmetric, so everything that fits
	# still fits.
	var flip_x := _rng.randf() < 0.5
	var flip_y := _rng.randf() < 0.5
	target = _mirror(target, size, flip_x, flip_y)
	cue_pos = _mirror(cue_pos, size, flip_x, flip_y)
	for i in positions.size():
		positions[i] = _mirror(positions[i], size, flip_x, flip_y)

	_layout = LayoutDef.new()
	for i in ids.size():
		_layout.ids.append(ids[i])
		_layout.positions.append(positions[i])
		_warn_if_off_table(positions[i], "ball %d (round %d)" % [ids[i], index + 1])
	_warn_if_off_table(cue_pos, "cue ball (round %d)" % (index + 1))
	_cue_spot = cue_pos

	_spec = TargetSpec.new()
	_spec.center = target
	_spec.radii.assign(RING_RADII)
	_spec.points.assign(RING_POINTS)

	_first_ball_id = rc.combo_id if rc.combo_id >= 0 else OBJECT_ID
	_avoid_ids = avoid_ids
	_start_pos.clear()
	for i in ids.size():
		if avoid_ids.has(ids[i]):
			_start_pos[ids[i]] = positions[i]


## Why this shot scores nothing, or "" if it counts. Also fills the foul list on `result`.
func _foul_reason(state: SimState, report: ShotReport, result: ShotResult) -> String:
	if report.cue_pocketed:
		result.fouls.append(ShotReport.Foul.SCRATCH)
		return "Scratch"
	if not report.made_contact():
		result.fouls.append(ShotReport.Foul.NO_CONTACT)
		return "No contact"
	if report.first_contact_ball != _first_ball_id:
		result.fouls.append(ShotReport.Foul.WRONG_FIRST_BALL)
		return "Wrong ball first"
	for id in _avoid_ids:
		var ball := state.get_ball(id)
		var start: Vector2 = _start_pos[id]
		if ball == null or not ball.is_on_table() or ball.pos.distance_to(start) > MOVED_EPS:
			return "Touched an avoid ball"
	return ""


## Takes balls that are not part of the next round off the table, and zeroes leftover spin on
## the rest. (BallsLayer frees the views of balls that are no longer in the state.)
func _clear_stale_balls(state: SimState) -> void:
	var keep := {ShotReport.CUE_ID: true}
	for id in _layout.ids:
		keep[id] = true
	for i in range(state.balls.size() - 1, -1, -1):
		var ball := state.balls[i]
		if not keep.has(ball.id):
			state.balls.remove_at(i)
		else:
			ball.roll_spin = Vector2.ZERO
			ball.side_spin = 0.0


# ---------------------------------------------------------------- helpers

func _display_round() -> int:
	return mini(_round_index + 1, _rounds.size())


func _ring_text(points: int) -> String:
	match points:
		100:
			return "Bullseye! +100"
		50:
			return "Middle ring +50"
		25:
			return "Outer ring +25"
	return "Missed the target"


func _perp(v: Vector2) -> Vector2:
	return Vector2(-v.y, v.x)


func _mirror(p: Vector2, size: Vector2, flip_x: bool, flip_y: bool) -> Vector2:
	return Vector2(size.x - p.x if flip_x else p.x, size.y - p.y if flip_y else p.y)


func _warn_if_off_table(p: Vector2, what: String) -> void:
	if p.x < EDGE_MARGIN or p.y < EDGE_MARGIN \
			or p.x > _table.size.x - EDGE_MARGIN or p.y > _table.size.y - EDGE_MARGIN:
		push_warning("TargetPracticeMode: %s is too close to a cushion or off the table at %s." % [what, p])
