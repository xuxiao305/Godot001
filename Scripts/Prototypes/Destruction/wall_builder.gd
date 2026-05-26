# Scripts/Prototypes/Destruction/wall_builder.gd
# Programmatic block placer for test scenes.
# Attach to a Node2D child of GridStructure. At _ready(), creates
# Block children via BlockFactory, then triggers constraint build.
extends Node2D

const BlockFactoryKlass := preload("res://Scripts/Prototypes/Destruction/block_factory.gd")
const GridStructureKlass := preload("res://Scripts/Prototypes/Destruction/grid_structure.gd")

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
	# 10x10 brick wall, origin at top-left
	for row in 10:
		for col in 10:
			var pos := Vector2(col * block_size, row * block_size)
			var b := BlockFactoryKlass.create(pipeline, pos, block_size, impact, block_health)
			b.name = "Block_%d_%d" % [row, col]
			grid.add_child(b)

func _build_arch(grid, pipeline, impact) -> void:
	# Left pillar: 1x5
	for row in 5:
		var b := BlockFactoryKlass.create(pipeline, Vector2(-75, row * block_size), block_size, impact, block_health)
		b.name = "PillarL_%d" % row
		grid.add_child(b)
	# Right pillar: 1x5
	for row in 5:
		var b := BlockFactoryKlass.create(pipeline, Vector2(75, row * block_size), block_size, impact, block_health)
		b.name = "PillarR_%d" % row
		grid.add_child(b)
	# Beam: 7x1, sitting on top of pillars (row 5)
	for col in 7:
		var b := BlockFactoryKlass.create(pipeline, Vector2((-75 + col * block_size), 5 * block_size), block_size, impact, block_health)
		b.name = "Beam_%d" % col
		grid.add_child(b)

func _build_house(grid, pipeline, impact) -> void:
	# Left wall: 1x6
	for row in 6:
		var b := BlockFactoryKlass.create(pipeline, Vector2(-87.5, row * block_size), block_size, impact, block_health)
		b.name = "WallL_%d" % row
		grid.add_child(b)
	# Right wall: 1x6
	for row in 6:
		var b := BlockFactoryKlass.create(pipeline, Vector2(87.5, row * block_size), block_size, impact, block_health)
		b.name = "WallR_%d" % row
		grid.add_child(b)
	# 3 floors + roof: each 8x1
	for floor_idx in 4:
		var y := floor_idx * 2 * block_size + block_size  # 1,3,5,7 * block_size
		for col in 8:
			var b := BlockFactoryKlass.create(pipeline, Vector2((-87.5 + col * block_size), y), block_size, impact, block_health)
			b.name = "Floor%d_%d" % [floor_idx, col]
			grid.add_child(b)
