# Scripts/Prototypes/Weapon/weapon.gd
# 瞄准（鼠标）+ 触发节流（cooldown）+ 生成 Projectile + 后坐力。
# 挂在持枪者（Player3C）下；持枪者作为 holder 在 holder_path 指明。
# 后坐力 = 给 holder 施加反向冲量（与自爆跳无关，ADR-0008）。
class_name Weapon
extends Node2D

const PX_PER_M: float = 100.0

@export var projectile: PackedScene
# Fire1 是 Godot 默认的左键点击，玩家可在 InputMap 里改；也可指定其他 action 实现多种武器。
@export var fire_action: StringName = &"Fire1"       # InputMap action
@export var cooldown: float = 0.2
@export var projectile_initial_speed: float = 120.0 * PX_PER_M  # px/s

# 枪口相对于 Weapon 节点的局部偏移，随 Weapon 翻转自动跟随。
@export var muzzle_offset: Vector2 = Vector2(50.0, 20.0)        # 0.5 m, 0.2 m
@export var recoil_impulse: float = 1.0 * PX_PER_M              # 1 N·s 默认（手枪）
@export var recoil_enabled: bool = true
@export var holder_path: NodePath
@export var aim_line_length: float = 200.0  # 视觉辅助线，Debug 可调

var _last_fire_time: float = -1000.0
var _holder: RigidBody2D

func _ready() -> void:
	if holder_path != NodePath():
		_holder = get_node(holder_path) as RigidBody2D

func _physics_process(_dt: float) -> void:
	_update_facing()
	if Input.is_action_pressed(fire_action):
		_try_fire()
	queue_redraw()

func _update_facing() -> void:
	if _holder == null:
		return
	var mouse_x := get_global_mouse_position().x
	var holder_x := _holder.global_position.x
	if mouse_x < holder_x:
		scale.x = -1
	else:
		scale.x = 1
	# 同步翻转玩家精灵
	var sprite := _holder.get_node_or_null("AnimatedSprite2D")
	if sprite:
		sprite.scale.x = scale.x

func _check_fire_conditions(current_fire_time: float) -> bool:
	if projectile == null:
		return false
	if _holder == null:
		return false
	if current_fire_time - _last_fire_time < cooldown:
		return false
	return true

func _spawn_projectile(muzzle: Vector2, dir: Vector2) -> void:
	var proj := projectile.instantiate() as RigidBody2D
	if proj == null:
		push_warning("Weapon.projectile is not RigidBody2D")
		return
	get_tree().current_scene.add_child(proj)
	proj.global_position = muzzle
	proj.linear_velocity = dir * projectile_initial_speed

func _recoil_impulse(dir: Vector2) -> void:
	if not recoil_enabled or recoil_impulse <= 0.0:
		return
	if _holder == null:
		return
	_holder.apply_central_impulse(-dir * recoil_impulse)

func _try_fire() -> void:
	var current_fire_time := Time.get_ticks_msec() / 1000.0
	if not (_check_fire_conditions(current_fire_time)):
		return

	var muzzle := _get_muzzle_position_world()
	var dir := _aim_direction(muzzle)
	if dir == Vector2.ZERO:
		return

	_spawn_projectile(muzzle, dir)
	_recoil_impulse(dir)
	_last_fire_time = current_fire_time

func _get_muzzle_position_world() -> Vector2:
	return to_global(muzzle_offset)

func _aim_direction(muzzle: Vector2) -> Vector2:
	var mouse := get_global_mouse_position()
	var v := mouse - muzzle
	if v.length_squared() < 0.0001:
		return Vector2.ZERO
	return v.normalized()

func _draw() -> void:
	if _holder == null:
		return
	var muzzle_world := _get_muzzle_position_world()
	var dir := _aim_direction(muzzle_world)
	if dir == Vector2.ZERO:
		return
	var end_world := muzzle_world + dir * aim_line_length
	draw_line(to_local(muzzle_world), to_local(end_world), Color(1, 1, 1, 0.5), 1.0)
