class_name FreePracticeMode
extends GameMode
## Simplest mode: rack 15 balls + cue, never ends. After a scratch the player places the cue ball
## anywhere. Clearing the table records the shots it took and (optionally) reracks.
## Fouls are detected and shown as a message so the foul framework can be tested, but nothing is penalized.

## Optional custom layout (e.g. a trick-shot puzzle). If null, a standard 15-ball rack is used.
## A custom layout is never reracked.
var layout: LayoutDef

## Show detected fouls (scratch, no contact, no rail) in the HUD message.
var show_detected_fouls: bool = true

## Rack again when the last object ball is pocketed.
var rerack_when_cleared: bool = true

## Shots taken on the current rack, and the stats from completed racks (0 = none yet).
var shots_this_rack: int = 0
var last_clear_shots: int = 0
var best_clear_shots: int = 0

## Tally for the solo bar. Balls pocketed on racks that were already reracked, the size of a
## rack, and a flag that hides the old rack's count for the frame between clearing and reracking.
var _banked_balls: int = 0
var _rack_size: int = 0
var _rerack_pending: bool = false

var _state: SimState
var _table: TableDef


func setup(state: SimState, table: TableDef) -> void:
	_table = table
	_state = state
	shots_this_rack = 0
	_banked_balls = 0
	_rerack_pending = false
	if layout != null:
		layout.apply_to(state)
	else:
		RackBuilder.new_game(state, table, RackBuilder.triangle_15(table))
	_rack_size = _count_object_balls(state)


## Same opening as 9-ball: the player places the cue ball anywhere behind the head string.
## Custom layouts (trick-shot puzzles) keep the cue ball where the layout put it.
func initial_cue_placement() -> CuePlacement:
	if layout != null:
		return null
	return CuePlacement.behind_head_string(_table)


## Panels for the solo bar: balls pocketed in total and on this rack, shots, best clear.
func solo_stats() -> Array[SoloStat]:
	var on_rack := 0 if _rerack_pending else _count_pocketed_object_balls(_state)
	var stats: Array[SoloStat] = []
	stats.append(SoloStat.make_number("POCKETED", _banked_balls + on_rack))
	stats.append(SoloStat.make_text("THIS RACK", "%d / %d" % [on_rack, _rack_size]))
	stats.append(SoloStat.make_number("SHOTS", shots_this_rack))
	stats.append(SoloStat.make_text("BEST CLEAR", "-" if best_clear_shots == 0 else str(best_clear_shots)))
	return stats


func on_shot_taken(shot: Shot) -> void:
	shots_this_rack += 1
	_rerack_pending = false


func on_shot_ended(state: SimState, report: ShotReport) -> ShotResult:
	var result := ShotResult.new()

	# Any ball is a legal first contact in free practice.
	result.fouls = report.detect_fouls([], true)
	result.foul = not result.fouls.is_empty()
	if result.foul and show_detected_fouls:
		var names := PackedStringArray()
		for f in result.fouls:
			names.append(ShotReport.foul_name(f))
		result.message = "Foul: " + ", ".join(names)

	if report.cue_pocketed:
		result.cue_placement = CuePlacement.anywhere(CuePlacement.head_spot(_table))

	if _table_cleared(state):
		last_clear_shots = shots_this_rack
		best_clear_shots = last_clear_shots if best_clear_shots == 0 else mini(best_clear_shots, last_clear_shots)
		shots_this_rack = 0
		var note := "Table cleared in %d shots" % last_clear_shots
		result.message = note if result.message.is_empty() else result.message + " | " + note
		if rerack_when_cleared and layout == null:
			result.rerack = RackBuilder.triangle_15(_table)
			_banked_balls += _rack_size
			_rerack_pending = true
	return result


func _count_object_balls(state: SimState) -> int:
	var n := 0
	for b in state.balls:
		if b.id != ShotReport.CUE_ID:
			n += 1
	return n


func _count_pocketed_object_balls(state: SimState) -> int:
	if state == null:
		return 0
	var n := 0
	for b in state.balls:
		if b.id != ShotReport.CUE_ID and not b.is_on_table():
			n += 1
	return n


## True when object balls exist but none are left on the table.
func _table_cleared(state: SimState) -> bool:
	var has_object_balls := false
	for b in state.balls:
		if b.id == ShotReport.CUE_ID:
			continue
		has_object_balls = true
		if b.is_on_table():
			return false
	return has_object_balls
