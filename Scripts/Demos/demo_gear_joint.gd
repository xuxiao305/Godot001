# GearJoint Demo —— 脚本耦合两个 PinJoint 齿轮的角速度，模拟齿轮联动
extends DemoLevel


@export var gear_a_path: NodePath
@export var gear_b_path: NodePath
@export var ratio: float = -1.0   ## GearB 的角速度 = GearA 的角速度 * ratio（-1 表示同速反向）

var _gear_a: RigidBody2D = null
var _gear_b: RigidBody2D = null


func _ready() -> void:
	super._ready()
	if gear_a_path != NodePath(""):
		_gear_a = get_node_or_null(gear_a_path) as RigidBody2D
	if gear_b_path != NodePath(""):
		_gear_b = get_node_or_null(gear_b_path) as RigidBody2D


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _gear_a == null or _gear_b == null:
		return
	# 双向耦合：哪个被拖就以哪个为主动
	if _drag_body == _gear_a or (_drag_body == null and abs(_gear_a.angular_velocity) >= abs(_gear_b.angular_velocity)):
		_gear_b.angular_velocity = _gear_a.angular_velocity * ratio
	else:
		_gear_a.angular_velocity = _gear_b.angular_velocity / ratio
