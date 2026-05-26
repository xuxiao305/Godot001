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

@export var initial_health: float = 0.0
@export var damage_propagation_ratio: float = 0.3

var health: float = 0.0 # 当前血量，初始值由 initial_health 设定
var pipeline = null  # DestructionPipeline
var connected_constraints: Array = []  # Constraint 对象

var impact_watcher = null  # ImpactWatcher (Task 5)
var _queued_for_destroy: bool = false

static var debug_contact_impulse := true  # Toggle from DebugPanel or code

# Tracks Block instance_ids in contact with self last physics frame.
# Used to gate ImpactWatcher to first-contact-only — settling/steady stacking
# stops firing damage after the first frame of contact, while genuine impact
# events (falling debris, projectile-spawned debris) reliably fire on the new
# contact frame. Stress path (sustained joint reaction force) is independent
# and deferred to v2.
var _prev_contact_ids: Dictionary = {}
var _all_time_contact_ids: Dictionary = {}  # For re-contact diagnosis

func _ready() -> void:
	health = initial_health

func take_damage(amount: float, point: Vector2, source) -> void:
	if _queued_for_destroy:
		return
	health -= amount

	# Path X 伤害传递（可通过 DebugPanel → impact_watcher.propagation_enabled 关闭）
	if impact_watcher == null or impact_watcher.propagation_enabled:
		for constraint in connected_constraints:
			constraint.take_damage(amount * damage_propagation_ratio, point, source)

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
	var this_frame: Dictionary = {}

	for i in state.get_contact_count():
		var other = state.get_contact_collider_object(i)

		# spec §4.3: impact damage is Block↔Block only. Exclude projectile / player /
		# world contacts (otherwise weapon hits would double-tap damage).
		if not (other is Block):
			continue

		# Prevent double-counting: only the lesser instance_id reports the pair.

		if self.get_instance_id() >= other.get_instance_id():
			continue

		var other_id := other.get_instance_id()
		this_frame[other_id] = true

		# First-contact gate: skip if this pair was already touching last frame.
		# Filters out self-weight / stacking pressure (steady contact) while still
		# catching new impact events (debris falling onto structure, etc.).
		if _prev_contact_ids.has(other_id):
			continue

		# Constraint gate: skip if blocks share any constraint (Weld/Flex).
		# Prevents "friendly fire" from solver-induced separation → re-contact
		# between structural neighbors. Only true foreign-body impacts pass.
		if _has_shared_constraint(other):
			continue

		var impulse: Vector2 = state.get_contact_impulse(i)
		var impulse_magnitude: float = impulse.length()
		var local_pos := state.get_contact_local_position(i)
		if debug_contact_impulse:
			var dmg := ImpactWatcher.impact_to_damage(impulse_magnitude, impact_watcher.impact_threshold, impact_watcher.impact_coefficient)
			var tag := ""
			if _all_time_contact_ids.has(other_id):
				tag = " [RECONTACT]"
			else:
				tag = " [NEW]"
			print("[contact]%s %s <-X-> %s | impulse=%.3f damage=%.1f pos=%s" % [tag, self.name, other.name, impulse_magnitude, dmg, local_pos])
		impact_watcher.on_contact(self, other, impulse_magnitude, local_pos)

	for id in this_frame:
		_all_time_contact_ids[id] = true
	_prev_contact_ids = this_frame


func _has_shared_constraint(other) -> bool:
	for c in connected_constraints:
		if c.block_a == other or c.block_b == other:
			return true
	return false
