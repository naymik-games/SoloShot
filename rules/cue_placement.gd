class_name CuePlacement
extends RefCounted
## How the cue ball goes back on the table after a scratch or foul. A mode returns one of these in
## ShotResult.cue_placement; PoolGame carries it out. All positions and regions are in table
## meters, and refer to the cue ball's CENTER.
##
##   NONE     - leave the cue ball where it is (if it was pocketed, PoolGame falls back to the head spot).
##   FIXED    - put it back at `spot` automatically (nearest free position if the spot is occupied).
##   LIMITED  - the player drags it, but only inside `region` (e.g. behind the head string).
##   ANYWHERE - the player drags it anywhere on the playfield.
##
## For LIMITED and ANYWHERE, `spot` is where the ball starts out.

enum Mode { NONE, FIXED, LIMITED, ANYWHERE }

var mode: Mode = Mode.NONE
var spot: Vector2 = Vector2.ZERO
var region: Rect2 = Rect2()


static func none() -> CuePlacement:
	return CuePlacement.new()


static func fixed(p_spot: Vector2) -> CuePlacement:
	var p := CuePlacement.new()
	p.mode = Mode.FIXED
	p.spot = p_spot
	return p


static func limited(p_region: Rect2, p_spot: Vector2) -> CuePlacement:
	var p := CuePlacement.new()
	p.mode = Mode.LIMITED
	p.region = p_region
	p.spot = p_spot
	return p


static func anywhere(p_spot: Vector2) -> CuePlacement:
	var p := CuePlacement.new()
	p.mode = Mode.ANYWHERE
	p.spot = p_spot
	return p


# ---------------------------------------------------------------- common spots

## Head spot: on the head string, centered across the table.
static func head_spot(table: TableDef) -> Vector2:
	return Vector2(table.size.x * 0.25, table.size.y * 0.5)


## "Behind the head string": everything between the head rail and the head string.
static func behind_head_string(table: TableDef) -> CuePlacement:
	var head_x := table.size.x * 0.25
	return limited(Rect2(0.0, 0.0, head_x, table.size.y), head_spot(table))
