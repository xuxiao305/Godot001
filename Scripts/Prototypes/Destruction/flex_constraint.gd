# Scripts/Prototypes/Destruction/flex_constraint.gd
# FlexConstraint —— 一对相邻 Block 之间的"松销"约束。spec §4.2 (flex variant)。
#
# 实现：单根 PinJoint2D + angular_limit_lower=angular_limit_upper=0。
# Rapier 把 angular_limit 当软约束（iterative solver corrective force），重力 + 堆叠
# 载荷下两块仍可绕销轴微旋 → 宏观"软体感 / 木栅 / 绳网"，适合需要弹性的材质。
# 真焊死的刚体壳走 weld_constraint.gd（双 PinJoint 几何锁死）。
#
# 断裂路径（v1）：仅伤害路径。血量归零 → 入 constraint_destroy_queue → 帧末销毁。
class_name FlexConstraint
extends RefCounted

var pin: PinJoint2D
var block_a  # Block
var block_b  # Block

var initial_health: float = 50.0
var health: float = 50.0
var pipeline = null  # DestructionPipeline

var _queued_for_destroy: bool = false

# 装配：在两 block 共享边中点创建 PinJoint2D。
static func create(
	a,  # Block
	b,  # Block
	shared_center: Vector2,
	parent: Node
):  # -> FlexConstraint
	# load() instead of FlexConstraint.new(): GDScript class_name self-reference
	# inside a static func of the same file fails to resolve at compile time.
	var c = load("res://Scripts/Prototypes/Destruction/flex_constraint.gd").new()
	c.block_a = a
	c.block_b = b
	c.health = c.initial_health

	var pin := PinJoint2D.new()
	pin.global_position = shared_center
	pin.disable_collision = true
	pin.angular_limit_enabled = true
	pin.angular_limit_lower = 0.0
	pin.angular_limit_upper = 0.0
	parent.add_child(pin)
	# node_a / node_b 必须在 add_child 之后设（NodePath 解析依赖 in_tree）
	pin.node_a = a.get_path()
	pin.node_b = b.get_path()
	c.pin = pin
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
func destroy() -> void:
	if _queued_for_destroy:
		if is_instance_valid(pin):
			pin.queue_free()
		if is_instance_valid(block_a):
			block_a.connected_constraints.erase(self)
		if is_instance_valid(block_b):
			block_b.connected_constraints.erase(self)
