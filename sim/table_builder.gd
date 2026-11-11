class_name TableBuilder
extends RefCounted
## Generates cushion segments and pockets from a TableDef.
##
## Cushions: 6 segments (2 on each long rail, 1 on each short rail), trimmed to leave pocket mouths.
## Normals point INTO the table. Segment endpoints act as the rounded jaw tips in the simulator.
##
## Pocket order (indices used by SimEvent.pocket_index):
##   0 top-left, 1 top-middle, 2 top-right, 3 bottom-left, 4 bottom-middle, 5 bottom-right


static func build(table: TableDef) -> void:
	table.cushions.clear()
	table.pockets.clear()

	var w := table.size.x
	var h := table.size.y
	var cm := table.corner_mouth
	var sm := table.side_mouth_half
	var mid := w * 0.5

	# Top rail (y = 0), normal points down into the table.
	_add_cushion(table, Vector2(cm, 0.0), Vector2(mid - sm, 0.0), Vector2.DOWN)
	_add_cushion(table, Vector2(mid + sm, 0.0), Vector2(w - cm, 0.0), Vector2.DOWN)
	# Bottom rail (y = h), normal points up.
	_add_cushion(table, Vector2(cm, h), Vector2(mid - sm, h), Vector2.UP)
	_add_cushion(table, Vector2(mid + sm, h), Vector2(w - cm, h), Vector2.UP)
	# Left rail (x = 0), normal points right.
	_add_cushion(table, Vector2(0.0, cm), Vector2(0.0, h - cm), Vector2.RIGHT)
	# Right rail (x = w), normal points left.
	_add_cushion(table, Vector2(w, cm), Vector2(w, h - cm), Vector2.LEFT)

	var co := table.corner_pocket_overhang
	var so := table.side_pocket_overhang
	var cr := table.corner_pocket_capture_radius
	var sr := table.side_pocket_capture_radius
	table.pockets.append(Pocket.new(Vector2(-co, -co), cr))        # 0 top-left
	table.pockets.append(Pocket.new(Vector2(mid, -so), sr))        # 1 top-middle
	table.pockets.append(Pocket.new(Vector2(w + co, -co), cr))     # 2 top-right
	table.pockets.append(Pocket.new(Vector2(-co, h + co), cr))     # 3 bottom-left
	table.pockets.append(Pocket.new(Vector2(mid, h + so), sr))     # 4 bottom-middle
	table.pockets.append(Pocket.new(Vector2(w + co, h + co), cr))  # 5 bottom-right


static func _add_cushion(table: TableDef, a: Vector2, b: Vector2, normal: Vector2) -> void:
	table.cushions.append(CushionSegment.new(a, b, normal))
