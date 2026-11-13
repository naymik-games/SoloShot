class_name TableView
extends Node2D
## Draws the table: your art texture if TableDef.art_texture is set, otherwise the procedural table.
## Keep this node at (0,0).
## (Replaces the earlier version: adds art drawing, a background, and a collision-geometry overlay.)

@export var background_color: Color = Color("#1d263b")

@export_group("Procedural look")
@export var rail_color: Color = Color(0.36, 0.23, 0.12)
@export var felt_color: Color = Color(0.12, 0.48, 0.29)
@export var cushion_color: Color = Color(0.09, 0.41, 0.25)
@export var pocket_color: Color = Color(0.04, 0.04, 0.04)
@export var mark_color: Color = Color(1, 1, 1, 0.3)

@export_group("Debug")
## Draws the REAL collision geometry (cushion lines + pocket capture circles) over the art.
## Turn on to check that the art and the physics line up, then turn off.
@export var show_collision_geometry: bool = false
@export var draw_art_backing: bool = false
var table: TableDef
var mapper: CoordinateMapper


func setup(p_table: TableDef, p_mapper: CoordinateMapper) -> void:
	table = p_table
	mapper = p_mapper
	queue_redraw()


func _draw() -> void:
	if table == null or mapper == null:
		return
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), background_color)
	if table.art_texture != null and mapper.art_scale > 0.0:
		_draw_art()
	else:
		_draw_procedural()
	if show_collision_geometry:
		_draw_collision_geometry()


func _draw_art() -> void:
	var k := mapper.art_scale
	var rect := Rect2(mapper.art_origin, table.art_texture.get_size() * k)
	if draw_art_backing:
		var backing := StyleBoxFlat.new()
		backing.bg_color = pocket_color
		backing.set_corner_radius_all(int(16.0 * k))
		draw_style_box(backing, rect)
	draw_texture_rect(table.art_texture, rect, false)


func _draw_procedural() -> void:
	var s := mapper.scale
	var top_left := mapper.to_screen(Vector2.ZERO)
	var size_px := table.size * s
	var rail_px := table.rail_width * s

	draw_rect(Rect2(top_left - Vector2(rail_px, rail_px), size_px + Vector2(rail_px, rail_px) * 2.0), rail_color)
	draw_rect(Rect2(top_left, size_px), felt_color)

	var head_x := table.size.x * 0.25
	var mid_y := table.size.y * 0.5
	draw_line(mapper.to_screen(Vector2(head_x, 0.0)), mapper.to_screen(Vector2(head_x, table.size.y)), mark_color, 1.0)
	draw_circle(mapper.to_screen(Vector2(head_x, mid_y)), 3.0, mark_color)
	draw_circle(mapper.to_screen(Vector2(table.size.x * 0.75, mid_y)), 3.0, mark_color)

	var t := table.cushion_thickness
	for c in table.cushions:
		var out := -c.normal * (t * 0.5)
		draw_line(mapper.to_screen(c.a + out), mapper.to_screen(c.b + out), cushion_color, t * s)

	for p in table.pockets:
		draw_circle(mapper.to_screen(p.center), p.capture_radius * s * 0.8, pocket_color)


func _draw_collision_geometry() -> void:
	var s := mapper.scale
	for c in table.cushions:
		draw_line(mapper.to_screen(c.a), mapper.to_screen(c.b), Color(1, 0.2, 0.9, 0.9), 1.5)
	for p in table.pockets:
		draw_arc(mapper.to_screen(p.center), p.capture_radius * s, 0.0, TAU, 40, Color(1, 1, 0, 0.8), 1.5, true)
	# Playfield outline.
	draw_rect(Rect2(mapper.to_screen(Vector2.ZERO), table.size * s), Color(0, 1, 1, 0.5), false, 1.0)
