# Scripts/Prototypes/Destruction/tests/test_destruction_pipeline.gd
# 纯算法测试 —— pipeline 的入队 / 派发 / 幂等性。
extends Node

const DestructionPipeline := preload("res://Scripts/Prototypes/Destruction/destruction_pipeline.gd")

func _ready() -> void:
	var p := DestructionPipeline.new()

	# 1) 入队 + 计数
	p.queue_damage_event({"target": "block_a", "amount": 10.0, "point": Vector2.ZERO, "source": "test"})
	p.queue_damage_event({"target": "block_b", "amount": 5.0, "point": Vector2.ZERO, "source": "test"})
	assert(p.damage_events.size() == 2, "damage_events 应有 2 项")

	# 2) 销毁队列幂等（同一对象重复入队只销毁一次）
	var fake_block := RefCounted.new()
	p.queue_block_destroy(fake_block)
	p.queue_block_destroy(fake_block)
	assert(p.block_destroy_queue.size() == 1, "重复入队应被去重")

	# 3) drain_damage_events 清空 + 返回有序快照
	var snap := p.drain_damage_events()
	assert(snap.size() == 2, "drain 应返回入队顺序 2 项")
	assert(p.damage_events.is_empty(), "drain 后队列应为空")

	# 4) drain_block_destroys 清空
	var snap2 := p.drain_block_destroys()
	assert(snap2.size() == 1, "drain block 应返回 1 项")
	assert(p.block_destroy_queue.is_empty(), "drain 后应为空")

	# 5) constraint_destroy 与 debris_spawn 同理
	var fake_constraint := RefCounted.new()
	p.queue_constraint_destroy(fake_constraint)
	assert(p.drain_constraint_destroys().size() == 1, "constraint 队列幂等 + drain")

	p.queue_debris_spawn({"pos": Vector2(1, 2), "vel": Vector2.ZERO, "ang_vel": 0.0})
	assert(p.drain_debris_spawns().size() == 1, "debris 队列 drain")

	print("[TEST destruction_pipeline] ALL PASS")
	get_tree().quit()
