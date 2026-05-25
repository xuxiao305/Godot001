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

# 枪口相对于 holder 的局部偏移（不随瞄准旋转）—— spec §4.1。
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

# _physics_process 只处理输入和视觉辅助线，生成 Projectile 和后坐力在 _try_fire 中；绝不直接修改 linear_velocity
# _physics 是引擎的内置回调，每帧固定频率调用，适合处理输入和物理相关逻辑。
func _physics_process(_dt: float) -> void:
	if Input.is_action_pressed(fire_action):
		_try_fire()
	queue_redraw()  # 瞄准辅助线每帧重画

func _check_fire_conditions(current_fire_time: float) -> bool:
	if projectile == null:
		return false
		
	# _holder的意义是施加后坐力；如果 recoil_enabled 是 false，理论上 _holder 可以不存在，但为了简化逻辑，这里要求它必须存在。
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
	
	# 计算瞄准方向 = 从 muzzle 指向鼠标的单位向量；如果鼠标和 muzzle 太近则不发射（避免数值不稳定）
	var muzzle := _get_muzzle_position_world()
	var dir := _aim_direction(muzzle)
	if dir == Vector2.ZERO:
		return

	# 生成子弹
	_spawn_projectile(muzzle, dir)

	# 施加后坐力
	_recoil_impulse(dir)

	_last_fire_time = current_fire_time

func _get_muzzle_position_world() -> Vector2:
	# v1：muzzle_offset 是 holder 局部偏移（不随瞄准旋转）—— spec §4.1。
	return _holder.global_position + muzzle_offset

func _aim_direction(muzzle: Vector2) -> Vector2:
	var mouse := get_global_mouse_position()
	var v := mouse - muzzle
	if v.length_squared() < 0.0001:
		return Vector2.ZERO
	return v.normalized()

func _draw() -> void:
	# 瞄准辅助线（v1 = 直线，长度 aim_line_length）—— spec §4.10 Debug 项
	if _holder == null:
		return
	# 注意：_draw 在 Weapon 局部坐标系，muzzle / 方向需转 local
	var muzzle_local := to_local(_get_muzzle_position_world())
	var dir := _aim_direction(_get_muzzle_position_world())
	if dir == Vector2.ZERO:
		return
	var end_local := muzzle_local + dir * aim_line_length
	draw_line(muzzle_local, end_local, Color(1, 1, 1, 0.5), 1.0)
