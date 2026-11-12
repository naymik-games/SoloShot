class_name CoordinateMapper
extends RefCounted
## Single place where meters <-> pixels conversion happens.
## Assumes the nodes that draw with it sit at (0,0) with no camera.
## (Replaces the earlier version: adds fit_to_area() and the table art placement.)

## Screen-space rectangle of the whole table (rails included), updated by fit_to_area().
var table_rect: Rect2 = Rect2()

var scale: float = 300.0  ## pixels per meter
var offset: Vector2 = Vector2.ZERO  ## pixel position of table origin (0,0)

## Where the table art (if any) is drawn: top-left pixel and pixels-per-texture-pixel.
var art_origin: Vector2 = Vector2.ZERO
var art_scale: float = 0.0


func to_screen(meters: Vector2) -> Vector2:
	return offset + meters * scale


func to_world(pixels: Vector2) -> Vector2:
	return (pixels - offset) / scale


func length_to_screen(meters: float) -> float:
	return meters * scale


## Fits the whole table (art including rails, or the procedural table with rails) inside `area`,
## preserving aspect ratio and centering it. The area is the part of the screen NOT used by UI.
func fit_to_area(table: TableDef, area: Rect2) -> void:
	if table.art_texture != null:
		var art_size := table.art_texture.get_size()
		var k := maxf(minf(area.size.x / art_size.x, area.size.y / art_size.y), 0.01)
		art_scale = k
		art_origin = area.position + (area.size - art_size * k) * 0.5
		# Meters -> pixels is anchored to the art's playfield rectangle.
		scale = k * table.art_playfield_rect.size.x / table.size.x
		offset = art_origin + table.art_playfield_rect.position * k
		table_rect = Rect2(art_origin, art_size * k) 
	else:
		art_scale = 0.0
		var total := table.size + Vector2.ONE * table.rail_width * 2.0  # meters, including rails
		scale = maxf(minf(area.size.x / total.x, area.size.y / total.y), 1.0)
		offset = area.position + (area.size - table.size * scale) * 0.5
		table_rect = Rect2(offset - Vector2.ONE * table.rail_width * scale, total * scale)  # <- new


## Older helper, still available for procedural tables: margin pixels on every side of the viewport.
func fit_table(table_size: Vector2, viewport_size: Vector2, margin: float = 40.0, rail_width: float = 0.0) -> void:
	var total := table_size + Vector2.ONE * rail_width * 2.0
	var avail := viewport_size - Vector2.ONE * margin * 2.0
	scale = maxf(minf(avail.x / total.x, avail.y / total.y), 1.0)
	offset = (viewport_size - table_size * scale) * 0.5
	art_scale = 0.0
