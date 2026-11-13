class_name Player
extends RefCounted
## One participant in a game: who they are and who makes their decisions.
## Rules that need per-player state (8-ball groups, scores) keep it in the GameMode, keyed by `index`.

var index: int
var display_name: String
var controller: PlayerController


func _init(p_index: int, p_name: String, p_controller: PlayerController) -> void:
	index = p_index
	display_name = p_name
	controller = p_controller
