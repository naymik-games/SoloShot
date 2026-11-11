class_name AimState
extends RefCounted
## UI-side aiming state. Angle is authoritative (makes fine adjust drift-free).

var cue_ball_pos: Vector2 = Vector2.ZERO  ## Meters.
var angle: float = 0.0  ## Radians, wrapped to [-PI, PI].
var power_input: float = 0.0  ## Raw control value 0..1 (what the power bar shows).
var power: float = 0.0  ## Curved power 0..1 (what the Shot uses).


func angle_degrees() -> float:
	return rad_to_deg(angle)


func to_shot() -> Shot:
	return Shot.new(Vector2.RIGHT.rotated(angle), power)
