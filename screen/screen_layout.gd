class_name ScreenLayout
extends Resource
## Where things go on screen: the table's area, the pocketed-ball tray strip, the power / fine-aim
## controls beside the table, the spin control, and the home button's safe-area shift.
## PoolGame owns one. Leave `screen_layout` empty in the inspector to use these defaults, or
## create one there ("New ScreenLayout") to tune the values.

@export_group("Table (fractions of the screen kept clear around the table)")
@export_range(0.0, 0.4, 0.005) var table_inset_left: float = 0.065
@export_range(0.0, 0.4, 0.005) var table_inset_right: float = 0.065
## Pixels between the bottom of the table art and the bottom of the screen.
@export var table_bottom_margin_px: float = 25.0
## Height the table may use, as a fraction of screen height. 0.815 is what the old
## top/bottom insets gave, so the table keeps its current size. Everything above it
## becomes the top band.
@export_range(0.3, 1.0, 0.005) var table_height_fraction: float = 0.815
## Pixels kept free between the pocketed-ball tray and the top of the table area.
@export_group("Pocketed tray")
## Width of the vertical tray column, at the right edge of the safe area.
@export var tray_width_px: float = 40.0
## Distance from the top and the right edge of the safe area.
@export var tray_margin_px: float = 10.0
@export var tray_margin_top_px: float = 60.0
## Pixels kept free between the bottom of the tray and the spin control.
@export var tray_gap_px: float = 6.0

@export_group("Player panels")
## Space kept above and below the player section, inside the band above the table.
@export var player_panel_margin_px: float = 8.0
## The section is as tall as the band allows, up to this.
@export var player_panel_max_height_px: float = 72.0
## Width of the whole player section (both panels) as a fraction of the table area's width.
@export_range(0.3, 1.0, 0.01) var player_panel_width_fraction: float = 0.72

@export_group("Side controls")
## Gap between the table and the power / fine-aim controls.
@export var side_control_gap_px: float = 24.0
## Control height as a fraction of the table's height (0 = keep the control's own size).
@export_range(0.0, 1.0, 0.05) var side_control_height_fraction: float = 0.0

@export_group("Spin control")
## Diameter of the cue-ball spin control, drawn in the bottom-right corner (inside the safe area).
## Default matches the 80 px that was set on the pool_game scene.
@export var spin_control_size_px: float = 80.0
@export var spin_control_margin_px: float = 10.0

# Runtime state for the home button (not saved with the resource).
var _home_button: Control
var _home_base: Vector4 = Vector4.ZERO  # left, top, right, bottom offsets from the editor


## The part of the screen reserved for the table (everything except the UI insets).
func table_area(viewport_size: Vector2) -> Rect2:
	var left := viewport_size.x * table_inset_left
	var height := viewport_size.y * table_height_fraction
	var bottom := viewport_size.y - table_bottom_margin_px
	return Rect2(left, maxf(bottom - height, 0.0),
		viewport_size.x - left - viewport_size.x * table_inset_right, height)

## The band above the table, used by the pocketed-ball tray.
## Right-edge column for the pocketed-ball tray, ending just above the spin control.
## Pass the safe rect (SafeArea.get_rect(viewport)) so it respects notches and the home bar.
func tray_strip(viewport_size: Vector2, safe_rect: Rect2 = Rect2()) -> Rect2:
	var safe := safe_rect if safe_rect.size.x > 0.0 else Rect2(Vector2.ZERO, viewport_size)
	var x := safe.end.x - tray_margin_px - tray_width_px
	var top := safe.position.y + tray_margin_top_px
	var bottom := safe.end.y - spin_control_margin_px - spin_control_size_px - tray_gap_px
	return Rect2(x, top, tray_width_px, maxf(bottom - top, 0.0))

## The player section: centered over the table, in the band above it. Pass the safe rect
## (SafeArea.get_rect(viewport)) so it respects notches.
func player_strip(viewport_size: Vector2, safe_rect: Rect2 = Rect2()) -> Rect2:
	var safe := safe_rect if safe_rect.size.x > 0.0 else Rect2(Vector2.ZERO, viewport_size)
	var table := table_area(viewport_size)
	var top := safe.position.y + player_panel_margin_px
	var bottom := table.position.y - player_panel_margin_px
	var available := maxf(bottom - top, 0.0)
	var h := minf(available, player_panel_max_height_px)
	var w := table.size.x * player_panel_width_fraction
	return Rect2(table.get_center().x - w * 0.5, top + (available - h) * 0.5, w, h)


## Power control goes just left of the table, fine-aim strip just right of it.
func place_side_controls(table_rect: Rect2, viewport_size: Vector2,
		left_control: Control, right_control: Control) -> void:
	if left_control == null or right_control == null:
		return
	_place_beside(left_control, table_rect, viewport_size, true)
	_place_beside(right_control, table_rect, viewport_size, false)


## Bottom-right corner, inside the safe area.
func place_spin_control(control: Control, viewport: Viewport) -> void:
	if control == null:
		return
	var safe := SafeArea.get_rect(viewport)
	var d := spin_control_size_px
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.custom_minimum_size = Vector2(d, d)
	control.size = Vector2(d, d)
	control.position = Vector2(
		safe.end.x - d - spin_control_margin_px,
		safe.end.y - d - spin_control_margin_px)


## Call once, BEFORE the first apply_home_button_safe_area(): remembers the offsets the button
## has in the editor so the safe-area shift is always applied to those, never stacked.
func bind_home_button(button: Control) -> void:
	_home_button = button
	_home_base = Vector4(button.offset_left, button.offset_top,
		button.offset_right, button.offset_bottom)


## Keeps the home button pinned to its editor position, moved inside the safe area.
func apply_home_button_safe_area(viewport: Viewport) -> void:
	if _home_button == null or not is_instance_valid(_home_button):
		return
	var vp := viewport.get_visible_rect()
	var safe := SafeArea.get_rect(viewport)
	var dx := safe.position.x - vp.position.x
	var dy := safe.position.y - vp.position.y
	_home_button.offset_left = _home_base.x + dx
	_home_button.offset_top = _home_base.y + dy
	_home_button.offset_right = _home_base.z + dx
	_home_button.offset_bottom = _home_base.w + dy


func _place_beside(control: Control, table_rect: Rect2, viewport_size: Vector2, on_left: bool) -> void:
	if side_control_height_fraction > 0.0:
		var h := table_rect.size.y * side_control_height_fraction
		control.custom_minimum_size.y = h
		control.size.y = h
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)  # plain pixel positioning
	var x: float
	if on_left:
		x = table_rect.position.x - control.size.x - side_control_gap_px
	else:
		x = table_rect.end.x + side_control_gap_px
	x = clampf(x, 0.0, viewport_size.x - control.size.x)  # never off-screen
	control.position = Vector2(x, table_rect.get_center().y - control.size.y * 0.5)
