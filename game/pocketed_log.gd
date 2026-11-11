class_name PocketedLog
extends RefCounted
## Record of every object ball pocketed, in order. Owned by PoolGame and fed live from the
## simulator events. The cue ball is not logged (scratches are handled by the rules).
##
## The log is history; what is *currently* pocketed comes from the live ball state. visible_ids()
## combines them, so a ball a mode respots (e.g. the 9 after a foul) drops out of the tray on
## its own and is shown again, last, if it gets pocketed a second time.

## Emitted whenever entries are added or cleared.
signal changed


class Entry:
	var ball_id: int
	var pocket_index: int
	var shot_number: int

	func _init(p_ball_id: int, p_pocket_index: int, p_shot_number: int) -> void:
		ball_id = p_ball_id
		pocket_index = p_pocket_index
		shot_number = p_shot_number


var entries: Array[Entry] = []


## `shot_number` is the 1-based number of the shot these events belong to.
func add_events(events: Array[SimEvent], shot_number: int) -> void:
	var added := false
	for e in events:
		if e.type != SimEvent.Type.BALL_POCKETED or e.ball_a == ShotReport.CUE_ID:
			continue
		entries.append(Entry.new(e.ball_a, e.pocket_index, shot_number))
		added = true
	if added:
		changed.emit()


## Forget everything (rerack, mode restart).
func clear() -> void:
	if entries.is_empty():
		return
	entries.clear()
	changed.emit()


## Total pocketing events logged, including balls that were later respotted.
func count() -> int:
	return entries.size()


## Ball ids that are pocketed right now, in the order they dropped.
func visible_ids(state: SimState) -> Array[int]:
	var last := {}  # ball id -> index of its most recent entry
	for i in entries.size():
		last[entries[i].ball_id] = i
	var ids: Array[int] = []
	for i in entries.size():
		var entry := entries[i]
		if last[entry.ball_id] != i:
			continue
		var ball := state.get_ball(entry.ball_id)
		if ball != null and not ball.is_on_table():
			ids.append(entry.ball_id)
	return ids
