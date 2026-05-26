# Scripts/Prototypes/Destruction/tests/test_damage_propagation.gd
# 验 Block.take_damage 内的 Path X：按 damage_propagation_ratio 传递给所有相连 Constraint。
# 也验 Constraint.take_damage 致命伤入队。
extends Node

const Block := preload("res://Scripts/Prototypes/Destruction/block.gd")
const FlexConstraint := preload("res://Scripts/Prototypes/Destruction/flex_constraint.gd")
const WeldConstraint := preload("res://Scripts/Prototypes/Destruction/weld_constraint.gd")
const DestructionPipeline := preload("res://Scripts/Prototypes/Destruction/destruction_pipeline.gd")

# 用伪 Constraint 收传递量 —— 不实例化 PinJoint2D。
class FakeConstraint extends RefCounted:
	var received_damage: float = 0.0
	var received_count: int = 0
	func take_damage(amount: float, point: Vector2, source) -> void:
		received_damage += amount
		received_count += 1

func _ready() -> void:
	var pipeline := DestructionPipeline.new()

	# Path X：Block 受 100 → 传递 100*0.3 = 30 到每条相连 Constraint
	var b := Block.new()
	b.pipeline = pipeline
	b.initial_health = 200.0
	b.health = 200.0
	b.damage_propagation_ratio = 0.3
	var c1 := FakeConstraint.new()
	var c2 := FakeConstraint.new()
	b.connected_constraints = [c1, c2]
	b.take_damage(100.0, Vector2.ZERO, "test")
	assert(absf(c1.received_damage - 30.0) < 0.001, "c1 应收 30, got %f" % c1.received_damage)
	assert(absf(c2.received_damage - 30.0) < 0.001, "c2 应收 30, got %f" % c2.received_damage)
	assert(c1.received_count == 1, "c1 应只被调一次")

	# Block 致死后再 take_damage 不再传递（early return）
	b.take_damage(200.0, Vector2.ZERO, "test")  # health <= 0，入队
	var prev := c1.received_damage  # = 30 + 60 = 90
	b.take_damage(50.0, Vector2.ZERO, "test")  # 死后再打
	assert(absf(c1.received_damage - prev) < 0.001, "Block 已死，不应再传递")

	# FlexConstraint take_damage 致死入队
	var real_c := FlexConstraint.new()
	real_c.pipeline = pipeline
	real_c.initial_health = 50.0
	real_c.health = 50.0
	real_c.take_damage(60.0, Vector2.ZERO, "test")
	assert(pipeline.constraint_destroy_queue.size() == 1, "flex 致死应入 constraint_destroy_queue")

	# WeldConstraint take_damage 行为相同（duck-type 一致性）
	var weld_c := WeldConstraint.new()
	weld_c.pipeline = pipeline
	weld_c.initial_health = 50.0
	weld_c.health = 50.0
	weld_c.take_damage(60.0, Vector2.ZERO, "test")
	assert(pipeline.constraint_destroy_queue.size() == 2, "weld 致死应再加 1 入队, got %d" % pipeline.constraint_destroy_queue.size())

	print("[TEST damage_propagation] ALL PASS")
	get_tree().quit()
