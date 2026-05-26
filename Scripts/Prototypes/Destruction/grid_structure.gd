# Scripts/Prototypes/Destruction/grid_structure.gd
# 可复用 Prefab：扫描子节点 RigidBody2D → 邻居检测 → 建 PinJoint + Constraint。
# spec §4.6 / §4.11。
class_name GridStructure
extends Node2D

const Block := preload("res://Scripts/Prototypes/Destruction/block.gd")
const Constraint := preload("res://Scripts/Prototypes/Destruction/constraint.gd")
const ConstraintVisualizer := preload("res://Scripts/Prototypes/Destruction/constraint_visualizer.gd")

@export var block_size: float = 25.0
@export var constraint_health: float = 50.0
@export var auto_build: bool = true
var pipeline: DestructionPipeline = null
var impact_watcher: ImpactWatcher = null

var _blocks: Array = []
var _constraints: Array = []

@onready var _visualizer: ConstraintVisualizer = $ConstraintVisualizer

func _ready() -> void:
	if auto_build:
		build_constraints()

func build_constraints() -> void:
	_blocks.clear()
	for child in get_children():
		if child is Block:
			_blocks.append(child)
			if pipeline != null and child.pipeline == null:
				child.pipeline = pipeline
			if impact_watcher != null and child.impact_watcher == null:
				child.impact_watcher = impact_watcher

	var threshold := block_size * 1.05
	for i in _blocks.size():
		var a: Block = _blocks[i]
		for j in range(i + 1, _blocks.size()):
			var b: Block = _blocks[j]
			if a.global_position.distance_to(b.global_position) <= threshold:
				_attach_constraint(a, b)

	if _visualizer != null:
		_visualizer.set_data(_blocks, _constraints)

func _attach_constraint(a: Block, b: Block) -> void:
	var center := (a.global_position + b.global_position) * 0.5
	var c := Constraint.create(a, b, center, self)
	c.initial_health = constraint_health
	c.health = constraint_health
	c.pipeline = pipeline
	a.connected_constraints.append(c)
	b.connected_constraints.append(c)
	_constraints.append(c)

func clear() -> void:
	for c in _constraints:
		if c.pin != null and is_instance_valid(c.pin):
			c.pin.queue_free()
	_constraints.clear()
	for blk in _blocks:
		if is_instance_valid(blk):
			blk.queue_free()
	_blocks.clear()
	if _visualizer != null:
		_visualizer.set_data([], [])
