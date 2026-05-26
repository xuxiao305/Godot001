# Scripts/Prototypes/Destruction/constraint.gd
# Constraint —— 一对相邻 Block 之间的约束封装。spec §4.2。
#
# 实现：单根 PinJoint2D + angular_limit_lower=angular_limit_upper=0 等效 weld。
# Rapier2D 原生支持 angular_limit，无需 godot-box2d 的 2× PinJoint 方案。
#
# 断裂路径（v1）：仅伤害路径。血量归零 → 入 constraint_destroy_queue → 帧末销毁。
# （v2 加应力路径：每帧检测 PinJoint 内部应力超 stress_threshold。）
class_name Constraint
extends RefCounted

var pin: PinJoint2D
var block_a: Block
var block_b: Block

var initial_health: float = 50.0
var health: float = 50.0
var pipeline: DestructionPipeline = null

var _queued_for_destroy: bool = false

# 装配：在两 block 共享边中点创建 PinJoint2D，angular_limit 锁死相对旋转。
# shared_center = 共享边中点世界坐标。
static func create(
	a: Block, b: Block,
	shared_center: Vector2,
	parent: Node
) -> Constraint:
	var c := Constraint.new()
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
		_queued_for_destroy = false  # 防重入
