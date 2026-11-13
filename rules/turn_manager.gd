class_name TurnManager
extends RefCounted
## Whose turn it is. Knows nothing about rules: the mode says when the turn passes
## (ShotResult.turn) and PoolGame calls advance().

var players: Array[Player] = []
var current_index: int = 0


func setup(p_players: Array[Player]) -> void:
	assert(not p_players.is_empty(), "A game needs at least one player.")
	players = p_players
	current_index = 0


func count() -> int:
	return players.size()


func current() -> Player:
	return players[current_index]


## Pass the turn to the next player (wraps around; with one player it stays on them).
func advance() -> void:
	current_index = (current_index + 1) % players.size()
