class_name PoolGame
extends Node2D
## Conductor: owns live state, simulator, mode, and the fixed-timestep loop.

enum Phase { SETUP, AIMING, PLACING, SIMULATING, RESOLVING, GAME_OVER }
enum ModeType { FREE_PRACTICE, NINE_BALL }

## Which rules to play.
@export var mode_type: ModeType = ModeType.NINE_BALL

@export var table_def: TableDef
@export var physics_params: PhysicsParams
@export var aim_config: AimConfig
## Optional starting layout handed to the game mode.
@export var layout: LayoutDef
## Prints a one-line summary of each shot (first contact, pockets, cushion contact) to the output panel.
@export var debug_print_shot_report: bool = false
## Pixels kept free between the pocketed-ball tray and the top of the table area.
@export var tray_gap_px: float = 6.0

@export_group("Table layout (fractions of the screen kept clear around the table)")
## The table is scaled to fit inside the screen minus these insets.
## Power bar sits in the left margin, fine-aim strip in the right margin,
## tray in the top band, Place button / messages in the bottom band.
@export_range(0.0, 0.4, 0.005) var table_inset_left: float = 0.065
@export_range(0.0, 0.4, 0.005) var table_inset_right: float = 0.065
@export_range(0.0, 0.4, 0.005) var table_inset_top: float = 0.085
@export_range(0.0, 0.4, 0.005) var table_inset_bottom: float = 0.10

# Typed so GDScript can check member access (shot_requested, mapper, etc.).
@onready var table_view: TableView = $TableView
@onready var balls_layer: BallsLayer = $BallsLayer
@onready var aim_overlay: AimOverlay = $AimOverlay
@onready var aim_controller: AimController = $AimController
@onready var debug_overlay: DebugOverlay = get_node_or_null("DebugOverlay")
@onready var hud: Hud = get_node_or_null("UI/HUD")

# Unique-name nodes: enable "Access as Unique Name" on each in the scene tree.
@onready var power_control: PowerControl = %PowerControl
@onready var fine_aim: FineAimControl = %FinAimControl



var state: SimState
var simulator: PoolSimulator
var predictor: ShotPredictor
var mode: GameMode
var mapper: CoordinateMapper
var phase: Phase = Phase.SETUP

var _accumulator: float = 0.0
var _shot_events: Array[SimEvent] = []
var _report: ShotReport = ShotReport.new()  # Rebuilt for every shot.
var _prediction_dirty: bool = true
var _score: int = 0
const MAX_STEPS_PER_FRAME: int = 20

var cue_stick: CueStick

## History of pocketed object balls, and the tray that displays it.
var pocketed_log: PocketedLog
var tray: PocketedTray
## Number of shots taken so far (the shot being played counts).
var shots_taken: int = 0

## Cue ball placement (ball in hand) after a scratch or foul.
var placement_controller: CuePlacementController
var placement_overlay: PlacementOverlay
var place_button: Button
var _cue_placement: CuePlacement

func _ready() -> void:
	assert(table_def != null, "Assign table_def in the inspector.")
	assert(physics_params != null, "Assign physics_params in the inspector.")
	if aim_config == null:
		aim_config = AimConfig.new()

	# --- Core objects (order matters: later steps need these to exist) ---
	TableBuilder.build(table_def)
	simulator = PoolSimulator.new(table_def, physics_params)
	predictor = ShotPredictor.new(simulator, aim_config)
	state = SimState.new()
	mapper = CoordinateMapper.new()
	balls_layer.ball_radius = table_def.ball_radius
	_on_viewport_resized()
	get_viewport().size_changed.connect(_on_viewport_resized)

	# --- Views ---
	aim_overlay.mapper = mapper
	aim_overlay.config = aim_config
	aim_overlay.ball_radius = table_def.ball_radius
	if debug_overlay != null:
		debug_overlay.state = state
		debug_overlay.table = table_def
		debug_overlay.mapper = mapper

	# --- Input: share one AimConfig so tuning the .tres affects every control ---
	aim_controller.mapper = mapper
	aim_controller.config = aim_config
	aim_controller.world_node = self
	fine_aim.config = aim_config


	aim_controller.shot_requested.connect(_on_shot_requested)
	aim_controller.aim_changed.connect(_on_aim_changed)
	aim_controller.input_enabled_changed.connect(func(_e: bool) -> void: _sync_ui())
	power_control.power_changed.connect(aim_controller.set_power_input)
	fine_aim.nudge.connect(aim_controller.nudge_angle)

	
	power_control.released.connect(aim_controller.release_power)
	# --- Cue stick (visual only) ---
	cue_stick = CueStick.new()
	cue_stick.mapper = mapper
	cue_stick.aim = aim_controller.aim
	cue_stick.ball_radius = table_def.ball_radius
	add_child(cue_stick)
	move_child(cue_stick, aim_overlay.get_index() + 1)
	
	# --- Pocketed-ball log + tray (above the table) ---
	pocketed_log = PocketedLog.new()
	tray = PocketedTray.new()
	tray.setup(pocketed_log, state, table_def.ball_radius, mapper)
	add_child(tray)
	tray.layout(_tray_strip())
	pocketed_log.changed.connect(tray.refresh)

	# --- Cue ball placement (ball in hand after a scratch or foul) ---
	placement_controller = CuePlacementController.new()
	placement_controller.mapper = mapper
	placement_controller.table = table_def
	placement_controller.world_node = self
	add_child(placement_controller)
	placement_controller.placement_changed.connect(_on_placement_changed)
	placement_controller.confirmed.connect(_on_placement_confirmed)

	placement_overlay = PlacementOverlay.new()
	placement_overlay.mapper = mapper
	placement_overlay.table = table_def
	placement_overlay.visible = false
	add_child(placement_overlay)
	move_child(placement_overlay, balls_layer.get_index() + 1)

	var ui_root: Node = get_node_or_null("UI")
	if ui_root == null:
		ui_root = CanvasLayer.new()
		add_child(ui_root)
	place_button = Button.new()
	place_button.text = "Place cue ball"
	place_button.custom_minimum_size = Vector2(220.0, 44.0)
	place_button.visible = false
	place_button.pressed.connect(placement_controller.confirm)
	ui_root.add_child(place_button)
	# Centered in the band below the table: 220 x 44, 10 px above the bottom edge.
	place_button.set_anchor(SIDE_LEFT, 0.5)
	place_button.set_anchor(SIDE_RIGHT, 0.5)
	place_button.set_anchor(SIDE_TOP, 1.0)
	place_button.set_anchor(SIDE_BOTTOM, 1.0)
	place_button.offset_left = -110.0
	place_button.offset_right = 110.0
	place_button.offset_top = -54.0
	place_button.offset_bottom = -10.0
	place_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	place_button.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# --- Rules ---
	mode = _create_mode()
	mode.setup(state, table_def)
	balls_layer.sync_from(state, mapper)
	_refresh_hud_status()
	var start_placement := mode.initial_cue_placement()
	if start_placement != null and start_placement.mode != CuePlacement.Mode.NONE:
		_begin_cue_placement(start_placement)  # e.g. the break: player places the cue ball
	else:
		_set_phase(Phase.AIMING)


func _create_mode() -> GameMode:
	match mode_type:
		ModeType.NINE_BALL:
			return NineBallMode.new()
		_:
			var free_mode := FreePracticeMode.new()
			free_mode.layout = layout
			return free_mode


func _refresh_hud_status() -> void:
	if hud != null:
		hud.set_status(mode.status_text())


func _physics_process(delta: float) -> void:
	match phase:
		Phase.SIMULATING:
			_run_simulation(delta)
		Phase.AIMING:
			if _prediction_dirty:
				_prediction_dirty = false
				_update_prediction()


# ---------------------------------------------------------------- simulation

func _run_simulation(delta: float) -> void:
	_accumulator += delta
	var steps := 0
	while _accumulator >= physics_params.substep and steps < MAX_STEPS_PER_FRAME:
		simulator.step(state, _shot_events)
		_accumulator -= physics_params.substep
		steps += 1
		if not state.any_moving():
			break

	# If we hit the cap, drop the backlog so a lag spike can't snowball.
	if steps >= MAX_STEPS_PER_FRAME:
		_accumulator = minf(_accumulator, physics_params.substep)

	# Hand this frame's events to the rules layer (it must not keep the array), then clear.
	if not _shot_events.is_empty():
		_report.add_events(_shot_events)
		pocketed_log.add_events(_shot_events, shots_taken)
		mode.on_events(_shot_events, state)
		_shot_events.clear()

	balls_layer.sync_from(state, mapper)

	# Robust rest check: doesn't depend on the simulator emitting BALLS_AT_REST.
	if not state.any_moving():
		_set_phase(Phase.RESOLVING)


func _on_shot_requested(shot: Shot) -> void:
	if phase != Phase.AIMING:
		return
	mode.on_shot_taken(shot)
	_refresh_hud_status()
	simulator.apply_shot(state, shot)
	_shot_events.clear()
	_report = ShotReport.new()
	shots_taken += 1
	_accumulator = 0.0
	_set_phase(Phase.SIMULATING)


# ---------------------------------------------------------------- phases

func _set_phase(new_phase: Phase) -> void:
	phase = new_phase
	_set_placement_ui(new_phase == Phase.PLACING)
	match phase:
		Phase.SETUP:
			aim_controller.set_input_enabled(false)
			aim_overlay.clear()
			cue_stick.visible = false
		Phase.AIMING:
			var cue := state.get_cue_ball()
			if cue != null and cue.is_on_table():
				aim_controller.begin_aiming(cue.pos)
				_prediction_dirty = true
				cue_stick.refresh()
				cue_stick.visible = true
			else:
				push_warning("AIMING phase with no cue ball on the table.")
				aim_controller.set_input_enabled(false)
				aim_overlay.clear()
				cue_stick.visible = false
		Phase.PLACING:
			aim_controller.set_input_enabled(false)
			aim_overlay.clear()
			cue_stick.visible = false
			placement_controller.begin(state, _cue_placement)
		Phase.SIMULATING:
			aim_controller.set_input_enabled(false)
			aim_overlay.clear()
			cue_stick.visible = false
		Phase.RESOLVING:
			_resolve_shot()
		Phase.GAME_OVER:
			aim_controller.set_input_enabled(false)
			aim_overlay.clear()
			cue_stick.visible = false


func _resolve_shot() -> void:
	aim_controller.set_input_enabled(false)
	if debug_print_shot_report:
		print("Shot report: ", _report.describe())
	var result := mode.on_shot_ended(state, _report)  # Mode may move/respot balls in `state`.
	if result != null:
		_score += result.score_delta
		if hud != null:
			hud.set_score(_score)
			if not result.message.is_empty():
				hud.show_message(result.message, result.game_over)
		# TODO: result.respot_balls (if the mode doesn't mutate `state` itself) and result.foul handling.
	_refresh_hud_status()
	if result != null and result.rerack != null:
		RackBuilder.place_rack(state, result.rerack)
	balls_layer.sync_from(state, mapper)
	tray.refresh()  # The mode may have respotted or reracked balls.
	if result != null and result.game_over:
		_set_phase(Phase.GAME_OVER)
		return

	var placement: CuePlacement = null
	if result != null:
		placement = result.cue_placement
	var cue := state.get_cue_ball()
	if placement == null and cue != null:
		if not cue.is_on_table():
			# The mode didn't say where the pocketed cue ball goes: never leave the table without one.
			placement = CuePlacement.fixed(CuePlacement.head_spot(table_def))
		elif result != null and result.rerack != null and CuePlacer.overlaps_other_ball(cue.pos, state, table_def):
			# The new rack landed on the cue ball: move it clear (nearest free spot to the head spot).
			placement = CuePlacement.fixed(CuePlacement.head_spot(table_def))
	if placement != null and placement.mode != CuePlacement.Mode.NONE:
		_begin_cue_placement(placement)
	else:
		_set_phase(Phase.AIMING)


# ---------------------------------------------------------------- cue ball placement

func _begin_cue_placement(placement: CuePlacement) -> void:
	_cue_placement = placement
	var cue := state.get_cue_ball()
	if cue == null:
		_set_phase(Phase.AIMING)
		return
	if placement.mode == CuePlacement.Mode.FIXED:
		# Automatic respot; if the spot is occupied, the nearest free position is used.
		CuePlacer.set_cue_ball(cue, CuePlacer.find_free_position(placement.spot, state, table_def, placement))
		balls_layer.sync_from(state, mapper)
		_set_phase(Phase.AIMING)
	else:
		_set_phase(Phase.PLACING)  # Player drags the ball and confirms.


func _on_placement_changed() -> void:
	balls_layer.sync_from(state, mapper)
	var cue := state.get_cue_ball()
	if cue != null:
		placement_overlay.show_placement(_cue_placement, cue.pos, placement_controller.valid)
	place_button.disabled = not placement_controller.valid


func _on_placement_confirmed() -> void:
	_set_phase(Phase.AIMING)


## Shows the placement UI (overlay + Place button) and hides the aiming controls, or the reverse.
func _set_placement_ui(placing: bool) -> void:
	if placement_overlay == null or place_button == null:
		return
	placement_overlay.visible = placing
	place_button.visible = placing
	if not placing:
		placement_controller.cancel_input()
	for control in [fine_aim.get_parent(), power_control.get_parent()]:
		if control is CanvasItem and control != get_node_or_null("UI"):
			control.visible = not placing


# ---------------------------------------------------------------- aiming / UI

func _update_prediction() -> void:
	var cue := state.get_cue_ball()
	if cue == null or not cue.is_on_table():
		aim_overlay.clear()
		return
	aim_overlay.update_overlay(predictor.predict(state, aim_controller.aim.angle))


func _on_aim_changed() -> void:
	_sync_ui()
	_prediction_dirty = true  # Coalesce: at most one recompute per physics frame.
	if cue_stick != null:
		cue_stick.refresh()

func _sync_ui() -> void:
	power_control.set_value(aim_controller.aim.power_input)
	power_control.enabled = aim_controller.input_enabled

func _on_viewport_resized() -> void:
	mapper.fit_to_area(table_def, _table_area())
	table_view.setup(table_def, mapper)
	if balls_layer != null and state != null:
		balls_layer.sync_from(state, mapper)
	aim_overlay.queue_redraw()
	if cue_stick != null:
		cue_stick.refresh()
	if tray != null:
		tray.layout(_tray_strip())
	if placement_overlay != null:
		placement_overlay.queue_redraw()

## The band above the table, used by the pocketed-ball tray.
func _tray_strip() -> Rect2:
	var area := _table_area()
	return Rect2(area.position.x, 0.0, area.size.x, maxf(area.position.y - tray_gap_px, 0.0))

## The part of the screen reserved for the table (everything except the UI insets).
func _table_area() -> Rect2:
	var v := get_viewport_rect().size
	var left := v.x * table_inset_left
	var top := v.y * table_inset_top
	return Rect2(left, top, v.x - left - v.x * table_inset_right, v.y - top - v.y * table_inset_bottom)
