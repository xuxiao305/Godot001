extends CharacterBody2D

# --------- VARIABLES ---------- #

@export_category("Point-Click Properties")
@export var move_speed : float = 250.0           ## 角色移动速度 (px/s)
@export var stop_threshold : float = 1.0          ## 距离目标点多近时视为到达
@export var boundary_path : NodePath              ## 指向场景中的 CollisionPolygon2D

var target_position : Vector2 = Vector2.ZERO      ## 鼠标点击的目标世界坐标
var is_moving : bool = false                      ## 是否正在移动中
var boundary_polygon : PackedVector2Array          ## 边界多边形（全局坐标）

@onready var player_sprite = $AnimatedSprite2D
@onready var particle_trails = $ParticleTrails

# --------- BUILT-IN FUNCTIONS ---------- #

func _ready():
	target_position = global_position

	# 将边界多边形的顶点转换为全局坐标
	if boundary_path:
		var boundary_node := get_node(boundary_path) as CollisionPolygon2D
		boundary_polygon = boundary_node.polygon
		var offset := boundary_node.global_position
		for i in boundary_polygon.size():
			boundary_polygon[i] += offset

func _input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var click_pos := get_global_mouse_position()
		if not boundary_polygon.is_empty():
			click_pos = clamp_to_boundary(click_pos)
		target_position = click_pos
		is_moving = true

func _physics_process(_delta: float):
	movement()
	player_animations()
	flip_player()

# --------- CUSTOM FUNCTIONS ---------- #

## 驱动角色向 target_position 直线移动
func movement():
	if not is_moving:
		velocity = Vector2.ZERO
		return

	var direction := (target_position - global_position).normalized()
	var distance := global_position.distance_to(target_position)


	if distance < stop_threshold:
		# 到达目标 ── 停止
		velocity = Vector2.ZERO
		global_position = target_position
		is_moving = false
	else:
		velocity = direction * move_speed;
		is_moving = true


	move_and_slide()

	# 防止角色越界
	if not boundary_polygon.is_empty():
		global_position = clamp_to_boundary(global_position)

## 将位置夹逼到边界多边形内
func clamp_to_boundary(pos: Vector2) -> Vector2:
	if Geometry2D.is_point_in_polygon(pos, boundary_polygon):
		return pos
	# 找到多边形边界上最近的点
	var closest := boundary_polygon[0]
	var min_dist := pos.distance_squared_to(closest)
	for i in range(1, boundary_polygon.size()):
		var seg_end := boundary_polygon[i]
		var seg_start := boundary_polygon[i - 1]
		var nearest := Geometry2D.get_closest_point_to_segment(pos, seg_start, seg_end)
		var d := pos.distance_squared_to(nearest)
		if d < min_dist:
			min_dist = d
			closest = nearest
	return closest

## 根据移动状态播放动画和粒子
func player_animations():
	if is_moving:
		player_sprite.play("Walk", 1.5)
	else:
		player_sprite.play("Idle")

## 根据移动方向翻转精灵
func flip_player():
	if velocity.x < -1.0:
		player_sprite.flip_h = true
	elif velocity.x > 1.0:
		player_sprite.flip_h = false
