class_name PlacementOverlay
extends Node2D
## Drawn during the PLACING phase: the allowed region (for limited placement) and a ring around
## the cue ball that is green on a legal spot and red otherwise. Keep at (0,0): positions are
## screen pixels from the CoordinateMapper.

var mapper: CoordinateMapper
var table: TableDef

var valid_color: Color = Color(0.35, 0.9, 0.45, 0.95)
var invalid_color: Color = Color(0.95, 0.3, 0.3, 0.95)
var region_fill: Color = Color(1.0, 1.0, 1.0, 0.07)
var region_edge: Color = Color(1.0, 1.0, 1.0, 0.5)

var _placement: CuePlacement
var _cue_pos: Vector2 = Vector2.ZERO  # meters
var _valid: bool = true


func show_placement(placement: CuePlacement, cue_pos: Vector2, valid: bool) -> void:
	_placement = placement
	_cue_pos = cue_pos
	_valid = valid
	queue_redraw()


func _draw() -> void:
	if _placement == null or mapper == null or table == null:
		return

	if _placement.mode == CuePlacement.Mode.LIMITED:
		var field := Rect2(Vector2.ZERO, table.size).intersection(_placement.region)
		if field.has_area():
			var tl := mapper.to_screen(field.position)
			var br := mapper.to_screen(field.end)
			draw_rect(Rect2(tl, br - tl), region_fill)
			# Edge lines only where the region ends inside the playfield (e.g. the head string).
			if field.position.x > 0.001:
				draw_line(tl, Vector2(tl.x, br.y), region_edge, 2.0, true)
			if field.end.x < table.size.x - 0.001:
				draw_line(Vector2(br.x, tl.y), br, region_edge, 2.0, true)
			if field.position.y > 0.001:
				draw_line(tl, Vector2(br.x, tl.y), region_edge, 2.0, true)
			if field.end.y < table.size.y - 0.001:
				draw_line(Vector2(tl.x, br.y), br, region_edge, 2.0, true)

	var center := mapper.to_screen(_cue_pos)
	var radius := mapper.length_to_screen(table.ball_radius) * 1.45
	draw_arc(center, radius, 0.0, TAU, 40, valid_color if _valid else invalid_color, 2.5, true)
