# Demo 基类 —— 所有物理 Demo 关卡继承此类
class_name DemoLevel
extends Node2D

# --------- EXPORT VARIABLES ---------- #

@export_category("Demo Info")
@export var title: String = "Demo"                 ## Demo 名称
@export var description: String = ""               ## 单行说明
@export var demo_index: int = 0                    ## 在 Demo 序列中的序号
@export_file("*.tscn") var next_scene: String = ""  ## 下一个 Demo 场景路径（用字符串而非 PackedScene，避免循环 ext_resource）
@export_file("*.tscn") var prev_scene: String = ""  ## 上一个 Demo 场景路径

# --------- PRIVATE VARIABLES ---------- #

const DRAG_STIFFNESS: float = 60.0                ## 拖拽刚度（越大越紧跟鼠标）
const DRAG_DAMPING: float = 15.0                  ## 拖拽阻尼（建议约 2*sqrt(stiffness) 临界阻尼）
const DRAG_MAX_FORCE: float = 8000.0              ## 单帧拖拽力上限，防止鼠标跳变时爆冲

var _drag_body: RigidBody2D = null                ## 当前拖拽中的刚体
var _ui_canvas: CanvasLayer = null
var _title_label: Label = null
var _desc_label: Label = null

# --------- BUILT-IN FUNCTIONS ---------- #

func _ready() -> void:
	_setup_ui()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_try_pick_body(event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_release_body()

func _physics_process(_delta: float) -> void:
	if _drag_body != null and is_instance_valid(_drag_body):
		var target := get_global_mouse_position()
		var offset := target - _drag_body.global_position
		# 弹簧拉向鼠标 + 临界阻尼抑制速度；用力而非覆写 velocity，避免和 joint 互相清掉
		var force := offset * DRAG_STIFFNESS - _drag_body.linear_velocity * DRAG_DAMPING
		if force.length() > DRAG_MAX_FORCE:
			force = force.normalized() * DRAG_MAX_FORCE
		_drag_body.apply_central_force(force * _drag_body.mass)

# --------- UI SETUP ---------- #

func _setup_ui() -> void:
	_ui_canvas = CanvasLayer.new()
	_ui_canvas.layer = 100
	add_child(_ui_canvas)

	# 顶部面板
	var panel := Panel.new()
	panel.size = Vector2(400, 80)
	panel.position = Vector2(10, 10)
	_ui_canvas.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(16, 14)
	vbox.size_flags_horizontal = Control.SIZE_FILL
	panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.text = title
	vbox.add_child(_title_label)

	_desc_label = Label.new()
	_desc_label.add_theme_font_size_override("font_size", 13)
	_desc_label.text = description
	vbox.add_child(_desc_label)

	# 返回按钮
	var back_btn := Button.new()
	back_btn.text = "< 返回菜单"
	back_btn.position = Vector2(10, 100)
	back_btn.size = Vector2(120, 32)
	back_btn.pressed.connect(_on_back_pressed)
	_ui_canvas.add_child(back_btn)

	# 上/下翻页按钮
	var prev_btn := Button.new()
	prev_btn.text = "<< 上一项"
	prev_btn.position = Vector2(140, 100)
	prev_btn.size = Vector2(100, 32)
	prev_btn.pressed.connect(_on_prev_pressed)
	prev_btn.disabled = (prev_scene == "")
	_ui_canvas.add_child(prev_btn)

	var next_btn := Button.new()
	next_btn.text = "下一项 >>"
	next_btn.position = Vector2(250, 100)
	next_btn.size = Vector2(100, 32)
	next_btn.pressed.connect(_on_next_pressed)
	next_btn.disabled = (next_scene == "")
	_ui_canvas.add_child(next_btn)

# --------- MOUSE DRAG ---------- #

func _try_pick_body(_screen_pos: Vector2) -> void:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = get_global_mouse_position()
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var results: Array = space_state.intersect_point(query)

	for result in results:
		var body := result.get("collider") as Node
		if body is RigidBody2D and not body.freeze:
			_start_drag(body)
			break

func _start_drag(body: RigidBody2D) -> void:
	_drag_body = body

func _release_body() -> void:
	_drag_body = null

func get_drag_body() -> RigidBody2D:
	return _drag_body

# --------- NAVIGATION ---------- #

func _on_back_pressed() -> void:
	_load_scene("res://Scenes/Demos/demo_menu.tscn")

func _on_prev_pressed() -> void:
	if prev_scene != "":
		get_tree().change_scene_to_file(prev_scene)

func _on_next_pressed() -> void:
	if next_scene != "":
		get_tree().change_scene_to_file(next_scene)

func _load_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)
