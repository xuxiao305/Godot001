# Scripts/Prototypes/Destruction/tests/test_block_damage.gd
# 验 Block 的血量、take_damage、信号、入队行为。不验 PinJoint2D。
extends Node

const DBlock := preload("res://Scripts/Prototypes/Destruction/block.gd")
const DestructionPipeline := preload("res://Scripts/Prototypes/Destruction/destruction_pipeline.gd")

func _ready() -> void:
	var pipeline := DestructionPipeline.new()

	# 1) 初始血量
	var b := DBlock.new()
	b.pipeline = pipeline
	b.initial_health = 100.0
	b.health = 100.0
	assert(b.health == 100.0, "初始血量")

	# 2) take_damage 扣血
	b.take_damage(30.0, Vector2.ZERO, "test")
	assert(b.health == 70.0, "扣 30 后血量 70, got %f" % b.health)

	# 3) 血量未归零 → 不入销毁队列
	assert(pipeline.block_destroy_queue.is_empty(), "血量 > 0 不入销毁队列")

	# 4) 致命伤 → 入队，且只入一次
	b.take_damage(80.0, Vector2.ZERO, "test")
	assert(b.health <= 0.0, "致命伤后 health <= 0")
	assert(pipeline.block_destroy_queue.size() == 1, "入销毁队列")
	b.take_damage(5.0, Vector2.ZERO, "test")  # 死后再打
	assert(pipeline.block_destroy_queue.size() == 1, "死后再打不会重复入队")

	# 5) damage_to_constraint_ratio 默认 0.3
	assert(absf(b.damage_to_constraint_ratio - 0.3) < 0.001, "默认转发比 0.3")

	print("[TEST block_damage] ALL PASS")
	get_tree().quit()
