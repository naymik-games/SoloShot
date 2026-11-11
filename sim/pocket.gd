class_name Pocket
extends RefCounted

var center: Vector2
var capture_radius: float


func _init(p_center: Vector2 = Vector2.ZERO, p_capture_radius: float = 0.0) -> void:
	center = p_center
	capture_radius = p_capture_radius
