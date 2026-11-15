class_name SoloStat
extends RefCounted
## One panel of the solo bar above the table (see SoloPanel). A game mode returns a list of these
## from GameMode.solo_stats(); the mode only says WHAT to show, SoloPanel decides how it looks.

enum Kind {
	TEXT,  ## small label on top, big value underneath
	BALL,  ## small label on top, a ball icon underneath (e.g. the next ball to pocket)
	PIPS,  ## no label: row of circles that fill in half steps (the Quick Fire multiplier)
}

var kind: Kind = Kind.TEXT
var label: String = ""
## TEXT: the value as shown.
var text: String = ""
## TEXT with count_up: the value the display rolls toward (the score).
var number: int = 0
var count_up: bool = false
## Flashes the value red (low time).
var warn: bool = false
## Solid tint for the value (e.g. penalty shots). Alpha 0 = default color.
var tint: Color = Color(0.0, 0.0, 0.0, 0.0)
## Gold frame and glow, like the active player's panel.
var accent: bool = false
## Relative width of this panel.
var weight: float = 1.0
## BALL: ball id to draw, or -1 for an empty slot.
var ball_id: int = -1
## PIPS: number of circles, and how many half steps are filled (2 = one full circle).
var pips_total: int = 0
var pips_steps: int = 0


static func make_text(p_label: String, p_text: String) -> SoloStat:
	var s := SoloStat.new()
	s.kind = Kind.TEXT
	s.label = p_label
	s.text = p_text
	return s


static func make_number(p_label: String, value: int, p_count_up: bool = false) -> SoloStat:
	var s := make_text(p_label, str(value))
	s.number = value
	s.count_up = p_count_up
	return s


static func make_ball(p_label: String, p_ball_id: int) -> SoloStat:
	var s := SoloStat.new()
	s.kind = Kind.BALL
	s.label = p_label
	s.ball_id = p_ball_id
	return s


static func make_pips(total: int, filled_half_steps: int) -> SoloStat:
	var s := SoloStat.new()
	s.kind = Kind.PIPS
	s.pips_total = total
	s.pips_steps = clampi(filled_half_steps, 0, total * 2)
	return s
