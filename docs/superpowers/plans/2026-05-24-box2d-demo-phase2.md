# Box2D Demo 合集 Phase 2 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Phase 1 基础上新增 3 个"双体约束"类关节 Demo：WeldJoint（焊接）、DampedSpring（弹簧）、RopeJoint（绳索）

**Architecture:** 复用 Phase 1 已建立的 `DemoLevel` 基类（鼠标拖拽 + UI + 导航）。每个 Phase 2 Demo 都是一个 `.tscn` 场景，根节点继承 `demo_level.gd`，子节点放刚体 + 关节 + 可视化辅助节点。新增一个共享工具脚本 `joint_line_visualizer.gd`，用 `Line2D` 实时绘制两个节点之间的连线（适用于绳索和弹簧；焊接不需要）。菜单脚本 `demo_menu.gd` 把 Phase 2 的 path 字段填上，并在每个 Demo 场景中通过 `next_scene`/`prev_scene` 导出变量串联导航链。

**Tech Stack:** Godot 4.6 + GDScript + godot-box2d (v0.9.11) — 关节类型：内置 `DampedSpringJoint2D` + Box2D 扩展提供的 `WeldJoint2D` / `RopeJoint2D`

---

### Task 1: 创建关节连线可视化工具脚本

**Files:**
- Create: `Scripts/Demos/joint_line_visualizer.gd`

关节节点本身不会被渲染。对于绳索和弹簧这类"看得见才好玩"的关节，需要一个独立的 `Line2D` 节点每帧把两个端点位置画出来。这个脚本可以挂在场景里的任意 `Line2D` 节点上，导出两个 `NodePath` 指向需要连接的端点。

- [ ] **Step 1: 编写 `joint_line_visualizer.gd`**

```gdscript
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
```

- [ ] **Step 2: 在 Godot 编辑器中打开项目，让其自动生成 `.uid` 文件**

打开 Godot 编辑器，让它扫描新文件并生成 `Scripts/Demos/joint_line_visualizer.gd.uid`。无需在编辑器中做任何修改，只要打开一次让索引刷新。

- [ ] **Step 3: 验证工具脚本能被编辑器识别**

在 Godot 编辑器的 FileSystem 面板里，确认 `joint_line_visualizer.gd` 旁边出现了 `class_name` 图标，说明 `class_name JointLineVisualizer` 已注册。

- [ ] **Step 4: Commit**

```bash
git add Scripts/Demos/joint_line_visualizer.gd Scripts/Demos/joint_line_visualizer.gd.uid
git commit -m "feat(demos): add JointLineVisualizer Line2D helper"
```

---

### Task 2: 更新主菜单注册 Phase 2 路径

**Files:**
- Modify: `Scripts/Demos/demo_menu.gd:10-24` （把 3、4、5 三个 entry 的 `path` 字段填上）

目前 demo 字典里 WeldJoint / DampedSpring / RopeJoint 三项的 `path` 都是空字符串，按钮被禁用。Phase 2 完成后这些场景就存在了，把路径填上即可激活按钮。

- [ ] **Step 1: 修改 entry 3 (WeldJoint)**

把现有内容：

```gdscript
	3: {
		"name": "WeldJoint 焊接关节",
		"path": "",
		"description": "多个物体焊接成一体"
	},
```

替换为：

```gdscript
	3: {
		"name": "WeldJoint 焊接关节",
		"path": "res://Scenes/Demos/demo_weld_joint.tscn",
		"description": "多个物体焊接成一体"
	},
```

- [ ] **Step 2: 修改 entry 4 (DampedSpring)**

```gdscript
	4: {
		"name": "DampedSpring 弹簧关节",
		"path": "res://Scenes/Demos/demo_damped_spring.tscn",
		"description": "弹簧悬挂与振荡"
	},
```

- [ ] **Step 3: 修改 entry 5 (RopeJoint)**

```gdscript
	5: {
		"name": "RopeJoint 绳索关节",
		"path": "res://Scenes/Demos/demo_rope_joint.tscn",
		"description": "绳索摆锤与长度约束"
	},
```

- [ ] **Step 4: 在 Godot 编辑器里运行 `demo_menu.tscn`（F6）**

预期：菜单里 RigidBody / WeldJoint / DampedSpring / RopeJoint 四个按钮可点击（不再灰色）；点击 WeldJoint/DampedSpring/RopeJoint 会因场景文件还不存在而报错。这是预期 —— 后续任务会创建这些场景。

- [ ] **Step 5: Commit**

```bash
git add Scripts/Demos/demo_menu.gd
git commit -m "feat(demos): enable Phase 2 menu entries (weld/spring/rope)"
```

---

### Task 3: 创建 WeldJoint Demo 脚本

**Files:**
- Create: `Scripts/Demos/demo_weld_joint.gd`

和 `demo_rigid_body.gd` 一样，这是一个空壳脚本，所有交互由 `DemoLevel` 基类处理。专门拆成一个脚本是为了：（a）保持每个 demo 场景有独立挂载点，未来加 demo 专属逻辑（如复位按钮）时不影响其他 demo；（b）保持基类（`demo_level.gd`）的"基类"语义。

- [ ] **Step 1: 编写 `demo_weld_joint.gd`**

```gdscript
# WeldJoint Demo —— 展示多个刚体被焊接成一个整体
extends DemoLevel


func _ready() -> void:
	super._ready()
```

- [ ] **Step 2: 在 Godot 编辑器中打开项目，让其生成 `.uid` 文件**

- [ ] **Step 3: Commit**

```bash
git add Scripts/Demos/demo_weld_joint.gd Scripts/Demos/demo_weld_joint.gd.uid
git commit -m "feat(demos): add demo_weld_joint.gd extending DemoLevel"
```

---

### Task 4: 创建 WeldJoint Demo 场景

**Files:**
- Create: `Scenes/Demos/demo_weld_joint.tscn`

场景结构：
- 摄像机 + 背景 + 地面 + 左右墙（同 `demo_rigid_body.tscn`）
- **塔（Tower）**：4 个 RigidBody2D 方块上下叠放，相邻两个之间用 `WeldJoint2D` 焊接 —— 拖动任意一块都会带动整座塔
- **雪人（Snowman）**：3 个 RigidBody2D 圆球纵向叠加，相邻两个用 `WeldJoint2D` 焊接 —— 拖动任意球都会带动整个雪人

WeldJoint2D 的 `node_a` 和 `node_b` 必须指向 RigidBody2D 节点；位置无需对齐，焊接会按当前位置硬性固定。

> **关于场景文件手工编写：** Godot 的 `.tscn` 用文本格式描述场景，原则上可以手写。`uid` 字段如果省略，Godot 在编辑器中首次打开时会自动生成。`unique_id` 同理。脚本/资源 ext_resource 的 `uid` 可以照搬现有项目里相应文件的 `.uid` 文件内容（如 `Scripts/Demos/demo_weld_joint.gd.uid` 里的字符串）。**实操建议**：先写一份"骨架"`.tscn`，在编辑器里打开，编辑器会补全 uid 并提示任何错误。

- [ ] **Step 1: 创建 `demo_weld_joint.tscn` 文件**

写入以下内容（注意：`ext_resource` 的 `uid="..."` 必须替换为当前项目里 `Scripts/Demos/demo_weld_joint.gd.uid` 文件中的实际字符串；如果你不确定就先省略 `uid` 属性，Godot 会在打开时补全）：

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://Scripts/Demos/demo_weld_joint.gd" id="1"]

[sub_resource type="RectangleShape2D" id="GroundShape"]
size = Vector2(1152, 40)

[sub_resource type="RectangleShape2D" id="WallShape"]
size = Vector2(20, 648)

[sub_resource type="RectangleShape2D" id="BrickShape"]
size = Vector2(56, 40)

[sub_resource type="CircleShape2D" id="BallShape"]
radius = 28.0

[node name="WeldJointDemo" type="Node2D"]
script = ExtResource("1")
title = "WeldJoint 焊接关节"
description = "拖动任意一块 — 整座塔/雪人作为一个整体响应"
demo_index = 3

[node name="Camera2D" type="Camera2D" parent="."]
position = Vector2(576, 324)
zoom = Vector2(0.8, 0.8)

[node name="Background" type="ColorRect" parent="."]
offset_right = 1152.0
offset_bottom = 648.0
color = Color(0.15, 0.18, 0.2, 1)

[node name="Ground" type="StaticBody2D" parent="."]
[node name="CollisionShape2D" type="CollisionShape2D" parent="Ground"]
position = Vector2(576, 620)
shape = SubResource("GroundShape")
[node name="ColorRect" type="ColorRect" parent="Ground"]
offset_top = 600.0
offset_right = 1152.0
offset_bottom = 640.0
color = Color(0.3, 0.25, 0.2, 1)

[node name="LeftWall" type="StaticBody2D" parent="."]
[node name="CollisionShape2D" type="CollisionShape2D" parent="LeftWall"]
position = Vector2(10, 324)
shape = SubResource("WallShape")

[node name="RightWall" type="StaticBody2D" parent="."]
[node name="CollisionShape2D" type="CollisionShape2D" parent="RightWall"]
position = Vector2(1142, 324)
shape = SubResource("WallShape")

; ===== Tower: 4 bricks stacked =====
[node name="Brick1" type="RigidBody2D" parent="."]
position = Vector2(350, 560)
[node name="CollisionShape2D" type="CollisionShape2D" parent="Brick1"]
shape = SubResource("BrickShape")
[node name="ColorRect" type="ColorRect" parent="Brick1"]
offset_left = -28.0
offset_top = -20.0
offset_right = 28.0
offset_bottom = 20.0
color = Color(0.85, 0.55, 0.25, 1)

[node name="Brick2" type="RigidBody2D" parent="."]
position = Vector2(350, 520)
[node name="CollisionShape2D" type="CollisionShape2D" parent="Brick2"]
shape = SubResource("BrickShape")
[node name="ColorRect" type="ColorRect" parent="Brick2"]
offset_left = -28.0
offset_top = -20.0
offset_right = 28.0
offset_bottom = 20.0
color = Color(0.85, 0.55, 0.25, 1)

[node name="Brick3" type="RigidBody2D" parent="."]
position = Vector2(350, 480)
[node name="CollisionShape2D" type="CollisionShape2D" parent="Brick3"]
shape = SubResource("BrickShape")
[node name="ColorRect" type="ColorRect" parent="Brick3"]
offset_left = -28.0
offset_top = -20.0
offset_right = 28.0
offset_bottom = 20.0
color = Color(0.85, 0.55, 0.25, 1)

[node name="Brick4" type="RigidBody2D" parent="."]
position = Vector2(350, 440)
[node name="CollisionShape2D" type="CollisionShape2D" parent="Brick4"]
shape = SubResource("BrickShape")
[node name="ColorRect" type="ColorRect" parent="Brick4"]
offset_left = -28.0
offset_top = -20.0
offset_right = 28.0
offset_bottom = 20.0
color = Color(0.85, 0.55, 0.25, 1)

[node name="Weld1_2" type="WeldJoint2D" parent="."]
position = Vector2(350, 540)
node_a = NodePath("../Brick1")
node_b = NodePath("../Brick2")

[node name="Weld2_3" type="WeldJoint2D" parent="."]
position = Vector2(350, 500)
node_a = NodePath("../Brick2")
node_b = NodePath("../Brick3")

[node name="Weld3_4" type="WeldJoint2D" parent="."]
position = Vector2(350, 460)
node_a = NodePath("../Brick3")
node_b = NodePath("../Brick4")

; ===== Snowman: 3 balls stacked =====
[node name="Snow1" type="RigidBody2D" parent="."]
position = Vector2(800, 560)
[node name="CollisionShape2D" type="CollisionShape2D" parent="Snow1"]
shape = SubResource("BallShape")
[node name="ColorRect" type="ColorRect" parent="Snow1"]
offset_left = -28.0
offset_top = -28.0
offset_right = 28.0
offset_bottom = 28.0
color = Color(0.95, 0.95, 1.0, 1)

[node name="Snow2" type="RigidBody2D" parent="."]
position = Vector2(800, 504)
[node name="CollisionShape2D" type="CollisionShape2D" parent="Snow2"]
shape = SubResource("BallShape")
[node name="ColorRect" type="ColorRect" parent="Snow2"]
offset_left = -28.0
offset_top = -28.0
offset_right = 28.0
offset_bottom = 28.0
color = Color(0.95, 0.95, 1.0, 1)

[node name="Snow3" type="RigidBody2D" parent="."]
position = Vector2(800, 448)
[node name="CollisionShape2D" type="CollisionShape2D" parent="Snow3"]
shape = SubResource("BallShape")
[node name="ColorRect" type="ColorRect" parent="Snow3"]
offset_left = -28.0
offset_top = -28.0
offset_right = 28.0
offset_bottom = 28.0
color = Color(0.95, 0.95, 1.0, 1)

[node name="WeldS1_2" type="WeldJoint2D" parent="."]
position = Vector2(800, 532)
node_a = NodePath("../Snow1")
node_b = NodePath("../Snow2")

[node name="WeldS2_3" type="WeldJoint2D" parent="."]
position = Vector2(800, 476)
node_a = NodePath("../Snow2")
node_b = NodePath("../Snow3")
```

- [ ] **Step 2: 在 Godot 编辑器中打开 `Scenes/Demos/demo_weld_joint.tscn`**

编辑器应能加载场景。若有 ext_resource uid 警告，编辑器会自动修复并写回文件 —— 在场景标签栏点保存（Ctrl+S）即可。

- [ ] **Step 3: 在编辑器里运行（F6）当前场景**

预期：
- 4 块方块叠成一座小塔
- 3 个球叠成一个雪人
- 鼠标左键按住任意一块，可以把整组结构拖来拖去（不会散架）
- 顶部 UI 显示标题 "WeldJoint 焊接关节" 和说明
- "返回菜单" 按钮可用

- [ ] **Step 4: Commit**

```bash
git add Scenes/Demos/demo_weld_joint.tscn
git commit -m "feat(demos): add WeldJoint scene with tower + snowman"
```

---

### Task 5: 创建 DampedSpring Demo 脚本

**Files:**
- Create: `Scripts/Demos/demo_damped_spring.gd`

- [ ] **Step 1: 编写 `demo_damped_spring.gd`**

```gdscript
# DampedSpring Demo —— 展示弹簧悬挂、刚度与阻尼差异
extends DemoLevel


func _ready() -> void:
	super._ready()
```

- [ ] **Step 2: 在 Godot 编辑器里让其生成 `.uid` 文件**

- [ ] **Step 3: Commit**

```bash
git add Scripts/Demos/demo_damped_spring.gd Scripts/Demos/demo_damped_spring.gd.uid
git commit -m "feat(demos): add demo_damped_spring.gd extending DemoLevel"
```

---

### Task 6: 创建 DampedSpring Demo 场景

**Files:**
- Create: `Scenes/Demos/demo_damped_spring.tscn`

场景结构：
- 摄像机 + 背景 + 地面 + 左右墙
- **两个并列的弹簧系统**：
  - 左边："硬而紧"弹簧（高 stiffness、高 damping）—— 拖下去后快速回弹、很少振荡
  - 右边："软而松"弹簧（低 stiffness、低 damping）—— 拖下去后长时间上下摆动
- 每个弹簧由：上方一个 StaticBody2D 锚点 + 下方一个 RigidBody2D 重物 + 一个 `DampedSpringJoint2D` 连接两者 + 一个 `Line2D`（挂 `JointLineVisualizer` 脚本，`spring_segments=10`）可视化构成

**DampedSpringJoint2D 关键属性（Godot 内置节点）：**
- `node_a` / `node_b`：两端的 NodePath
- `length`：关节自然长度（rest length）
- `rest_length`：留 0 即用 length
- `stiffness`：弹簧刚度
- `damping`：阻尼

- [ ] **Step 1: 创建 `demo_damped_spring.tscn`**

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://Scripts/Demos/demo_damped_spring.gd" id="1"]
[ext_resource type="Script" path="res://Scripts/Demos/joint_line_visualizer.gd" id="2"]

[sub_resource type="RectangleShape2D" id="GroundShape"]
size = Vector2(1152, 40)

[sub_resource type="RectangleShape2D" id="WallShape"]
size = Vector2(20, 648)

[sub_resource type="RectangleShape2D" id="AnchorShape"]
size = Vector2(80, 16)

[sub_resource type="RectangleShape2D" id="WeightShape"]
size = Vector2(60, 60)

[node name="DampedSpringDemo" type="Node2D"]
script = ExtResource("1")
title = "DampedSpring 弹簧关节"
description = "拖下重物 — 左侧硬高阻尼，右侧软低阻尼"
demo_index = 4

[node name="Camera2D" type="Camera2D" parent="."]
position = Vector2(576, 324)
zoom = Vector2(0.8, 0.8)

[node name="Background" type="ColorRect" parent="."]
offset_right = 1152.0
offset_bottom = 648.0
color = Color(0.12, 0.14, 0.2, 1)

[node name="Ground" type="StaticBody2D" parent="."]
[node name="CollisionShape2D" type="CollisionShape2D" parent="Ground"]
position = Vector2(576, 620)
shape = SubResource("GroundShape")
[node name="ColorRect" type="ColorRect" parent="Ground"]
offset_top = 600.0
offset_right = 1152.0
offset_bottom = 640.0
color = Color(0.3, 0.25, 0.2, 1)

[node name="LeftWall" type="StaticBody2D" parent="."]
[node name="CollisionShape2D" type="CollisionShape2D" parent="LeftWall"]
position = Vector2(10, 324)
shape = SubResource("WallShape")

[node name="RightWall" type="StaticBody2D" parent="."]
[node name="CollisionShape2D" type="CollisionShape2D" parent="RightWall"]
position = Vector2(1142, 324)
shape = SubResource("WallShape")

; ===== Spring 1: stiff + damped =====
[node name="AnchorStiff" type="StaticBody2D" parent="."]
position = Vector2(380, 120)
[node name="CollisionShape2D" type="CollisionShape2D" parent="AnchorStiff"]
shape = SubResource("AnchorShape")
[node name="ColorRect" type="ColorRect" parent="AnchorStiff"]
offset_left = -40.0
offset_top = -8.0
offset_right = 40.0
offset_bottom = 8.0
color = Color(0.5, 0.5, 0.55, 1)

[node name="WeightStiff" type="RigidBody2D" parent="."]
position = Vector2(380, 350)
mass = 2.0
[node name="CollisionShape2D" type="CollisionShape2D" parent="WeightStiff"]
shape = SubResource("WeightShape")
[node name="ColorRect" type="ColorRect" parent="WeightStiff"]
offset_left = -30.0
offset_top = -30.0
offset_right = 30.0
offset_bottom = 30.0
color = Color(0.85, 0.35, 0.35, 1)
[node name="Label" type="Label" parent="WeightStiff"]
offset_left = -40.0
offset_top = -10.0
offset_right = 40.0
offset_bottom = 10.0
text = "硬 + 高阻尼"
horizontal_alignment = 1

[node name="SpringStiff" type="DampedSpringJoint2D" parent="."]
position = Vector2(380, 235)
length = 230.0
rest_length = 230.0
stiffness = 80.0
damping = 5.0
node_a = NodePath("../AnchorStiff")
node_b = NodePath("../WeightStiff")

[node name="SpringStiffLine" type="Line2D" parent="."]
script = ExtResource("2")
width = 4.0
default_color = Color(0.8, 0.8, 0.4, 1.0)
point_a = NodePath("../AnchorStiff")
point_b = NodePath("../WeightStiff")
spring_segments = 12
spring_amplitude = 10.0

; ===== Spring 2: soft + lightly damped =====
[node name="AnchorSoft" type="StaticBody2D" parent="."]
position = Vector2(780, 120)
[node name="CollisionShape2D" type="CollisionShape2D" parent="AnchorSoft"]
shape = SubResource("AnchorShape")
[node name="ColorRect" type="ColorRect" parent="AnchorSoft"]
offset_left = -40.0
offset_top = -8.0
offset_right = 40.0
offset_bottom = 8.0
color = Color(0.5, 0.5, 0.55, 1)

[node name="WeightSoft" type="RigidBody2D" parent="."]
position = Vector2(780, 350)
mass = 2.0
[node name="CollisionShape2D" type="CollisionShape2D" parent="WeightSoft"]
shape = SubResource("WeightShape")
[node name="ColorRect" type="ColorRect" parent="WeightSoft"]
offset_left = -30.0
offset_top = -30.0
offset_right = 30.0
offset_bottom = 30.0
color = Color(0.3, 0.6, 0.9, 1)
[node name="Label" type="Label" parent="WeightSoft"]
offset_left = -40.0
offset_top = -10.0
offset_right = 40.0
offset_bottom = 10.0
text = "软 + 低阻尼"
horizontal_alignment = 1

[node name="SpringSoft" type="DampedSpringJoint2D" parent="."]
position = Vector2(780, 235)
length = 230.0
rest_length = 230.0
stiffness = 15.0
damping = 0.5
node_a = NodePath("../AnchorSoft")
node_b = NodePath("../WeightSoft")

[node name="SpringSoftLine" type="Line2D" parent="."]
script = ExtResource("2")
width = 4.0
default_color = Color(0.5, 0.85, 1.0, 1.0)
point_a = NodePath("../AnchorSoft")
point_b = NodePath("../WeightSoft")
spring_segments = 12
spring_amplitude = 10.0
```

- [ ] **Step 2: 在 Godot 编辑器中打开 `Scenes/Demos/demo_damped_spring.tscn` 并保存（Ctrl+S）**

让编辑器补全 uid 并写回。

- [ ] **Step 3: 在编辑器里运行（F6）当前场景**

预期：
- 两个红/蓝重物挂在天花板锚点下，由黄/青色锯齿弹簧连接
- 左侧（红/黄）：拖下去松开后短促回弹，几下就静止
- 右侧（蓝/青）：拖下去松开后大幅上下振荡，缓慢衰减
- 锯齿弹簧线条随物体上下伸缩

- [ ] **Step 4: Commit**

```bash
git add Scenes/Demos/demo_damped_spring.tscn
git commit -m "feat(demos): add DampedSpring scene with stiff vs. soft pair"
```

---

### Task 7: 创建 RopeJoint Demo 脚本

**Files:**
- Create: `Scripts/Demos/demo_rope_joint.gd`

- [ ] **Step 1: 编写 `demo_rope_joint.gd`**

```gdscript
# RopeJoint Demo —— 展示绳索的长度约束（拉到极限才生效）
extends DemoLevel


func _ready() -> void:
	super._ready()
```

- [ ] **Step 2: 在 Godot 编辑器里让其生成 `.uid` 文件**

- [ ] **Step 3: Commit**

```bash
git add Scripts/Demos/demo_rope_joint.gd Scripts/Demos/demo_rope_joint.gd.uid
git commit -m "feat(demos): add demo_rope_joint.gd extending DemoLevel"
```

---

### Task 8: 创建 RopeJoint Demo 场景

**Files:**
- Create: `Scenes/Demos/demo_rope_joint.tscn`

场景结构：
- 摄像机 + 背景 + 地面 + 左右墙
- **摆锤（Pendulum）**：天花板上一个静态锚点，下方挂一个重球，用 `RopeJoint2D` 限制最大距离 = 280。拖动球可在最大长度范围内自由移动；超出后会被拉住。
- **链条（Chain）**：5 个 `RigidBody2D` 小球依次用 `RopeJoint2D` 串接（每段 max_length = 36）。第一个球用 `RopeJoint2D` 连接到天花板另一个静态锚点。形成可拖动的"项链"。

每个 `RopeJoint2D` 都用一个 `Line2D` + `JointLineVisualizer`（spring_segments = 0）画直线表示绳子。

**RopeJoint2D 关键属性（godot-box2d 扩展）：**
- `node_a` / `node_b`：两端 NodePath
- `max_length`：绳子最大长度（超出会被拉住）

- [ ] **Step 1: 创建 `demo_rope_joint.tscn`**

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://Scripts/Demos/demo_rope_joint.gd" id="1"]
[ext_resource type="Script" path="res://Scripts/Demos/joint_line_visualizer.gd" id="2"]

[sub_resource type="RectangleShape2D" id="GroundShape"]
size = Vector2(1152, 40)

[sub_resource type="RectangleShape2D" id="WallShape"]
size = Vector2(20, 648)

[sub_resource type="RectangleShape2D" id="AnchorShape"]
size = Vector2(60, 16)

[sub_resource type="CircleShape2D" id="WeightShape"]
radius = 28.0

[sub_resource type="CircleShape2D" id="LinkShape"]
radius = 10.0

[node name="RopeJointDemo" type="Node2D"]
script = ExtResource("1")
title = "RopeJoint 绳索关节"
description = "左:摆锤(max=280); 右:链条(每节 36)"
demo_index = 5

[node name="Camera2D" type="Camera2D" parent="."]
position = Vector2(576, 324)
zoom = Vector2(0.8, 0.8)

[node name="Background" type="ColorRect" parent="."]
offset_right = 1152.0
offset_bottom = 648.0
color = Color(0.12, 0.18, 0.18, 1)

[node name="Ground" type="StaticBody2D" parent="."]
[node name="CollisionShape2D" type="CollisionShape2D" parent="Ground"]
position = Vector2(576, 620)
shape = SubResource("GroundShape")
[node name="ColorRect" type="ColorRect" parent="Ground"]
offset_top = 600.0
offset_right = 1152.0
offset_bottom = 640.0
color = Color(0.3, 0.25, 0.2, 1)

[node name="LeftWall" type="StaticBody2D" parent="."]
[node name="CollisionShape2D" type="CollisionShape2D" parent="LeftWall"]
position = Vector2(10, 324)
shape = SubResource("WallShape")

[node name="RightWall" type="StaticBody2D" parent="."]
[node name="CollisionShape2D" type="CollisionShape2D" parent="RightWall"]
position = Vector2(1142, 324)
shape = SubResource("WallShape")

; ===== Pendulum =====
[node name="PendAnchor" type="StaticBody2D" parent="."]
position = Vector2(360, 100)
[node name="CollisionShape2D" type="CollisionShape2D" parent="PendAnchor"]
shape = SubResource("AnchorShape")
[node name="ColorRect" type="ColorRect" parent="PendAnchor"]
offset_left = -30.0
offset_top = -8.0
offset_right = 30.0
offset_bottom = 8.0
color = Color(0.5, 0.5, 0.55, 1)

[node name="PendBob" type="RigidBody2D" parent="."]
position = Vector2(360, 360)
mass = 3.0
[node name="CollisionShape2D" type="CollisionShape2D" parent="PendBob"]
shape = SubResource("WeightShape")
[node name="ColorRect" type="ColorRect" parent="PendBob"]
offset_left = -28.0
offset_top = -28.0
offset_right = 28.0
offset_bottom = 28.0
color = Color(0.85, 0.45, 0.2, 1)

[node name="PendRope" type="RopeJoint2D" parent="."]
position = Vector2(360, 230)
max_length = 280.0
node_a = NodePath("../PendAnchor")
node_b = NodePath("../PendBob")

[node name="PendLine" type="Line2D" parent="."]
script = ExtResource("2")
width = 2.5
default_color = Color(0.9, 0.85, 0.6, 1)
point_a = NodePath("../PendAnchor")
point_b = NodePath("../PendBob")
spring_segments = 0

; ===== Chain (5 links) =====
[node name="ChainAnchor" type="StaticBody2D" parent="."]
position = Vector2(820, 100)
[node name="CollisionShape2D" type="CollisionShape2D" parent="ChainAnchor"]
shape = SubResource("AnchorShape")
[node name="ColorRect" type="ColorRect" parent="ChainAnchor"]
offset_left = -30.0
offset_top = -8.0
offset_right = 30.0
offset_bottom = 8.0
color = Color(0.5, 0.5, 0.55, 1)

[node name="Link1" type="RigidBody2D" parent="."]
position = Vector2(820, 140)
mass = 0.5
[node name="CollisionShape2D" type="CollisionShape2D" parent="Link1"]
shape = SubResource("LinkShape")
[node name="ColorRect" type="ColorRect" parent="Link1"]
offset_left = -10.0
offset_top = -10.0
offset_right = 10.0
offset_bottom = 10.0
color = Color(0.7, 0.7, 0.8, 1)

[node name="Link2" type="RigidBody2D" parent="."]
position = Vector2(820, 176)
mass = 0.5
[node name="CollisionShape2D" type="CollisionShape2D" parent="Link2"]
shape = SubResource("LinkShape")
[node name="ColorRect" type="ColorRect" parent="Link2"]
offset_left = -10.0
offset_top = -10.0
offset_right = 10.0
offset_bottom = 10.0
color = Color(0.7, 0.7, 0.8, 1)

[node name="Link3" type="RigidBody2D" parent="."]
position = Vector2(820, 212)
mass = 0.5
[node name="CollisionShape2D" type="CollisionShape2D" parent="Link3"]
shape = SubResource("LinkShape")
[node name="ColorRect" type="ColorRect" parent="Link3"]
offset_left = -10.0
offset_top = -10.0
offset_right = 10.0
offset_bottom = 10.0
color = Color(0.7, 0.7, 0.8, 1)

[node name="Link4" type="RigidBody2D" parent="."]
position = Vector2(820, 248)
mass = 0.5
[node name="CollisionShape2D" type="CollisionShape2D" parent="Link4"]
shape = SubResource("LinkShape")
[node name="ColorRect" type="ColorRect" parent="Link4"]
offset_left = -10.0
offset_top = -10.0
offset_right = 10.0
offset_bottom = 10.0
color = Color(0.7, 0.7, 0.8, 1)

[node name="Link5" type="RigidBody2D" parent="."]
position = Vector2(820, 290)
mass = 1.5
[node name="CollisionShape2D" type="CollisionShape2D" parent="Link5"]
shape = SubResource("WeightShape")
[node name="ColorRect" type="ColorRect" parent="Link5"]
offset_left = -28.0
offset_top = -28.0
offset_right = 28.0
offset_bottom = 28.0
color = Color(0.3, 0.6, 0.9, 1)

[node name="ChainRope0" type="RopeJoint2D" parent="."]
position = Vector2(820, 120)
max_length = 40.0
node_a = NodePath("../ChainAnchor")
node_b = NodePath("../Link1")

[node name="ChainRope1" type="RopeJoint2D" parent="."]
position = Vector2(820, 158)
max_length = 36.0
node_a = NodePath("../Link1")
node_b = NodePath("../Link2")

[node name="ChainRope2" type="RopeJoint2D" parent="."]
position = Vector2(820, 194)
max_length = 36.0
node_a = NodePath("../Link2")
node_b = NodePath("../Link3")

[node name="ChainRope3" type="RopeJoint2D" parent="."]
position = Vector2(820, 230)
max_length = 36.0
node_a = NodePath("../Link3")
node_b = NodePath("../Link4")

[node name="ChainRope4" type="RopeJoint2D" parent="."]
position = Vector2(820, 270)
max_length = 42.0
node_a = NodePath("../Link4")
node_b = NodePath("../Link5")

[node name="ChainLine0" type="Line2D" parent="."]
script = ExtResource("2")
width = 2.0
default_color = Color(0.9, 0.85, 0.6, 1)
point_a = NodePath("../ChainAnchor")
point_b = NodePath("../Link1")
spring_segments = 0

[node name="ChainLine1" type="Line2D" parent="."]
script = ExtResource("2")
width = 2.0
default_color = Color(0.9, 0.85, 0.6, 1)
point_a = NodePath("../Link1")
point_b = NodePath("../Link2")
spring_segments = 0

[node name="ChainLine2" type="Line2D" parent="."]
script = ExtResource("2")
width = 2.0
default_color = Color(0.9, 0.85, 0.6, 1)
point_a = NodePath("../Link2")
point_b = NodePath("../Link3")
spring_segments = 0

[node name="ChainLine3" type="Line2D" parent="."]
script = ExtResource("2")
width = 2.0
default_color = Color(0.9, 0.85, 0.6, 1)
point_a = NodePath("../Link3")
point_b = NodePath("../Link4")
spring_segments = 0

[node name="ChainLine4" type="Line2D" parent="."]
script = ExtResource("2")
width = 2.0
default_color = Color(0.9, 0.85, 0.6, 1)
point_a = NodePath("../Link4")
point_b = NodePath("../Link5")
spring_segments = 0
```

- [ ] **Step 2: 在 Godot 编辑器中打开 `Scenes/Demos/demo_rope_joint.tscn` 并保存（Ctrl+S）让 uid 补全**

- [ ] **Step 3: 在编辑器里运行（F6）当前场景**

预期：
- 左侧：橙色摆锤球用一根细线挂在天花板锚点下；拖动球远离锚点 → 接近 280 像素时被绳子拽住，无法再远离；拖回近距离时绳子松弛（线段画得比锚点-球距离短或恰好等长）
- 右侧：5 节珠链从天花板挂下，末端是较大的蓝色球；可以拖动链条任意一节，链条摆动如真实项链

- [ ] **Step 4: Commit**

```bash
git add Scenes/Demos/demo_rope_joint.tscn
git commit -m "feat(demos): add RopeJoint scene with pendulum + chain"
```

---

### Task 9: 串联 next/prev 导航链

**Files:**
- Modify: `Scenes/Demos/demo_rigid_body.tscn` （为根节点新增 `next_scene` 导出值）
- Modify: `Scenes/Demos/demo_weld_joint.tscn` （为根节点新增 `prev_scene` 和 `next_scene`）
- Modify: `Scenes/Demos/demo_damped_spring.tscn` （同上）
- Modify: `Scenes/Demos/demo_rope_joint.tscn` （只新增 `prev_scene`，下一项尚未存在）

Phase 1 的 `DemoLevel` 基类已经实现了 "<< 上一项" / "下一项 >>" 按钮 —— 当 `next_scene` 或 `prev_scene` 导出变量为非 null 时按钮会启用。这里把 demo 链表串起来：rigid_body → weld → damped_spring → rope。

> **关于 `PackedScene` 在 .tscn 中的写法：** 在文本场景里，导出变量赋值为另一个场景的方法是用 `ExtResource`：
> 1. 在文件顶部 `[ext_resource]` 区域新增一行声明被引用的场景；
> 2. 在 `[node]` 块里设置 `next_scene = ExtResource("ID")`。
> 编辑器会负责生成正确的 uid。手工编写时，可以省略 uid 让编辑器在第一次打开时补全。

- [ ] **Step 1: 在 Godot 编辑器中打开 `Scenes/Demos/demo_rigid_body.tscn`**

在场景树选中根节点 `RigidBodyDemo`，在右侧检视面板的 "Demo Info" 分类下：
- `Next Scene`：拖入 `Scenes/Demos/demo_weld_joint.tscn` 或点 "Quick Load" 选择

保存场景。

- [ ] **Step 2: 在 Godot 编辑器中打开 `Scenes/Demos/demo_weld_joint.tscn`**

选中根节点 `WeldJointDemo`：
- `Prev Scene`：选择 `demo_rigid_body.tscn`
- `Next Scene`：选择 `demo_damped_spring.tscn`

保存。

- [ ] **Step 3: 在 Godot 编辑器中打开 `Scenes/Demos/demo_damped_spring.tscn`**

选中根节点 `DampedSpringDemo`：
- `Prev Scene`：选择 `demo_weld_joint.tscn`
- `Next Scene`：选择 `demo_rope_joint.tscn`

保存。

- [ ] **Step 4: 在 Godot 编辑器中打开 `Scenes/Demos/demo_rope_joint.tscn`**

选中根节点 `RopeJointDemo`：
- `Prev Scene`：选择 `demo_damped_spring.tscn`
- `Next Scene`：留空（下一项 Phase 3 才有）

保存。

- [ ] **Step 5: 在编辑器里运行 `demo_menu.tscn`，串通整条链**

预期流程：
1. 进入 RigidBody → 顶部 "下一项 >>" 可点击 → 跳到 WeldJoint
2. WeldJoint → "<< 上一项" 回到 RigidBody；"下一项 >>" 到 DampedSpring
3. DampedSpring → 上一项到 WeldJoint；下一项到 RopeJoint
4. RopeJoint → 上一项到 DampedSpring；"下一项 >>" 灰色禁用

- [ ] **Step 6: Commit**

```bash
git add Scenes/Demos/demo_rigid_body.tscn Scenes/Demos/demo_weld_joint.tscn Scenes/Demos/demo_damped_spring.tscn Scenes/Demos/demo_rope_joint.tscn
git commit -m "feat(demos): wire next/prev navigation between Phase 1/2 demos"
```

---

### Task 10: 端到端验证

由于 `.tscn` 包含子资源引用、ext_resource uid 等需要 Godot 正确解析的内容，这一步必须在编辑器里手动跑通完整流程：

- [ ] 在 Godot 编辑器中打开 `Scenes/Demos/demo_menu.tscn`，按 F6 启动
- [ ] 主菜单：确认 RigidBody / WeldJoint / DampedSpring / RopeJoint 四个按钮都可点击
- [ ] 点 WeldJoint：验证塔和雪人可拖动且各自作为整体响应
- [ ] 顶部用 "下一项 >>" 切到 DampedSpring：验证两个弹簧响应差异明显（左快回稳、右长振荡），锯齿弹簧可视化跟随
- [ ] "下一项 >>" 到 RopeJoint：验证摆锤在 280 px 内自由、超过被拉住；链条 5 节可拖摆
- [ ] "<< 上一项" 链路：rope → spring → weld → rigid 一路返回正常
- [ ] 任意 demo 里 "< 返回菜单" 回到主菜单正常

如发现 ext_resource uid 报错或场景加载失败：在编辑器里打开报错的 `.tscn`，让编辑器修复并保存，然后 commit 一次 "fix(demos): regenerate scene uids"。

---

## 文件变更汇总 (Phase 2)

| 操作 | 文件 |
|------|------|
| Create | `Scripts/Demos/joint_line_visualizer.gd` |
| Create | `Scripts/Demos/demo_weld_joint.gd` |
| Create | `Scripts/Demos/demo_damped_spring.gd` |
| Create | `Scripts/Demos/demo_rope_joint.gd` |
| Create | `Scenes/Demos/demo_weld_joint.tscn` |
| Create | `Scenes/Demos/demo_damped_spring.tscn` |
| Create | `Scenes/Demos/demo_rope_joint.tscn` |
| Modify | `Scripts/Demos/demo_menu.gd` (启用 3/4/5 三项的 path) |
| Modify | `Scenes/Demos/demo_rigid_body.tscn` (next_scene) |

不修改 `project.godot`。

---

## Phase 2 范围说明

Phase 2 选定"双体约束"类的 3 个关节作为一个内聚的小阶段，每个 Demo 都依赖鼠标拖拽来直观感受约束效果：

- **WeldJoint** — 刚性合并：拖一块带动整体
- **DampedSpring** — 弹性约束 + 衰减：拖了会反弹和振荡
- **RopeJoint** — 单边长度约束：拖到极限才会被拽住

剩余 5 个关节（Pulley / Motor / Wheel / Gear / MouseJoint 可视化）按 spec 编号 6-10 留给 Phase 3+，因为它们的演示场景更复杂（需要轮子+地形、齿轮联动、可视化拖拽弹力等），单独成阶更合适。
