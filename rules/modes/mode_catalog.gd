class_name ModeCatalog
extends RefCounted
## The playable game modes and how to build each one. The home menu and PoolGame both use
## ModeCatalog.Type, so the menu no longer has to depend on the PoolGame scene script.

## New types go at the end so a mode_type saved in a scene's inspector keeps its meaning.
enum Type { FREE_PRACTICE, NINE_BALL, TIME_TRIAL, EIGHT_BALL, NINE_BALL_VERSUS, TARGET_PRACTICE }


## `layout` is only used by Free Practice (an optional drill layout instead of a standard rack).
static func create(type: Type, layout: LayoutDef = null) -> GameMode:
	match type:
		Type.NINE_BALL:
			return NineBallMode.new()
		Type.NINE_BALL_VERSUS:
			return NineBallVersusMode.new()
		Type.TIME_TRIAL:
			return TimeTrialMode.new()
		Type.EIGHT_BALL:
			return EightBallMode.new()
		Type.TARGET_PRACTICE:
			return TargetPracticeMode.new()
		_:
			var free_mode := FreePracticeMode.new()
			free_mode.layout = layout
			return free_mode
