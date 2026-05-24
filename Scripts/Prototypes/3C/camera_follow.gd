# Scripts/Prototypes/3C/camera_follow.gd
# 平滑跟随摄像机：临界阻尼弹簧 + 死区 + 垂直 lookahead。
# 来源：spec §4.8
class_name CameraFollow
extends Camera2D

@export var target_path: NodePath
@export var follow_time_constant: float = 0.15      # ~0.15s 临界阻尼
@export var dead_zone: Vector2 = Vector2(32, 24)    # ±32, ±24
@export var lookahead_offset_y: float = 64.0
@export var lookahead_vy_threshold: float = 500.0   # 5 m/s × 100 px/m
@export var lookahead_stable_time: float = 0.3

var _target: Node2D
var _lookahead_target_y: float = 0.0
var _vy_sign_held_since: float = -INF
var _last_vy_sign: int = 0

func _ready() -> void:
	if not target_path.is_empty():
		_target = get_node(target_path) as Node2D

func _physics_process(delta: float) -> void:
	if _target == null:
		return
	var target_pos := _target.global_position

	# 死区：目标相对摄像机偏移如果在死区内则不变 anchor
	var diff := target_pos - global_position
	var anchor := global_position
	if absf(diff.x) > dead_zone.x:
		anchor.x = target_pos.x - signf(diff.x) * dead_zone.x
	if absf(diff.y) > dead_zone.y:
		anchor.y = target_pos.y - signf(diff.y) * dead_zone.y

	# 垂直 lookahead
	var vy := _get_target_vy()
	var cur_sign := 0
	if absf(vy) > lookahead_vy_threshold:
		cur_sign = signf(vy) as int
	var now := Time.get_ticks_msec() / 1000.0
	if cur_sign != _last_vy_sign:
		_last_vy_sign = cur_sign
		_vy_sign_held_since = now
	if cur_sign != 0 and (now - _vy_sign_held_since) >= lookahead_stable_time:
		_lookahead_target_y = lookahead_offset_y * cur_sign
	else:
		_lookahead_target_y = 0.0
	anchor.y += _lookahead_target_y

	# 临界阻尼平滑（指数松弛）
	var alpha := 1.0 - exp(-delta / follow_time_constant)
	global_position = global_position.lerp(anchor, alpha)

func _get_target_vy() -> float:
	if _target is RigidBody2D:
		return (_target as RigidBody2D).linear_velocity.y
	return 0.0

# 预留接口（spec §4.8）
func shake(_intensity: float, _duration: float) -> void:
	pass

func set_target(node: Node2D) -> void:
	_target = node
