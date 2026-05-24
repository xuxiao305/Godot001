# Demo 基类 —— 所有 Box2D Demo 关卡继承此类
extends Node2D

# --------- EXPORT VARIABLES ---------- #

@export_category("Demo Info")
@export var title: String = "Demo"                 ## Demo 名称
@export var description: String = ""               ## 单行说明
@export var demo_index: int = 0                    ## 在 Demo 序列中的序号
@export var next_scene: PackedScene                ## 下一个 Demo 场景
@export var prev_scene: PackedScene                ## 上一个 Demo 场景

# --------- PRIVATE VARIABLES ---------- #

var _mouse_joint: MouseJoint2D = null             ## 当前拖拽中的关节
var _static_anchor: StaticBody2D = null           ## MouseJoint 的静态锚点
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

	elif event is InputEventMouseMotion and _mouse_joint != null:
		_update_drag_target(event.position)

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
	prev_btn.disabled = (prev_scene == null)
	_ui_canvas.add_child(prev_btn)

	var next_btn := Button.new()
	next_btn.text = "下一项 >>"
	next_btn.position = Vector2(250, 100)
	next_btn.size = Vector2(100, 32)
	next_btn.pressed.connect(_on_next_pressed)
	next_btn.disabled = (next_scene == null)
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
		if body is RigidBody2D and body.freeze_mode != RigidBody2D.FREEZE_MODE_STATIC:
			_start_drag(body)
			break

func _start_drag(body: RigidBody2D) -> void:
	# 创建静态锚点（放在鼠标位置）
	_static_anchor = StaticBody2D.new()
	_static_anchor.global_position = get_global_mouse_position()
	add_child(_static_anchor)

	# 创建 MouseJoint2D
	_mouse_joint = MouseJoint2D.new()
	_mouse_joint.node_a = _static_anchor.get_path()
	_mouse_joint.node_b = body.get_path()
	_mouse_joint.target = body.global_position
	_mouse_joint.stiffness = 100.0
	_mouse_joint.damping = 0.7
	_mouse_joint.max_force = 5000.0
	add_child(_mouse_joint)

func _update_drag_target(_screen_pos: Vector2) -> void:
	if _mouse_joint != null:
		_mouse_joint.target = get_global_mouse_position()

func _release_body() -> void:
	if _mouse_joint != null:
		_mouse_joint.queue_free()
		_mouse_joint = null
	if _static_anchor != null:
		_static_anchor.queue_free()
		_static_anchor = null

# --------- NAVIGATION ---------- #

func _on_back_pressed() -> void:
	_load_scene("res://Scenes/Demos/demo_menu.tscn")

func _on_prev_pressed() -> void:
	if prev_scene != null:
		SceneTransition.load_scene(prev_scene)

func _on_next_pressed() -> void:
	if next_scene != null:
		SceneTransition.load_scene(next_scene)

func _load_scene(path: String) -> void:
	var packed := load(path) as PackedScene
	if packed != null:
		SceneTransition.load_scene(packed)
