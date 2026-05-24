# Scripts/Prototypes/Weapon/force_fields/directional_impulse.gd
# ForceField 子组件 —— 命中点最近一个 RigidBody2D 沿弹道方向施加冲量。
# direction 来自 ctx.direction（Projectile 命中时由 linear_velocity.normalized() 提供）。
class_name DirectionalImpulse
extends Node2D

const PX_PER_M: float = 100.0

@export var magnitude: float = 1.0 * PX_PER_M  # 1 N·s 默认（spec §4.5）

func apply(space_state: PhysicsDirectSpaceState2D, center: Vector2, ctx: Dictionary) -> void:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = center
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var hits := space_state.intersect_point(q, 1)
	if hits.is_empty():
		return
	var body := hits[0].get("collider") as RigidBody2D
	if body == null:
		return
	var dir: Vector2 = ctx.get("direction", Vector2.ZERO)
	if dir == Vector2.ZERO:
		return
	body.apply_central_impulse(dir.normalized() * magnitude)
