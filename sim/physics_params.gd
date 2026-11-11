class_name PhysicsParams
extends Resource
## Tunable physics constants. Save as a .tres so you can tweak in the inspector.
## (Replaces the earlier version: ball_collision_iterations removed; collisions are now exact.)

@export var ball_restitution: float = 0.95
@export var cushion_restitution: float = 0.75
@export var cushion_tangent_loss: float = 0.0  ## Optional, 0..~0.05
@export var sliding_friction: float = 0.2
@export var rolling_friction: float = 0.01
@export var gravity: float = 9.81
@export var stop_speed: float = 0.005  ## Below this, snap velocity to zero.
@export var max_shot_speed: float = 6.0  ## Speed at power = 1.0
## Friction is applied once per substep. Collisions are resolved at their exact time inside it,
## so the substep no longer affects contact accuracy.
@export var substep: float = 1.0 / 480.0
