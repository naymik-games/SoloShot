class_name ShotResult
extends RefCounted

enum Turn { CONTINUE, SWITCH }

## Who shoots next. CONTINUE = the same player again (default, and all a solo mode ever needs).
## SWITCH = pass to the next player. `cue_placement` below applies to whoever shoots next.
var turn: Turn = Turn.CONTINUE

var score_delta: int = 0
var foul: bool = false
## Which fouls occurred (ShotReport.Foul values). `foul` should be true whenever this is non-empty.
var fouls: Array[int] = []
var respot_balls: Array[int] = []
## How the cue ball goes back on the table (null = leave it). If the cue ball was pocketed and this
## is null, PoolGame falls back to a fixed respot at the head spot.
var cue_placement: CuePlacement = null
## Put these balls back on the table at their rack positions (null = no rerack). Build it with
## RackBuilder. If the new rack lands on the cue ball, PoolGame moves the cue ball to the head spot.
var rerack: LayoutDef = null
var game_over: bool = false
var message: String = ""
