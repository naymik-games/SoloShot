class_name PredictionResult
extends RefCounted
## Data only. The overlay draws from this; it never touches the simulator.

enum Outcome { NOTHING, HITS_BALL, POCKETS_CUE }

var outcome: Outcome = Outcome.NOTHING

## Cue ball center path in meters: start, each cushion bounce followed, and the end point
## (ghost position if a ball is hit, otherwise where the line stopped).
var cue_path: PackedVector2Array = PackedVector2Array()

var hit_ball_id: int = -1  ## First ball contacted (HITS_BALL only).
var hit_cushion_first: bool = false  ## True if the cue ball touched a rail before the ball.
var ghost_pos: Vector2 = Vector2.ZERO  ## Cue ball center at first ball contact.
var object_start: Vector2 = Vector2.ZERO  ## Object ball center at contact.
var object_dir: Vector2 = Vector2.ZERO  ## Object ball departure direction (unit), ZERO if none.
var cue_dir_after: Vector2 = Vector2.ZERO  ## Cue ball direction right after contact (unit).
var stop_pos: Vector2 = Vector2.ZERO  ## Where the predicted line ended.
