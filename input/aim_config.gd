class_name AimConfig
extends Resource
## All aiming feel tunables. Save as a .tres (e.g. data/aim_config.tres) and tweak live.
## (Replaces the earlier version: adds the "Prediction" group.)

@export_group("Coarse drag")
## Ignore drag rotation when the touch is closer than this to the cue ball (pixels).
@export var coarse_dead_zone_px: float = 55.0

@export_group("Fine adjust")
## Radians of aim change per pixel dragged on the fine strip.
@export var fine_strip_sensitivity: float = 0.001


@export_group("Power")
## power = power_input ^ exponent. >1 gives more resolution for soft shots.
@export var power_curve_exponent: float = 1.6
## Fire is disabled below this power (in curved power units).
@export var min_fire_power: float = 0.02


@export_group("Prediction")
## Prediction always runs at full power (ignores the power bar).
## Stop simulating after this many seconds even if nothing happened.
@export var prediction_time_cap: float = 4.0
## Cushion bounces to follow before the aim line ends. 0 = line ends at the first rail.
@export var max_bounces: int = 0
@export var show_aim_line: bool = true
@export var show_ghost_ball: bool = true
@export var show_object_line: bool = true
## Length of the object-ball line, in meters, measured from the ball's edge.
@export var object_line_length: float = 0.25

@export_group("Desktop testing")
@export var key_nudge_degrees: float = 0.25
## Holding Shift multiplies key nudges by this.
@export var key_fine_multiplier: float = 0.1
@export var key_power_step: float = 0.05
@export var wheel_power_step: float = 0.02
