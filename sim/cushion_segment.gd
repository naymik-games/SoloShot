class_name CushionSegment
extends RefCounted
## A straight cushion segment. Endpoints act as rounded caps (see ball-cushion phase).

var a: Vector2
var b: Vector2
var normal: Vector2  ## Unit normal pointing INTO the table.


func _init(p_a: Vector2 = Vector2.ZERO, p_b: Vector2 = Vector2.ZERO, p_normal: Vector2 = Vector2.ZERO) -> void:
	a = p_a
	b = p_b
	normal = p_normal
