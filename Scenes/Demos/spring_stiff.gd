extends Node2D

@export var anchor_path: NodePath
@export var body_path: NodePath
@export var rest_length: float = 100.0
@export var stiffness: float = 200.0
@export var spring_damping: float = 30.0

var _anchor: Node2D
var _body: RigidBody2D

func _ready() -> void:
	_anchor = get_node(anchor_path) as Node2D
	_body = get_node(body_path) as RigidBody2D

func _physics_process(_delta: float) -> void:
	if _anchor == null or _body == null:
		return
	var to_anchor: Vector2 = _anchor.global_position - _body.global_position
	var dist: float = to_anchor.length()
	if dist < 0.001:
		return
	var dir: Vector2 = to_anchor / dist
	var radial_vel: float = _body.linear_velocity.dot(dir)
	var force: float = stiffness * (dist - rest_length) - spring_damping * radial_vel
	_body.apply_central_force(dir * force)
