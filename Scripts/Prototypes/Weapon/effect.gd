# Scripts/Prototypes/Weapon/effect.gd
# 双通道容器（DamageField + ForceField），ADR-0007。
# 子节点用 duck typing 匹配：has_method("apply") 即视为子组件。
# 视觉：白圆闪 → 半透淡出 → queue_free（与物理 apply 并行）。
class_name Effect
extends Node2D

@export var visual_duration: float = 0.3
@export var visual_radius_px: float = 50.0
@export var visual_color: Color = Color(1, 0.8, 0.4, 0.9)

# context 由触发者（Projectile / 鼠标 spawn）调用 trigger() 时传入。
# direction = 弹道方向（DirectionalImpulse 需要）；normal = 命中面法线（可选）；source = Projectile 节点（受体打印用）。
var _ctx: Dictionary = {}

# Projectile / weapon_demo 在 instantiate + add_child 之后调用一次此方法。
# 必须先 add_child（取得 world_2d）再 trigger。
func trigger(center: Vector2, ctx: Dictionary) -> void:
	global_position = center
	_ctx = ctx
	var space_state := get_world_2d().direct_space_state
	# 让所有挂着 apply(space_state, center, ctx) 的子组件各跑一遍。
	for child in get_children():
		if child.has_method("apply"):
			child.apply(space_state, center, _ctx)
	_start_visual()

func _start_visual() -> void:
	# 简易视觉：一个 ColorRect（圆形 mask 用 draw 更简单）—— 这里用自绘 + tween。
	queue_redraw()
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, visual_duration)
	t.tween_callback(queue_free)

func _draw() -> void:
	# 自绘一个圆（避免额外子节点）。半径在 visual_duration 内不变，靠 modulate 淡出。
	draw_circle(Vector2.ZERO, visual_radius_px, visual_color)
