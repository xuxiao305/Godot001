extends CharacterBody2D

# --------- VARIABLES ---------- #

@export_category("Point-Click Properties")
@export var move_speed : float = 250.0           ## 角色移动速度 (px/s)
@export var stop_threshold : float = 1.0          ## 距离目标点多近时视为到达

var target_position : Vector2 = Vector2.ZERO      ## 鼠标点击的目标世界坐标
var is_moving : bool = false                      ## 是否正在移动中

@onready var player_sprite = $AnimatedSprite2D
@onready var particle_trails = $ParticleTrails

# --------- BUILT-IN FUNCTIONS ---------- #

func _ready():
	# 初始化目标点为出生位置，防止未点击就移动
	target_position = global_position

func _input(event: InputEvent):
	# 检测鼠标左键点击
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		target_position = get_global_mouse_position()
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
