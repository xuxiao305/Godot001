# 拖拽可视化 —— 配合 DemoLevel 的 velocity-drag 显示弹簧线 + 拖尾
@tool
class_name DragVisualizer
extends Node2D


@export var spring_segments: int = 10
@export var spring_amplitude: float = 8.0
@export var spring_color: Color = Color(1.0, 0.9, 0.3, 1.0)
@export var spring_width: float = 3.0

@export var trail_length: int = 60          ## 拖尾保留的位置点数量
@export var trail_color: Color = Color(0.5, 0.85, 1.0, 0.8)
@export var trail_width: float = 4.0


var _spring_line: Line2D = null
var _trail_line: Line2D = null
var _trail_points: PackedVector2Array = PackedVector2Array()
var _demo: DemoLevel = null


func _ready() -> void:
	top_level = true   # 用全局坐标绘制
	_spring_line = Line2D.new()
	_spring_line.width = spring_width
	_spring_line.default_color = spring_color
	add_child(_spring_line)

	_trail_line = Line2D.new()
	_trail_line.width = trail_width
	_trail_line.default_color = trail_color
	add_child(_trail_line)

	_demo = _find_demo_ancestor()


func _physics_process(_delta: float) -> void:
	if _demo == null:
		return
	var body: RigidBody2D = _demo._drag_body
	if body == null or not is_instance_valid(body):
		_spring_line.clear_points()
		_trail_points.clear()
		_trail_line.clear_points()
		return

	var mouse := get_global_mouse_position()
	var body_pos := body.global_position
	_spring_line.points = _make_spring_points(mouse, body_pos)

	_trail_points.append(body_pos)
	while _trail_points.size() > trail_length:
		_trail_points.remove_at(0)
	_trail_line.points = _trail_points


func _make_spring_points(a: Vector2, b: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.push_back(a)
	var dir := b - a
	var length := dir.length()
	if length < 0.01 or spring_segments <= 0:
		pts.push_back(b)
		return pts
	var step := dir / float(spring_segments + 1)
	var perp := Vector2(-dir.y, dir.x).normalized() * spring_amplitude
	for i in range(1, spring_segments + 1):
		var base := a + step * float(i)
		var sign := 1.0 if (i % 2 == 1) else -1.0
		pts.push_back(base + perp * sign)
	pts.push_back(b)
	return pts


func _find_demo_ancestor() -> DemoLevel:
	var n: Node = get_parent()
	while n != null:
		if n is DemoLevel:
			return n
		n = n.get_parent()
	return null
