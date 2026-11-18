class_name AiProfiles
extends RefCounted
## Difficulty profiles for the computer opponent. A profile is just an AiConfig with a few
## values changed, so the player picks Easy / Medium / Hard while the individual knobs stay
## here (and in ai_config.gd) for you to tune.
##
## MEDIUM is a plain AiConfig.new(), i.e. whatever the defaults in ai_config.gd are today.
## All Easy / Hard numbers are starting points: playtest and adjust.

enum Level { EASY, MEDIUM, HARD }

const LEVEL_NAMES: Array[String] = ["Easy", "Medium", "Hard"]


## One line for the settings screen.
static func describe(level: int) -> String:
	match level:
		Level.EASY:
			return "Misses more often and just plays the simplest shot, without planning the next one."
		Level.HARD:
			return "Aims precisely, controls its speed and sets up its next shot."
		_:
			return "A solid player that thinks one shot ahead."


## A fresh AiConfig for the given Level. Safe to tweak further, nothing is shared.
static func make(level: int) -> AiConfig:
	var c := AiConfig.new()
	match level:
		Level.EASY:
			c.aim_sigma_deg = 0.7
			c.power_sigma = 0.10
			c.max_cut_deg = 55.0
			c.max_corner_entry_deg = 50.0
			c.max_side_entry_deg = 35.0
			c.position_weight = 0.0  # Off: the basic AI, best pocketing shot by geometry alone.
		Level.HARD:
			c.aim_sigma_deg = 0.06
			c.power_sigma = 0.03
			c.max_cut_deg = 75.0
			c.max_corner_entry_deg = 65.0
			c.max_side_entry_deg = 50.0
			c.position_weight = 0.8
			c.position_candidates = 6
			c.position_samples = 2  # Scores lines by how they hold up with its own noise (slower planning).
		_:
			pass  # MEDIUM: the AiConfig defaults.
	return c
