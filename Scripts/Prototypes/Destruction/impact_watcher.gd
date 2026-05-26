# Scripts/Prototypes/Destruction/impact_watcher.gd
# System: listens to contact impulses -> converts above-threshold impulses to damage events
# queued into damage_events queue.
# spec section 4.3: do NOT call take_damage directly from contact callback (avoids topology
# changes mid-physics-step).
#
# Actual contact detection is done by Block._integrate_forces (reads get_contact_impulse),
# this class only handles conversion + enqueueing.
class_name ImpactWatcher
extends RefCounted

const BlockKlass := preload("res://Scripts/Prototypes/Destruction/block.gd")
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
