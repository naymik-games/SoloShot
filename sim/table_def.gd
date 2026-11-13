class_name TableDef
extends Resource
## Static table definition. Units are meters. Origin (0,0) = top-left of playfield, +Y down.
## (Replaces the earlier version: defaults now match the London table art, plus optional art fields.)

@export var size: Vector2 = Vector2(2.54, 1.27)
@export var ball_radius: float = 0.02858
@export var corner_pocket_capture_radius: float = 0.07
@export var side_pocket_capture_radius: float = 0.06

@export_group("Cushion gaps and pocket placement")
## Distance from a corner along each rail where the cushion starts (corner pocket mouth).
@export var corner_mouth: float = 0.098
## Half-width of the side pocket mouth along the long rails.
@export var side_mouth_half: float = 0.079
## How far corner pocket centers sit outside the playfield, on both axes.
@export var corner_pocket_overhang: float = 0.038
## How far side pocket centers sit outside the long rails.
@export var side_pocket_overhang: float = 0.069

@export_group("Procedural look (used when no art texture is set)")
@export var rail_width: float = 0.09
@export var cushion_thickness: float = 0.04

@export_group("Art (optional)")
## Full table image including rails. Pocket holes should be transparent.
@export var art_texture: Texture2D
## The playfield (cushion nose to cushion nose) inside the texture, in TEXTURE PIXELS.
## Defaults are measured from singletableLondon-hd.png (970 x 538).
var art_playfield_rect = Rect2(74, 74, 866, 433)

## Built by TableBuilder.build(); not exported.
var cushions: Array[CushionSegment] = []
var pockets: Array[Pocket] = []
