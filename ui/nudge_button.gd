class_name NudgeButton
extends Button
## Fixed-step aim nudge with hold-to-repeat. Use two: direction = -1 (left) and +1 (right).

signal nudge(delta_radians: float)

@export var direction: int = 1
@export var config: AimConfig

var _held: bool = false
var _timer: float = 0.0


func _ready() -> void:
	if config == null:
		config = AimConfig.new()
	focus_mode = Control.FOCUS_NONE  # Keep Space from "clicking" a focused button.
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	set_process(false)


func _on_down() -> void:
	_held = true
	_timer = config.nudge_repeat_delay
	_emit_step()
	set_process(true)


func _on_up() -> void:
	_held = false
	set_process(false)


func _process(delta: float) -> void:
	if not _held:
		return
	_timer -= delta
	if _timer <= 0.0:
		_emit_step()
		_timer = config.nudge_repeat_rate


func _emit_step() -> void:
	nudge.emit(deg_to_rad(config.nudge_step_degrees) * direction)
