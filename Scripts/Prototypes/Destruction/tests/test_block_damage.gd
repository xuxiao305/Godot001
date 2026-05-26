# Scripts/Prototypes/Destruction/tests/test_block_damage.gd
# 验 Block 的血量、take_damage、销毁入队行为。不验 Constraint 传递。
extends Node

const Block := preload("res://Scripts/Prototypes/Destruction/block.gd")
const DestructionPipeline := preload("res://Scripts/Prototypes/Destruction/destruction_pipeline.gd")

func _ready() -> void:
	var pipeline := DestructionPipeline.new()

	# 1) 初始血量 —— _ready() 从 initial_health 初始化
	var b := Block.new()
	b.pipeline = pipeline
	b.initial_health = 50.0
	b._ready()
	assert(b.health == 50.0, "_ready() 应从 initial_health 初始化 health, got %f" % b.health)

	# 2) take_damage 扣血
	b.take_damage(30.0, Vector2.ZERO, "test")
	assert(b.health == 20.0, "扣 30 后血量 20, got %f" % b.health)

	# 3) 血量未归零 → 不入销毁队列
	assert(pipeline.block_destroy_queue.is_empty(), "血量 > 0 不入销毁队列")

	# 4) 致命伤 → 入队，且只入一次
	b.take_damage(25.0, Vector2.ZERO, "test")
	assert(b.health <= 0.0, "致命伤后 health <= 0")
	assert(pipeline.block_destroy_queue.size() == 1, "入销毁队列")
	b.take_damage(5.0, Vector2.ZERO, "test")  # 死后再打
	assert(pipeline.block_destroy_queue.size() == 1, "死后再打不会重复入队")

	# 5) damage_propagation_ratio 默认 0.3
	assert(absf(b.damage_propagation_ratio - 0.3) < 0.001, "默认传递比 0.3")

	# 6) connected_constraints 默认空数组
	assert(b.connected_constraints.is_empty(), "初始无连接约束")

	print("[TEST block_damage] ALL PASS")
	get_tree().quit()
