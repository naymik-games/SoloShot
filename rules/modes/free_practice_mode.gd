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

var _table: TableDef


func setup(state: SimState, table: TableDef) -> void:
	_table = table
	shots_this_rack = 0
	if layout != null:
		layout.apply_to(state)
		return
	RackBuilder.new_game(state, table, RackBuilder.triangle_15(table))


## Same opening as 9-ball: the player places the cue ball anywhere behind the head string.
## Custom layouts (trick-shot puzzles) keep the cue ball where the layout put it.
func initial_cue_placement() -> CuePlacement:
	if layout != null:
		return null
	return CuePlacement.behind_head_string(_table)


func on_shot_taken(shot: Shot) -> void:
	shots_this_rack += 1


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
	return result


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
