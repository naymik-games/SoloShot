class_name HumanController
extends PlayerController
## A person using the touch/mouse controls. A thin adapter over AimController (aim, power, spin)
## and PlacementFlow (ball in hand). Every human player shares one instance: in pass-and-play the
## same controls just belong to whoever's turn it is.

var _aim: AimController
var _placement_flow: PlacementFlow


func _init(aim: AimController, placement_flow: PlacementFlow) -> void:
	_aim = aim
	_placement_flow = placement_flow
	_aim.shot_requested.connect(_on_aim_shot_requested)
	_placement_flow.confirmed.connect(_on_placement_flow_confirmed)


func uses_touch_controls() -> bool:
	return true


func begin_shot(state: SimState) -> void:
	var cue := state.get_cue_ball()
	if cue != null and cue.is_on_table():
		_aim.begin_aiming(cue.pos)


func begin_placement(state: SimState, placement: CuePlacement) -> void:
	_placement_flow.begin(state, placement)


func cancel() -> void:
	_aim.set_input_enabled(false)


func _on_aim_shot_requested(shot: Shot) -> void:
	# The spin set on the cue ball face stays in the aim state until the next begin_aiming().
	shot_decided.emit(shot, _aim.aim.spin)


func _on_placement_flow_confirmed() -> void:
	placement_confirmed.emit()
