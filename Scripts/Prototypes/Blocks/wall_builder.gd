# Scripts/Prototypes/Destruction/wall_builder.gd
# Programmatic block placer for test scenes.
# Attach to a Node2D child of GridStructure. At _ready(), creates
# Block children via BlockFactory, then triggers constraint build.
extends Node2D

const BlockFactoryKlass := preload("res://Scripts/Prototypes/Blocks/block_factory.gd")
const GridStructureKlass := preload("res://Scripts/Prototypes/Blocks/grid_structure.gd")

## Override in subclass or set in inspector
@export var pattern: String = ""  # "grid W H", "arch", "house"
@export var block_size: float = 25.0
@export var block_health: float = 100.0

func _ready() -> void:
	# Defer construction to after scene tree is fully set up
	call_deferred("_build")

func _build() -> void:
	var grid := get_parent()
	if not grid.has_method("build_constraints"):
		push_error("WallBuilder parent must be GridStructure")
		return

	var pipeline = grid.pipeline
	var impact = grid.impact_watcher

	match pattern:
		"grid":
			_build_grid(grid, pipeline, impact)
		"arch":
			_build_arch(grid, pipeline, impact)
		"house":
			_build_house(grid, pipeline, impact)
		_:
			push_error("Unknown pattern: " + pattern)

	# Trigger constraint build AFTER all blocks are added
	grid.build_constraints()
	queue_free()

func _build_grid(grid, pipeline, impact) -> void:
	# 10x10 brick wall. Godot 2D: +y is DOWN, so row=0 sits at y=0 (bottom)
	# and rows stack UP via -y. Demo's ground top sits at y=30 → row=0 bottom
	# edge at y=12.5 has ~17 px clearance.
	for row in 10:
		for col in 10:
			var pos := Vector2(col * block_size, -row * block_size)
			var b := BlockFactoryKlass.create(pipeline, pos, block_size, impact, block_health)
			b.name = "Block_%d_%d" % [row, col]
			grid.add_child(b)

func _build_arch(grid, pipeline, impact) -> void:
	# Left/right pillars 5 high, stacking UP (-y). Beam 7 wide sits at row 5 (one above pillar tops).
	for row in 5:
		var bl := BlockFactoryKlass.create(pipeline, Vector2(-75, -row * block_size), block_size, impact, block_health)
		bl.name = "PillarL_%d" % row
		grid.add_child(bl)
		var br := BlockFactoryKlass.create(pipeline, Vector2(75, -row * block_size), block_size, impact, block_health)
		br.name = "PillarR_%d" % row
		grid.add_child(br)
	for col in 7:
		var b := BlockFactoryKlass.create(pipeline, Vector2(-75 + col * block_size, -5 * block_size), block_size, impact, block_health)
		b.name = "Beam_%d" % col
		grid.add_child(b)

func _build_house(grid, pipeline, impact) -> void:
	# Walls at x=±112.5 (9 block_size apart center-to-center) so floors fit INSIDE without overlap.
	# Walls 7 high so roof at row 6 connects via wall_row_6.
	# Floors 8 wide at x = -87.5 .. +87.5 (cols 0-7), heights stagger with wall rows.
	for row in 7:
		var bl := BlockFactoryKlass.create(pipeline, Vector2(-112.5, -row * block_size), block_size, impact, block_health)
		bl.name = "WallL_%d" % row
		grid.add_child(bl)
		var br := BlockFactoryKlass.create(pipeline, Vector2(112.5, -row * block_size), block_size, impact, block_health)
		br.name = "WallR_%d" % row
		grid.add_child(br)
	# floor 0 / 1 / 2 anchor to wall rows 1 / 3 / 5; roof anchors to wall row 6.
	var floor_rows := [1, 3, 5, 6]
	for floor_idx in floor_rows.size():
		var y: float = -float(floor_rows[floor_idx]) * block_size
		for col in 8:
			var b := BlockFactoryKlass.create(pipeline, Vector2(-87.5 + col * block_size, y), block_size, impact, block_health)
			b.name = "Floor%d_%d" % [floor_idx, col]
			grid.add_child(b)
