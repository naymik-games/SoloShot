class_name Shot
extends RefCounted
## The only thing that crosses from input into the simulator.

var direction: Vector2 = Vector2.RIGHT  ## Unit vector.
var power: float = 0.0  ## 0..1

# Reserved for later (spin):
# var tip_offset: Vector2 = Vector2.ZERO


func _init(p_direction: Vector2 = Vector2.RIGHT, p_power: float = 0.0) -> void:
	direction = p_direction
	power = p_power
