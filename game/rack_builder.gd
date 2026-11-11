class_name RackBuilder
extends RefCounted
## Standard rack layouts and helpers to put them on the table. Layouts hold object balls only
## (no cue ball) as a LayoutDef (parallel arrays of ids and positions, in table meters).
## Modes build the layout they want; PoolGame places it when a mode asks for a rerack.

## Tiny gap between racked balls so none starts overlapping.
const BALL_GAP: float = 0.0004

## 15-ball triangle rows, apex first: 1 at the apex, 8 in the center, one solid and one stripe
## in the back corners.
const ROWS_15: Array = [[1], [9, 2], [10, 8, 3], [11, 4, 12, 5], [6, 13, 14, 7, 15]]


## The apex of a rack sits on the foot spot.
static func foot_spot(table: TableDef) -> Vector2:
	return Vector2(table.size.x * 0.75, table.size.y * 0.5)


static func triangle_15(table: TableDef) -> LayoutDef:
	return _build(table, ROWS_15)


## 9-ball diamond: 1 at the apex, 9 in the center, the other seven balls shuffled.
## Pass shuffle = false for a fixed 2..8 order.
static func diamond_9(table: TableDef, shuffle: bool = true) -> LayoutDef:
	var others: Array[int] = [2, 3, 4, 5, 6, 7, 8]
	if shuffle:
		others.shuffle()
	var rows: Array = [
		[1],
		[others[0], others[1]],
		[others[2], 9, others[3]],
		[others[4], others[5]],
		[others[6]],
	]
	return _build(table, rows)


## Starts a fresh game on `state`: cue ball on the head spot plus the given rack.
static func new_game(state: SimState, table: TableDef, rack: LayoutDef) -> void:
	state.balls.clear()
	state.time = 0.0
	var cue := BallState.new()
	cue.id = ShotReport.CUE_ID
	cue.pos = CuePlacement.head_spot(table)
	state.balls.append(cue)
	place_rack(state, rack)


## Puts every ball in `rack` on the table at its rack position, at rest. Existing BallStates are
## reused (so their views carry over, including balls that were pocketed); missing ones are created.
## Balls that are not part of the rack, such as the cue ball, are left alone.
static func place_rack(state: SimState, rack: LayoutDef) -> void:
	for i in rack.ids.size():
		var ball := state.get_ball(rack.ids[i])
		if ball == null:
			ball = BallState.new()
			ball.id = rack.ids[i]
			state.balls.append(ball)
		ball.pos = rack.positions[i]
		ball.vel = Vector2.ZERO
		ball.status = BallState.Status.ON_TABLE
		ball.rolling = false


## Rows are laid out apex first, each row one ball-diameter-times-sqrt(3)/2 further toward the
## foot rail, centered on the table's long axis.
static func _build(table: TableDef, rows: Array) -> LayoutDef:
	var layout := LayoutDef.new()
	var d := 2.0 * table.ball_radius + BALL_GAP
	var foot := foot_spot(table)
	for row in rows.size():
		var ids: Array = rows[row]
		for k in ids.size():
			layout.ids.append(int(ids[k]))
			layout.positions.append(Vector2(
				foot.x + row * d * sqrt(3.0) * 0.5,
				foot.y + (k - (ids.size() - 1) * 0.5) * d))
	return layout
