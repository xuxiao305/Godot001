# Scripts/Prototypes/Destruction/weld_constraint.gd
# WeldConstraint —— 一对相邻 Block 之间的"焊死"约束。spec §4.2 (weld variant)。
#
# 实现策略（v1，与最初 spec 描述不同）：
#   单根 PinJoint2D 负责位置约束 + 两端 Block.lock_rotation = true 各自锁旋转。
#   为何不用 2-pin "weld"：Rapier2D 的 RevoluteJoint 对同一 body pair 的多个实例
#   不作独立硬约束，第二根销没效果（实测确认）；改用 per-block lock_rotation。
#   断裂后若 Block 的 connected_constraints 全空，解锁旋转 → 孤块能自由翻滚。
#
# 对照 [[flex_constraint]]（单销 + 不锁旋转）—— 块可绕销旋，宏观软体感。
#
# 断裂路径（v1）：仅伤害路径。血量归零 → 入 constraint_destroy_queue → 帧末销毁。
class_name WeldConstraint
extends RefCounted

var pin: PinJoint2D
var block_a  # Block
var block_b  # Block

var initial_health: float = 50.0
var health: float = 50.0
var pipeline = null  # DestructionPipeline

var _queued_for_destroy: bool = false

# 装配：单 PinJoint2D + 两端 Block.lock_rotation。
static func create(
	a,  # Block
	b,  # Block
	shared_center: Vector2,
	parent: Node
):  # -> WeldConstraint
	# load() instead of WeldConstraint.new(): GDScript class_name self-reference
	# inside a static func of the same file fails to resolve at compile time.
	var c = load("res://Scripts/Prototypes/Constraints/weld_constraint.gd").new()
	c.block_a = a
	c.block_b = b
	c.health = c.initial_health

	var pin := PinJoint2D.new()
	pin.global_position = shared_center
	pin.disable_collision = true
	parent.add_child(pin)
	pin.node_a = a.get_path()
	pin.node_b = b.get_path()
	c.pin = pin

	# Lock rotation on both blocks while bonded. Idempotent — multiple
	# weld constraints on the same block all set this to true.
	a.lock_rotation = true
	b.lock_rotation = true
	return c

func take_damage(amount: float, point: Vector2, source) -> void:
	if _queued_for_destroy:
		return
	health -= amount
	if health <= 0.0:
		_queued_for_destroy = true
		if pipeline != null:
			pipeline.queue_constraint_destroy(self)

# 由 DestructionPipeline 帧末调用。
# 副作用：若 Block 失去所有 connected_constraints，解锁其旋转 → 孤块物理化。
func destroy() -> void:
	if not _queued_for_destroy:
		return
	if is_instance_valid(pin):
		pin.queue_free()
	if is_instance_valid(block_a):
		block_a.connected_constraints.erase(self)
		if block_a.connected_constraints.is_empty():
			block_a.lock_rotation = false
	if is_instance_valid(block_b):
		block_b.connected_constraints.erase(self)
		if block_b.connected_constraints.is_empty():
			block_b.lock_rotation = false
