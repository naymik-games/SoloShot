class_name SafeArea
extends RefCounted
## Safe screen rectangle (notches, rounded corners, gesture bar) in the viewport's own
## coordinates, i.e. the same units your UI offsets use. Returns the full viewport on desktop.

static func get_rect(viewport: Viewport) -> Rect2:
	var vp: Rect2 = viewport.get_visible_rect()
	if not (OS.has_feature("mobile")):
		return vp

	var screen := Vector2(DisplayServer.screen_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var win := Vector2(DisplayServer.window_get_size())
	if screen.x <= 0.0 or screen.y <= 0.0 or win.x <= 0.0 or win.y <= 0.0 \
			or safe.size.x <= 0.0 or safe.size.y <= 0.0:
		return vp

	# Insets in physical pixels...
	var inset_tl := safe.position
	var inset_br := screen - safe.end
	# ...converted to stretched viewport units.
	var k := vp.size / win
	return Rect2(
		vp.position + inset_tl * k,
		vp.size - (inset_tl + inset_br) * k)
