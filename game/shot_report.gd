class_name ShotReport
extends RefCounted
## Summary of one shot. PoolGame builds it from the simulator's events and hands it to the mode
## in on_shot_ended, so modes judge the shot without tracking events themselves.

enum Foul { SCRATCH, NO_CONTACT, WRONG_FIRST_BALL, NO_RAIL }

const CUE_ID: int = 0

## First object ball the cue ball touched (-1 = the cue ball never touched anything).
var first_contact_ball: int = -1
var first_contact_time: float = -1.0

## Balls pocketed this shot, in order. Parallel arrays: pocketed_ids[i] went into pocketed_pockets[i].
## Includes the cue ball (id 0) if it was pocketed.
var pocketed_ids: Array[int] = []
var pocketed_pockets: Array[int] = []

var cue_pocketed: bool = false

## True if any ball hit a cushion after the cue ball's first contact with an object ball.
var cushion_after_contact: bool = false


## Feed events in the order the simulator produced them (batches can be added frame by frame).
func add_events(events: Array[SimEvent]) -> void:
	for e in events:
		match e.type:
			SimEvent.Type.BALL_BALL:
				if first_contact_ball < 0:
					if e.ball_a == CUE_ID:
						_set_first_contact(e.ball_b, e.time)
					elif e.ball_b == CUE_ID:
						_set_first_contact(e.ball_a, e.time)
			SimEvent.Type.BALL_CUSHION:
				if first_contact_ball >= 0:
					cushion_after_contact = true
			SimEvent.Type.BALL_POCKETED:
				pocketed_ids.append(e.ball_a)
				pocketed_pockets.append(e.pocket_index)
				if e.ball_a == CUE_ID:
					cue_pocketed = true


func _set_first_contact(ball_id: int, time: float) -> void:
	first_contact_ball = ball_id
	first_contact_time = time


func made_contact() -> bool:
	return first_contact_ball >= 0


## Pocketed balls excluding the cue ball, in the order they dropped.
func object_balls_pocketed() -> Array[int]:
	var ids: Array[int] = []
	for id in pocketed_ids:
		if id != CUE_ID:
			ids.append(id)
	return ids


## Returns the fouls found in this shot (empty = clean shot). The mode decides which of these
## matter and what they cost; this only reports what happened.
##   legal_first_balls: ball ids the cue ball may legally hit first. Empty = any ball is legal.
##   require_rail:      apply the "something must reach a cushion or be pocketed" rule.
func detect_fouls(legal_first_balls: Array[int] = [], require_rail: bool = true) -> Array[int]:
	var fouls: Array[int] = []
	if cue_pocketed:
		fouls.append(Foul.SCRATCH)
	if not made_contact():
		fouls.append(Foul.NO_CONTACT)
		return fouls  # Wrong-ball and rail rules are meaningless without a first contact.
	if not legal_first_balls.is_empty() and not legal_first_balls.has(first_contact_ball):
		fouls.append(Foul.WRONG_FIRST_BALL)
	if require_rail and not cushion_after_contact and object_balls_pocketed().is_empty():
		fouls.append(Foul.NO_RAIL)
	return fouls


static func foul_name(foul: int) -> String:
	match foul:
		Foul.SCRATCH:
			return "Scratch"
		Foul.NO_CONTACT:
			return "No contact"
		Foul.WRONG_FIRST_BALL:
			return "Wrong ball first"
		Foul.NO_RAIL:
			return "No rail"
	return "Foul"


## One-line summary for debugging.
func describe() -> String:
	return "first contact: %s | pocketed: %s | cue pocketed: %s | cushion after contact: %s" % [
		str(first_contact_ball) if made_contact() else "none",
		str(pocketed_ids),
		str(cue_pocketed),
		str(cushion_after_contact)]
