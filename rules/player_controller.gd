class_name PlayerController
extends RefCounted
## Decides what a player does on their turn: take a shot, or place the cue ball.
## PoolGame owns the phases and the simulation; a controller only makes decisions and reports them
## through the signals below. HumanController wraps the touch/mouse input; a computer opponent
## will implement the same interface.

## The player chose a shot. `spin` is the cue contact point on the ball (unit disc, ZERO = none).
@warning_ignore("unused_signal")
signal shot_decided(shot: Shot, spin: Vector2)
## The player is happy with the cue ball position (the ball in the SimState is already there).
@warning_ignore("unused_signal")
signal placement_confirmed


## True if this player uses the on-screen controls (aim line, power bar, spin, cue stick).
## False = a computer player: PoolGame hides those and the controller drives everything itself.
func uses_touch_controls() -> bool:
	return true


## It is this player's turn to shoot. Emit `shot_decided` when they have chosen.
func begin_shot(state: SimState) -> void:
	pass


## This player has the cue ball in hand under `placement`. Move the cue ball in `state`
## (see CuePlacer) to a legal spot, then emit `placement_confirmed`.
func begin_placement(state: SimState, placement: CuePlacement) -> void:
	pass


## Stop whatever is in progress (input, thinking). Called whenever the game leaves aiming/placing.
func cancel() -> void:
	pass
