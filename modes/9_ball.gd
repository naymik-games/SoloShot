class_name NineBallMode
extends GameMode
## Solo 9-ball: pocket every ball in order in as few shots as possible.
##
## - Break: cue ball placed freely behind the head string, standard diamond rack.
## - Every shot the cue ball must hit the lowest-numbered ball on the table first.
## - Any ball may be pocketed on a legal shot. Pocketing the 9 on a legal shot ends the game.
## - Fouls add penalty shots and STACK: wrong ball first / no contact +1, scratch +2,
##   no cushion after contact +2 (counted as a scratch).
## - Scratch: cue ball respawns at the head spot (nearest free spot if occupied).
## - The 9 pocketed on a foul is respotted at its rack position, +2 shots.

const NINE: int = 9

const PENALTY_WRONG_BALL: int = 1
const PENALTY_NO_CONTACT: int = 1
const PENALTY_SCRATCH: int = 2
const PENALTY_NO_RAIL: int = 2
const PENALTY_NINE_RESPOT: int = 2

## Random order for balls 2-8 (1 stays at the apex, 9 in the center).
var shuffle_rack: bool = true

## If true, a no-cushion foul also sends the cue ball back to the head spot, like a real scratch.
## Default: it only costs the penalty and the cue ball stays where it stopped.
var no_rail_repositions_cue: bool = false

## Shot counter: every shot taken plus all penalty shots.
var shots: int = 0
## How many of `shots` were penalties.
var penalty_shots: int = 0
var finished: bool = false

var _state: SimState
var _table: TableDef
var _nine_spot: Vector2
var _required_ball: int = -1


func setup(state: SimState, table: TableDef) -> void:
	_state = state
	_table = table
	shots = 0
	penalty_shots = 0
	finished = false
	var rack := RackBuilder.diamond_9(table, shuffle_rack)
	_nine_spot = _spot_of(rack, NINE)
	RackBuilder.new_game(state, table, rack)
	_required_ball = _lowest_on_table(state)


func initial_cue_placement() -> CuePlacement:
	return CuePlacement.behind_head_string(_table)


func status_text() -> String:
	var text := "Shots: %d" % shots
	if penalty_shots > 0:
		text += "  (%d penalty)" % penalty_shots
	var next := _lowest_on_table(_state)
	if next > 0 and not finished:
		text += "\nNext ball: %d" % next
	return text


func on_shot_taken(shot: Shot) -> void:
	# Capture the ball that must be hit first BEFORE the shot changes the table.
	_required_ball = _lowest_on_table(_state)
	shots += 1


func on_shot_ended(state: SimState, report: ShotReport) -> ShotResult:
	var result := ShotResult.new()

	var fouls: Array[int] = report.detect_fouls([_required_ball], true)
	# A scratch is already penalized; don't charge the same event again as "no cushion".
	if fouls.has(ShotReport.Foul.SCRATCH):
		fouls.erase(ShotReport.Foul.NO_RAIL)
	result.fouls = fouls
	result.foul = not fouls.is_empty()

	var penalty: int = 0
	var parts := PackedStringArray()
	for f in fouls:
		var p := _penalty_for(f)
		penalty += p
		parts.append("%s (+%d)" % [ShotReport.foul_name(f), p])

	# --- The 9 ball ---
	if report.pocketed_ids.has(NINE):
		if not result.foul:
			finished = true
			result.game_over = true
			result.message = "9-ball! Cleared in %d shots" % shots
			return result
		_respot_nine(state)
		result.respot_balls.append(NINE)
		penalty += PENALTY_NINE_RESPOT
		parts.append("9 ball respotted (+%d)" % PENALTY_NINE_RESPOT)

	shots += penalty
	penalty_shots += penalty
	if not parts.is_empty():
		result.message = ", ".join(parts)

	# --- Cue ball ---
	if report.cue_pocketed:
		result.cue_placement = CuePlacement.fixed(CuePlacement.head_spot(_table))
	elif no_rail_repositions_cue and fouls.has(ShotReport.Foul.NO_RAIL):
		result.cue_placement = CuePlacement.fixed(CuePlacement.head_spot(_table))

	return result


# ---------------------------------------------------------------- helpers

func _penalty_for(foul: int) -> int:
	match foul:
		ShotReport.Foul.SCRATCH:
			return PENALTY_SCRATCH
		ShotReport.Foul.NO_CONTACT:
			return PENALTY_NO_CONTACT
		ShotReport.Foul.WRONG_FIRST_BALL:
			return PENALTY_WRONG_BALL
		ShotReport.Foul.NO_RAIL:
			return PENALTY_NO_RAIL
	return 0


## Lowest-numbered object ball still on the table (-1 if none).
func _lowest_on_table(state: SimState) -> int:
	var lowest: int = -1
	for b in state.balls:
		if b.id == ShotReport.CUE_ID or not b.is_on_table():
			continue
		if lowest < 0 or b.id < lowest:
			lowest = b.id
	return lowest


func _spot_of(rack: LayoutDef, ball_id: int) -> Vector2:
	var i := rack.ids.find(ball_id)
	return rack.positions[i] if i >= 0 else RackBuilder.foot_spot(_table)


## Puts the 9 back at its rack position. If another ball is sitting there, it goes to the nearest
## free spot straight behind it (toward the foot rail), then toward the head rail if needed.
func _respot_nine(state: SimState) -> void:
	var nine := state.get_ball(NINE)
	if nine == null:
		return
	var r := _table.ball_radius
	var step := r * 0.25
	var found := _nine_spot
	var ok := false
	for dir in [1.0, -1.0]:
		var p := _nine_spot
		while p.x >= r and p.x <= _table.size.x - r:
			if _spot_free(p, state):
				found = p
				ok = true
				break
			p.x += dir * step
		if ok:
			break
	nine.pos = found
	nine.vel = Vector2.ZERO
	nine.status = BallState.Status.ON_TABLE
	nine.rolling = false


func _spot_free(p: Vector2, state: SimState) -> bool:
	var min_dist := 2.0 * _table.ball_radius + RackBuilder.BALL_GAP
	for b in state.balls:
		if b.id == NINE or not b.is_on_table():
			continue
		if b.pos.distance_to(p) < min_dist:
			return false
	return true
