class_name TimeTrialMode
extends GameMode
## Solo time trial: pocket as many balls as you can before the clock runs out.
##
## - Standard 15-ball rack. Clear it within the time limit and a fresh rack appears.
## - Every object ball pocketed adds bonus time: 10s on rack 1, 9s on rack 2, 8s on rack 3, ...
##   multiplied by the current multiplier (the same one the points use).
## - 100 points per object ball, multiplied by the current multiplier.
## - Multiplier: starts at 1x. Every shot that pockets a ball raises it by 0.5 BEFORE scoring
##   (1.5x on the 1st consecutive shot ... 4x on the 6th, the max). A miss lowers it by 0.5.
## - Scratch: -SCRATCH_TIME seconds and the multiplier resets to 1x. Balls pocketed on the same
##   shot still score and add time at the multiplier they earned, then it resets.
##   The cue ball respawns at the head spot.
## - No other fouls. The clock starts on the first shot (placing the break is free).
## - If the clock runs out during a shot, that shot still scores, but earns no bonus time.

const BALL_POINTS: int = 100

const MULT_MIN: float = 1.0
const MULT_MAX: float = 4.0
const MULT_STEP: float = 0.5

const BONUS_FIRST_RACK: float = 10.0
const BONUS_DROP_PER_RACK: float = 1.0
const BONUS_MIN: float = 0.0

const SCRATCH_TIME: float = 30.0

## Seconds on the clock at the start.
var start_time: float = 120.0
var time_left: float = 0.0
var score: int = 0
var multiplier: float = MULT_MIN
## Current rack, starting at 1.
var rack_number: int = 1
var balls_pocketed: int = 0
var racks_cleared: int = 0
var scratches: int = 0
var finished: bool = false

var _state: SimState
var _table: TableDef
var _clock_running: bool = false


func setup(state: SimState, table: TableDef) -> void:
	_state = state
	_table = table
	time_left = start_time
	score = 0
	multiplier = MULT_MIN
	rack_number = 1
	balls_pocketed = 0
	racks_cleared = 0
	scratches = 0
	finished = false
	_clock_running = false
	RackBuilder.new_game(state, table, _build_rack())


func initial_cue_placement() -> CuePlacement:
	return CuePlacement.behind_head_string(_table)


func status_text() -> String:
	return "Time %s   Score %d\nx%.1f   Rack %d   Balls %d" % [
		_format_time(time_left), score, multiplier, rack_number, balls_pocketed
	]


func tick(delta: float) -> void:
	if not _clock_running or finished:
		return
	time_left = maxf(time_left - delta, 0.0)


func is_time_up() -> bool:
	return _clock_running and time_left <= 0.0


func time_up_message() -> String:
	return "Time's up!\nScore %d  |  %d balls  |  %d racks cleared" % [score, balls_pocketed, racks_cleared]


func on_shot_taken(shot: Shot) -> void:
	_clock_running = true  # The clock starts on the first shot.


func on_shot_ended(state: SimState, report: ShotReport) -> ShotResult:
	var result := ShotResult.new()
	var expired := time_left <= 0.0
	var parts := PackedStringArray()

	var count: int = 0
	for id in report.pocketed_ids:
		if id != ShotReport.CUE_ID:
			count += 1

	# --- Points, multiplier and bonus time ---
	if count > 0:
		var points := roundi(count * BALL_POINTS * multiplier)
		multiplier = minf(multiplier + MULT_STEP, MULT_MAX)
		
		score += points
		result.score_delta = points
		balls_pocketed += count
		parts.append("+%d (x%.1f)" % [points, multiplier])
		if not expired:
			var bonus := count * _bonus_per_ball() #* multiplier
			time_left += bonus
			if bonus > 0.0:
				parts.append("+%ss" % _format_seconds(bonus))
	elif not report.cue_pocketed:
		multiplier = maxf(multiplier - MULT_STEP, MULT_MIN)  # plain miss

	# --- Scratch ---
	if report.cue_pocketed:
		scratches += 1
		multiplier = MULT_MIN
		time_left = maxf(time_left - SCRATCH_TIME, 0.0)
		parts.append("Scratch -%ds" % roundi(SCRATCH_TIME))
		result.foul = true
		result.fouls.append(ShotReport.Foul.SCRATCH)
		result.cue_placement = CuePlacement.fixed(CuePlacement.head_spot(_table))

	# --- Time up? ---
	if time_left <= 0.0:
		finished = true
		result.game_over = true
		result.message = time_up_message()
		return result

	# --- Rack cleared: fresh rack ---
	if _object_balls_on_table(state) == 0:
		racks_cleared += 1
		rack_number += 1
		result.rerack = _build_rack()
		parts.append("Rack cleared!")

	if not parts.is_empty():
		result.message = "  ".join(parts)
	return result


# ---------------------------------------------------------------- helpers

func _bonus_per_ball() -> float:
	return maxf(BONUS_FIRST_RACK - (rack_number - 1) * BONUS_DROP_PER_RACK, BONUS_MIN)


func _build_rack() -> LayoutDef:
	return RackBuilder.triangle_15(_table)


func _object_balls_on_table(state: SimState) -> int:
	var n: int = 0
	for b in state.balls:
		if b.id != ShotReport.CUE_ID and b.is_on_table():
			n += 1
	return n


func _format_seconds(t: float) -> String:
	return "%d" % roundi(t) if is_equal_approx(t, roundf(t)) else "%.1f" % t


func _format_time(t: float) -> String:
	var minutes := floori(t / 60.0)
	return "%d:%04.1f" % [minutes, t - minutes * 60.0]
