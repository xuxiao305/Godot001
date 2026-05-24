# Box2D Demo 合集 Phase 3 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Phase 1/2 基础上新增 4 个 Demo，覆盖 spec 编号 7-10：MotorJoint（线性马达）、WheelJoint（带悬挂的轮子）、GearJoint（齿轮联动）、以及替代 MouseJoint 的 MouseDrag 拖拽可视化。Spec entry 6（PulleyJoint）跳过 —— 没有可用的等长约束 joint，无法物理正确模拟，菜单按钮保持禁用并加注释。

**Architecture:** 关键约束是 `godot-box2d` 这个 GDExtension 其实是 **PhysicsServer2D backend only** —— 它不注册任何 Joint 节点类，可用的只有 Godot 内置的 `PinJoint2D` / `GrooveJoint2D` / `DampedSpringJoint2D`（详见项目记忆 `godot-box2d-joints-not-registered`）。所以每个 Phase 3 demo 都用这 3 个原语 + GDScript 自定义逻辑来"模拟"对应的高级 joint 行为，命名上仍沿用 spec 的关节名（如 `demo_motor_joint.tscn`）以保持菜单/spec 的一致性。

复用 Phase 2 已建立的模式：每个 demo = 一个 `*.gd`（extends `DemoLevel`） + 一个 `*.tscn`（根节点挂脚本，子节点放刚体 + 关节 + Line2D 可视化）。

**Tech Stack:** Godot 4.6 + GDScript + godot-box2d v0.9.11（仅用作 PhysicsServer2D 替换，不依赖任何 addon 节点类）。可用 joint 类：`PinJoint2D` / `GrooveJoint2D` / `DampedSpringJoint2D`。

---

### Task 1: 启用主菜单 Phase 3 路径（跳过 Pulley）

**Files:**
- Modify: `Scripts/Demos/demo_menu.gd:25-50`

把 entries 7-10 的 path 字段填上对应场景路径；entry 6 保持空，并把 description 改写明白原因。

- [ ] **Step 1: 修改 entry 6 (PulleyJoint — 保持禁用 + 加注释)**

把现有内容：

```gdscript
	6: {
		"name": "PulleyJoint 滑轮关节",
		"path": "",
		"description": "滑轮对重系统"
	},
```

替换为：

```gdscript
	# PulleyJoint 需要"两段绳子等长约束"的关节；godot-box2d v0.9.11 不提供
	# PulleyJoint2D 节点类，只能用脚本伪造（失去物理正确性）。暂时跳过。
	6: {
		"name": "PulleyJoint 滑轮关节 (不可用)",
		"path": "",
		"description": "addon 未提供 PulleyJoint2D 类，需等长约束 — 跳过"
	},
```

- [ ] **Step 2: 修改 entry 7 (MotorJoint)**

替换为：

```gdscript
	7: {
		"name": "MotorJoint 马达关节",
		"path": "res://Scenes/Demos/demo_motor_joint.tscn",
		"description": "GrooveJoint2D + 周期性推力 — 平台沿直线往返"
	},
```

- [ ] **Step 3: 修改 entry 8 (WheelJoint)**

替换为：

```gdscript
	8: {
		"name": "WheelJoint 轮子关节",
		"path": "res://Scenes/Demos/demo_wheel_joint.tscn",
		"description": "PinJoint 轮 + DampedSpringJoint 悬挂 — 拖动车身体验弹跳"
	},
```

- [ ] **Step 4: 修改 entry 9 (GearJoint)**

替换为：

```gdscript
	9: {
		"name": "GearJoint 齿轮关节",
		"path": "res://Scenes/Demos/demo_gear_joint.tscn",
		"description": "脚本耦合两个 PinJoint 齿轮的角速度 — 拨动一个另一个反向同步转"
	},
```

- [ ] **Step 5: 修改 entry 10 (MouseJoint → MouseDrag)**

替换为：

```gdscript
	10: {
		"name": "MouseDrag 拖拽可视化",
		"path": "res://Scenes/Demos/demo_mouse_drag.tscn",
		"description": "拖拽弹性线 + 拖尾（addon 未提供 MouseJoint2D 类）"
	},
```

- [ ] **Step 6: 在 Godot 编辑器里运行 `demo_menu.tscn`（F6），确认按钮状态**

预期：
- 按钮 6 灰色禁用（PulleyJoint）
- 按钮 7/8/9/10 可点击（点击会因场景未创建报错 — 这是预期，后续任务创建）

- [ ] **Step 7: Commit**

```bash
git add Scripts/Demos/demo_menu.gd
git commit -m "feat(demos): enable Phase 3 menu entries (motor/wheel/gear/mouse-drag)"
```

---

### Task 2: 创建 MotorJoint Demo 脚本

**Files:**
- Create: `Scripts/Demos/demo_motor_joint.gd`
- Create: `Scripts/Demos/demo_motor_joint.gd.uid`

**实现思路：** Box2D MotorJoint2D 在 addon 里不可用。用 `GrooveJoint2D` 约束一个 RigidBody2D 沿水平直线滑动（消除 y 方向自由度和旋转），然后用脚本每帧根据 sin(t) 给它施加水平推力，让平台在槽里来回滑。

- [ ] **Step 1: 编写 `Scripts/Demos/demo_motor_joint.gd`**

```gdscript
# MotorJoint Demo —— 用 GrooveJoint2D + 周期性推力模拟线性马达
extends DemoLevel


@export var platform_path: NodePath
@export var force_magnitude: float = 1500.0   ## 推力幅度（牛）
@export var period: float = 4.0               ## 往返周期（秒）

var _platform: RigidBody2D = null
var _elapsed: float = 0.0


func _ready() -> void:
	super._ready()
	if platform_path != NodePath(""):
		_platform = get_node_or_null(platform_path) as RigidBody2D


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _platform == null:
		return
	# 拖拽中由基类的 velocity 覆盖逻辑接管，不要叠加马达推力
	if _drag_body == _platform:
		_elapsed = 0.0
		return
	_elapsed += delta
	var phase := TAU * _elapsed / period
	var fx := sin(phase) * force_magnitude
	_platform.apply_central_force(Vector2(fx, 0.0))
```

- [ ] **Step 2: 创建 uid 文件 `Scripts/Demos/demo_motor_joint.gd.uid`**

写入一行：

```
uid://dmotorjnt001b
```

- [ ] **Step 3: 在 Godot 编辑器中打开项目让其扫描新文件**

确认 FileSystem 面板能看到这两个文件且无解析错误。

- [ ] **Step 4: Commit**

```bash
git add Scripts/Demos/demo_motor_joint.gd Scripts/Demos/demo_motor_joint.gd.uid
git commit -m "feat(demos): add demo_motor_joint.gd with grooved sinusoidal motor"
```

---

### Task 3: 创建 MotorJoint Demo 场景

**Files:**
- Create: `Scenes/Demos/demo_motor_joint.tscn`

**场景结构：**
- 摄像机 + 背景 + 地面 + 左右墙
- 中央一根 StaticBody2D "Track"（视觉用 ColorRect 画一条横槽）
- 一个 RigidBody2D "Platform"（长方形，gravity_scale=0，linear_damp 高一点抑制无限振荡）
- **GrooveJoint2D**：`node_a = Track`，`node_b = Platform`，槽的两端在 local 坐标 (-300, 0) 和 (300, 0) —— 平台被强制约束沿这条 600px 的水平线移动
- 平台上方放一个 Label（"按基类 velocity 拖拽即可手动覆盖"）
- 顶部和地面之间还放几个普通的 RigidBody2D 小箱子作背景物体，验证拖拽功能没坏

**GrooveJoint2D 关键属性：**
- `node_a`：定义槽的物体（一般是 StaticBody2D）
- `node_b`：被约束在槽里滑动的物体
- `length`：槽长度（从锚点起向 local +x 方向延伸的距离，单位 px）；本场景设 600
- `initial_offset`：node_b 沿槽方向的初始偏移（局部坐标系）
- joint 自身的 `position` 在父节点（demo 根）坐标系下，槽方向跟随 joint 自身的 rotation

> **注意：** GrooveJoint2D 默认槽方向是 local +y（向下），而我们想要水平槽 —— 通过把 joint 自身 `rotation = -PI/2`（顺时针 90° 即 -1.5707963）让 +y 旋到指向屏幕右方。

- [ ] **Step 1: 创建 `Scenes/Demos/demo_motor_joint.tscn`**

```
[gd_scene load_steps=6 format=3 uid="uid://dmotorscn01b"]

[ext_resource type="Script" uid="uid://dmotorjnt001b" path="res://Scripts/Demos/demo_motor_joint.gd" id="1"]

[sub_resource type="RectangleShape2D" id="GroundShape"]
size = Vector2(1152, 40)

[sub_resource type="RectangleShape2D" id="WallShape"]
size = Vector2(20, 648)

[sub_resource type="RectangleShape2D" id="TrackShape"]
size = Vector2(20, 20)

[sub_resource type="RectangleShape2D" id="PlatformShape"]
size = Vector2(220, 24)

[sub_resource type="RectangleShape2D" id="CrateShape"]
size = Vector2(48, 48)

[node name="MotorJointDemo" type="Node2D"]
script = ExtResource("1")
title = "MotorJoint 马达关节"
description = "GrooveJoint2D 约束 + sin 推力 — 平台沿水平槽往返；顶部箱子随之颠"
demo_index = 7
platform_path = NodePath("Platform")
force_magnitude = 1500.0
period = 4.0

[node name="Camera2D" type="Camera2D" parent="."]
position = Vector2(576, 324)
zoom = Vector2(0.8, 0.8)

[node name="Background" type="ColorRect" parent="."]
offset_right = 1152.0
offset_bottom = 648.0
color = Color(0.12, 0.16, 0.2, 1)

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

; ===== Visual: groove line across the middle =====
[node name="TrackVisual" type="ColorRect" parent="."]
offset_left = 270.0
offset_top = 416.0
offset_right = 880.0
offset_bottom = 424.0
color = Color(0.4, 0.4, 0.45, 1)

; ===== Static track body =====
[node name="Track" type="StaticBody2D" parent="."]
position = Vector2(575, 420)
[node name="CollisionShape2D" type="CollisionShape2D" parent="Track"]
shape = SubResource("TrackShape")
disabled = true

; ===== Platform (constrained by GrooveJoint2D) =====
[node name="Platform" type="RigidBody2D" parent="."]
position = Vector2(575, 420)
gravity_scale = 0.0
mass = 5.0
linear_damp = 1.5
angular_damp = 5.0
[node name="CollisionShape2D" type="CollisionShape2D" parent="Platform"]
shape = SubResource("PlatformShape")
[node name="ColorRect" type="ColorRect" parent="Platform"]
offset_left = -110.0
offset_top = -12.0
offset_right = 110.0
offset_bottom = 12.0
color = Color(0.45, 0.7, 0.45, 1)

; ===== Groove joint: horizontal track 600px (rotated -PI/2 so +y becomes +x) =====
[node name="Groove" type="GrooveJoint2D" parent="."]
position = Vector2(275, 420)
rotation = -1.5707963
length = 600.0
initial_offset = 300.0
node_a = NodePath("../Track")
node_b = NodePath("../Platform")

; ===== Crates on the platform =====
[node name="Crate1" type="RigidBody2D" parent="."]
position = Vector2(540, 380)
mass = 0.8
[node name="CollisionShape2D" type="CollisionShape2D" parent="Crate1"]
shape = SubResource("CrateShape")
[node name="ColorRect" type="ColorRect" parent="Crate1"]
offset_left = -24.0
offset_top = -24.0
offset_right = 24.0
offset_bottom = 24.0
color = Color(0.85, 0.55, 0.25, 1)

[node name="Crate2" type="RigidBody2D" parent="."]
position = Vector2(610, 380)
mass = 0.8
[node name="CollisionShape2D" type="CollisionShape2D" parent="Crate2"]
shape = SubResource("CrateShape")
[node name="ColorRect" type="ColorRect" parent="Crate2"]
offset_left = -24.0
offset_top = -24.0
offset_right = 24.0
offset_bottom = 24.0
color = Color(0.85, 0.55, 0.25, 1)

[node name="Crate3" type="RigidBody2D" parent="."]
position = Vector2(570, 340)
mass = 0.8
[node name="CollisionShape2D" type="CollisionShape2D" parent="Crate3"]
shape = SubResource("CrateShape")
[node name="ColorRect" type="ColorRect" parent="Crate3"]
offset_left = -24.0
offset_top = -24.0
offset_right = 24.0
offset_bottom = 24.0
color = Color(0.85, 0.55, 0.25, 1)
```

- [ ] **Step 2: 在 Godot 编辑器中打开 `Scenes/Demos/demo_motor_joint.tscn` 并保存（Ctrl+S）**

让编辑器补全缺失 uid 并写回。

- [ ] **Step 3: 在编辑器里运行（F6）当前场景**

预期：
- 灰色横槽贯穿屏幕中央；绿色长条平台在槽中央
- 平台水平方向被脚本周期推力左右推动（≈ ±300px 范围，往返 4 秒），y 方向被 GrooveJoint 死锁
- 平台顶上 3 个橙色箱子被推动 / 摔落 / 滚动
- 拖拽平台：基类 velocity 覆盖逻辑会接管（demo_motor_joint.gd 里 `if _drag_body == _platform: return` 暂停马达），松手后马达继续

- [ ] **Step 4: Commit**

```bash
git add Scenes/Demos/demo_motor_joint.tscn
git commit -m "feat(demos): add MotorJoint scene (groove + sinusoidal force)"
```

---

### Task 4: 创建 WheelJoint Demo 脚本

**Files:**
- Create: `Scripts/Demos/demo_wheel_joint.gd`
- Create: `Scripts/Demos/demo_wheel_joint.gd.uid`

**实现思路：** Box2D WheelJoint2D 在 addon 里不可用。用 **PinJoint2D**（车身 ↔ 轮子；让轮子绕自身中心自由旋转）+ **DampedSpringJoint2D**（车身 ↔ 轮子；垂直方向上的弹簧悬挂）的组合模拟。脚本提供 A/D 键控制：按下时给轮子施加 `apply_torque`，让车前后开。

- [ ] **Step 1: 编写 `Scripts/Demos/demo_wheel_joint.gd`**

```gdscript
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
```

- [ ] **Step 2: 创建 uid 文件 `Scripts/Demos/demo_wheel_joint.gd.uid`**

写入：

```
uid://dwheeljnt001c
```

- [ ] **Step 3: 在 Godot 编辑器中打开项目让其扫描新文件**

- [ ] **Step 4: Commit**

```bash
git add Scripts/Demos/demo_wheel_joint.gd Scripts/Demos/demo_wheel_joint.gd.uid
git commit -m "feat(demos): add demo_wheel_joint.gd with A/D torque drive"
```

---

### Task 5: 创建 WheelJoint Demo 场景

**Files:**
- Create: `Scenes/Demos/demo_wheel_joint.tscn`

**场景结构：**
- 摄像机 + 背景 + 多段地形（3 段平地 + 2 个 bump）
- 一辆"车"：
  - 1 个 RigidBody2D `CarBody` (长方形车身)
  - 2 个 RigidBody2D `LeftWheelBody` / `RightWheelBody` (圆形轮子)
  - 每个轮子用 **PinJoint2D** 连到车身（注意：PinJoint2D 不约束相对位置，但会把它们维持在同一个点；这就允许轮子绕该点旋转）—— **错误！PinJoint2D 强制两个 body 共享一个点，没有"通过弹簧支撑"的语义**
  - 正确做法：用 PinJoint2D 把每个轮子和车身上对应位置 (anchor) 连接，让轮子能在该 anchor 处自由旋转；车身底部上下 bump 时，由于车身和轮子被 pin 在一起，整车作为刚体一起跳 —— 没有独立悬挂。
  - **要做真正的悬挂：** 引入"摇臂" body —— `LeftArm` / `RightArm`（小段刚体），用 PinJoint2D 连到车身（摆臂支点），再用 PinJoint2D 把摇臂另一端连到轮子（轮子绕摆臂端旋转），再用 DampedSpringJoint2D 在 车身 ↔ 轮子 之间做垂直弹簧。这样轮子可以相对车身上下浮动（摆臂转动），同时弹簧提供恢复力。
  - 本实现采用这种 swing-arm + spring 方案

**场景节点列表（摆臂悬挂方案）：**
- CarBody
- LeftArm + LeftWheelBody + LeftArmPin (CarBody ↔ LeftArm) + LeftWheelPin (LeftArm ↔ LeftWheelBody) + LeftSpring (CarBody ↔ LeftWheelBody, 模拟悬挂)
- 同样 Right 一组

- [ ] **Step 1: 创建 `Scenes/Demos/demo_wheel_joint.tscn`**

```
[gd_scene load_steps=8 format=3 uid="uid://dwheelscn01c"]

[ext_resource type="Script" uid="uid://dwheeljnt001c" path="res://Scripts/Demos/demo_wheel_joint.gd" id="1"]

[sub_resource type="RectangleShape2D" id="WallShape"]
size = Vector2(20, 648)

[sub_resource type="RectangleShape2D" id="GroundFlat"]
size = Vector2(400, 40)

[sub_resource type="RectangleShape2D" id="GroundBump"]
size = Vector2(120, 60)

[sub_resource type="RectangleShape2D" id="BodyShape"]
size = Vector2(160, 36)

[sub_resource type="RectangleShape2D" id="ArmShape"]
size = Vector2(36, 8)

[sub_resource type="CircleShape2D" id="WheelShape"]
radius = 22.0

[node name="WheelJointDemo" type="Node2D"]
script = ExtResource("1")
title = "WheelJoint 轮子关节"
description = "摆臂(PinJoint) + DampedSpring 悬挂；A/D 给轮子施加扭矩前后开"
demo_index = 8
left_wheel_path = NodePath("LeftWheelBody")
right_wheel_path = NodePath("RightWheelBody")
drive_torque = 5000.0

[node name="Camera2D" type="Camera2D" parent="."]
position = Vector2(576, 324)
zoom = Vector2(0.8, 0.8)

[node name="Background" type="ColorRect" parent="."]
offset_right = 1152.0
offset_bottom = 648.0
color = Color(0.1, 0.14, 0.2, 1)

; ===== Walls =====
[node name="LeftWall" type="StaticBody2D" parent="."]
[node name="CollisionShape2D" type="CollisionShape2D" parent="LeftWall"]
position = Vector2(10, 324)
shape = SubResource("WallShape")

[node name="RightWall" type="StaticBody2D" parent="."]
[node name="CollisionShape2D" type="CollisionShape2D" parent="RightWall"]
position = Vector2(1142, 324)
shape = SubResource("WallShape")

; ===== Terrain =====
[node name="GroundA" type="StaticBody2D" parent="."]
[node name="CollisionShape2D" type="CollisionShape2D" parent="GroundA"]
position = Vector2(220, 600)
shape = SubResource("GroundFlat")
[node name="ColorRect" type="ColorRect" parent="GroundA"]
offset_left = 20.0
offset_top = 580.0
offset_right = 420.0
offset_bottom = 620.0
color = Color(0.3, 0.25, 0.2, 1)

[node name="Bump1" type="StaticBody2D" parent="."]
[node name="CollisionShape2D" type="CollisionShape2D" parent="Bump1"]
position = Vector2(480, 590)
shape = SubResource("GroundBump")
[node name="ColorRect" type="ColorRect" parent="Bump1"]
offset_left = 420.0
offset_top = 560.0
offset_right = 540.0
offset_bottom = 620.0
color = Color(0.35, 0.3, 0.22, 1)

[node name="GroundB" type="StaticBody2D" parent="."]
[node name="CollisionShape2D" type="CollisionShape2D" parent="GroundB"]
position = Vector2(740, 600)
shape = SubResource("GroundFlat")
[node name="ColorRect" type="ColorRect" parent="GroundB"]
offset_left = 540.0
offset_top = 580.0
offset_right = 940.0
offset_bottom = 620.0
color = Color(0.3, 0.25, 0.2, 1)

[node name="Bump2" type="StaticBody2D" parent="."]
[node name="CollisionShape2D" type="CollisionShape2D" parent="Bump2"]
position = Vector2(1000, 590)
shape = SubResource("GroundBump")
[node name="ColorRect" type="ColorRect" parent="Bump2"]
offset_left = 940.0
offset_top = 560.0
offset_right = 1060.0
offset_bottom = 620.0
color = Color(0.35, 0.3, 0.22, 1)

[node name="GroundC" type="StaticBody2D" parent="."]
[node name="CollisionShape2D" type="CollisionShape2D" parent="GroundC"]
position = Vector2(1100, 600)
shape = SubResource("GroundFlat")
[node name="ColorRect" type="ColorRect" parent="GroundC"]
offset_left = 1060.0
offset_top = 580.0
offset_right = 1132.0
offset_bottom = 620.0
color = Color(0.3, 0.25, 0.2, 1)

; ===== Car body =====
[node name="CarBody" type="RigidBody2D" parent="."]
position = Vector2(220, 480)
mass = 4.0
[node name="CollisionShape2D" type="CollisionShape2D" parent="CarBody"]
shape = SubResource("BodyShape")
[node name="ColorRect" type="ColorRect" parent="CarBody"]
offset_left = -80.0
offset_top = -18.0
offset_right = 80.0
offset_bottom = 18.0
color = Color(0.85, 0.35, 0.35, 1)

; ===== Left wheel assembly =====
[node name="LeftArm" type="RigidBody2D" parent="."]
position = Vector2(150, 500)
mass = 0.3
[node name="CollisionShape2D" type="CollisionShape2D" parent="LeftArm"]
shape = SubResource("ArmShape")
disabled = true
[node name="ColorRect" type="ColorRect" parent="LeftArm"]
offset_left = -18.0
offset_top = -4.0
offset_right = 18.0
offset_bottom = 4.0
color = Color(0.5, 0.5, 0.5, 1)

[node name="LeftWheelBody" type="RigidBody2D" parent="."]
position = Vector2(135, 520)
mass = 0.5
[node name="CollisionShape2D" type="CollisionShape2D" parent="LeftWheelBody"]
shape = SubResource("WheelShape")
[node name="ColorRect" type="ColorRect" parent="LeftWheelBody"]
offset_left = -22.0
offset_top = -22.0
offset_right = 22.0
offset_bottom = 22.0
color = Color(0.2, 0.2, 0.2, 1)
[node name="Marker" type="ColorRect" parent="LeftWheelBody"]
offset_left = 0.0
offset_top = -2.0
offset_right = 20.0
offset_bottom = 2.0
color = Color(0.95, 0.95, 0.6, 1)

[node name="LeftArmPin" type="PinJoint2D" parent="."]
position = Vector2(168, 500)
node_a = NodePath("../CarBody")
node_b = NodePath("../LeftArm")
softness = 0.0

[node name="LeftWheelPin" type="PinJoint2D" parent="."]
position = Vector2(135, 520)
node_a = NodePath("../LeftArm")
node_b = NodePath("../LeftWheelBody")
softness = 0.0

[node name="LeftSpring" type="DampedSpringJoint2D" parent="."]
position = Vector2(135, 500)
length = 40.0
rest_length = 40.0
stiffness = 80.0
damping = 8.0
node_a = NodePath("../CarBody")
node_b = NodePath("../LeftWheelBody")

; ===== Right wheel assembly =====
[node name="RightArm" type="RigidBody2D" parent="."]
position = Vector2(290, 500)
mass = 0.3
[node name="CollisionShape2D" type="CollisionShape2D" parent="RightArm"]
shape = SubResource("ArmShape")
disabled = true
[node name="ColorRect" type="ColorRect" parent="RightArm"]
offset_left = -18.0
offset_top = -4.0
offset_right = 18.0
offset_bottom = 4.0
color = Color(0.5, 0.5, 0.5, 1)

[node name="RightWheelBody" type="RigidBody2D" parent="."]
position = Vector2(305, 520)
mass = 0.5
[node name="CollisionShape2D" type="CollisionShape2D" parent="RightWheelBody"]
shape = SubResource("WheelShape")
[node name="ColorRect" type="ColorRect" parent="RightWheelBody"]
offset_left = -22.0
offset_top = -22.0
offset_right = 22.0
offset_bottom = 22.0
color = Color(0.2, 0.2, 0.2, 1)
[node name="Marker" type="ColorRect" parent="RightWheelBody"]
offset_left = 0.0
offset_top = -2.0
offset_right = 20.0
offset_bottom = 2.0
color = Color(0.95, 0.95, 0.6, 1)

[node name="RightArmPin" type="PinJoint2D" parent="."]
position = Vector2(272, 500)
node_a = NodePath("../CarBody")
node_b = NodePath("../RightArm")
softness = 0.0

[node name="RightWheelPin" type="PinJoint2D" parent="."]
position = Vector2(305, 520)
node_a = NodePath("../RightArm")
node_b = NodePath("../RightWheelBody")
softness = 0.0

[node name="RightSpring" type="DampedSpringJoint2D" parent="."]
position = Vector2(305, 500)
length = 40.0
rest_length = 40.0
stiffness = 80.0
damping = 8.0
node_a = NodePath("../CarBody")
node_b = NodePath("../RightWheelBody")
```

- [ ] **Step 2: 在 Godot 编辑器中打开 `Scenes/Demos/demo_wheel_joint.tscn` 并保存（Ctrl+S）**

让编辑器补全 uid。

- [ ] **Step 3: 在编辑器里运行（F6）当前场景**

预期：
- 红色车身落到地面，两个黑色轮子（带黄色标记线，可看清旋转）撑住车身
- 按住 D：车向右开，过 bump 时车身会颠（弹簧悬挂吸收一部分）
- 按住 A：车向左开
- 鼠标可以拖车身（强行换位置/翻车）

> **预期局限：** 这种摆臂 + 弹簧的组合悬挂行为不如真正的 WheelJoint2D 准确（摆臂会摆动出非物理姿态、可能"分家"在剧烈冲击下），但展示概念足够。如果车在启动时就分崩离析，调高弹簧 `stiffness` 到 200 或调短 `length` 到 20。

- [ ] **Step 4: Commit**

```bash
git add Scenes/Demos/demo_wheel_joint.tscn
git commit -m "feat(demos): add WheelJoint scene (swing arm + spring suspension)"
```

---

### Task 6: 创建 GearJoint Demo 脚本

**Files:**
- Create: `Scripts/Demos/demo_gear_joint.gd`
- Create: `Scripts/Demos/demo_gear_joint.gd.uid`

**实现思路：** Box2D GearJoint2D 在 addon 里不可用。用 2 个 PinJoint2D 把两个齿轮 RigidBody2D 分别固定到静态锚点（让它们只能绕中心转），然后脚本每 `_physics_process` 把 GearA 的 angular_velocity 按 `ratio` 写到 GearB（取相反值实现反向同步）。

不是物理硬约束，但效果上 GearA 旋转 → GearB 立即按比例反向旋转，符合"齿轮联动"的视觉直觉。

- [ ] **Step 1: 编写 `Scripts/Demos/demo_gear_joint.gd`**

```gdscript
# GearJoint Demo —— 脚本耦合两个 PinJoint 齿轮的角速度，模拟齿轮联动
extends DemoLevel


@export var gear_a_path: NodePath
@export var gear_b_path: NodePath
@export var ratio: float = -1.0   ## GearB 的角速度 = GearA 的角速度 * ratio（-1 表示同速反向）

var _gear_a: RigidBody2D = null
var _gear_b: RigidBody2D = null


func _ready() -> void:
	super._ready()
	if gear_a_path != NodePath(""):
		_gear_a = get_node_or_null(gear_a_path) as RigidBody2D
	if gear_b_path != NodePath(""):
		_gear_b = get_node_or_null(gear_b_path) as RigidBody2D


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _gear_a == null or _gear_b == null:
		return
	# 双向耦合：哪个被拖就以哪个为主动
	if _drag_body == _gear_a or (_drag_body == null and abs(_gear_a.angular_velocity) >= abs(_gear_b.angular_velocity)):
		_gear_b.angular_velocity = _gear_a.angular_velocity * ratio
	else:
		_gear_a.angular_velocity = _gear_b.angular_velocity / ratio
```

- [ ] **Step 2: 创建 uid 文件 `Scripts/Demos/demo_gear_joint.gd.uid`**

写入：

```
uid://dgearjnt0001d
```

- [ ] **Step 3: 在 Godot 编辑器中打开项目让其扫描新文件**

- [ ] **Step 4: Commit**

```bash
git add Scripts/Demos/demo_gear_joint.gd Scripts/Demos/demo_gear_joint.gd.uid
git commit -m "feat(demos): add demo_gear_joint.gd with script-coupled angular velocity"
```

---

### Task 7: 创建 GearJoint Demo 场景

**Files:**
- Create: `Scenes/Demos/demo_gear_joint.tscn`

**场景结构：**
- 摄像机 + 背景 + 地面 + 左右墙
- 两个并排齿轮 (RigidBody2D + CircleShape2D，半径 80)，gravity_scale=0
- 每个齿轮中心位置都有一个 StaticBody2D 锚点
- 每个齿轮通过 PinJoint2D 与对应锚点连接（强制齿轮只能绕中心旋转）
- 每个齿轮上画一根 "辐条" ColorRect 从中心延伸到边缘，让旋转视觉化
- 脚本（Task 6）读 gear_a.angular_velocity 写 gear_b.angular_velocity * -1

- [ ] **Step 1: 创建 `Scenes/Demos/demo_gear_joint.tscn`**

```
[gd_scene load_steps=5 format=3 uid="uid://dgearscn001d"]

[ext_resource type="Script" uid="uid://dgearjnt0001d" path="res://Scripts/Demos/demo_gear_joint.gd" id="1"]

[sub_resource type="RectangleShape2D" id="GroundShape"]
size = Vector2(1152, 40)

[sub_resource type="RectangleShape2D" id="WallShape"]
size = Vector2(20, 648)

[sub_resource type="CircleShape2D" id="GearShape"]
radius = 80.0

[sub_resource type="RectangleShape2D" id="AnchorShape"]
size = Vector2(20, 20)

[node name="GearJointDemo" type="Node2D"]
script = ExtResource("1")
title = "GearJoint 齿轮关节"
description = "拖任一齿轮转动 → 另一齿轮反向同速联动 (脚本耦合 ratio=-1)"
demo_index = 9
gear_a_path = NodePath("LeftGear")
gear_b_path = NodePath("RightGear")
ratio = -1.0

[node name="Camera2D" type="Camera2D" parent="."]
position = Vector2(576, 324)
zoom = Vector2(0.8, 0.8)

[node name="Background" type="ColorRect" parent="."]
offset_right = 1152.0
offset_bottom = 648.0
color = Color(0.13, 0.16, 0.2, 1)

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

; ===== Anchors =====
[node name="LeftAnchor" type="StaticBody2D" parent="."]
position = Vector2(420, 320)
[node name="CollisionShape2D" type="CollisionShape2D" parent="LeftAnchor"]
shape = SubResource("AnchorShape")
disabled = true
[node name="ColorRect" type="ColorRect" parent="LeftAnchor"]
offset_left = -10.0
offset_top = -10.0
offset_right = 10.0
offset_bottom = 10.0
color = Color(0.6, 0.6, 0.65, 1)

[node name="RightAnchor" type="StaticBody2D" parent="."]
position = Vector2(720, 320)
[node name="CollisionShape2D" type="CollisionShape2D" parent="RightAnchor"]
shape = SubResource("AnchorShape")
disabled = true
[node name="ColorRect" type="ColorRect" parent="RightAnchor"]
offset_left = -10.0
offset_top = -10.0
offset_right = 10.0
offset_bottom = 10.0
color = Color(0.6, 0.6, 0.65, 1)

; ===== Gears =====
[node name="LeftGear" type="RigidBody2D" parent="."]
position = Vector2(420, 320)
mass = 1.0
gravity_scale = 0.0
angular_damp = 0.5
[node name="CollisionShape2D" type="CollisionShape2D" parent="LeftGear"]
shape = SubResource("GearShape")
[node name="ColorRect" type="ColorRect" parent="LeftGear"]
offset_left = -80.0
offset_top = -80.0
offset_right = 80.0
offset_bottom = 80.0
color = Color(0.85, 0.55, 0.25, 0.6)
[node name="RadiusMarker" type="ColorRect" parent="LeftGear"]
offset_left = 0.0
offset_top = -4.0
offset_right = 78.0
offset_bottom = 4.0
color = Color(0.1, 0.1, 0.15, 1)

[node name="RightGear" type="RigidBody2D" parent="."]
position = Vector2(720, 320)
mass = 1.0
gravity_scale = 0.0
angular_damp = 0.5
[node name="CollisionShape2D" type="CollisionShape2D" parent="RightGear"]
shape = SubResource("GearShape")
[node name="ColorRect" type="ColorRect" parent="RightGear"]
offset_left = -80.0
offset_top = -80.0
offset_right = 80.0
offset_bottom = 80.0
color = Color(0.3, 0.6, 0.9, 0.6)
[node name="RadiusMarker" type="ColorRect" parent="RightGear"]
offset_left = 0.0
offset_top = -4.0
offset_right = 78.0
offset_bottom = 4.0
color = Color(0.1, 0.1, 0.15, 1)

; ===== Pin joints (each gear pinned to its anchor) =====
[node name="LeftPin" type="PinJoint2D" parent="."]
position = Vector2(420, 320)
node_a = NodePath("../LeftAnchor")
node_b = NodePath("../LeftGear")
softness = 0.0

[node name="RightPin" type="PinJoint2D" parent="."]
position = Vector2(720, 320)
node_a = NodePath("../RightAnchor")
node_b = NodePath("../RightGear")
softness = 0.0
```

- [ ] **Step 2: 在 Godot 编辑器中打开 `Scenes/Demos/demo_gear_joint.tscn` 并保存（Ctrl+S）**

- [ ] **Step 3: 在编辑器里运行（F6）当前场景**

预期：
- 两个圆盘（左橙 + 右蓝）固定在中央两个 anchor 上，黑色辐条显示角度
- 鼠标拖动 LeftGear 的边缘（不是中心）让它旋转 → RightGear 立刻反向同速转
- 反过来拖 RightGear 也行（demo_gear_joint.gd 中的双向耦合判断）

> **预期局限：** 这是脚本耦合（每帧 angular_velocity 复制），不是真正的硬约束。如果给 GearA 施加大冲量，可能在一帧内偏差被放大；正常拖拽下视觉效果足够。

- [ ] **Step 4: Commit**

```bash
git add Scenes/Demos/demo_gear_joint.tscn
git commit -m "feat(demos): add GearJoint scene (two pinned gears, script-coupled)"
```

---

### Task 8: 创建 MouseDrag 可视化辅助脚本

**Files:**
- Create: `Scripts/Demos/drag_visualizer.gd`
- Create: `Scripts/Demos/drag_visualizer.gd.uid`

由于 `MouseJoint2D` 在 addon 里不可用，spec entry 10 改造为 "MouseDrag 拖拽可视化" Demo。它复用 `DemoLevel` 已有的 velocity-based 拖拽逻辑，本脚本挂在 demo 根下的 Node2D 上，每帧绘制：
1. 鼠标位置 → 当前被拖物体的弹簧锯齿线
2. 被拖物体身后的拖尾 Line2D（最近 N 帧位置）

挂载方式：场景里挂一个 Node2D，再把这个脚本挂上去；脚本会向上查找 `DemoLevel` 祖先并读 `_drag_body`。

- [ ] **Step 1: 编写 `Scripts/Demos/drag_visualizer.gd`**

```gdscript
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
```

- [ ] **Step 2: 创建 uid 文件 `Scripts/Demos/drag_visualizer.gd.uid`**

写入：

```
uid://ddragvisl001e
```

- [ ] **Step 3: 在 Godot 编辑器中打开项目让其扫描新文件**

确认 `DragVisualizer` 在 FileSystem 面板带 class_name 图标。

- [ ] **Step 4: Commit**

```bash
git add Scripts/Demos/drag_visualizer.gd Scripts/Demos/drag_visualizer.gd.uid
git commit -m "feat(demos): add DragVisualizer (spring line + trail)"
```

---

### Task 9: 创建 MouseDrag Demo 脚本

**Files:**
- Create: `Scripts/Demos/demo_mouse_drag.gd`
- Create: `Scripts/Demos/demo_mouse_drag.gd.uid`

- [ ] **Step 1: 编写 `Scripts/Demos/demo_mouse_drag.gd`**

```gdscript
# MouseDrag Demo —— 用 DragVisualizer 展示拖拽弹性线 + 拖尾
# (addon 未提供 MouseJoint2D 类，用 DemoLevel 已有的 velocity-drag + 可视化代替)
extends DemoLevel


func _ready() -> void:
	super._ready()
```

- [ ] **Step 2: 创建 uid 文件 `Scripts/Demos/demo_mouse_drag.gd.uid`**

写入：

```
uid://dmousdrg001f
```

- [ ] **Step 3: 在 Godot 编辑器中打开项目让其扫描新文件**

- [ ] **Step 4: Commit**

```bash
git add Scripts/Demos/demo_mouse_drag.gd Scripts/Demos/demo_mouse_drag.gd.uid
git commit -m "feat(demos): add demo_mouse_drag.gd extending DemoLevel"
```

---

### Task 10: 创建 MouseDrag Demo 场景

**Files:**
- Create: `Scenes/Demos/demo_mouse_drag.tscn`

**场景结构：**
- 摄像机 + 背景 + 地面 + 左右墙
- 4 个不同形状/颜色的 RigidBody2D 物体（方块、圆球、扁条、小立方），分散在地面上
- 根节点下挂一个 Node2D + DragVisualizer 脚本

- [ ] **Step 1: 创建 `Scenes/Demos/demo_mouse_drag.tscn`**

```
[gd_scene load_steps=7 format=3 uid="uid://dmousescn01f"]

[ext_resource type="Script" uid="uid://dmousdrg001f" path="res://Scripts/Demos/demo_mouse_drag.gd" id="1"]
[ext_resource type="Script" uid="uid://ddragvisl001e" path="res://Scripts/Demos/drag_visualizer.gd" id="2"]

[sub_resource type="RectangleShape2D" id="GroundShape"]
size = Vector2(1152, 40)

[sub_resource type="RectangleShape2D" id="WallShape"]
size = Vector2(20, 648)

[sub_resource type="RectangleShape2D" id="BoxShape"]
size = Vector2(64, 64)

[sub_resource type="CircleShape2D" id="BallShape"]
radius = 32.0

[sub_resource type="RectangleShape2D" id="BarShape"]
size = Vector2(120, 24)

[sub_resource type="RectangleShape2D" id="MiniShape"]
size = Vector2(36, 36)

[node name="MouseDragDemo" type="Node2D"]
script = ExtResource("1")
title = "MouseDrag 拖拽可视化"
description = "拖拽任意物体 — 黄色弹簧线 = 鼠标牵引；蓝色拖尾 = 物体轨迹"
demo_index = 10

[node name="Camera2D" type="Camera2D" parent="."]
position = Vector2(576, 324)
zoom = Vector2(0.8, 0.8)

[node name="Background" type="ColorRect" parent="."]
offset_right = 1152.0
offset_bottom = 648.0
color = Color(0.08, 0.1, 0.15, 1)

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

; ===== Bodies =====
[node name="Box" type="RigidBody2D" parent="."]
position = Vector2(300, 500)
mass = 1.5
[node name="CollisionShape2D" type="CollisionShape2D" parent="Box"]
shape = SubResource("BoxShape")
[node name="ColorRect" type="ColorRect" parent="Box"]
offset_left = -32.0
offset_top = -32.0
offset_right = 32.0
offset_bottom = 32.0
color = Color(0.85, 0.35, 0.35, 1)

[node name="Ball" type="RigidBody2D" parent="."]
position = Vector2(500, 500)
mass = 1.0
[node name="CollisionShape2D" type="CollisionShape2D" parent="Ball"]
shape = SubResource("BallShape")
[node name="ColorRect" type="ColorRect" parent="Ball"]
offset_left = -32.0
offset_top = -32.0
offset_right = 32.0
offset_bottom = 32.0
color = Color(0.3, 0.6, 0.9, 1)

[node name="Bar" type="RigidBody2D" parent="."]
position = Vector2(700, 500)
mass = 1.2
[node name="CollisionShape2D" type="CollisionShape2D" parent="Bar"]
shape = SubResource("BarShape")
[node name="ColorRect" type="ColorRect" parent="Bar"]
offset_left = -60.0
offset_top = -12.0
offset_right = 60.0
offset_bottom = 12.0
color = Color(0.45, 0.75, 0.4, 1)

[node name="Mini" type="RigidBody2D" parent="."]
position = Vector2(880, 500)
mass = 0.4
[node name="CollisionShape2D" type="CollisionShape2D" parent="Mini"]
shape = SubResource("MiniShape")
[node name="ColorRect" type="ColorRect" parent="Mini"]
offset_left = -18.0
offset_top = -18.0
offset_right = 18.0
offset_bottom = 18.0
color = Color(0.85, 0.55, 0.25, 1)

; ===== Drag visualizer =====
[node name="DragViz" type="Node2D" parent="."]
script = ExtResource("2")
spring_segments = 12
spring_amplitude = 8.0
spring_color = Color(1.0, 0.9, 0.3, 1.0)
spring_width = 3.0
trail_length = 80
trail_color = Color(0.5, 0.85, 1.0, 0.7)
trail_width = 4.0
```

- [ ] **Step 2: 在 Godot 编辑器中打开 `Scenes/Demos/demo_mouse_drag.tscn` 并保存（Ctrl+S）**

- [ ] **Step 3: 在编辑器里运行（F6）当前场景**

预期：
- 4 个不同物体在地面上
- 鼠标按住任意物体：物体被拖到鼠标位置；一根黄色锯齿弹簧线从鼠标连到物体中心；物体身后留蓝色淡出拖尾
- 松开后弹簧线消失，拖尾立即清空

- [ ] **Step 4: Commit**

```bash
git add Scenes/Demos/demo_mouse_drag.tscn
git commit -m "feat(demos): add MouseDrag scene with spring line + trail visualizer"
```

---

### Task 11: 串联 next/prev 导航链（跳过禁用的 Pulley）

**Files:**
- Modify: `Scenes/Demos/demo_rope_joint.tscn`（next_scene → motor，跳过禁用的 pulley）
- Modify: `Scenes/Demos/demo_motor_joint.tscn`（prev = rope, next = wheel）
- Modify: `Scenes/Demos/demo_wheel_joint.tscn`（prev = motor, next = gear）
- Modify: `Scenes/Demos/demo_gear_joint.tscn`（prev = wheel, next = mouse_drag）
- Modify: `Scenes/Demos/demo_mouse_drag.tscn`（prev = gear, next 留空）

> 链顺序：rope → motor → wheel → gear → mouse_drag（跳过 pulley 这一不可用项）。

> 用编辑器选 next/prev 比手写 ext_resource 容易，下面优先用编辑器方式。

- [ ] **Step 1: 在 Godot 编辑器中打开 `Scenes/Demos/demo_rope_joint.tscn`**

选中根节点 `RopeJointDemo`：
- `Next Scene`：选择 `demo_motor_joint.tscn`（之前为空）

保存。

- [ ] **Step 2: 打开 `Scenes/Demos/demo_motor_joint.tscn`**

选中根节点 `MotorJointDemo`：
- `Prev Scene`：选择 `demo_rope_joint.tscn`
- `Next Scene`：选择 `demo_wheel_joint.tscn`

保存。

- [ ] **Step 3: 打开 `Scenes/Demos/demo_wheel_joint.tscn`**

选中根节点 `WheelJointDemo`：
- `Prev Scene`：选择 `demo_motor_joint.tscn`
- `Next Scene`：选择 `demo_gear_joint.tscn`

保存。

- [ ] **Step 4: 打开 `Scenes/Demos/demo_gear_joint.tscn`**

选中根节点 `GearJointDemo`：
- `Prev Scene`：选择 `demo_wheel_joint.tscn`
- `Next Scene`：选择 `demo_mouse_drag.tscn`

保存。

- [ ] **Step 5: 打开 `Scenes/Demos/demo_mouse_drag.tscn`**

选中根节点 `MouseDragDemo`：
- `Prev Scene`：选择 `demo_gear_joint.tscn`
- `Next Scene`：留空

保存。

- [ ] **Step 6: 在编辑器里运行 `demo_menu.tscn`，沿"下一项 >>"一路按到 MouseDrag**

预期完整链：rigid → weld → spring → rope → motor → wheel → gear → mouse_drag（共 8 步，每步"<< 上一项"能回退）。

- [ ] **Step 7: Commit**

```bash
git add Scenes/Demos/demo_rope_joint.tscn Scenes/Demos/demo_motor_joint.tscn Scenes/Demos/demo_wheel_joint.tscn Scenes/Demos/demo_gear_joint.tscn Scenes/Demos/demo_mouse_drag.tscn
git commit -m "feat(demos): wire next/prev navigation through Phase 3 demos"
```

---

### Task 12: 端到端验证

`.tscn` 包含子资源引用、ext_resource uid 等需要 Godot 解析的内容，最后一步必须在编辑器里手动跑通完整流程：

- [ ] 在 Godot 编辑器中打开 `Scenes/Demos/demo_menu.tscn`，按 F6 启动
- [ ] 主菜单：
  - 按钮 6 (PulleyJoint) 灰色禁用
  - 按钮 2/3/4/5/7/8/9/10 都可点击
- [ ] 点 **MotorJoint**：绿色平台在水平槽中往返；顶部箱子被推动；拖动平台时马达暂停，松手继续
- [ ] **下一项 >>** 到 **WheelJoint**：车身落地，按 D 向右开过 bump 颠簸；A 向左开；车不分崩离析
- [ ] **下一项 >>** 到 **GearJoint**：拖左齿轮旋转，右齿轮反向同速；反向亦同
- [ ] **下一项 >>** 到 **MouseDrag**：拖任一物体出现黄色弹簧线 + 蓝色拖尾
- [ ] **<< 上一项** 链路：mouse_drag → gear → wheel → motor → rope → spring → weld → rigid 一路返回正常
- [ ] 任意 demo 里 **< 返回菜单** 回到主菜单正常

如发现 ext_resource uid 报错或场景加载失败：在编辑器里打开报错的 `.tscn`，让编辑器修复并保存，再单独 commit：

```bash
git commit -am "fix(demos): regenerate Phase 3 scene uids"
```

---

### Task 13: 更新 Phase 3 自身记录

**Files:**
- Modify: `docs/superpowers/specs/2026-05-24-box2d-demo-collection-design.md` 末尾追加附录

把 spec 末尾的"后续 Demo (Phase 2+) "表格更新为反映"Phase 3 实际范围"和"Pulley 被跳过的原因"。

- [ ] **Step 1: 在 spec 文件末尾追加一段**

```markdown

## 附录：Phase 3 实施变更（2026-05-24）

inspection of `addons/godot-box2d/bin/libgodot-box2d.windows.template_release.x86_64.dll` 显示该 GDExtension 是 PhysicsServer2D backend only —— 它不注册任何 Joint 节点类。spec 中编号 3-10 的 Box2D 扩展 joint 全部**不可用**：WeldJoint2D / RopeJoint2D / PulleyJoint2D / MotorJoint2D / WheelJoint2D / GearJoint2D / MouseJoint2D 均为图标。

可用 joint 类只有 Godot 内置三个：`PinJoint2D` / `GrooveJoint2D` / `DampedSpringJoint2D`。

**Phase 3 已交付：**
- 7 MotorJoint → GrooveJoint2D + sin 推力模拟
- 8 WheelJoint → PinJoint2D（轮转） + DampedSpringJoint2D（弹簧悬挂） + 摆臂模拟
- 9 GearJoint → 2 PinJoint2D + 脚本 angular_velocity 耦合
- 10 MouseDrag → DemoLevel velocity-drag + DragVisualizer（无 joint）

**Phase 3 已跳过：**
- 6 PulleyJoint → 需要等长约束 joint，无可行的伪造方案，菜单按钮保持灰色

如未来 godot-box2d 升级到注册更多 joint 类，可重做以上 demos 用真正的 Box2D joint，并启用 Pulley demo。
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-05-24-box2d-demo-collection-design.md
git commit -m "docs(demos): record Phase 3 joint substitutions and Pulley skip"
```

---

## 文件变更汇总 (Phase 3)

| 操作 | 文件 |
|------|------|
| Create | `Scripts/Demos/demo_motor_joint.gd` (+ .uid) |
| Create | `Scripts/Demos/demo_wheel_joint.gd` (+ .uid) |
| Create | `Scripts/Demos/demo_gear_joint.gd` (+ .uid) |
| Create | `Scripts/Demos/drag_visualizer.gd` (+ .uid) |
| Create | `Scripts/Demos/demo_mouse_drag.gd` (+ .uid) |
| Create | `Scenes/Demos/demo_motor_joint.tscn` |
| Create | `Scenes/Demos/demo_wheel_joint.tscn` |
| Create | `Scenes/Demos/demo_gear_joint.tscn` |
| Create | `Scenes/Demos/demo_mouse_drag.tscn` |
| Modify | `Scripts/Demos/demo_menu.gd` (启用 7/8/9/10；6 改写为禁用说明) |
| Modify | `Scenes/Demos/demo_rope_joint.tscn` (next_scene → motor) |
| Modify | `docs/superpowers/specs/2026-05-24-box2d-demo-collection-design.md` (附录) |

不修改 `project.godot`。不修改 `Scripts/Demos/demo_level.gd`。

---

## Phase 3 范围说明

godot-box2d v0.9.11 是 PhysicsServer2D backend only，只能用 Godot 内置 3 个 joint 类（PinJoint2D / GrooveJoint2D / DampedSpringJoint2D）。Phase 3 在这个限制下用 "原语组合 + 脚本逻辑" 模拟 spec 编号 7-10 的高级 joint：

- **MotorJoint** → GrooveJoint2D 约束水平滑 + sin 推力
- **WheelJoint** → PinJoint2D 摆臂 + DampedSpringJoint2D 垂直弹簧
- **GearJoint** → 2 PinJoint2D 锚定 + 脚本 angular_velocity 反向耦合
- **MouseDrag**（替 MouseJoint）→ 已有 velocity-drag + 弹簧线 + 拖尾可视化

spec 编号 6 **PulleyJoint** 跳过 —— 需要"等长约束"，3 个原语组合不出物理正确的方案。菜单按钮保持灰色 + 注释说明。

> **未来：** 如果 godot-box2d 真的注册了 PulleyJoint2D / MotorJoint2D / WheelJoint2D / GearJoint2D，可以重写这几个 demo 用真正的 Box2D joint（行为会更稳定准确）。
