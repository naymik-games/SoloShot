class_name CuePlacementController
extends Node
## Input for the PLACING phase. Drag anywhere to move the cue ball (relative to where the drag
## began, so a finger never covers the ball); it slides around other balls and stays inside the
## allowed region. Confirm with the Place button (PoolGame) or Enter/Space.
##
## Moves the real cue BallState in the SimState, so BallsLayer draws it like any other ball.

signal placement_changed
signal confirmed

## Node2D whose local space matches CoordinateMapper pixels (normally the PoolGame node).
var world_node: Node2D
var mapper: CoordinateMapper
var table: TableDef

var enabled: bool = false
## Whether the cue ball is currently on a legal spot. Confirm is refused while false.
var valid: bool = true
var placement: CuePlacement

var _state: SimState
var _dragging: bool = false
var _drag_start_pointer: Vector2 = Vector2.ZERO  # pixels
var _drag_start_ball: Vector2 = Vector2.ZERO  # meters


## Start placing. The ball starts where it stands if that spot is legal (ball in hand after a foul),
## otherwise at the placement's spot.
func begin(state: SimState, p_placement: CuePlacement) -> void:
	_state = state
	placement = p_placement
	_dragging = false
	enabled = true

	var cue := state.get_cue_ball()
	if cue == null:
		enabled = false
		return
	var start := placement.spot
	if cue.is_on_table() and CuePlacer.is_valid(cue.pos, state, table, placement):
		start = cue.pos
	_apply(CuePlacer.find_free_position(start, state, table, placement))


func confirm() -> void:
	if not enabled or not valid:
		return
	enabled = false
	_dragging = false
	confirmed.emit()


func cancel_input() -> void:
	enabled = false
	_dragging = false


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_begin_drag(_local_pos(button))
			else:
				_dragging = false
	elif event is InputEventMouseMotion:
		if _dragging:
			var delta_m := (_local_pos(event as InputEventMouse) - _drag_start_pointer) / mapper.scale
			_apply(CuePlacer.constrain(_drag_start_ball + delta_m, _state, table, placement))
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.keycode == KEY_SPACE):
			confirm()


func _begin_drag(pointer: Vector2) -> void:
	var cue := _state.get_cue_ball()
	if cue == null:
		return
	_dragging = true
	_drag_start_pointer = pointer
	_drag_start_ball = cue.pos


func _apply(pos: Vector2) -> void:
	var cue := _state.get_cue_ball()
	CuePlacer.set_cue_ball(cue, pos)
	valid = CuePlacer.is_valid(pos, _state, table, placement)
	placement_changed.emit()


func _local_pos(event: InputEventMouse) -> Vector2:
	if world_node != null:
		var local := world_node.make_input_local(event) as InputEventMouse
		return local.position
	return event.position
