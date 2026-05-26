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
var _hit_point: Vector2 = Vector2.ZERO
var _hit_dir: Vector2 = Vector2.RIGHT

func _ready() -> void:
	add_to_group("projectile")
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= max_lifetime:
		queue_free()
	if linear_velocity.length_squared() > 0.01:
		rotation = linear_velocity.angle()

func _on_body_entered(body: Node) -> void:
	if _hit_handled:
		return
	_hit_handled = true
	# 捕获命中位置和方向，然后 defer 到空闲帧再做 Effect spawn。
	# 物理 step 内做 intersect_point / add_child 会破坏物理引擎内部状态导致卡死。
	_hit_point = global_position
	_hit_dir = linear_velocity.normalized() if linear_velocity.length_squared() > 0.0 else Vector2.RIGHT
	call_deferred("_handle_hit_deferred")

func _handle_hit_deferred() -> void:
	_spawn_effect(_hit_point, _hit_dir)
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
