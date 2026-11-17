class_name NineBallVersusMode
extends GameMode
## Two-player 9-ball, pass and play (or against the computer in seat 2). One rack, first to
## pocket the 9 legally wins. Any legal pocket counts (no called pocket).
##
## - Break: the first player places the cue ball behind the head string, standard diamond rack.
##   A legal break pockets a ball or drives at least four object balls to a cushion, and must
##   hit the 1 first. The breaker keeps shooting only if a ball dropped.
## - Every shot the cue ball must hit the lowest-numbered ball on the table first. Any ball may
##   be pocketed on a legal shot.
## - You keep shooting after a legal shot that pockets any object ball. Otherwise the turn passes.
## - Fouls: scratch, no contact, wrong ball first, no cushion after contact (and nothing
##   pocketed), illegal break. The opponent gets ball in hand anywhere (behind the head string
##   after a scratch on the break). Balls pocketed on a foul stay down, except the 9.
## - The 9: pocketed on a legal shot (the break included) it wins the game. Pocketed on a foul
##   it is respotted at its rack position and the game goes on.
## - No push-out and no three-foul rule.

const NINE: int = 9
## Object balls that must reach a cushion on a legal break if nothing is pocketed.
const BREAK_CUSHION_BALLS: int = 4

## Random order for balls 2-8 (1 stays at the apex, 9 in the center).
var shuffle_rack: bool = true

var _state: SimState
var _table: TableDef
var _nine_spot: Vector2

## Player shooting now (PoolGame tells us through on_turn_started).
var _current: int = 0
## True until the break has been played.
var _break_pending: bool = true
var _player_names: Array[String] = []
## Balls each player has legally pocketed, in drop order (index = player; shown on the panels).
var _pocketed_by: Array = [[], []]

# Captured in on_shot_taken, before the shot changes the table.
var _shooter: int = 0
var _shot_is_break: bool = false
var _legal_first: Array[int] = []
## Object balls that reached a cushion during the break shot (ball id -> true).
var _cushion_balls: Dictionary = {}


func setup(state: SimState, table: TableDef) -> void:
	_state = state
	_table = table
	_current = 0
	_break_pending = true
	_pocketed_by = [[], []]
	var rack := RackBuilder.diamond_9(table, shuffle_rack)
	_nine_spot = _spot_of(rack, NINE)
	RackBuilder.new_game(state, table, rack)


func initial_cue_placement() -> CuePlacement:
	return CuePlacement.behind_head_string(_table)


func player_count() -> int:
	return 2


func on_turn_started(player_index: int) -> void:
	_current = player_index


func set_player_names(names: Array[String]) -> void:
	_player_names = names


func is_break_shot() -> bool:
	return _break_pending


func status_text() -> String:
	if _break_pending:
		return "Break"
	var next := _lowest_on_table(_state)
	return "Next ball: %d" % next if next > 0 else ""


## No groups in 9-ball, so nothing here; the panels show the balls each player has pocketed
## through player_panel_balls() instead.
func player_group_name(_player_index: int) -> String:
	return ""


## The panels show the balls a player has legally pocketed. (Not player_group_balls: the computer
## player may read that as "my targets", and in 9-ball everybody shoots at the same ball.)
func player_panel_balls(player_index: int) -> Array[int]:
	var ids: Array[int] = []
	if player_index >= 0 and player_index < _pocketed_by.size():
		for id in _pocketed_by[player_index]:
			ids.append(id)
	return ids


## Only the lowest-numbered ball on the table may be hit first (the 1 on the break).
func legal_first_balls(_player_index: int) -> Array[int]:
	var ids: Array[int] = []
	var lowest := _lowest_on_table(_state)
	if lowest > 0:
		ids.append(lowest)
	return ids


## Ring the next ball at the start of every shot.
func hint_ball_ids(player_index: int, _new_turn: bool) -> Array[int]:
	return legal_first_balls(player_index)


func on_shot_taken(_shot: Shot) -> void:
	_shooter = _current
	_shot_is_break = _break_pending
	# Same rule the hints and the red aim line use. Captured BEFORE the shot changes the table.
	_legal_first = legal_first_balls(_shooter)
	_cushion_balls.clear()


func on_events(events: Array[SimEvent], _sim_state: SimState) -> void:
	if not _shot_is_break:
		return
	for e in events:
		if e.type == SimEvent.Type.BALL_CUSHION and e.ball_a != ShotReport.CUE_ID:
			_cushion_balls[e.ball_a] = true


func on_shot_ended(state: SimState, report: ShotReport) -> ShotResult:
	var result := ShotResult.new()
	var shooter := _shooter
	var opponent := _other(shooter)
	var pocketed := report.object_balls_pocketed()

	# --- Fouls ---
	var fouls: Array[int] = report.detect_fouls(_legal_first, not _shot_is_break)
	# A scratch is already a foul; don't also report it as "no rail".
	if fouls.has(ShotReport.Foul.SCRATCH):
		fouls.erase(ShotReport.Foul.NO_RAIL)
	var foul_names := PackedStringArray()
	for f in fouls:
		foul_names.append(ShotReport.foul_name(f))
	if _shot_is_break and pocketed.is_empty() and _cushion_balls.size() < BREAK_CUSHION_BALLS:
		foul_names.append("Illegal break")
	var foul := not foul_names.is_empty()
	result.fouls = fouls
	result.foul = foul

	# --- Credit the shooter with legally pocketed balls (shown on their panel) ---
	if not foul:
		for id in pocketed:
			(_pocketed_by[shooter] as Array).append(id)

	# --- The 9 ---
	var respotted_nine := false
	if pocketed.has(NINE):
		if not foul:
			result.game_over = true
			result.message = "9-ball! %s wins" % _name(shooter)
			if _shot_is_break:
				_break_pending = false
			return result
		_respot_nine(state)
		result.respot_balls.append(NINE)
		respotted_nine = true

	# --- Who shoots next ---
	if foul or pocketed.is_empty():
		result.turn = ShotResult.Turn.SWITCH

	# --- Message and ball in hand ---
	var lines := PackedStringArray()
	if foul:
		lines.append("Foul: %s" % ", ".join(foul_names))
	if respotted_nine:
		lines.append("9-ball respotted")
	if foul:
		if _shot_is_break and report.cue_pocketed:
			result.cue_placement = CuePlacement.behind_head_string(_table)
		else:
			result.cue_placement = CuePlacement.anywhere(CuePlacement.head_spot(_table))
		lines.append("%s: ball in hand" % _name(opponent))
	result.message = "\n".join(lines)

	if _shot_is_break:
		_break_pending = false
	return result


# ---------------------------------------------------------------- helpers

func _other(player: int) -> int:
	return 1 - player


func _name(player: int) -> String:
	if player >= 0 and player < _player_names.size():
		return _player_names[player]
	return "Player %d" % (player + 1)


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
