class_name GameSession
extends RefCounted
## Tiny static hand-off between the home menu and the pool game.
## No autoload needed: static vars live for the whole run of the game.

## -1 means "nothing chosen" (e.g. you pressed F6 on pool_game.tscn directly),
## in which case PoolGame keeps the mode set in the inspector.
static var selected_mode: int = -1

## Who plays seat 2 in two-player modes: 1 = the computer, 0 = a second human,
## -1 = nothing chosen (PoolGame keeps its computer_opponent inspector value).
static var computer_opponent: int = -1
