# GearJoint Demo —— 脚本耦合两个 PinJoint 齿轮的角速度，模拟齿轮联动
extends DemoLevel


@export var gear_a_path: NodePath
@export var gear_b_path: NodePath
@export var ratio: float = -1.0   ## GearB 的角速度 = GearA 的角速度 * ratio（-1 表示同速反向）

var _gear_a: RigidBody2D = null
var _gear_b: RigidBody2D = null
var _drag_tracking_body: RigidBody2D = null
var _drag_last_angle: float = 0.0


func _ready() -> void:
	super._ready()
	if gear_a_path != NodePath(""):
		_gear_a = get_node_or_null(gear_a_path) as RigidBody2D
	if gear_b_path != NodePath(""):
		_gear_b = get_node_or_null(gear_b_path) as RigidBody2D


func _physics_process(delta: float) -> void:
	# 不调用 super._physics_process(delta) —— 齿轮被 PinJoint 锁在中心，
	# 基类的 linear_velocity 拖拽既无法转动它，又会与 pin 约束冲突。
	if _gear_a == null or _gear_b == null:
		return

	var dragged: RigidBody2D = null
	if _drag_body == _gear_a:
		dragged = _gear_a
	elif _drag_body == _gear_b:
		dragged = _gear_b

	if dragged != null:
		var current_angle := (get_global_mouse_position() - dragged.global_position).angle()
		if _drag_tracking_body != dragged:
			_drag_tracking_body = dragged
			_drag_last_angle = current_angle
		var d := wrapf(current_angle - _drag_last_angle, -PI, PI)
		_drag_last_angle = current_angle
		if delta > 0.0:
			dragged.angular_velocity = d / delta
	else:
		_drag_tracking_body = null

	if _drag_body == _gear_a or (_drag_body == null and abs(_gear_a.angular_velocity) >= abs(_gear_b.angular_velocity)):
		_gear_b.angular_velocity = _gear_a.angular_velocity * ratio
	else:
		_gear_a.angular_velocity = _gear_b.angular_velocity / ratio
