# Scripts/Prototypes/Destruction/destruction_pipeline.gd
# 单例：拓扑变更批处理。
# spec §4.4：所有 body/joint 销毁与创建只能在 _physics_process 末尾批量执行；
# 不在 Box2D 解算或 contact callback 中途改拓扑。
#
# 4 个队列：
#  - damage_events       —— { target, amount, point, source }
#  - constraint_destroy_queue
#  - block_destroy_queue
#  - debris_spawn_queue  —— { pos, vel, ang_vel }
#
# 销毁队列用 Dictionary{instance_id: object} 去重，保证幂等。
class_name DestructionPipeline
extends RefCounted

var damage_events: Array = []
var block_destroy_queue: Dictionary = {}
var constraint_destroy_queue: Dictionary = {}
var debris_spawn_queue: Array = []

func queue_damage_event(ev: Dictionary) -> void:
	damage_events.append(ev)

func queue_block_destroy(block) -> void:
	block_destroy_queue[block.get_instance_id()] = block

func queue_constraint_destroy(c) -> void:
	constraint_destroy_queue[c.get_instance_id()] = c

func queue_debris_spawn(d: Dictionary) -> void:
	debris_spawn_queue.append(d)

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

func drain_debris_spawns() -> Array:
	var snap := debris_spawn_queue
	debris_spawn_queue = []
	return snap
