# Scripts/Prototypes/Destruction/impact_watcher.gd
# 系统：监听接触冲量 -> 将超过阈值的冲量转换为伤害事件
# 将damage_events设计为一个纯数据结构（字典列表），而不是直接调用take_damage接口，是为了避免在物理步骤中直接修改Block状态（take_damage可能导致Block销毁，进而修改物理拓扑）
# DestructionPipeline会在物理步骤结束后处理

# 实际的接触检测由 Block._integrate_forces 完成（读取 get_contact_impulse），
# 以便直接访问接触冲量数据（ImpactWatcher 只负责转换和入队）。

# 这个类只负责转换和入队。实际的接触检测由 Block._integrate_forces 完成（读取 get_contact_impulse）
# 以便直接访问接触冲量数据（ImpactWatcher 只负责转换和入队）。

class_name ImpactWatcher
extends RefCounted

const BlockKlass := preload("res://Scripts/Prototypes/Blocks/block.gd")
const DestructionPipelineKlass := preload("res://Scripts/Prototypes/Destruction/destruction_pipeline.gd")

var impact_threshold: float = 2.0
var impact_coefficient: float = 10.0

var pipeline = null  # DestructionPipeline
var enabled: bool = true
var propagation_enabled: bool = true

# Pure function: impulse -> damage amount
static func impact_to_damage(normal_impulse: float, threshold: float, coefficient: float) -> float:
	if normal_impulse <= threshold:
		return 0.0
	return (normal_impulse - threshold) * coefficient

# Called by Block._integrate_forces. One call per contact (instance_id comparison
# to prevent double-counting is handled on the Block side).
func on_contact(block_a, block_b, normal_impulse: float, point: Vector2) -> void:
	if not enabled:
		return
	var dmg := impact_to_damage(normal_impulse, impact_threshold, impact_coefficient)
	if dmg <= 0.0:
		return
	if pipeline == null:
		return
	pipeline.queue_damage_event({"target": block_a, "amount": dmg, "point": point, "source": "impact"})
	pipeline.queue_damage_event({"target": block_b, "amount": dmg, "point": point, "source": "impact"})
