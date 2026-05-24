# Box2D Demo 主菜单 —— 列出所有可用的 Demo 关卡
extends Node2D

const DEMOS: Dictionary = {
	2: {
		"name": "RigidBody 物理属性",
		"path": "res://Scenes/Demos/demo_rigid_body.tscn",
		"description": "拖拽物体 — 体验不同质量、弹性和摩擦力的表现"
	},
	3: {
		"name": "WeldJoint 焊接关节",
		"path": "",
		"description": "多个物体焊接成一体"
	},
	4: {
		"name": "DampedSpring 弹簧关节",
		"path": "",
		"description": "弹簧悬挂与振荡"
	},
	5: {
		"name": "RopeJoint 绳索关节",
		"path": "",
		"description": "绳索摆锤与长度约束"
	},
	6: {
		"name": "PulleyJoint 滑轮关节",
		"path": "",
		"description": "滑轮对重系统"
	},
	7: {
		"name": "MotorJoint 马达关节",
		"path": "",
		"description": "线性马达驱动"
	},
	8: {
		"name": "WheelJoint 轮子关节",
		"path": "",
		"description": "轮子滚动与悬挂"
	},
	9: {
		"name": "GearJoint 齿轮关节",
		"path": "",
		"description": "旋转联动传递"
	},
	10: {
		"name": "MouseJoint 鼠标关节",
		"path": "",
		"description": "拖拽弹性与拖尾效果"
	},
}


func _ready() -> void:
	print("[demo_menu] ready, setting up UI")
	_setup_menu_ui()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		print("[demo_menu] _input mouse btn=%d at %s" % [event.button_index, event.position])
	elif event is InputEventKey and event.pressed:
		print("[demo_menu] _input key=%d" % event.keycode)


func _setup_menu_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)

	# 居中面板
	var panel := Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -200.0
	panel.offset_top = -300.0
	panel.offset_right = 200.0
	panel.offset_bottom = 300.0
	canvas.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.anchor_left = 0.0
	vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 16.0
	vbox.offset_top = 16.0
	vbox.offset_right = -16.0
	vbox.offset_bottom = -16.0
	panel.add_child(vbox)

	# 标题
	var title_label := Label.new()
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.text = "Box2D 物理 Demo 合集"
	vbox.add_child(title_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	# Demo 按钮
	var sorted_keys := DEMOS.keys()
	sorted_keys.sort()

	for index in sorted_keys:
		var demo := DEMOS[index] as Dictionary
		var btn := Button.new()
		btn.text = "%d - %s" % [index, demo["name"]]
		btn.custom_minimum_size = Vector2(340, 40)

		if demo["path"] != "":
			var path: String = demo["path"]
			btn.pressed.connect(_on_demo_selected.bind(path))
		else:
			btn.disabled = true
			btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

		vbox.add_child(btn)

	# 返回游戏的按钮
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer2)

	var game_btn := Button.new()
	game_btn.text = "回到平台游戏"
	game_btn.custom_minimum_size = Vector2(200, 36)
	game_btn.pressed.connect(_on_game_pressed)
	vbox.add_child(game_btn)


func _on_demo_selected(scene_path: String) -> void:
	print("[demo_menu] button clicked, loading: ", scene_path)
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("[demo_menu] failed to load: %s" % scene_path)
		return
	print("[demo_menu] loaded OK, requesting transition")
	SceneTransition.load_scene(packed)


func _on_game_pressed() -> void:
	print("[demo_menu] back-to-game pressed")
	var scene := load("res://Scenes/Levels/Level_01.tscn") as PackedScene
	if scene == null:
		push_error("[demo_menu] failed to load Level_01.tscn")
		return
	SceneTransition.load_scene(scene)
