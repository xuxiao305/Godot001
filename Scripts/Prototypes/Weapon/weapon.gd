# Scripts/Prototypes/Weapon/weapon.gd
# 瞄准（鼠标）+ 触发节流（cooldown）+ 生成 Projectile + 后坐力。
# 挂在持枪者（Player3C）下；持枪者作为 wielder 在 wielder_path 指明。
# 后坐力 = 给 wielder 施加反向冲量（与自爆跳无关，ADR-0008）。
class_name Weapon
extends Node2D

const PX_PER_M: float = 100.0

@export var projectile_scene: PackedScene
@export var fire_action: StringName = &"Fire1"       # InputMap action
@export var cooldown: float = 0.2
@export var projectile_initial_speed: float = 120.0 * PX_PER_M  # px/s
@export var muzzle_offset: Vector2 = Vector2(50.0, 20.0)        # 0.5 m, 0.2 m
@export var recoil_impulse: float = 1.0 * PX_PER_M              # 1 N·s 默认（手枪）
@export var recoil_enabled: bool = true
@export var wielder_path: NodePath
@export var aim_line_length: float = 200.0  # 视觉辅助线，Debug 可调

var _last_fire_time: float = -1000.0
var _wielder: RigidBody2D

func _ready() -> void:
	if wielder_path != NodePath():
		_wielder = get_node(wielder_path) as RigidBody2D

func _physics_process(_dt: float) -> void:
	if Input.is_action_pressed(fire_action):
		_try_fire()
	queue_redraw()  # 瞄准辅助线每帧重画

func _try_fire() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_fire_time < cooldown:
		return
	if projectile_scene == null or _wielder == null:
		return
	var muzzle := _muzzle_world()
	var dir := _aim_direction(muzzle)
	if dir == Vector2.ZERO:
		return
	# 1) Spawn Projectile
	var proj := projectile_scene.instantiate() as RigidBody2D
	if proj == null:
		push_warning("Weapon.projectile_scene is not RigidBody2D")
		return
	get_tree().current_scene.add_child(proj)
	proj.global_position = muzzle
	proj.linear_velocity = dir * projectile_initial_speed
	# 2) 后坐力
	if recoil_enabled and recoil_impulse > 0.0:
		_wielder.apply_central_impulse(-dir * recoil_impulse)
	_last_fire_time = now

func _muzzle_world() -> Vector2:
	# v1：muzzle_offset 是 wielder 局部偏移（不随瞄准旋转）—— spec §4.1。
	return _wielder.global_position + muzzle_offset

func _aim_direction(muzzle: Vector2) -> Vector2:
	var mouse := get_global_mouse_position()
	var v := mouse - muzzle
	if v.length_squared() < 0.0001:
		return Vector2.ZERO
	return v.normalized()

func _draw() -> void:
	# 瞄准辅助线（v1 = 直线，长度 aim_line_length）—— spec §4.10 Debug 项
	if _wielder == null:
		return
	# 注意：_draw 在 Weapon 局部坐标系，muzzle / 方向需转 local
	var muzzle_local := to_local(_muzzle_world())
	var dir := _aim_direction(_muzzle_world())
	if dir == Vector2.ZERO:
		return
	var end_local := muzzle_local + dir * aim_line_length
	draw_line(muzzle_local, end_local, Color(1, 1, 1, 0.5), 1.0)
