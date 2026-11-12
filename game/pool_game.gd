class_name PoolGame
extends Node2D
## Conductor: owns live state, simulator, mode and the phase machine.
## The detail work lives in helpers:
##   ScreenLayout  - where the table, controls, tray and spin control sit on screen
##   ShotRunner    - fixed-timestep simulation of one shot (+ its ShotReport)
##   PlacementFlow - ball-in-hand UI after a scratch or foul

enum Phase { SETUP, AIMING, PLACING, SIMULATING, RESOLVING, GAME_OVER }
enum ModeType { FREE_PRACTICE, NINE_BALL, TIME_TRIAL }

## Which rules to play.
@export var mode_type: ModeType = ModeType.NINE_BALL

@export var table_def: TableDef
@export var physics_params: PhysicsParams
@export var aim_config: AimConfig
## Screen layout (table insets, side controls, spin control). Empty = defaults.
@export var screen_layout: ScreenLayout
## Optional starting layout handed to the game mode.
@export var layout: LayoutDef
## Prints a one-line summary of each shot (first contact, pockets, cushion contact) to the output panel.
@export var debug_print_shot_report: bool = false

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
@onready var home_button: Control = %home_button

var state: SimState
var simulator: PoolSimulator
var predictor: ShotPredictor
var mode: GameMode
var mapper: CoordinateMapper
var phase: Phase = Phase.SETUP
var runner: ShotRunner

var cue_stick: CueStick
## History of pocketed object balls, and the tray that displays it.
var pocketed_log: PocketedLog
var tray: PocketedTray
var placement_flow: PlacementFlow
var spin_control: SpinControl
## Number of shots taken so far (the shot being played counts).
var shots_taken: int = 0

var _ui_root: Node
var _prediction_dirty: bool = true
var _score: int = 0
var _cue_placement: CuePlacement

## Break handling: the first shot after a fresh rack uses the break speed cap and aim error.
var _is_break_shot: bool = false
var _shot_rng := RandomNumberGenerator.new()


# ---------------------------------------------------------------- setup

func _ready() -> void:
	# Mode picked on the home menu overrides the inspector value.
	if GameSession.selected_mode >= 0:
		mode_type = GameSession.selected_mode as ModeType
	assert(table_def != null, "Assign table_def in the inspector.")
	assert(physics_params != null, "Assign physics_params in the inspector.")
	if aim_config == null:
		aim_config = AimConfig.new()
	if screen_layout == null:
		screen_layout = ScreenLayout.new()

	_ui_root = get_node_or_null("UI")
	if _ui_root == null:
		_ui_root = CanvasLayer.new()
		add_child(_ui_root)

	# Order matters: later steps need the objects built by earlier ones.
	_build_core()
	_build_views()
	_wire_aim_input()
	_build_cue_stick()
	_build_pocketed_tray()
	_build_placement()
	_build_spin_control()
	_start_game()


func _build_core() -> void:
	TableBuilder.build(table_def)
	simulator = PoolSimulator.new(table_def, physics_params)
	predictor = ShotPredictor.new(simulator, aim_config)
	state = SimState.new()
	runner = ShotRunner.new(simulator, state, physics_params)
	mapper = CoordinateMapper.new()
	balls_layer.ball_radius = table_def.ball_radius
	screen_layout.bind_home_button(home_button)  # before the first safe-area shift
	_on_viewport_resized()
	get_viewport().size_changed.connect(_on_viewport_resized)


func _build_views() -> void:
	aim_overlay.mapper = mapper
	aim_overlay.config = aim_config
	aim_overlay.ball_radius = table_def.ball_radius
	if debug_overlay != null:
		debug_overlay.state = state
		debug_overlay.table = table_def
		debug_overlay.mapper = mapper


## Input: one AimConfig is shared so tuning the .tres affects every control.
func _wire_aim_input() -> void:
	aim_controller.mapper = mapper
	aim_controller.config = aim_config
	aim_controller.world_node = self
	fine_aim.config = aim_config

	aim_controller.shot_requested.connect(_on_shot_requested)
	aim_controller.aim_changed.connect(_on_aim_changed)
	aim_controller.input_enabled_changed.connect(func(_e: bool) -> void: _sync_ui())
	power_control.power_changed.connect(aim_controller.set_power_input)
	power_control.released.connect(aim_controller.release_power)
	fine_aim.nudge.connect(aim_controller.nudge_angle)


## Visual only.
func _build_cue_stick() -> void:
	cue_stick = CueStick.new()
	cue_stick.mapper = mapper
	cue_stick.aim = aim_controller.aim
	cue_stick.ball_radius = table_def.ball_radius
	add_child(cue_stick)
	move_child(cue_stick, aim_overlay.get_index() + 1)


## Pocketed-ball log + tray (in the band above the table).
func _build_pocketed_tray() -> void:
	pocketed_log = PocketedLog.new()
	tray = PocketedTray.new()
	tray.setup(pocketed_log, state, table_def.ball_radius, mapper)
	add_child(tray)
	tray.layout(screen_layout.tray_strip(get_viewport_rect().size))
	pocketed_log.changed.connect(tray.refresh)


## Cue ball placement (ball in hand after a scratch or foul).
func _build_placement() -> void:
	placement_flow = PlacementFlow.new()
	placement_flow.setup(self, _ui_root, mapper, table_def, balls_layer)
	placement_flow.moved.connect(_on_placement_moved)
	placement_flow.confirmed.connect(_on_placement_confirmed)


## Spin control (cue ball face: tap/drag where the cue strikes).
func _build_spin_control() -> void:
	spin_control = SpinControl.new()
	_ui_root.add_child(spin_control)
	spin_control.spin_changed.connect(aim_controller.set_spin_input)
	_layout_spin_control()


func _start_game() -> void:
	mode = _create_mode()
	mode.setup(state, table_def)
	_prepare_fresh_rack()
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
		ModeType.TIME_TRIAL:
			return TimeTrialMode.new()
		_:
			var free_mode := FreePracticeMode.new()
			free_mode.layout = layout
			return free_mode


func _refresh_hud_status() -> void:
	if hud != null:
		hud.set_status(mode.status_text())


# ---------------------------------------------------------------- frame loop

func _physics_process(delta: float) -> void:
	if phase == Phase.AIMING or phase == Phase.PLACING or phase == Phase.SIMULATING:
		mode.tick(delta)
		_refresh_hud_status()
		# During a shot, the clock expiring is handled when the shot resolves.
		if phase != Phase.SIMULATING and mode.is_time_up():
			if hud != null:
				hud.show_message(mode.time_up_message(), true)
			_set_phase(Phase.GAME_OVER)
			return
	match phase:
		Phase.SIMULATING:
			_run_simulation(delta)
		Phase.AIMING:
			if _prediction_dirty:
				_prediction_dirty = false
				_update_prediction()


func _run_simulation(delta: float) -> void:
	# Hand this frame's events to the rules layer (it must not keep the array).
	var events := runner.advance(delta)
	if not events.is_empty():
		pocketed_log.add_events(events, shots_taken)
		mode.on_events(events, state)

	balls_layer.sync_from(state, mapper)

	# Robust rest check: doesn't depend on the simulator emitting BALLS_AT_REST.
	if not state.any_moving():
		_set_phase(Phase.RESOLVING)


func _on_shot_requested(shot: Shot) -> void:
	if phase != Phase.AIMING:
		return
	mode.on_shot_taken(shot)
	_refresh_hud_status()
	_shot_rng.randomize()
	var cue_offset := aim_controller.aim.spin * physics_params.max_cue_offset
	simulator.apply_shot(state, shot, _is_break_shot, _shot_rng, cue_offset)
	_is_break_shot = false
	runner.begin()
	shots_taken += 1
	_set_phase(Phase.SIMULATING)


# ---------------------------------------------------------------- phases

func _set_phase(new_phase: Phase) -> void:
	phase = new_phase
	var placing := new_phase == Phase.PLACING
	_set_aim_controls_visible(not placing)
	if not placing:
		placement_flow.set_active(false)
	match phase:
		Phase.AIMING:
			_enter_aiming()
		Phase.PLACING:
			_enter_idle()
			placement_flow.begin(state, _cue_placement)
		Phase.RESOLVING:
			_resolve_shot()
		_:  # SETUP, SIMULATING, GAME_OVER
			_enter_idle()


## No aiming: input off, overlay and cue stick hidden.
func _enter_idle() -> void:
	aim_controller.set_input_enabled(false)
	aim_overlay.clear()
	cue_stick.visible = false


func _enter_aiming() -> void:
	var cue := state.get_cue_ball()
	if cue != null and cue.is_on_table():
		aim_controller.begin_aiming(cue.pos)
		_prediction_dirty = true
		cue_stick.refresh()
		cue_stick.visible = true
	else:
		push_warning("AIMING phase with no cue ball on the table.")
		_enter_idle()


## Aiming controls are hidden while the player is placing the cue ball.
func _set_aim_controls_visible(visible_now: bool) -> void:
	power_control.visible = visible_now
	fine_aim.visible = visible_now
	if spin_control != null:
		spin_control.visible = visible_now


func _resolve_shot() -> void:
	aim_controller.set_input_enabled(false)
	if debug_print_shot_report:
		print("Shot report: ", runner.report.describe())
	var result := mode.on_shot_ended(state, runner.report)  # Mode may move/respot balls in `state`.
	_apply_result(result)
	if result != null and result.game_over:
		_set_phase(Phase.GAME_OVER)
		return

	var next_placement := _choose_cue_placement(result)
	if next_placement != null and next_placement.mode != CuePlacement.Mode.NONE:
		_begin_cue_placement(next_placement)
	else:
		_set_phase(Phase.AIMING)


## Score, messages, rerack and view refresh after the mode has ruled on a shot.
func _apply_result(result: ShotResult) -> void:
	if result != null:
		_score += result.score_delta
		if hud != null:
			hud.set_score(_score)
			if not result.message.is_empty():
				hud.show_message(result.message, result.game_over)
		# TODO: result.respot_balls (if the mode doesn't mutate `state` itself) and result.foul handling.
	_refresh_hud_status()
	if result != null and result.rerack != null:
		pocketed_log.clear()
		RackBuilder.place_rack(state, result.rerack)
		_prepare_fresh_rack()
	balls_layer.sync_from(state, mapper)
	tray.refresh()  # The mode may have respotted or reracked balls.


## What the mode asked for, plus the safety nets: a pocketed cue ball is never left off the
## table, and a new rack that landed on the cue ball moves it clear.
func _choose_cue_placement(result: ShotResult) -> CuePlacement:
	var requested: CuePlacement = null
	if result != null:
		requested = result.cue_placement
	var cue := state.get_cue_ball()
	if requested == null and cue != null:
		if not cue.is_on_table():
			return CuePlacement.fixed(CuePlacement.head_spot(table_def))
		if result != null and result.rerack != null \
				and CuePlacer.overlaps_other_ball(cue.pos, state, table_def):
			return CuePlacement.fixed(CuePlacement.head_spot(table_def))
	return requested


# ---------------------------------------------------------------- break

## Call right after a rack is placed (first rack and every rerack): tiny random offsets so
## breaks come out differently, and flag the next shot as the break.
func _prepare_fresh_rack() -> void:
	# Free Practice with a custom layout is a drill, not a rack: leave it exact.
	if mode_type == ModeType.FREE_PRACTICE and layout != null:
		return
	_shot_rng.randomize()
	RackJitter.apply(state, table_def, physics_params, _shot_rng)
	_is_break_shot = true


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


func _on_placement_moved() -> void:
	balls_layer.sync_from(state, mapper)


func _on_placement_confirmed() -> void:
	_set_phase(Phase.AIMING)


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
	if spin_control != null:
		spin_control.set_value(aim_controller.aim.spin)
		spin_control.enabled = aim_controller.input_enabled


func _layout_spin_control() -> void:
	screen_layout.place_spin_control(spin_control, get_viewport())


func _on_viewport_resized() -> void:
	var viewport_size := get_viewport_rect().size
	mapper.fit_to_area(table_def, screen_layout.table_area(viewport_size))
	screen_layout.place_side_controls(mapper.table_rect, viewport_size, power_control, fine_aim)
	_layout_spin_control()
	screen_layout.apply_home_button_safe_area(get_viewport())
	table_view.setup(table_def, mapper)
	if balls_layer != null and state != null:
		balls_layer.sync_from(state, mapper)
	aim_overlay.queue_redraw()
	if cue_stick != null:
		cue_stick.refresh()
	if tray != null:
		tray.layout(screen_layout.tray_strip(viewport_size))
	if placement_flow != null:
		placement_flow.redraw()
