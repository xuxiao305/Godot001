# WheelJoint Demo —— 用 PinJoint2D + DampedSpringJoint2D 模拟带悬挂的轮子
# A/D 给轮子施加扭矩驱动车前后开
extends DemoLevel


@export var left_wheel_path: NodePath
@export var right_wheel_path: NodePath
@export var drive_torque: float = 5000.0   ## 单轮驱动扭矩

var _left_wheel: RigidBody2D = null
var _right_wheel: RigidBody2D = null


func _ready() -> void:
	super._ready()
	if left_wheel_path != NodePath(""):
		_left_wheel = get_node_or_null(left_wheel_path) as RigidBody2D
	if right_wheel_path != NodePath(""):
		_right_wheel = get_node_or_null(right_wheel_path) as RigidBody2D


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	var torque := 0.0
	if Input.is_key_pressed(KEY_D):
		torque = drive_torque
	elif Input.is_key_pressed(KEY_A):
		torque = -drive_torque
	if _left_wheel != null:
		_left_wheel.apply_torque(torque)
	if _right_wheel != null:
		_right_wheel.apply_torque(torque)
