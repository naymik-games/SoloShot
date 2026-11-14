class_name AiConfig
extends Resource
## Tuning for the computer opponent. Save one as a .tres (or just leave PoolGame's slot empty
## for the defaults) and tweak it in the inspector.

@export_group("Skill")
## Std deviation of the aim error, in degrees. This is the whole difficulty knob of the basic AI.
## The error at the object ball grows with distance and with the cut angle, so long and thin
## shots fail first, like for a real player. ~0.1 = near perfect, ~0.25 = decent, ~0.6 = weak.
@export_range(0.0, 3.0, 0.01) var aim_sigma_deg: float = 0.25
## Relative std deviation of the shot power (0.05 = about 5 %).
@export_range(0.0, 0.3, 0.005) var power_sigma: float = 0.05

@export_group("Shot selection")
## Largest cut angle (cue ball path vs. the object ball's path to the pocket) the AI will try.
@export_range(10.0, 89.0, 1.0) var max_cut_deg: float = 70.0
## Largest angle between the object ball's path and the pocket's axis (diagonal for corners,
## across the table for side pockets). Bigger = more shots that skim the jaws.
@export_range(10.0, 89.0, 1.0) var max_corner_entry_deg: float = 60.0
@export_range(10.0, 89.0, 1.0) var max_side_entry_deg: float = 45.0
## A ball closer than (this x ball diameter) to a ball's path blocks the shot.
@export_range(1.0, 1.5, 0.01) var path_clearance: float = 1.05
## Score = cut_deg * cut_weight + entry_deg * entry_weight + total distance / table length * distance_weight.
## Lower is better; the AI plays the lowest-scoring shot.
@export var cut_weight: float = 1.0
@export var entry_weight: float = 0.5
@export var distance_weight: float = 25.0

@export_group("Power")
## Speed (m/s) the object ball should still have when it reaches the pocket.
@export var pocket_arrival_speed: float = 0.4
## Multiplier on the computed power (friction is modelled simply, so shoot a little firm).
@export_range(1.0, 2.0, 0.01) var power_margin: float = 1.15
@export_range(0.0, 0.5, 0.01) var min_power: float = 0.06
## Power for a "safe" hit when no pocketing shot exists. Must be firm enough that a ball
## reaches a cushion (otherwise it is a no-rail foul).
@export_range(0.1, 1.0, 0.01) var safe_hit_power: float = 0.45
@export_range(0.1, 1.0, 0.01) var break_power: float = 1.0

@export_group("Behaviour")
## Seconds the computer "thinks" before shooting (nothing is animated yet).
@export var think_time: float = 1.0
## Seconds before the computer drops the cue ball when it has ball in hand.
@export var placement_think_time: float = 0.7
## Grid of spots tried for ball in hand (columns x rows over the allowed area).
@export var placement_grid: Vector2i = Vector2i(12, 6)
## Break: how far from the head spot the cue ball may be placed sideways, as a fraction of table width.
@export_range(0.0, 0.4, 0.01) var break_spot_spread: float = 0.12
## Prints what the computer is aiming at (legal balls, chosen shot) to the output panel.
@export var debug_print: bool = true
