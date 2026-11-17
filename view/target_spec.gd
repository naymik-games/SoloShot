class_name TargetSpec
extends RefCounted
## A painted target on the table, as a game mode describes it. Pure data: TargetView draws it,
## the mode scores against it. Units are table meters (same space as BallState.pos).

## Center of the target.
var center: Vector2 = Vector2.ZERO
## Ring radii in meters, smallest (bullseye) first.
var radii: Array[float] = []
## Points for each ring, same order as `radii`.
var points: Array[int] = []


## Points for a ball resting with its center at `pos`; 0 if it is outside every ring.
func points_at(pos: Vector2) -> int:
	var dist := pos.distance_to(center)
	for i in radii.size():
		if dist <= radii[i]:
			return points[i]
	return 0
