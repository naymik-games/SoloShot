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

@export_group("Break")
## Cue ball speed at power = 1.0 when the shot is a break (normal shots use max_shot_speed).
@export var break_max_shot_speed: float = 10.0
## Std deviation of the break's aim error in degrees, at full power. Scales linearly with power.
@export var break_aim_error_deg: float = 0.3
## Max random offset (meters, per axis) applied to each object ball when a rack is built.
@export var rack_jitter: float = 0.0002
## After jitter, balls are pushed apart until at least this far (meters) beyond touching,
## so the rack never starts with overlaps or perfectly flush contacts.
@export var rack_min_gap: float = 0.00002

@export_group("Spin")
## Where the cue tip lands when the spin control is at its edge, as a fraction of the ball radius.
## 1.0 would be the very rim of the ball (a miscue in real life); 0.7 is a generous but playable limit.
@export_range(0.0, 1.0, 0.01) var max_cue_offset: float = 0.7
## Side spin lost to the cloth, in m/s of rim speed per second. Higher = english dies out sooner.
@export var side_spin_decay: float = 1.5
## How hard a cushion grips side spin (0 = cushions ignore english). Limits how much sideways
## speed a bounce can add, relative to the bounce's normal impulse. Balls with no side spin are unaffected.
@export_range(0.0, 1.0, 0.01) var cushion_friction: float = 0.2
## Fraction of top/back spin kept through a cushion bounce. 0 = the ball restarts sliding with no
## roll spin (the old behaviour); side spin is handled separately by cushion_friction.
@export_range(0.0, 1.0, 0.01) var cushion_roll_retention: float = 0.0
