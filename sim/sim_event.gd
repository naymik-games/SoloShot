class_name SimEvent
extends RefCounted
## (Replaces the earlier version: adds exact contact positions and post-impact velocities.)
##
## Field usage by type:
##   BALL_BALL:     ball_a, ball_b, impact_speed (approach speed), position (midpoint),
##                  pos_a/pos_b (centers AT contact), vel_a_after/vel_b_after (right after impulse)
##   BALL_CUSHION:  ball_a, impact_speed (normal speed), position (point on cushion),
##                  pos_a (ball center at contact), vel_a_after
##   BALL_POCKETED: ball_a, pocket_index, impact_speed (speed on capture), position (pocket center),
##                  pos_a (ball center at capture)
##   BALLS_AT_REST: nothing else

enum Type { BALL_BALL, BALL_CUSHION, BALL_POCKETED, BALLS_AT_REST }

var type: Type
var time: float = 0.0
var ball_a: int = -1
var ball_b: int = -1
var pocket_index: int = -1
var impact_speed: float = 0.0
var position: Vector2 = Vector2.ZERO
var pos_a: Vector2 = Vector2.ZERO
var pos_b: Vector2 = Vector2.ZERO
var vel_a_after: Vector2 = Vector2.ZERO
var vel_b_after: Vector2 = Vector2.ZERO


static func make(p_type: Type, p_time: float) -> SimEvent:
	var e := SimEvent.new()
	e.type = p_type
	e.time = p_time
	return e
