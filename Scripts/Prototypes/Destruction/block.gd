# Scripts/Prototypes/Destruction/block.gd
# 体块 —— RigidBody2D 派生。spec §4.1。
#
# Body 参数（mass / friction / shape / damping）由 BlockFactory 配置，
# 本脚本只管数据 + 行为。
#
# take_damage 是统一伤害语言（ADR-0007）的实现。
# 外部（武器 DamageField / ImpactWatcher）都走这一个接口。
# Path X 伤害传递：扣自己血后按 damage_propagation_ratio 传给所有相连 Constraint。
class_name Block
extends RigidBody2D

const DestructionPipelineKlass := preload("res://Scripts/Prototypes/Destruction/destruction_pipeline.gd")

signal block_destroyed(position: Vector2)

@export var initial_health: float = 100.0
@export var damage_propagation_ratio: float = 0.3

var health: float = 100.0
var pipeline = null  # DestructionPipeline
var connected_constraints: Array = []  # Constraint 对象

var impact_watcher = null  # ImpactWatcher (Task 5)
var _queued_for_destroy: bool = false

func _ready() -> void:
	health = initial_health

func take_damage(amount: float, point: Vector2, source) -> void:
	if _queued_for_destroy:
		return
	health -= amount
	# Path X 伤害传递到所有相连 Constraint
	for c in connected_constraints:
		c.take_damage(amount * damage_propagation_ratio, point, source)
	if health <= 0.0:
		_queued_for_destroy = true
		if pipeline != null:
			pipeline.queue_block_destroy(self)
		block_destroyed.emit(global_position)

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if impact_watcher == null:
		return
	if not impact_watcher.enabled:
		return
	for i in state.get_contact_count():
		var other = state.get_contact_collider_object(i)
		if not (other is RigidBody2D):
			continue
		# Prevent double-counting: only process pairs where self.instance_id < other.instance_id
		if self.get_instance_id() >= other.get_instance_id():
			continue
		var impulse: Vector2 = state.get_contact_impulse(i)
		var j_normal: float = impulse.length()
		var local_pos := state.get_contact_local_position(i)
		impact_watcher.on_contact(self, other, j_normal, local_pos)
