class_name BallState
extends RefCounted
## (Replaces the earlier version: adds slide_remaining for the friction model.)

enum Status { ON_TABLE, POCKETED }

var id: int = 0  ## 0 = cue ball by convention.
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var status: Status = Status.ON_TABLE
var rolling: bool = false  ## false = sliding phase, true = pure rolling.
## While sliding: how much speed (m/s) sliding friction may still remove before the ball is rolling.
## Set to 2/7 of the speed whenever a ball starts sliding (after a shot, collision, or cushion hit).
var slide_remaining: float = 0.0

# Reserved for later (spin):
# var spin: Vector3 = Vector3.ZERO


func is_moving() -> bool:
	return vel.length_squared() > 0.0


func is_on_table() -> bool:
	return status == Status.ON_TABLE


func duplicate_state() -> BallState:
	var b := BallState.new()
	b.id = id
	b.pos = pos
	b.vel = vel
	b.status = status
	b.rolling = rolling
	b.slide_remaining = slide_remaining
	return b
