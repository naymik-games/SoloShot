class_name DebugOverlay
extends Node2D
## Toggleable: cushion segments, pocket circles, velocity vectors.

var state: SimState
var table: TableDef
var mapper: CoordinateMapper
var enabled: bool = false


func _process(_delta: float) -> void:
	if enabled:
		queue_redraw()


func _draw() -> void:
	if not enabled or state == null:
		return
	# TODO: draw cushions, pockets, ball velocity vectors, per-ball ids.
	pass
