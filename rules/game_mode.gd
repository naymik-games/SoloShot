class_name GameMode
extends RefCounted
## Base class for rules. Reads events, never touches physics directly.


## Rack / place balls. Called when the mode starts.
func setup(state: SimState, table: TableDef) -> void:
	pass


## Optional: how the cue ball is placed before the first shot (e.g. behind the head string for a
## break). Return null to start aiming immediately with the cue ball where setup() put it.
func initial_cue_placement() -> CuePlacement:
	return null


## Optional: text for the HUD status label (shot counter, next ball, ...). Empty = hide the label.
func status_text() -> String:
	return ""


## How many players take turns. 1 = solo (the default). PoolGame creates that many players.
func player_count() -> int:
	return 1


## A player's turn is starting (also called once when the game starts, for the first shooter).
## Modes with per-player state (groups, scores) key it by this index and remember it as the
## current shooter, so on_shot_ended knows whose shot it was.
func on_turn_started(player_index: int) -> void:
	pass


## For the player panels: the name of a player's group ("Solids", "Stripes", ...), or "" when
## they have none (yet) or the mode has no groups.
func player_group_name(player_index: int) -> String:
	return ""


## For the player panels: ids of the balls in a player's group, or empty when they have none.
func player_group_balls(player_index: int) -> Array[int]:
	return []


func on_shot_taken(shot: Shot) -> void:
	pass


## Called with events from a shot (streamed or batched).
## PoolGame also feeds the same events into the ShotReport, so most modes won't need this.
func on_events(events: Array[SimEvent], state: SimState) -> void:
	pass


## Called once all balls have stopped. `report` summarizes the whole shot (first contact,
## pocketed balls, cushion contact, ...). Return a verdict.
func on_shot_ended(state: SimState, report: ShotReport) -> ShotResult:
	return ShotResult.new()


## Called every physics frame while the game is live (aiming, placing, or a shot in flight).
func tick(delta: float) -> void:
	pass

func is_time_up() -> bool:
	return false

func time_up_message() -> String:
	return "Game over"
