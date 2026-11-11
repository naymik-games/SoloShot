class_name SimState
extends RefCounted
## Everything the simulator needs, as cloneable plain data.

var balls: Array[BallState] = []
var time: float = 0.0


func clone() -> SimState:
	var s := SimState.new()
	s.time = time
	for b in balls:
		s.balls.append(b.duplicate_state())
	return s


func get_ball(id: int) -> BallState:
	for b in balls:
		if b.id == id:
			return b
	return null


func get_cue_ball() -> BallState:
	return get_ball(0)


func any_moving() -> bool:
	for b in balls:
		if b.is_on_table() and b.is_moving():
			return true
	return false
