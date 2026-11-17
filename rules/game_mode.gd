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


## Optional: the panels of the solo stat bar above the table (see SoloPanel). Empty = no bar.
## Only used by one-player modes; the HUD's text status is hidden when a bar is shown.
func solo_stats() -> Array[SoloStat]:
	var none: Array[SoloStat] = []
	return none


## Optional: a target to paint on the table (Target Practice). Null = none. PoolGame redraws it
## after every shot, so a mode may return a different target each round.
func target_spec() -> TargetSpec:
	return null


## False for modes whose layout must stay exact: PoolGame then skips the rack jitter and does not
## treat the first shot as a break (no break speed cap, no break aim error).
func randomize_racks() -> bool:
	return true


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


## Ids of the balls the next shot may legally hit first. Single source of truth: foul detection,
## computer players, ball hints and the red aim line all use it.
## Empty = any ball is legal (the break, or a mode without such a rule).
func legal_first_balls(_player_index: int) -> Array[int]:
	var none: Array[int] = []
	return none


## True if hitting this ball first would be legal. Drives the red aim line.
func is_legal_first_ball(ball_id: int, player_index: int) -> bool:
	var legal := legal_first_balls(player_index)
	return legal.is_empty() or legal.has(ball_id)


## Balls to ring briefly when a human player starts aiming. `new_turn` is true only for the first
## aiming of a turn (not when the player pocketed a ball and keeps shooting). Empty = no hint.
func hint_ball_ids(_player_index: int, _new_turn: bool) -> Array[int]:
	var none: Array[int] = []
	return none


## For computer players: true while the next shot is the break.
func is_break_shot() -> bool:
	return false


## The players' display names, so messages ("... wins", "... ball in hand") match the panels.
## Called once, before setup(). Modes that don't print player names ignore it.
func set_player_names(_names: Array[String]) -> void:
	pass


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
