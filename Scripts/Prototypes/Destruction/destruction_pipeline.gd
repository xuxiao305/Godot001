# Scripts/Prototypes/Destruction/destruction_pipeline.gd
# 单例：拓扑变更批处理。
# spec §4.4：所有 body/joint 销毁只能在 _physics_process 末尾、Rapier 完成本帧解算之后批量执行。
# 不在 contact callback 或碰撞回调中途直接 queue_free()。
#
# 3 个队列：
#  - damage_events             —— { target, amount, point, source }
#  - constraint_destroy_queue  —— Dictionary{instance_id: Constraint}
#  - block_destroy_queue       —— Dictionary{instance_id: Block}
#
# 销毁队列用 Dictionary 去重，保证幂等。
class_name DestructionPipeline
extends RefCounted

var damage_events: Array = []
var block_destroy_queue: Dictionary = {}
var constraint_destroy_queue: Dictionary = {}

func queue_damage_event(ev: Dictionary) -> void:
	damage_events.append(ev)

func queue_block_destroy(block) -> void:
	block_destroy_queue[block.get_instance_id()] = block

func queue_constraint_destroy(c) -> void:
	constraint_destroy_queue[c.get_instance_id()] = c

func drain_damage_events() -> Array:
	var snap := damage_events
	damage_events = []
	return snap

func drain_block_destroys() -> Array:
	var snap := block_destroy_queue.values()
	block_destroy_queue = {}
	return snap

func drain_constraint_destroys() -> Array:
	var snap := constraint_destroy_queue.values()
	constraint_destroy_queue = {}
	return snap

# 派发伤害事件：遍历 damage_events，对每个 target 调 take_damage。
# 约束：target 必须 1) 仍有效（is_instance_valid）且 2) 有 take_damage 方法。
# 已在 destroy queue 的 target 仍会被派发（take_damage 内部的 _queued_for_destroy guard 处理幂等）。
func dispatch_damage_events() -> void:
	for damage_event in drain_damage_events():
		var target = damage_event.target
		if is_instance_valid(target) and target.has_method("take_damage"):
			target.take_damage(damage_event.amount, damage_event.point, damage_event.source)
