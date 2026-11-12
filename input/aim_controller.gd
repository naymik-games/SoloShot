class_name AimController
extends Node
## Turns raw input into AimState updates and (via fire()) a Shot.
##
## - Coarse aim: drag on the table. Relative to touch-down (grab offset), so the line never jumps.
##   Precision scales with distance from the cue ball (angle per pixel ~ 1 / distance).
## - Fine aim:   nudge_angle(), called by FineAimControl / NudgeButton / arrow keys.
## - Power:      set_power_input(), called by PowerControl / W,S / mouse wheel.
## - Fire:       fire(), called by FireButton / Space. The ONLY path to shot_requested.
##
## NOTE: v1 uses mouse events for the table drag. Godot emulates mouse from the first touch,
## so single-finger drag works on mobile. True simultaneous multi-touch (thumb on a control while
## another finger drags the table) would need InputEventScreenTouch/Drag with index tracking.

signal shot_requested(shot: Shot)
signal aim_changed
signal gesture_started
signal gesture_ended
signal input_enabled_changed(enabled: bool)

@export var config: AimConfig
## Node2D whose local space matches CoordinateMapper pixels (normally the PoolGame node).
@export var world_node: Node2D

var aim: AimState = AimState.new()
var mapper: CoordinateMapper
var input_enabled: bool = false

var _dragging: bool = false
var _grab_offset: float = 0.0


func _ready() -> void:
	if config == null:
		config = AimConfig.new()


# ---------------------------------------------------------------- lifecycle

## Call when entering the AIMING phase.
func begin_aiming(cue_ball_pos: Vector2) -> void:
	aim.cue_ball_pos = cue_ball_pos
	aim.spin = Vector2.ZERO  # Spin never carries over to the next shot.
	aim.power_input = 0.0
	aim.power = 0.0
	set_input_enabled(true)
	aim_changed.emit()


func set_input_enabled(enabled: bool) -> void:
	if input_enabled == enabled:
		return
	input_enabled = enabled
	if not enabled:
		_end_drag()
	input_enabled_changed.emit(enabled)


func can_fire() -> bool:
	return input_enabled and aim.power >= config.min_fire_power


# ---------------------------------------------------------------- public inputs

## Fine adjust / nudges / keyboard. Positive = clockwise on screen.
func nudge_angle(delta_radians: float) -> void:
	if not input_enabled:
		return
	_set_angle(aim.angle + delta_radians)


## Power control input, 0..1 raw. Curve is applied here.
func set_power_input(value: float) -> void:
	if not input_enabled:
		return
	aim.power_input = clampf(value, 0.0, 1.0)
	aim.power = pow(aim.power_input, config.power_curve_exponent)
	aim_changed.emit()


## Spin control input: cue contact point on the ball, unit disc (x right, y top). Doesn't affect the prediction.
func set_spin_input(value: Vector2) -> void:
	if not input_enabled:
		return
	aim.spin = value.limit_length(1.0)
	aim_changed.emit()


## Fire button / Space. Locks input immediately so nothing can alter the shot.
func fire() -> void:
	if not can_fire():
		return
	var shot := aim.to_shot()
	aim.power_input = 0.0
	aim.power = 0.0
	set_input_enabled(false)
	aim_changed.emit()
	shot_requested.emit(shot)

## Power handle released: fires if it was pulled down far enough, otherwise cancels.
func release_power() -> void:
	if not input_enabled:
		return
	if can_fire():
		fire()
	else:
		set_power_input(0.0)
# ---------------------------------------------------------------- input handling

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey:
		_handle_key(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_drag(_local_pos(event))
			else:
				_end_drag()
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				set_power_input(aim.power_input + config.wheel_power_step)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				set_power_input(aim.power_input - config.wheel_power_step)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _dragging or mapper == null:
		return
	var rel := _local_pos(event) - mapper.to_screen(aim.cue_ball_pos)
	if rel.length() < config.coarse_dead_zone_px:
		return
	_set_angle(rel.angle() + _grab_offset)


func _handle_key(event: InputEventKey) -> void:
	if not event.pressed:
		return
	var fine := config.key_fine_multiplier if event.shift_pressed else 1.0
	var step := deg_to_rad(config.key_nudge_degrees) * fine
	match event.keycode:
		KEY_LEFT:
			nudge_angle(-step)
		KEY_RIGHT:
			nudge_angle(step)
		KEY_W:
			set_power_input(aim.power_input + config.key_power_step)
		KEY_S:
			set_power_input(aim.power_input - config.key_power_step)
		KEY_SPACE:
			if not event.echo:
				fire()


# ---------------------------------------------------------------- coarse drag

func _begin_drag(p: Vector2) -> void:
	if mapper == null:
		return
	var rel := p - mapper.to_screen(aim.cue_ball_pos)
	if rel.length() < config.coarse_dead_zone_px:
		return  # Too close to the ball: angle would be erratic.
	_dragging = true
	# Offset so the aim line doesn't jump to the finger on touch-down.
	_grab_offset = angle_difference(rel.angle(), aim.angle)
	gesture_started.emit()


func _end_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	gesture_ended.emit()


func _set_angle(value: float) -> void:
	aim.angle = wrapf(value, -PI, PI)
	aim_changed.emit()


func _local_pos(event: InputEventMouse) -> Vector2:
	if world_node != null:
		var local := world_node.make_input_local(event) as InputEventMouse
		return local.position
	return event.position
