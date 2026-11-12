class_name GameSession
extends RefCounted
## Tiny static hand-off between the home menu and the pool game.
## No autoload needed: static vars live for the whole run of the game.

## -1 means "nothing chosen" (e.g. you pressed F6 on pool_game.tscn directly),
## in which case PoolGame keeps the mode set in the inspector.
static var selected_mode: int = -1
