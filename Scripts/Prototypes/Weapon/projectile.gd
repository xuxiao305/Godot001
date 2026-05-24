# Scripts/Prototypes/Weapon/projectile.gd
# 飞行物理 + 命中检测 + 触发 Effect。
# 高速直射弹 + 抛物线弹同一类，差异由 gravity_scale / initial_speed / max_lifetime 决定（ADR-0009 §Decision）。
# CCD 在 .tscn 里通过 continuous_cd = 2 (CCD_MODE_CAST_SHAPE) 打开。
class_name Projectile
extends RigidBody2D

@export var effect_scene: PackedScene
@export var max_lifetime: float = 1.5

var _age: float = 0.0
var _hit_handled: bool = false  # 防止同帧多 body_entered 触发多个 Effect

func _ready() -> void:
	add_to_group("projectile")
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= max_lifetime:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if _hit_handled:
		return
	_hit_handled = true
	# 命中点 = projectile 当前位置（精度足够；CCD 命中点可由 contact 取，v1 不做）
	var hit_point := global_position
	# 弹道方向 = 当前速度方向（命中瞬间）
	var dir := linear_velocity.normalized() if linear_velocity.length_squared() > 0.0 else Vector2.RIGHT
	_spawn_effect(hit_point, dir)
	queue_free()

func _spawn_effect(point: Vector2, direction: Vector2) -> void:
	if effect_scene == null:
		return
	var fx := effect_scene.instantiate() as Effect
	if fx == null:
		push_warning("Projectile.effect_scene is not an Effect: %s" % effect_scene)
		return
	# 必须先挂到 scene tree 才能 get_world_2d()
	get_tree().current_scene.add_child(fx)
	fx.trigger(point, {"source": self, "direction": direction})
