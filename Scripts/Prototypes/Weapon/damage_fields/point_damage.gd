# Scripts/Prototypes/Weapon/damage_fields/point_damage.gd
# DamageField 子组件 —— 命中点最近一个 dynamic body 单点扣血。
# ADR-0007：duck typing 调用 take_damage(amount, point, source)。
class_name PointDamage
extends Node2D

@export var amount: float = 50.0

# space_state: PhysicsDirectSpaceState2D（由 Effect 主类从 world 获取后传入）
# center: 命中点世界坐标
# ctx: { "source": Node }
func apply(space_state: PhysicsDirectSpaceState2D, center: Vector2, ctx: Dictionary) -> void:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = center
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var hits := space_state.intersect_point(q, 1)
	if hits.is_empty():
		return
	var body := hits[0].get("collider") as Node
	if body == null or not body.has_method("take_damage"):
		return
	body.take_damage(amount, center, ctx.get("source"))
