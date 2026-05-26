# spike_block_factory.gd
# F6 smoke: single block falls under gravity onto a ground plane
extends Node2D

const BlockFactoryCls := preload("res://Scripts/Prototypes/Destruction/block_factory.gd")
const DestructionPipelineCls := preload("res://Scripts/Prototypes/Destruction/destruction_pipeline.gd")

func _ready() -> void:
	var pipeline: RefCounted = DestructionPipelineCls.new()
	var block: RigidBody2D = BlockFactoryCls.create(
		pipeline,
		Vector2(0, -200),
		25.0,   # block_size px
		null,   # impact_watcher (nullable until Task 5)
		100.0   # initial_health
	)
	add_child(block)
