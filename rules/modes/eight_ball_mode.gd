class_name EightBallMode
extends GameMode
## Two-player 8-ball, pass and play. Any legal pocket counts (no called pocket).
##
## - Break: the first player places the cue ball behind the head string. A legal break pockets a
##   ball or drives at least four object balls to a cushion. The table stays open after the break
##   (balls pocketed on the break do not assign groups). The breaker keeps shooting only if a ball
##   dropped. The 8 on the break is a re-rack and the same player breaks again.
## - Open table: the first ball hit must be a solid or a stripe (not the 8). The first legal pocket
##   assigns the shooter that ball's group (solids 1-7, stripes 9-15); if several drop on the shot,
##   the one that dropped first decides.
## - With groups set: the first ball hit must be one of your own, or the 8 once your group is gone.
## - Fouls: scratch, no contact, wrong ball first, no cushion after contact (and nothing pocketed),
##   illegal break. The opponent gets ball in hand anywhere (behind the head string after a scratch
##   on the break).
## - You keep shooting after a legal shot that pockets one of your own balls. Otherwise the turn
##   passes. Balls of the other group that you pocket stay down.
## - The 8: pocket it on a legal shot after clearing your group and you win. Pocket it early, or on
##   a foul (scratch included), and you lose.

enum Group { NONE, SOLIDS, STRIPES }

const EIGHT: int = 8
## Object balls that must reach a cushion on a legal break if nothing is pocketed.
const BREAK_CUSHION_BALLS: int = 4

var _state: SimState
var _table: TableDef

## Player shooting now (PoolGame tells us through on_turn_started).
var _current: int = 0
## Group of each player (Group values). Both NONE = open table.
var _groups: Array[int] = [0, 0]
## True until the break has been played (again after a re-rack).
var _break_pending: bool = true
## Display names of the players (set by PoolGame; falls back to "Player N").
var _player_names: Array[String] = []

# Captured in on_shot_taken, before the shot changes the table.
var _shooter: int = 0
var _shot_is_break: bool = false
var _shooting_at_eight: bool = false
var _legal_first: Array[int] = []
## Object balls that reached a cushion during the break shot (ball id -> true).
var _cushion_balls: Dictionary = {}


func setup(state: SimState, table: TableDef) -> void:
	_state = state
	_table = table
	_current = 0
	_groups[0] = Group.NONE
	_groups[1] = Group.NONE
	_break_pending = true
	RackBuilder.new_game(state, table, RackBuilder.triangle_15(table))


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


## What a player may hit first right now (empty = anything, i.e. the break).
func legal_first_balls(player_index: int) -> Array[int]:
	var ids: Array[int] = []
	if _break_pending:
		return ids
	var group := _groups[player_index]
	if group == Group.NONE:
		return _object_balls_on_table(false)
	var own := _balls_of_group_on_table(group)
	if own.is_empty():
		ids.append(EIGHT)
		return ids
	return own


## Groups and pocketed balls are on the player panels; this only says what the panels can't.
func status_text() -> String:
	if _break_pending:
		return "Break"
	if _groups[0] == Group.NONE:
		return "Table open"
	if _balls_of_group_on_table(_groups[_current]).is_empty():
		return "Shoot the 8-ball"
	return ""


func player_group_name(player_index: int) -> String:
	var group := _groups[player_index]
	return "" if group == Group.NONE else _group_name(group)


func player_group_balls(player_index: int) -> Array[int]:
	var ids: Array[int] = []
	var group := _groups[player_index]
	if group == Group.SOLIDS:
		for id in range(1, 8):
			ids.append(id)
	elif group == Group.STRIPES:
		for id in range(9, 16):
			ids.append(id)
	return ids


func on_shot_taken(_shot: Shot) -> void:
	_shooter = _current
	_shot_is_break = _break_pending
	_shooting_at_eight = false
	_legal_first = []
	_cushion_balls.clear()
	if _shot_is_break:
		return  # Any first contact is fine on the break.
	var group := _groups[_shooter]
	if group == Group.NONE:
		_legal_first = _object_balls_on_table(false)
		return
	var own := _balls_of_group_on_table(group)
	if own.is_empty():
		_shooting_at_eight = true
		_legal_first = [EIGHT]
	else:
		_legal_first = own


func on_events(events: Array[SimEvent], _sim_state: SimState) -> void:
	if not _shot_is_break:
		return
	for e in events:
		if e.type == SimEvent.Type.BALL_CUSHION and e.ball_a != ShotReport.CUE_ID:
			_cushion_balls[e.ball_a] = true


func on_shot_ended(_sim_state: SimState, report: ShotReport) -> ShotResult:
	var result := ShotResult.new()
	var shooter := _shooter
	var opponent := _other(shooter)
	var pocketed := report.object_balls_pocketed()

	# 8 on the break: put everything back, same player breaks again.
	if _shot_is_break and pocketed.has(EIGHT):
		_break_pending = true
		result.rerack = RackBuilder.triangle_15(_table)
		result.cue_placement = CuePlacement.behind_head_string(_table)
		result.message = "8-ball on the break: re-rack"
		return result

	# --- Fouls ---
	var fouls: Array[int] = report.detect_fouls(_legal_first, not _shot_is_break)
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

	# --- The 8 ---
	if pocketed.has(EIGHT):
		result.game_over = true
		if _shooting_at_eight and not foul:
			result.message = "8-ball! %s wins" % _name(shooter)
		elif not _shooting_at_eight:
			result.message = "8-ball pocketed too early\n%s wins" % _name(opponent)
		else:
			result.message = "8-ball pocketed on a foul (%s)\n%s wins" % [
				", ".join(foul_names), _name(opponent)]
		return result

	# --- Groups: the first legal pocket on an open table decides ---
	var lines := PackedStringArray()
	if _groups[shooter] == Group.NONE and not _shot_is_break and not foul:
		for id in pocketed:
			var group := _group_of(id)
			if group != Group.NONE:
				_groups[shooter] = group
				_groups[opponent] = Group.STRIPES if group == Group.SOLIDS else Group.SOLIDS
				lines.append("%s: %s" % [_name(shooter), _group_name(group)])
				break

	# --- Who shoots next ---
	var keeps_turn := false
	if not foul:
		if _shot_is_break:
			keeps_turn = not pocketed.is_empty()
		else:
			for id in pocketed:
				if _group_of(id) == _groups[shooter]:
					keeps_turn = true
					break
	if not keeps_turn:
		result.turn = ShotResult.Turn.SWITCH

	# --- Ball in hand ---
	if foul:
		lines.insert(0, "Foul: %s" % ", ".join(foul_names))
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


## Solids are 1-7, stripes 9-15. The 8 and the cue ball belong to no group.
func _group_of(ball_id: int) -> int:
	if ball_id >= 1 and ball_id <= 7:
		return Group.SOLIDS
	if ball_id >= 9 and ball_id <= 15:
		return Group.STRIPES
	return Group.NONE


func _group_name(group: int) -> String:
	return "Solids" if group == Group.SOLIDS else "Stripes"


## Ids of one group's balls still on the table (`group` must be SOLIDS or STRIPES).
func _balls_of_group_on_table(group: int) -> Array[int]:
	var ids: Array[int] = []
	for b in _state.balls:
		if b.is_on_table() and _group_of(b.id) == group:
			ids.append(b.id)
	return ids


## Every object ball still on the table, optionally including the 8.
func _object_balls_on_table(include_eight: bool) -> Array[int]:
	var ids: Array[int] = []
	for b in _state.balls:
		if b.id == ShotReport.CUE_ID or not b.is_on_table():
			continue
		if b.id == EIGHT and not include_eight:
			continue
		ids.append(b.id)
	return ids
