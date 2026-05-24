# 3C 原型 v1 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 PlatformerPhysics 项目第一个原型 —— 基础 3C（角色 + 摄像机 + 控制），完整覆盖[3C-prototype-design](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/3C-prototype-design.md) §3.1 v1 MVP 范围，严格遵循 ADR-0001 ~ ADR-0005 的内在发动机派架构。

**Architecture:** 角色 = `RigidBody2D`（godot-box2d 后端），所有玩家操作 → `apply_central_force` / `apply_central_impulse`，**绝不写入 `linear_velocity`**。最大速度由发动机转速曲线涌现（ADR-0002），跳跃用初始冲量 + 持续小推力 + 恒定重力（ADR-0003），空中弱喷气无阻力（ADR-0004），Capsule + contact 法线接地检测（ADR-0005），所有参数 runtime 可调（生命线 Debug 面板）。

**Tech Stack:** Godot 4.6, GDScript, godot-box2d GDExtension v0.9.11（PhysicsServer2D 后端，标准 `RigidBody2D` API 透传 Box2D 仿真）。无单元测试框架；纯数学函数用嵌入式 `assert()` 测试场景验证，玩法用可观察行为 + Debug 面板验证。

---

## 文件结构

```
Scenes/Prototypes/3C/
├── player.tscn                     — Capsule RigidBody2D + 视觉占位
├── test_level.tscn                 — §4.10 测试关卡（多材质 + 台阶 + 跳跃 + dynamic box）
├── debug_panel.tscn                — F1 切换的滑条面板
└── tests/
    └── test_engine_torque.tscn     — 纯数学单元测试场景

Scripts/Prototypes/3C/
├── player.gd                       — 控制器主体；编排所有子系统
├── engine_torque.gd                — 静态类：转速曲线纯函数（可单测）
├── ground_check.gd                 — Contact + 法线接地检测；含 1 帧防抖开关
├── input_buffer.gd                 — Coyote + jump buffer 计时器
├── jump_controller.gd              — 跳跃冲量 + 持续推力状态
├── camera_follow.gd                — 临界阻尼跟随 + 死区 + 垂直 lookahead
├── debug_panel.gd                  — 实时滑条 + 数值显示 + JSON save/load
└── tests/
    └── test_engine_torque.gd       — 转速曲线单元测试
```

**职责划分原则：**
- `engine_torque.gd` / `input_buffer.gd` 是**纯逻辑**（无 Node 状态），可在测试场景独立验证；其他文件依赖物理状态。
- `player.gd` 是组合中心，每个 `_physics_process` tick 按 §5.1 顺序调用子系统，**自身不持有重复状态**。
- `debug_panel.gd` 直接读 / 写 `player` 上的 `@export` 变量，不引入 setting singleton。

**资源放置说明：**
- 选 `Scenes/Prototypes/3C/` 与现有 `Scenes/Demos/` 并列，**不修改 demo 体系**，互不污染。
- 项目主场景 (`project.godot` 的 `run/main_scene`) **暂不改**，保持 `demo_menu.tscn`；开发期通过 F6（运行当前场景）驱动测试关卡。Task 13 决定是否升级菜单入口。

---

## Task 1: Box2D 能力 Spike（30 分钟内）

> 来源：[spec §7 风险表](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/3C-prototype-design.md)第二行 "Godot 4 的 Box2D GDExtension 成熟度未知 → 实现前先做 30 分钟 spike"。
>
> **目的：** 在写一行真正的代码前确认 4 件事可行；任何一项失败必须停下来回到 brainstorming，不要硬上。

**Files:**
- Create: `Scenes/Prototypes/3C/tests/spike_box2d.tscn`
- Create: `Scripts/Prototypes/3C/tests/spike_box2d.gd`

- [ ] **Step 1: 写 spike 脚本**

```gdscript
# Scripts/Prototypes/3C/tests/spike_box2d.gd
# Box2D 能力 spike —— 验证后续依赖的 4 项 API 全部可用。
extends Node2D

func _ready() -> void:
	# 1) 能创建 RigidBody2D 并设置 Capsule shape
	var body := RigidBody2D.new()
	body.lock_rotation = true
	body.linear_damping = 0.0
	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 20.0
	capsule.height = 90.0
	shape.shape = capsule
	body.add_child(shape)
	body.position = Vector2(400, 100)
	body.contact_monitor = true
	body.max_contacts_reported = 8
	add_child(body)

	# 2) 能 apply_central_force / apply_central_impulse
	body.apply_central_impulse(Vector2(0, -200))
	print("[SPIKE] impulse applied, expect upward kick")

	# 3) 地面用 StaticBody2D + 自带 physics material
	var ground := StaticBody2D.new()
	var ground_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(800, 32)
	ground_shape.shape = rect
	ground.add_child(ground_shape)
	ground.position = Vector2(400, 500)
	var mat := PhysicsMaterial.new()
	mat.friction = 0.5
	ground.physics_material_override = mat
	add_child(ground)

	# 4) 等 0.5s 后探针 contact 列表（保证已落地）
	await get_tree().create_timer(0.5).timeout
	body.apply_central_force(Vector2(150, 0))
	await get_tree().create_timer(0.2).timeout

	# 通过 _integrate_forces 桥读 contact 数据 —— 见下方 PlayerProbe
	var probe := PlayerProbe.new()
	probe.target = body
	add_child(probe)

class PlayerProbe extends Node:
	var target: RigidBody2D
	func _physics_process(_dt: float) -> void:
		if target == null: return
		var state := PhysicsServer2D.body_get_direct_state(target.get_rid())
		var count := state.get_contact_count()
		print("[SPIKE] contacts=%d, vel=%s" % [count, state.linear_velocity])
		for i in count:
			var n := state.get_contact_local_normal(i)
			print("  contact %d normal=%s n.y=%.3f" % [i, n, n.y])
```

- [ ] **Step 2: 写 spike 场景**

`Scenes/Prototypes/3C/tests/spike_box2d.tscn` —— 编辑器新建 Node2D 根节点，附上 `spike_box2d.gd`，保存。

- [ ] **Step 3: F6 运行 spike，观察输出**

Expected (输出窗口)：
```
[SPIKE] impulse applied, expect upward kick
[SPIKE] contacts=1, vel=(150.xxx, ~0)
  contact 0 normal=(0, -1) n.y=-1.000
[SPIKE] contacts=1, vel=(150.xxx + force/mass*dt, ~0)
...
```

**通过判据**（全部满足）：
1. 物体出现并下落，撞地后停下 → RigidBody2D + Capsule + 重力工作
2. `apply_central_force` / `apply_central_impulse` 调用无报错 → API 透传 OK
3. `contact_count >= 1`，法线 y 分量 ≈ -1（向上）→ contact 探针可用
4. 物体被水平 150 N 推动 → 摩擦不会瞬时清掉力

**任一不通过 → 停下来，先解决，不要继续后续任务。** 常见问题：
- 物体不落 → 检查 `freeze` 默认值、`linear_damping` 是否为 0
- contact_count 一直为 0 → `contact_monitor = true` + `max_contacts_reported >= 1` 必须同时设
- 法线方向反 → spec §4.6 的 `cos_theta_max` 阈值后续要对应翻转，记一笔

- [ ] **Step 4: 提交**

```bash
git add Scenes/Prototypes/3C/tests/spike_box2d.tscn Scripts/Prototypes/3C/tests/spike_box2d.gd
git commit -m "spike(3c): verify godot-box2d capsule/force/contact APIs"
```

---

## Task 2: 发动机转速曲线纯函数（TDD）

> 来源：[spec §4.2](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/3C-prototype-design.md) + [ADR-0002](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/adr/0002-engine-torque-curve.md)。这是**整个 3C 的数学核心**，错了所有手感都没意义，所以放在 player.gd 之前先单测确定。

**Files:**
- Create: `Scripts/Prototypes/3C/engine_torque.gd`
- Create: `Scripts/Prototypes/3C/tests/test_engine_torque.gd`
- Create: `Scenes/Prototypes/3C/tests/test_engine_torque.tscn`

- [ ] **Step 1: 先写失败测试**

```gdscript
# Scripts/Prototypes/3C/tests/test_engine_torque.gd
# 纯函数测试 —— 在 _ready 时跑断言，全部通过则打印 PASS。
extends Node

const EngineTorque := preload("res://Scripts/Prototypes/3C/engine_torque.gd")

func _ready() -> void:
	# 1) 静止时无输入 → 力 = 0
	assert(_approx(EngineTorque.compute(0.0, 0.0, 80.0, 2.0), 0.0),
		"无输入静止应不出力")

	# 2) 满力区间：差值 > saturation_full → 满力且方向对
	assert(_approx(EngineTorque.compute(0.0, 8.0, 80.0, 2.0), 80.0),
		"启动应满力向右")
	assert(_approx(EngineTorque.compute(0.0, -8.0, 80.0, 2.0), -80.0),
		"启动应满力向左")

	# 3) 接近目标：差值在 (0, saturation_full) → 衰减
	var f1 := EngineTorque.compute(7.0, 8.0, 80.0, 2.0)
	assert(f1 > 0.0 and f1 < 80.0, "接近顶速应衰减出力, got %f" % f1)

	# 4) 到达目标 → 力 = 0
	assert(_approx(EngineTorque.compute(8.0, 8.0, 80.0, 2.0), 0.0),
		"到顶速应不出力")

	# 5) 超速且无反向输入（v_target=0）→ 力 = 0（不强行回拉，ADR-0002）
	assert(_approx(EngineTorque.compute(12.0, 0.0, 80.0, 2.0), 0.0),
		"超速无输入应放任摩擦衰减")

	# 5b) 低速且无输入（v_target=0）→ 力 = 0（不主动刹车，那是 f_active_brake 的事）
	assert(_approx(EngineTorque.compute(1.5, 0.0, 80.0, 2.0), 0.0),
		"低速无输入不应主动刹车（靠摩擦 + f_active_brake）")

	# 6) 超速且玩家反向输入 → 全力反向（ADR-0002 "反方向远离目标 → 全力反向"）
	assert(_approx(EngineTorque.compute(12.0, -8.0, 80.0, 2.0), -80.0),
		"超速反输入应全力反向刹车")

	# 7) 超速且玩家继续按同向 → 力 = 0（"超过目标方向 → 力 = 0"）
	assert(_approx(EngineTorque.compute(12.0, 8.0, 80.0, 2.0), 0.0),
		"超速继续按同向不应再加力")

	print("[TEST engine_torque] ALL PASS")
	get_tree().quit()

static func _approx(a: float, b: float) -> bool:
	return abs(a - b) < 0.001
```

- [ ] **Step 2: 写最小测试场景**

`Scenes/Prototypes/3C/tests/test_engine_torque.tscn` —— 编辑器新建 Node 根节点，附 `test_engine_torque.gd`，保存。

- [ ] **Step 3: F6 运行场景验证测试失败**

Expected: 解析报错或 assert 失败（`engine_torque.gd` 还不存在）

- [ ] **Step 4: 实现最小通过代码**

```gdscript
# Scripts/Prototypes/3C/engine_torque.gd
# 发动机转速曲线 —— 纯数学函数，不依赖 Node。
# 来源：ADR-0002 https://docs/adr/0002-engine-torque-curve.md
class_name EngineTorque
extends RefCounted

# 计算当前帧引擎输出力。
#   v_current:        当前水平速度
#   v_target:         目标水平速度（±v_max 或 0）
#   f_max:            发动机额定力上限
#   saturation_full:  |v_target - v_current| 大于此值时 saturation = 1
static func compute(v_current: float, v_target: float, f_max: float, saturation_full: float) -> float:
	var diff := v_target - v_current
	if absf(diff) < 0.0001:
		return 0.0
	# ADR-0002 "v_target=0 时发动机不出力，靠摩擦衰减"：无输入不主动刹车（那是 f_active_brake 的事）
	if v_target == 0.0:
		return 0.0
	# ADR-0002 "超过目标方向 → 力 = 0"：当前已超过 v_target 且方向相同
	if signf(v_current) == signf(v_target) and absf(v_current) > absf(v_target):
		return 0.0
	var dir := signf(diff)
	var saturation := minf(absf(diff) / saturation_full, 1.0)
	return f_max * dir * saturation
```

- [ ] **Step 5: F6 运行场景验证测试通过**

Expected (输出窗口)：
```
[TEST engine_torque] ALL PASS
```

游戏窗口自动关闭。

- [ ] **Step 6: 提交**

```bash
git add Scripts/Prototypes/3C/engine_torque.gd Scripts/Prototypes/3C/tests/test_engine_torque.gd Scenes/Prototypes/3C/tests/test_engine_torque.tscn
git commit -m "feat(3c): engine torque curve with unit tests"
```

---

## Task 3: 角色物理体（Capsule + 重力 + 接地检测）

> 来源：[spec §4.1 §4.6](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/3C-prototype-design.md) + [ADR-0005](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/adr/0005-capsule-as-learning-choice.md)。
>
> **关键：** 接地用 contact + 法线，**不用 raycast**（ADR-0005）。

**Files:**
- Create: `Scenes/Prototypes/3C/player.tscn`
- Create: `Scripts/Prototypes/3C/player.gd`
- Create: `Scripts/Prototypes/3C/ground_check.gd`

- [ ] **Step 1: 写接地检测纯函数（带断言）**

```gdscript
# Scripts/Prototypes/3C/ground_check.gd
# 接地判定 —— 给定 contact 法线列表，判定是否接地。
# 法线方向约定：来自 PhysicsDirectBodyState2D.get_contact_local_normal()，
#   "从碰撞对象指向角色"，所以"地面"对应 normal.y 显著为负（向上推角色）。
#   Spike Task 1 已验证：地面 contact 的 n.y ≈ -1。
class_name GroundCheck
extends RefCounted

# 输入 contact 数和 PhysicsDirectBodyState2D，返回 (is_grounded, ground_normal_y_min)
static func check(state: PhysicsDirectBodyState2D, cos_theta_max: float) -> Dictionary:
	var grounded := false
	var min_ny := 1.0  # 最"地面"的法线 y（最负的）
	for i in state.get_contact_count():
		var n := state.get_contact_local_normal(i)
		# 地面法线指向角色 → n.y < -cos_theta_max
		# cos_theta_max = 0.7 → 接受 n.y <= -0.7（约 45° 内的坡）
		if n.y < -cos_theta_max:
			grounded = true
			if n.y < min_ny:
				min_ny = n.y
	return {"grounded": grounded, "min_normal_y": min_ny}

# 1 帧防抖封装 —— 接地态从 true→false 时延迟 buffer_frames 帧。
# 来源：spec §4.6 ground_state_buffer_frames（默认关 = 0）
class Debouncer extends RefCounted:
	var buffer_frames: int = 0
	var _last_true: bool = false
	var _frames_since_false: int = 0

	func feed(raw_grounded: bool) -> bool:
		if raw_grounded:
			_last_true = true
			_frames_since_false = 0
			return true
		# raw = false
		if not _last_true:
			return false
		_frames_since_false += 1
		if _frames_since_false > buffer_frames:
			_last_true = false
			return false
		return true  # 仍处于防抖窗口
```

- [ ] **Step 2: 写 player.gd 最小版本（只有 Capsule + 重力 + 接地）**

```gdscript
# Scripts/Prototypes/3C/player.gd
# 3C 原型角色控制器 —— 内在发动机派（ADR-0001）。
# 每帧只 apply_force / apply_impulse，绝不写入 linear_velocity。
class_name Player3C
extends RigidBody2D

# --------- EXPORT (Debug 面板会读写这些) ---------- #
@export_category("Engine — Ground (§4.2)")
@export var v_max: float = 8.0 * 100.0          # m/s → 100 px/m
@export var f_max_ground: float = 80.0 * 100.0
@export var saturation_full: float = 2.0 * 100.0
@export var f_active_brake: float = 0.0

@export_category("Engine — Air (§4.3)")
@export var f_max_air: float = 40.0 * 100.0

@export_category("Jump (§4.4)")
@export var j_jump_initial: float = 11.2 * 100.0
@export var f_jump_hold: float = 8.0 * 100.0
@export var hold_window_max: float = 0.30
@export var gravity_y: float = 25.0 * 100.0      # 单位 px/s²

@export_category("Perceptual Compensation (§4.5)")
@export var coyote_time: float = 0.10
@export var jump_buffer_time: float = 0.10

@export_category("Ground Detection (§4.6)")
@export var cos_theta_max: float = 0.7
@export_range(0, 5) var ground_state_buffer_frames: int = 0

# --------- RUNTIME STATE (Debug 面板会读) ---------- #
var is_grounded: bool = false
var ground_normal_y: float = 0.0
var current_state: String = "Idle"
var net_force_this_frame: Vector2 = Vector2.ZERO

var _ground_debounce := GroundCheck.Debouncer.new()

# --------- LIFECYCLE ---------- #
func _ready() -> void:
	lock_rotation = true
	linear_damping = 0.0
	contact_monitor = true
	max_contacts_reported = 8
	# 单位策略：1 m = 100 px。所有 spec 中的 m, m/s, N 在 export 默认值里已乘 100。
	# 项目重力关掉（用 ADR-0003 的恒定 gravity_y）：
	gravity_scale = 0.0  # 我们自己施加重力，便于 Debug 面板调

# 用 _integrate_forces 而非 _physics_process —— Box2D 提供完整 state，且这是 Godot 推荐的物理操作时机。
func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# 1. 接地检测
	_ground_debounce.buffer_frames = ground_state_buffer_frames
	var gc := GroundCheck.check(state, cos_theta_max)
	is_grounded = _ground_debounce.feed(gc.grounded)
	ground_normal_y = gc.min_normal_y

	# 2. 恒定重力（ADR-0003）
	var force := Vector2(0, gravity_y * mass)

	# 3. 其他子系统的力会在后续 Task 累加进 force
	# TODO(Task 4): + 地面/空中发动机力（统一处理，is_grounded 分支）
	# TODO(Task 5): + 跳跃持续推力

	net_force_this_frame = force
	state.apply_central_force(force)
```

- [ ] **Step 3: 写 player.tscn**

`Scenes/Prototypes/3C/player.tscn` —— 编辑器构造：
- 根节点：`RigidBody2D`，附 `player.gd`
- 子节点 `CollisionShape2D`：`shape = CapsuleShape2D`，`radius = 40`, `height = 180`（对应 spec 的 0.4 m / 1.8 m × 100）
- 子节点 `Sprite2D` 或 `ColorRect` 占位（红色 80×180）便于看转向

保存场景。

- [ ] **Step 4: 写最小测试关卡确认重力 + 接地**

`Scenes/Prototypes/3C/test_level.tscn`（先做最简版本，Task 12 再扩展）：
- 根节点：`Node2D`
- 子节点 `Camera2D`：position (640, 360), enabled
- 子节点 `Player3C` 实例：position (400, 100)
- 子节点 `StaticBody2D`（地面）：CollisionShape2D rect 1280×40, position (640, 600)
  - physics_material_override: friction = 0.10（默认 μ）
- F6 运行

Expected: Capsule 落下，撞地停住，不弹（restitution=0）。打开 Remote 树观察 `Player3C.is_grounded` 变 true。

- [ ] **Step 5: 提交**

```bash
git add Scripts/Prototypes/3C/ground_check.gd Scripts/Prototypes/3C/player.gd Scenes/Prototypes/3C/player.tscn Scenes/Prototypes/3C/test_level.tscn
git commit -m "feat(3c): capsule body with constant gravity + contact-normal ground detection"
```

---

## Task 4: 地面发动机（接入转速曲线 + 摩擦惯性）

> 来源：[spec §4.2](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/3C-prototype-design.md)。把 Task 2 的纯函数接进 Task 3 的 `_integrate_forces`。

**Files:**
- Modify: `Scripts/Prototypes/3C/player.gd`

- [ ] **Step 1: 在 player.gd 加入输入读取 + 引擎力计算**

定位 `_integrate_forces` 中的 `# TODO(Task 5)` 注释，替换为：

```gdscript
	# 3. 地面/空中发动机力（§4.2 §4.3）
	var input_dir := Input.get_axis("Left", "Right")  # -1, 0, +1
	var v_target := input_dir * v_max
	var v_cur_x := state.linear_velocity.x
	var f_engine := 0.0
	if is_grounded:
		f_engine = EngineTorque.compute(v_cur_x, v_target, f_max_ground, saturation_full)
		# 主动刹车（spec §4.2，默认 f_active_brake = 0）
		if input_dir == 0.0 and absf(v_cur_x) > 0.01:
			f_engine -= signf(v_cur_x) * f_active_brake
	else:
		f_engine = EngineTorque.compute(v_cur_x, v_target, f_max_air, saturation_full)
	force.x += f_engine
```

并在文件顶部加 preload：

```gdscript
# 在 class_name Player3C 行下方
const EngineTorque := preload("res://Scripts/Prototypes/3C/engine_torque.gd")
```

- [ ] **Step 2: F6 运行 test_level**

Expected: 按 A/D 角色向左/右移动；松手后**滑行一段距离再停**（摩擦衰减，不瞬停）；不会越走越快（达到 v_max 后引擎不再加力）。

**手感校验：** 启动到顶速感觉 ≈ 0.1-0.15 s（spec §4.2 派生预期）。

- [ ] **Step 3: 提交**

```bash
git add Scripts/Prototypes/3C/player.gd
git commit -m "feat(3c): ground engine via torque curve, friction-driven inertia"
```

---

## Task 5: 跳跃（初始冲量 + 持续推力 + 恒定重力）

> 来源：[spec §4.4](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/3C-prototype-design.md) + [ADR-0003](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/adr/0003-jump-curve-via-assist-forces.md)。
>
> **关键：** v1 不实现 apex_hang / fall_multiplier；用真抛物线，未来通过 [ADR-0003] 留位辅助力补。

**Files:**
- Create: `Scripts/Prototypes/3C/jump_controller.gd`
- Modify: `Scripts/Prototypes/3C/player.gd`

- [ ] **Step 1: 写 jump_controller.gd**

```gdscript
# Scripts/Prototypes/3C/jump_controller.gd
# 跳跃状态机 —— 管理"按住期间持续推力"窗口。
class_name JumpController
extends RefCounted

var hold_active: bool = false
var _hold_elapsed: float = 0.0
var _hold_window: float = 0.30
var _f_hold: float = 0.0

# 接到合法的起跳信号 → 返回初始冲量（外部 apply）；并启动 hold 窗口。
func trigger_jump(j_initial: float, f_hold: float, hold_window: float) -> Vector2:
	hold_active = true
	_hold_elapsed = 0.0
	_hold_window = hold_window
	_f_hold = f_hold
	return Vector2(0, -j_initial)  # 向上（Y 轴朝下世界里 -y 是上）

# 每 physics tick 调用 —— 返回本帧的持续推力（vector，可能为 0）。
# input_held: 当前 Jump 键是否还按着
# vy:        角色当前 vy（vy >= 0 = 已开始下落，立刻停推）
func tick(delta: float, input_held: bool, vy: float) -> Vector2:
	if not hold_active:
		return Vector2.ZERO
	# 终止条件：松键 / 开始下落 / 窗口超时
	if not input_held or vy >= 0.0 or _hold_elapsed >= _hold_window:
		hold_active = false
		return Vector2.ZERO
	_hold_elapsed += delta
	return Vector2(0, -_f_hold)

func reset() -> void:
	hold_active = false
	_hold_elapsed = 0.0
```

- [ ] **Step 2: 在 player.gd 集成跳跃**

在 export 区下方加：

```gdscript
const JumpController := preload("res://Scripts/Prototypes/3C/jump_controller.gd")
var _jump := JumpController.new()
```

在 `_integrate_forces` 顶部（接地检测之后、力累加之前）加跳跃触发：

```gdscript
	# 2.5 跳跃触发（v1：只接地起跳；Coyote/Buffer 在 Task 7 加）
	if Input.is_action_just_pressed("Jump") and is_grounded:
		var impulse := _jump.trigger_jump(j_jump_initial, f_jump_hold, hold_window_max)
		state.apply_central_impulse(impulse)
```

在 `# TODO(Task 6)` 位置替换为：

```gdscript
	# 4. 跳跃持续推力（§4.4）
	var jump_hold_force := _jump.tick(state.step, Input.is_action_pressed("Jump"), state.linear_velocity.y)
	force += jump_hold_force
```

- [ ] **Step 3: F6 运行测试**

Expected:
- 按空格 → 角色起跳
- 长按 → 跳得更高（~2.5 m = 250 px 量级）
- 短按 → 跳得低（~1.9 m = 190 px）
- 下落速度逐渐增大（重力恒定，无 fall multiplier）
- 在空中再按 → 不跳（is_grounded = false 阻断；Coyote 在 Task 7）

- [ ] **Step 4: 提交**

```bash
git add Scripts/Prototypes/3C/jump_controller.gd Scripts/Prototypes/3C/player.gd
git commit -m "feat(3c): jump impulse + variable-hold force, constant gravity"
```

---

## Task 6: 空中喷气（弱推力 + 无阻力）

> 来源：[spec §4.3](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/3C-prototype-design.md) + [ADR-0004](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/adr/0004-air-control-model.md)。
>
> **注意：** Task 4 的引擎力计算已经处理了 `is_grounded ? f_max_ground : f_max_air` 的分支，所以**空中喷气已自动工作**。这个 Task 只是**验证 + 锁定行为**。

**Files:**
- Modify: `Scenes/Prototypes/3C/test_level.tscn`（增加一个缺口测试）

- [ ] **Step 1: 在 test_level 增加助跑跳验证场景**

在测试关卡里加：
- 平台 A（StaticBody2D + 矩形）：position (200, 600), 大小 (300, 40)
- 缺口宽 200 px
- 平台 B：position (700, 600), 大小 (300, 40)
- 另一处："原地跳缺口"：位置宽 200 px 但**没有助跑空间**（玩家从墙边起步）

- [ ] **Step 2: 验证 ADR-0004 的"助跑决定距离"**

F6 运行：
- 原地按 Jump + 按 D → 跳到对面缺口要费力 / 跳不过去（横向位移由空中弱推力 + 时间决定，最多到 v_max 的 30-50%）
- 助跑到顶速 → 起跳 → 不按 D → 横向距离明显更远，顺利过缺口（v_max × 滞空时间）

**通过判据：** 原地跳跨不过 200 px 但助跑跳能跨过 → ADR-0004 模型生效。

- [ ] **Step 3: 提交**

```bash
git add Scenes/Prototypes/3C/test_level.tscn
git commit -m "test(3c): verify air control = running-jump-decides-distance (ADR-0004)"
```

---

## Task 7: Coyote Time + Jump Buffer（知觉一致性补偿）

> 来源：[spec §4.5](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/3C-prototype-design.md) + [CONTEXT.md 知觉一致性补偿](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/CONTEXT.md)。
>
> **关键：** 这不是魔法，是补偿玩家延迟。判定通过后物理过程完全按 §4.4 走，所以集成点是"是否允许触发跳跃"，而**不是**修改跳跃力。

**Files:**
- Create: `Scripts/Prototypes/3C/input_buffer.gd`
- Create: `Scripts/Prototypes/3C/tests/test_input_buffer.gd`
- Create: `Scenes/Prototypes/3C/tests/test_input_buffer.tscn`
- Modify: `Scripts/Prototypes/3C/player.gd`

- [ ] **Step 1: 写 input_buffer 测试（TDD）**

```gdscript
# Scripts/Prototypes/3C/tests/test_input_buffer.gd
extends Node

const InputBuffer := preload("res://Scripts/Prototypes/3C/input_buffer.gd")

func _ready() -> void:
	# 1) Coyote: 接地的最后一帧是 t=0.10，离地后 coyote_time 窗内仍可起跳
	var b := InputBuffer.new()
	b.coyote_time = 0.10
	b.jump_buffer_time = 0.10
	# 模拟玩家在 t=0.10 时刻最后一次"被报告为接地"
	b.update_grounded(true, 0.10)
	# t=0.11 离地
	b.update_grounded(false, 0.11)
	# last_grounded_true_at = 0.10 → coyote 截止 = 0.20
	assert(b.can_coyote(0.15), "离地 0.05s 应有 coyote")
	assert(b.can_coyote(0.20), "离地 0.10s 边界仍有 coyote")
	assert(not b.can_coyote(0.21), "离地 0.11s 应过期")

	# 2) Buffer: 落地前 buffer 窗内按 Jump 算有效
	var b2 := InputBuffer.new()
	b2.coyote_time = 0.10
	b2.jump_buffer_time = 0.10
	b2.on_jump_pressed(0.0)
	assert(b2.can_buffer(0.05), "0.05s 时按过 jump 应 buffer 有效")
	assert(not b2.can_buffer(0.11), "0.11s 应过期")
	# Buffer 一旦消费应清零
	b2.consume_buffer()
	assert(not b2.can_buffer(0.05), "消费后 buffer 应失效")

	# 3) 落地（false→true）应自动复位 buffer
	var b3 := InputBuffer.new()
	b3.on_jump_pressed(0.0)
	b3.consume_buffer()
	b3.update_grounded(false, 0.01)
	b3.update_grounded(true, 0.02)  # 落地
	b3.on_jump_pressed(0.03)
	assert(b3.can_buffer(0.04), "落地后再按 Jump 应有 buffer")

	print("[TEST input_buffer] ALL PASS")
	get_tree().quit()
```

`Scenes/Prototypes/3C/tests/test_input_buffer.tscn` —— Node 根节点附该脚本，保存。

- [ ] **Step 2: F6 运行 → 验证测试失败**

Expected: 找不到 `input_buffer.gd`。

- [ ] **Step 3: 实现 input_buffer.gd**

```gdscript
# Scripts/Prototypes/3C/input_buffer.gd
# Coyote + Jump Buffer 计时器。时间使用绝对秒（从 SceneTree 拿）。
# 来源：spec §4.5 + CONTEXT.md
#
# 用法：每帧调用 update_grounded() 喂入当前接地状态（不是仅边缘）；
# 输入侧调用 on_jump_pressed() 记录按键时刻；
# 决策侧用 can_coyote() / can_buffer() 查询当前是否允许起跳；
# 起跳后调用 consume_buffer() 防止重复触发。
class_name InputBuffer
extends RefCounted

var coyote_time: float = 0.10
var jump_buffer_time: float = 0.10

var _last_grounded_true_at: float = -INF   # 上次接地（true）的时间
var _is_grounded: bool = false
var _last_jump_pressed_at: float = -INF
var _buffer_consumed: bool = false

# 每个 physics tick 调用 —— 不论 grounded 是否变化都要喂。
func update_grounded(grounded: bool, now: float) -> void:
	if grounded and not _is_grounded:
		# 落地 → buffer 复位（可用一次）
		_buffer_consumed = false
	if grounded:
		_last_grounded_true_at = now
	_is_grounded = grounded

# 离地后 _last_grounded_true_at 停在最后一次"接地 tick"的时间。
func can_coyote(now: float) -> bool:
	return (now - _last_grounded_true_at) <= coyote_time

func on_jump_pressed(now: float) -> void:
	_last_jump_pressed_at = now
	_buffer_consumed = false

func can_buffer(now: float) -> bool:
	if _buffer_consumed:
		return false
	return (now - _last_jump_pressed_at) <= jump_buffer_time

func consume_buffer() -> void:
	_buffer_consumed = true
	_last_jump_pressed_at = -INF
```

- [ ] **Step 4: F6 → 测试通过**

Expected: `[TEST input_buffer] ALL PASS` 然后退出。

- [ ] **Step 5: 集成进 player.gd**

顶部加 preload + 实例：

```gdscript
const InputBuffer := preload("res://Scripts/Prototypes/3C/input_buffer.gd")
var _input_buf := InputBuffer.new()
```

在 `_ready` 里同步参数：

```gdscript
	_input_buf.coyote_time = coyote_time
	_input_buf.jump_buffer_time = jump_buffer_time
```

修改 `_integrate_forces` 里的接地段，**每帧**喂 input_buf（不是仅边缘）：

```gdscript
	# 1. 接地检测
	_ground_debounce.buffer_frames = ground_state_buffer_frames
	var gc := GroundCheck.check(state, cos_theta_max)
	is_grounded = _ground_debounce.feed(gc.grounded)
	ground_normal_y = gc.min_normal_y
	var now := Time.get_ticks_msec() / 1000.0
	_input_buf.update_grounded(is_grounded, now)  # 每帧喂；buffer 复位由内部 edge 检测
```

替换跳跃触发段：

```gdscript
	# 2.5 跳跃触发（Coyote / Buffer）
	if Input.is_action_just_pressed("Jump"):
		_input_buf.on_jump_pressed(now)
	# 满足条件即起跳：
	#   - 接地 + 当前 buffer 有效（落地瞬间按下生效）
	#   - 不接地 + coyote 窗口内 + 当前 buffer 有效
	var can_jump_now := _input_buf.can_buffer(now) and (is_grounded or _input_buf.can_coyote(now))
	if can_jump_now and not _jump.hold_active:
		var impulse := _jump.trigger_jump(j_jump_initial, f_jump_hold, hold_window_max)
		state.apply_central_impulse(impulse)
		_input_buf.consume_buffer()
```

并在 `_integrate_forces` 里同步 export 参数到 `_input_buf`（每帧，便于 Debug 滑条生效）：

```gdscript
	_input_buf.coyote_time = coyote_time
	_input_buf.jump_buffer_time = jump_buffer_time
```

- [ ] **Step 6: F6 验证**

测试场景：
- 边缘 Coyote：走到平台边缘**走出去再按 Jump** → 角色仍起跳
- Buffer：跳起后下落**还没碰地就按 Jump** → 一碰地立即第二跳

- [ ] **Step 7: 提交**

```bash
git add Scripts/Prototypes/3C/input_buffer.gd Scripts/Prototypes/3C/tests/test_input_buffer.gd Scenes/Prototypes/3C/tests/test_input_buffer.tscn Scripts/Prototypes/3C/player.gd
git commit -m "feat(3c): coyote time + jump buffer (perceptual compensation)"
```

---

## Task 8: 状态机（最小可显示版）

> 来源：[spec §4.7](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/3C-prototype-design.md)。极简：5 个状态用字符串表示，**仅供 Debug 显示和将来挂动画**，不影响物理。

**Files:**
- Modify: `Scripts/Prototypes/3C/player.gd`

- [ ] **Step 1: 在 _integrate_forces 末尾加状态转换**

```gdscript
	# 5. 状态转换（仅用于显示，不影响物理）
	var vy := state.linear_velocity.y
	var vx := state.linear_velocity.x
	if is_grounded:
		if absf(vx) < 5.0:
			current_state = "Idle"
		else:
			current_state = "Running"
	else:
		if vy < 0.0:
			current_state = "Rising"
		else:
			current_state = "Falling"
	# Landed 是瞬时态，可在 on_grounded_changed 回调里设置一帧后让上面覆盖
	# v1 简化：不做单独 Landed 帧
```

- [ ] **Step 2: F6 验证**

Remote 树里看 `Player3C.current_state` 字段实时切换。Debug 面板（Task 10）会把它显示出来。

- [ ] **Step 3: 提交**

```bash
git add Scripts/Prototypes/3C/player.gd
git commit -m "feat(3c): minimal state machine for debug display"
```

---

## Task 9: 摄像机（临界阻尼跟随 + 死区 + 垂直 lookahead）

> 来源：[spec §4.8](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/3C-prototype-design.md)。

**Files:**
- Create: `Scripts/Prototypes/3C/camera_follow.gd`
- Modify: `Scenes/Prototypes/3C/test_level.tscn`（替换 Camera2D）

- [ ] **Step 1: 写 camera_follow.gd**

```gdscript
# Scripts/Prototypes/3C/camera_follow.gd
# 平滑跟随摄像机：临界阻尼弹簧 + 死区 + 垂直 lookahead。
# 来源：spec §4.8
class_name CameraFollow
extends Camera2D

@export var target_path: NodePath
@export var follow_time_constant: float = 0.15      # ~0.15s 临界阻尼
@export var dead_zone: Vector2 = Vector2(32, 24)    # ±32, ±24
@export var lookahead_offset_y: float = 64.0
@export var lookahead_vy_threshold: float = 500.0   # 5 m/s × 100 px/m
@export var lookahead_stable_time: float = 0.3

var _target: Node2D
var _lookahead_target_y: float = 0.0
var _vy_sign_held_since: float = -INF
var _last_vy_sign: int = 0

func _ready() -> void:
	if not target_path.is_empty():
		_target = get_node(target_path) as Node2D

func _physics_process(delta: float) -> void:
	if _target == null:
		return
	var target_pos := _target.global_position

	# 死区：目标相对摄像机偏移如果在死区内则不变 anchor
	var diff := target_pos - global_position
	var anchor := global_position
	if absf(diff.x) > dead_zone.x:
		anchor.x = target_pos.x - signf(diff.x) * dead_zone.x
	if absf(diff.y) > dead_zone.y:
		anchor.y = target_pos.y - signf(diff.y) * dead_zone.y

	# 垂直 lookahead
	var vy := _get_target_vy()
	var cur_sign := 0
	if absf(vy) > lookahead_vy_threshold:
		cur_sign = signf(vy) as int
	var now := Time.get_ticks_msec() / 1000.0
	if cur_sign != _last_vy_sign:
		_last_vy_sign = cur_sign
		_vy_sign_held_since = now
	if cur_sign != 0 and (now - _vy_sign_held_since) >= lookahead_stable_time:
		_lookahead_target_y = lookahead_offset_y * cur_sign
	else:
		_lookahead_target_y = 0.0
	anchor.y += _lookahead_target_y

	# 临界阻尼平滑（指数松弛）
	var alpha := 1.0 - expf(-delta / follow_time_constant)
	global_position = global_position.lerp(anchor, alpha)

func _get_target_vy() -> float:
	if _target is RigidBody2D:
		return (_target as RigidBody2D).linear_velocity.y
	return 0.0

# 预留接口（spec §4.8）
func shake(_intensity: float, _duration: float) -> void:
	pass

func set_target(node: Node2D) -> void:
	_target = node
```

- [ ] **Step 2: 在 test_level 替换 Camera2D 为 CameraFollow**

编辑 `test_level.tscn`：
- 删掉旧 Camera2D
- 新增 `CameraFollow`（脚本所在节点 → 直接用脚本作为类）
- 设 `target_path` 指向 Player3C 节点

- [ ] **Step 3: F6 验证**

Expected:
- 小幅移动不动摄像机（死区）
- 大幅移动摄像机平滑跟上（无突变）
- 持续下落或上升 > 0.3s → 摄像机偏移 ±64 px

- [ ] **Step 4: 提交**

```bash
git add Scripts/Prototypes/3C/camera_follow.gd Scenes/Prototypes/3C/test_level.tscn
git commit -m "feat(3c): camera with damped follow + dead zone + vertical lookahead"
```

---

## Task 10: Debug 面板（F1 切换、滑条、数值、JSON）

> 来源：[spec §4.9](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/3C-prototype-design.md)。**生命线** —— 没有它真机调参寸步难行。
>
> **决定：** 用原生 Godot Control（VBoxContainer + HSlider + Label），不引入 `imgui-godot` 依赖（spec §7 风险表的兜底选项）。理由：UI 项少（~15 个参数），原生足够；少一个三方依赖。

**Files:**
- Create: `Scenes/Prototypes/3C/debug_panel.tscn`
- Create: `Scripts/Prototypes/3C/debug_panel.gd`
- Modify: `Scenes/Prototypes/3C/test_level.tscn`（加入 debug_panel 实例）

- [ ] **Step 1: 写 debug_panel.gd**

```gdscript
# Scripts/Prototypes/3C/debug_panel.gd
# 实时滑条 + 数值显示 + JSON save/load。F1 切换可见。
# 来源：spec §4.9
class_name DebugPanel
extends CanvasLayer

@export var player_path: NodePath
@export var default_save_path: String = "user://3c_params.json"

var _player: Player3C
var _root: PanelContainer
var _value_labels: Dictionary = {}  # 实时数值显示
var _slider_bindings: Array = []    # [(prop_name, slider, label, min, max)]

const SLIDER_SPECS := [
	# (property, label, min, max)
	["v_max", "v_max (px/s)", 100.0, 1500.0],
	["f_max_ground", "F_max ground", 1000.0, 20000.0],
	["saturation_full", "saturation_full", 50.0, 1000.0],
	["f_active_brake", "F_active_brake", 0.0, 5000.0],
	["f_max_air", "F_max air", 500.0, 10000.0],
	["j_jump_initial", "Jump impulse", 200.0, 3000.0],
	["f_jump_hold", "Jump hold force", 0.0, 3000.0],
	["hold_window_max", "Hold window (s)", 0.0, 0.6],
	["gravity_y", "Gravity (px/s²)", 500.0, 6000.0],
	["coyote_time", "Coyote (s)", 0.0, 0.3],
	["jump_buffer_time", "Buffer (s)", 0.0, 0.3],
	["cos_theta_max", "cos_theta_max", 0.0, 1.0],
	["ground_state_buffer_frames", "Anti-debounce frames", 0.0, 5.0],
]

const READOUT_KEYS := [
	"position", "linear_velocity", "is_grounded", "current_state",
	"ground_normal_y", "net_force_this_frame",
]

func _ready() -> void:
	_player = get_node(player_path) as Player3C
	_build_ui()
	visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		visible = not visible

func _process(_dt: float) -> void:
	if not visible or _player == null:
		return
	for key in READOUT_KEYS:
		if _value_labels.has(key):
			(_value_labels[key] as Label).text = "%s: %s" % [key, _player.get(key)]

func _build_ui() -> void:
	_root = PanelContainer.new()
	_root.position = Vector2(900, 10)
	_root.custom_minimum_size = Vector2(360, 700)
	add_child(_root)

	var vbox := VBoxContainer.new()
	_root.add_child(vbox)

	# 标题
	var title := Label.new()
	title.text = "[F1] 3C Debug Panel"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	# 实时数值
	for key in READOUT_KEYS:
		var l := Label.new()
		l.text = "%s: ..." % key
		vbox.add_child(l)
		_value_labels[key] = l

	vbox.add_child(HSeparator.new())

	# 滑条
	for spec in SLIDER_SPECS:
		var prop: String = spec[0]
		var label_text: String = spec[1]
		var smin: float = spec[2]
		var smax: float = spec[3]

		var hb := HBoxContainer.new()
		vbox.add_child(hb)
		var lab := Label.new()
		lab.custom_minimum_size.x = 140
		hb.add_child(lab)
		var slider := HSlider.new()
		slider.min_value = smin
		slider.max_value = smax
		slider.step = (smax - smin) / 200.0
		slider.value = _player.get(prop)
		slider.custom_minimum_size.x = 180
		hb.add_child(slider)
		lab.text = "%s = %.2f" % [label_text, slider.value]
		slider.value_changed.connect(func(v: float) -> void:
			_player.set(prop, v)
			lab.text = "%s = %.2f" % [label_text, v]
		)
		_slider_bindings.append([prop, slider, lab, label_text])

	vbox.add_child(HSeparator.new())

	# 按钮：reset / save / load / toggle anti-debounce
	var btn_reset := Button.new()
	btn_reset.text = "Reset to defaults"
	btn_reset.pressed.connect(_on_reset)
	vbox.add_child(btn_reset)

	var btn_save := Button.new()
	btn_save.text = "Save to JSON"
	btn_save.pressed.connect(_on_save)
	vbox.add_child(btn_save)

	var btn_load := Button.new()
	btn_load.text = "Load from JSON"
	btn_load.pressed.connect(_on_load)
	vbox.add_child(btn_load)

func _on_reset() -> void:
	# 重新加载 player.gd 的默认值（用一个新实例读取）
	var fresh := preload("res://Scripts/Prototypes/3C/player.gd").new()
	for binding in _slider_bindings:
		var prop: String = binding[0]
		var slider: HSlider = binding[1]
		var lab: Label = binding[2]
		var label_text: String = binding[3]
		var v = fresh.get(prop)
		_player.set(prop, v)
		slider.value = v
		lab.text = "%s = %.2f" % [label_text, v]
	fresh.queue_free()

func _on_save() -> void:
	var data := {}
	for binding in _slider_bindings:
		var prop: String = binding[0]
		data[prop] = _player.get(prop)
	var f := FileAccess.open(default_save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	print("[DebugPanel] saved to %s" % default_save_path)

func _on_load() -> void:
	if not FileAccess.file_exists(default_save_path):
		push_warning("No saved params at %s" % default_save_path)
		return
	var f := FileAccess.open(default_save_path, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	for binding in _slider_bindings:
		var prop: String = binding[0]
		var slider: HSlider = binding[1]
		var lab: Label = binding[2]
		var label_text: String = binding[3]
		if data.has(prop):
			var v: float = data[prop]
			_player.set(prop, v)
			slider.value = v
			lab.text = "%s = %.2f" % [label_text, v]
```

- [ ] **Step 2: 写 debug_panel.tscn**

新建场景：根节点 `CanvasLayer`，附 `debug_panel.gd`，`layer = 100`，保存。

- [ ] **Step 3: 在 test_level 添加 DebugPanel 实例**

把 debug_panel 实例拖入 test_level，设 `player_path` 指向 Player3C。

- [ ] **Step 4: F6 验证**

Expected:
- 按 F1 切换面板显隐
- 实时数值随玩家动作变化（velocity, is_grounded, state）
- 拖动 `v_max` 滑条 → 实际跑动速度立刻变
- 拖动 `gravity_y` → 跳跃高度立刻变
- "Save to JSON" → `user://3c_params.json` 出现
- 改参数 → "Load" → 滑条 + 实际值回到保存值

- [ ] **Step 5: 提交**

```bash
git add Scripts/Prototypes/3C/debug_panel.gd Scenes/Prototypes/3C/debug_panel.tscn Scenes/Prototypes/3C/test_level.tscn
git commit -m "feat(3c): debug panel with live sliders, readouts, JSON save/load"
```

---

## Task 11: 完整测试关卡（§4.10 全部场景）

> 来源：[spec §4.10](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/3C-prototype-design.md)。
>
> **关键：** 多材质区段要用**不同 friction 的 StaticBody2D**（Box2D 实际摩擦 = sqrt(player.friction × ground.friction)，所以 ground.friction 直接 ≈ μ²；调参时按"想要的 μ → 设 ground = μ²/player.friction" 推算，player.friction 统一设 1.0）。

**Files:**
- Modify: `Scenes/Prototypes/3C/test_level.tscn`

- [ ] **Step 1: 设计场景布局**

参考布局（从左到右一字摆开，方便玩家走完整路线）：

```
位置(x)    内容                       宽度  备注
0-600      平地走廊 (μ=0.10 默认)        — 启动/滑行测试
600-1000   冰区 (μ≈0.02)             400   低摩擦失控感
1000-1400  泥区 (μ≈0.3)              400   高摩擦急停
1400-1800  台阶序列（5 级，每级高 60px）—  Capsule 弹跳学习（ADR-0005）
1800-2000  缺口 200 px                —   原地跳跨不过测试
2000-2400  助跑长跑道                 400   助跑跳验证
2400-2600  缺口 200 px                —   ADR-0004 助跑跳能跨
2600-2800  小凸起（高 0.08 m=8 px）   —   物理可干预性测试
2800-3200  多高度平台（200/350/500px）—   跳跃高度精度
3200-3400  紧密悬崖边                 —   Coyote 测试
3400-3800  下降式平台序列              —   Buffer 测试
3800-4000  墙                        —   撞墙不卡
4000-4400  dynamic box（RigidBody2D） —   物理交互（v1 末期）
```

**关键参数：** 
- ground 默认 friction 设 0.10（player.friction=1.0 → 有效 μ ≈ sqrt(0.10)=0.316，比 spec 略偏；如果手感偏粘，统一调）。**或者**把 player.friction 设到 0.10、各 surface 设需要的 μ —— 选其一保持一致，**建议 player.friction = 1.0，地面就是 effective μ²**，调试更直接。
- 冰：ground.friction = 0.0004（→ effective μ ≈ 0.02）
- 泥：ground.friction = 0.09（→ effective μ ≈ 0.3）

> **注意：** 编辑器里 PhysicsMaterial.friction 可调；不同段就是不同 StaticBody2D，各自带 physics_material_override。

- [ ] **Step 2: 在编辑器里搭场景**

按上表逐段加 StaticBody2D + CollisionShape2D（RectangleShape2D）+ PhysicsMaterial。Player3C 起点放 (100, 500)。

**视觉辅助：** 每段加一个 ColorRect 子节点不同颜色（冰=蓝、泥=棕、台阶=灰、缺口前=黄）方便分辨。

dynamic box：RigidBody2D + RectangleShape2D(60×60) + 默认参数，放在最右段地面上。

- [ ] **Step 3: F6 走完整关卡**

按 spec §4.10 + §6 的对应验证项逐一感受。

- [ ] **Step 4: 提交**

```bash
git add Scenes/Prototypes/3C/test_level.tscn
git commit -m "feat(3c): full test level covering §4.10 scenarios"
```

---

## Task 12: §6 验证标准过一遍 + 参数调优

> 来源：[spec §6](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/3C-prototype-design.md) 验证清单。**这是真正的"完成"节点** —— 之前所有任务都是写代码，这一步是用代码。

**Files:**
- Modify: `Scripts/Prototypes/3C/player.gd`（参数调整，根据真机感受）
- Create: `docs/superpowers/plans/2026-05-24-3c-prototype-v1-validation.md`（验证记录）

- [ ] **Step 1: 逐条执行 §6 验证标准**

对每一条记录通过 / 不通过 + 备注。逐条原文：

1. 所有 §4.9 参数都能在 runtime 滑条调
2. 在测试关卡能制造"边缘 Coyote 起跳"和"提前 Buffer 起跳"的成功 case
3. 调整地面 μ 能明显改变滑行距离（冰 vs 泥 vs 默认 显著不同）
4. 走过台阶序列能直接看到 Capsule 弹跳症状：接地态闪烁 + 水平减速 + 视觉颠簸 + debug 面板法线变化
5. 开启 1 帧防抖后，弹跳现象的一部分症状（接地态闪烁）被掩盖，但水平减速仍在
6. 助跑跳能跨过比原地跳明显更宽的缺口
7. 把一个 dynamic box 放进关卡 → 跳上去 → 角色能站稳，box 会被踩动少量
8. 推一下 dynamic box → 角色受反作用力被微微减速
9. 摄像机平移不眩晕、不卡顿
10. 至少给一个朋友试玩，能给出"挺顺手"或更高评价（可后做）

- [ ] **Step 2: 把验证结果写进 validation.md**

```markdown
# 3C v1 验证记录 — 2026-05-24

## §6 验证标准结果

| # | 标准 | 通过? | 备注 |
|---|---|---|---|
| 1 | 滑条全可调 | | |
| 2 | Coyote/Buffer 成功制造 | | |
| 3 | 三种 μ 差异显著 | | |
| 4 | Capsule 弹跳可见 | | |
| 5 | 防抖差异可见 | | |
| 6 | 助跑跳 vs 原地跳 | | |
| 7 | dynamic box 踩稳 | | |
| 8 | 推 box 角色被推 | | |
| 9 | 摄像机平滑 | | |
| 10 | 朋友试玩 | | |

## 调整后的参数（如有偏离 spec 默认值）

（贴最终 `user://3c_params.json` 内容）

## 发现的问题 / 未来 ADR 候选

（如 Capsule 弹跳真的太严重 → 是否触发 ADR-0007 切换 Box+脚趾？  
如 apex 飘感不足 → 是否启动 ADR-0003 的辅助力？等）
```

- [ ] **Step 3: 把 Save 按钮存出的最终参数 JSON 也提交一份**

```bash
cp $env:APPDATA/Godot/app_userdata/2D\ Platformer\ -\ Starter\ Kit/3c_params.json docs/superpowers/plans/3c_params_v1_tuned.json
# 路径在 Windows 上是 %APPDATA%\Godot\app_userdata\<project name>\3c_params.json
```

- [ ] **Step 4: 提交验证记录**

```bash
git add docs/superpowers/plans/2026-05-24-3c-prototype-v1-validation.md docs/superpowers/plans/3c_params_v1_tuned.json
git commit -m "docs(3c): v1 validation results + tuned parameters"
```

---

## Task 13: 收尾 — 主菜单入口（可选）

> 决定项：要不要把 3C 原型挂进现有 `demo_menu`？
> - 如果近期还要继续 box2d demo 工作 → 加菜单按钮，互不干扰
> - 如果 3C 是主线，box2d demos 是 legacy → 改 `project.godot` 的 `run/main_scene` 直接进 3C
>
> **本 Task 默认走第一条**（保守）。

**Files:**
- Modify: `Scenes/Demos/demo_menu.tscn`（加按钮）
- Modify: `Scripts/Demos/demo_menu.gd`（加条目）

- [ ] **Step 1: 在 demo_menu.gd 的条目字典加 "3C Prototype"**

读现有 `Scripts/Demos/demo_menu.gd`，找到关卡列表字典，按现有模式追加：

```gdscript
# 在 LEVELS 字典末尾或合适位置加
11: {"name": "3C 原型", "path": "res://Scenes/Prototypes/3C/test_level.tscn", "description": "角色控制 + 摄像机 + Debug 面板"},
```

> 编号 11 因为 spec §125 表里 box2d demos 已占到 10。

- [ ] **Step 2: 在 demo_menu.tscn 加对应按钮**

如果菜单是按字典自动生成的（demo_menu.gd 里循环），无需改 .tscn；否则手加 Button。

- [ ] **Step 3: F6 主菜单 → 点 "3C 原型" → 进入 test_level**

Expected: 场景切换正常，3C 原型加载。

- [ ] **Step 4: 提交**

```bash
git add Scenes/Demos/demo_menu.tscn Scripts/Demos/demo_menu.gd
git commit -m "feat(menu): add 3C prototype entry"
```

---

## 完成准则

完成本计划 = 所有 13 个 Task 提交 + Task 12 的 validation.md 里每条都有结论（通过 / 不通过的话说明为什么，触发后续 ADR 候选）。

完成后回 [项目总览 §6 路线图](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/项目总览.md) 把"原型 1: 3C"打勾，并在 spec §8 把"下一步" 1-4 项更新为已完成。
