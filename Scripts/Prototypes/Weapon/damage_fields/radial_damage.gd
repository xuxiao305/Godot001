# Scripts/Prototypes/Weapon/damage_fields/radial_damage.gd
# DamageField 子组件 —— 圆形范围内对所有 take_damage 受体按线性衰减扣血。
# 范围查询：CircleShape2D + intersect_shape（Godot 原生 API，已在 demo_level.gd 验证）。
# ADR-0007：duck typing，不接触 Constraint。
class_name RadialDamage
extends Node2D

const PX_PER_M: float = 100.0

@export var base: float = 100.0
@export var radius: float = 3.0 * PX_PER_M  # 3 m 默认（spec §4.4）
@export var max_bodies: int = 50

# 衰减纯函数 —— 同 spec §4.4 linear falloff。
static func compute_falloff(distance: float, r: float) -> float:
	if r <= 0.0:
		return 0.0
	return clampf(1.0 - distance / r, 0.0, 1.0)

func apply(space_state: PhysicsDirectSpaceState2D, center: Vector2, ctx: Dictionary) -> void:
	var circle := CircleShape2D.new()
	circle.radius = radius
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = circle
	q.transform = Transform2D(0.0, center)
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var hits := space_state.intersect_shape(q, max_bodies)
	var source: Node = ctx.get("source")
	for hit in hits:
		var body := hit.get("collider") as Node
		if body == null or not body.has_method("take_damage"):
			continue
		var d: float = (body.global_position - center).length() if body is Node2D else 0.0
		var amt := base * compute_falloff(d, radius)
		if amt <= 0.0:
			continue
		body.take_damage(amt, body.global_position if body is Node2D else center, source)
