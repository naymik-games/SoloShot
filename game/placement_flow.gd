class_name PlacementFlow
extends RefCounted
## Cue-ball placement (ball in hand) after a scratch or foul: owns the drag controller, the
## region/ring overlay and the "Place cue ball" button. PoolGame decides WHEN to place (phases);
## this decides how it looks and behaves.

## The cue ball moved (or its legality changed): redraw the balls.
signal moved
## The player accepted the spot (Place button, Enter or Space).
signal confirmed

var controller: CuePlacementController
var overlay: PlacementOverlay
var button: Button

var _state: SimState
var _placement: CuePlacement


## `world` is the Node2D whose local space matches CoordinateMapper pixels (the PoolGame node);
## the controller and overlay are added to it, with the overlay drawn just above `draw_above`
## (the balls layer). The button goes into `ui_root`.
func setup(world: Node2D, ui_root: Node, mapper: CoordinateMapper, table: TableDef,
		draw_above: Node) -> void:
	controller = CuePlacementController.new()
	controller.mapper = mapper
	controller.table = table
	controller.world_node = world
	world.add_child(controller)
	controller.placement_changed.connect(_on_controller_changed)
	controller.confirmed.connect(_on_controller_confirmed)

	overlay = PlacementOverlay.new()
	overlay.mapper = mapper
	overlay.table = table
	overlay.visible = false
	world.add_child(overlay)
	world.move_child(overlay, draw_above.get_index() + 1)

	button = Button.new()
	button.text = "Place cue ball"
	button.custom_minimum_size = Vector2(220.0, 44.0)
	button.visible = false
	button.pressed.connect(controller.confirm)
	ui_root.add_child(button)
	# Centered in the band below the table: 220 x 44, 10 px above the bottom edge.
	button.set_anchor(SIDE_LEFT, 0.5)
	button.set_anchor(SIDE_RIGHT, 0.5)
	button.set_anchor(SIDE_TOP, 1.0)
	button.set_anchor(SIDE_BOTTOM, 1.0)
	button.offset_left = -110.0
	button.offset_right = 110.0
	button.offset_top = -54.0
	button.offset_bottom = -10.0
	button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	button.grow_vertical = Control.GROW_DIRECTION_BEGIN


## Starts placing: shows the overlay and button and lets the player drag the cue ball.
func begin(state: SimState, placement: CuePlacement) -> void:
	_state = state
	_placement = placement
	set_active(true)
	controller.begin(state, placement)


## Shows or hides the placement UI. Hiding also stops the controller from taking input.
func set_active(active: bool) -> void:
	overlay.visible = active
	button.visible = active
	if not active:
		controller.cancel_input()


func redraw() -> void:
	overlay.queue_redraw()


func _on_controller_changed() -> void:
	moved.emit()
	var cue := _state.get_cue_ball()
	if cue != null:
		overlay.show_placement(_placement, cue.pos, controller.valid)
	button.disabled = not controller.valid


func _on_controller_confirmed() -> void:
	confirmed.emit()
