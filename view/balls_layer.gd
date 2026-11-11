class_name BallsLayer
extends Node2D
## Syncs BallView nodes to SimState. Read-only with respect to the state. Keep at (0,0).

## Optional: a scene whose root has ball_view.gd. If empty, BallView nodes are created in code.
@export var ball_view_scene: PackedScene

## Meters. PoolGame sets this from TableDef.ball_radius.
var ball_radius: float = 0.02858

var _views: Dictionary = {}  # ball id -> BallView


func sync_from(state: SimState, mapper: CoordinateMapper) -> void:
	var seen := {}
	for b in state.balls:
		seen[b.id] = true
		var view: BallView = _views.get(b.id)
		if view == null:
			view = _create_view(b.id)
		view.update_from(b, mapper)

	for id in _views.keys():
		if not seen.has(id):
			_views[id].queue_free()
			_views.erase(id)


func _create_view(id: int) -> BallView:
	var view: BallView
	if ball_view_scene != null:
		view = ball_view_scene.instantiate() as BallView
	else:
		view = BallView.new()
	view.ball_id = id
	view.radius_m = ball_radius
	add_child(view)
	_views[id] = view
	return view
