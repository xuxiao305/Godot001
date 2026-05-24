# 关节连线可视化 —— 挂在 Line2D 节点上，每帧把 point_a → point_b 重画一次
@tool
class_name JointLineVisualizer
extends Line2D

# --------- EXPORT VARIABLES ---------- #

@export var point_a: NodePath          ## 端点 A（通常是 RigidBody2D 或 StaticBody2D）
@export var point_b: NodePath          ## 端点 B
@export var anchor_a: Vector2 = Vector2.ZERO   ## A 端的局部偏移
@export var anchor_b: Vector2 = Vector2.ZERO   ## B 端的局部偏移
@export var spring_segments: int = 0   ## > 0 时把直线画成锯齿弹簧；0 = 直线
@export var spring_amplitude: float = 8.0      ## 弹簧锯齿振幅

# --------- BUILT-IN FUNCTIONS ---------- #

func _ready() -> void:
	top_level = true   # 不跟随父节点 transform，自己用全局坐标画
	if width <= 0.0:
		width = 3.0
	if default_color.a == 0.0:
		default_color = Color(0.85, 0.85, 0.3, 1.0)

func _process(_delta: float) -> void:
	var a := get_node_or_null(point_a) as Node2D
	var b := get_node_or_null(point_b) as Node2D
	if a == null or b == null:
		clear_points()
		return

	var p_a := a.global_position + anchor_a
	var p_b := b.global_position + anchor_b

	if spring_segments <= 0:
		points = PackedVector2Array([p_a, p_b])
		return

	# 绘制锯齿弹簧
	var new_points := PackedVector2Array()
	new_points.push_back(p_a)
	var dir := (p_b - p_a)
	var length := dir.length()
	if length < 0.01:
		points = PackedVector2Array([p_a, p_b])
		return
	var step := dir / float(spring_segments + 1)
	var perp := Vector2(-dir.y, dir.x).normalized() * spring_amplitude
	for i in range(1, spring_segments + 1):
		var base := p_a + step * float(i)
		var sign := 1.0 if (i % 2 == 1) else -1.0
		new_points.push_back(base + perp * sign)
	new_points.push_back(p_b)
	points = new_points
