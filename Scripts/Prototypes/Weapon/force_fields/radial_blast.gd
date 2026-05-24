# Scripts/Prototypes/Weapon/force_fields/radial_blast.gd
# ForceField 子组件 —— 圆形范围内对所有 dynamic body 按 (1 - d/R) 线性衰减施径向冲量。
# affect_player = true 是自爆跳的物理来源（ADR-0008 核心 invariant）。
# Debug 可关，仅用于 A/B 验证；产品默认 true。
class_name RadialBlast
extends Node2D

const PX_PER_M: float = 100.0
const RadialDamage := preload("res://Scripts/Prototypes/Weapon/damage_fields/radial_damage.gd")

@export var peak_impulse: float = 12.0 * PX_PER_M  # 12 N·s 默认（spec §4.5）
@export var radius: float = 3.0 * PX_PER_M
@export var affect_player: bool = true             # ADR-0008 invariant，默认 true
@export var max_bodies: int = 50

func apply(space_state: PhysicsDirectSpaceState2D, center: Vector2, ctx: Dictionary) -> void:
	var circle := CircleShape2D.new()
	circle.radius = radius
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = circle
	q.transform = Transform2D(0.0, center)
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var hits := space_state.intersect_shape(q, max_bodies)
	for hit in hits:
		var body := hit.get("collider") as RigidBody2D
		if body == null:
			continue
		if not affect_player and body.is_in_group("player"):
			continue
		var delta := body.global_position - center
		var d := delta.length()
		var f := RadialDamage.compute_falloff(d, radius)
		if f <= 0.0:
			continue
		var dir := delta.normalized() if d > 0.001 else Vector2.UP
		body.apply_central_impulse(dir * peak_impulse * f)
