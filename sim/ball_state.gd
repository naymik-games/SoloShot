class_name BallState
extends RefCounted
## (Replaces the earlier version: slide_remaining is gone; spin is now stored directly.)

enum Status { ON_TABLE, POCKETED }

var id: int = 0  ## 0 = cue ball by convention.
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var status: Status = Status.ON_TABLE
var rolling: bool = false  ## false = sliding phase (cloth contact point is slipping), true = pure rolling.

## Top/back spin, stored as the velocity (m/s) the ball's bottom contact point has relative to the
## ball's centre. Pure rolling is roll_spin == -vel. No spin is (0, 0).
## Topspin points against the direction of travel, backspin along it.
var roll_spin: Vector2 = Vector2.ZERO
## Side spin (english) as rim speed in m/s (spin rate * ball radius). Positive = clockwise on screen.
var side_spin: float = 0.0


## True while the ball is moving, or is still slipping on the cloth (e.g. a ball with backspin
## that has just stopped dead against another ball and is about to move again).
func is_moving() -> bool:
	if vel.length_squared() > 0.0:
		return true
	return not rolling and (vel + roll_spin).length_squared() > 1e-12


func is_on_table() -> bool:
	return status == Status.ON_TABLE


func duplicate_state() -> BallState:
	var b := BallState.new()
	b.id = id
	b.pos = pos
	b.vel = vel
	b.status = status
	b.rolling = rolling
	b.roll_spin = roll_spin
	b.side_spin = side_spin
	return b
