class_name ShotRunner
extends RefCounted
## Fixed-timestep driver for one shot: feeds real frame time to the simulator in `substep`
## slices and collects what happened into a ShotReport. It knows nothing about rules or UI;
## PoolGame hands each frame's events to the mode and the pocketed log.

const MAX_STEPS_PER_FRAME: int = 20

## Rebuilt by begin() for every shot and filled as events arrive.
var report: ShotReport = ShotReport.new()

var _simulator: PoolSimulator
var _state: SimState
var _params: PhysicsParams
var _accumulator: float = 0.0
var _events: Array[SimEvent] = []


func _init(simulator: PoolSimulator, state: SimState, params: PhysicsParams) -> void:
	_simulator = simulator
	_state = state
	_params = params


## Call right after the shot has been applied to the simulation state.
func begin() -> void:
	_accumulator = 0.0
	_events.clear()
	report = ShotReport.new()


## Advances the simulation by `delta` seconds of real time. Returns the events from this frame
## (they are already added to `report`). The array is reused: use it right away, don't keep it.
func advance(delta: float) -> Array[SimEvent]:
	_events.clear()
	_accumulator += delta
	var steps := 0
	while _accumulator >= _params.substep and steps < MAX_STEPS_PER_FRAME:
		_simulator.step(_state, _events)
		_accumulator -= _params.substep
		steps += 1
		if not _state.any_moving():
			break

	# If we hit the cap, drop the backlog so a lag spike can't snowball.
	if steps >= MAX_STEPS_PER_FRAME:
		_accumulator = minf(_accumulator, _params.substep)

	if not _events.is_empty():
		report.add_events(_events)
	return _events
