class_name LayoutDef
extends Resource
## A starting layout: parallel arrays of ball ids and positions (meters).
## Shared by racks and trick-shot puzzles.

@export var ids: PackedInt32Array = PackedInt32Array()
@export var positions: PackedVector2Array = PackedVector2Array()


## Populates a SimState from this layout.
func apply_to(state: SimState) -> void:
	state.balls.clear()
	state.time = 0.0
	for i in ids.size():
		var b := BallState.new()
		b.id = ids[i]
		b.pos = positions[i]
		state.balls.append(b)
