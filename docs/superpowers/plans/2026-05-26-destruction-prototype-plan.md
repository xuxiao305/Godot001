# 体块化破坏框架 v1 — 实施计划（Rapier2D 版）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Godot 4 + Rapier2D 上实现 Block + Constraint 破坏沙盒，编辑器手摆 cube → GridStructure 运行时自动建约束 → 武器系统 Effect 驱动破坏 → 伤害传递 + ImpactWatcher 涌现链式塌方。

**Architecture:** 单例 `DestructionPipeline` 集中调度拓扑变更（damage_events + block_destroy + constraint_destroy 队列），帧末统一批处理。Block（RigidBody2D 子类）自带血量 + take_damage + 伤害传递；Constraint（RefCounted）封装单根 PinJoint2D（angular_limit=0） + 血量。破坏源走已有武器系统的 RadialDamage/RadialBlast（单向依赖）。

**Tech Stack:** Godot 4.x + Rapier2D（godot-rapier-physics GDExtension）；GDScript；纯函数测试沿用 `test_engine_torque.gd` 风格（`_ready` 跑断言 → `print PASS` → `get_tree().quit()`）。

**验证级别（参 memory `feedback_verify_each_edit`）：**
- 纯算法 task（pipeline 队列、damage 传递计算、ImpactWatcher 阈值）：**第 4 层（自动化测试）**
- 涉及 Rapier 拓扑、PinJoint 装配、GridStructure 场景的 task：**第 5 层（人工 F6 签字）必需**
- 每个 Implementer subagent prompt 必须显式带上"先按上述层级跑验证，不通过不交付"

**相关文档：**
- Spec：[2026-05-24-destruction-prototype-design.md](../../2026-05-24-destruction-prototype-design.md)
- 术语：[CONTEXT.md](../../CONTEXT.md)
- 跨 spec 契约：[ADR-0007](../../adr/0007-effect-dual-channel.md)

---

## 文件结构

模块根目录 `Scripts/Prototypes/Destruction/`。场景根目录 `Scenes/Prototypes/Destruction/`。

**已有文件（需修改）：**
- `Scripts/Prototypes/Destruction/destruction_pipeline.gd` — 删 debris 队列，加伤害派发
- `Scripts/Prototypes/Destruction/tests/test_destruction_pipeline.gd` — 删 debris 测试段

**Create — Scripts:**
- `Scripts/Prototypes/Destruction/block.gd` — class_name Block，RigidBody2D 子类（血量、take_damage、伤害传递、销毁入队）
- `Scripts/Prototypes/Destruction/constraint.gd` — class_name Constraint，RefCounted（封装 PinJoint + 血量 + take_damage）
- `Scripts/Prototypes/Destruction/impact_watcher.gd` — 系统：_integrate_forces 取 contact impulse → 转 damage_events
- `Scripts/Prototypes/Destruction/block_factory.gd` — 工厂：创建 Block + 配物理参数 + 碰撞形状
- `Scripts/Prototypes/Destruction/grid_structure.gd` — Prefab 脚本：扫描子节点 RigidBody2D → 邻居检测 → 建 PinJoint + Constraint
- `Scripts/Prototypes/Destruction/constraint_visualizer.gd` — 可视化：_draw() 根据约束血量画彩色连线
- `Scripts/Prototypes/Destruction/debug_panel.gd` — CanvasLayer：FPS / Block 数 / Constraint 数 / 帧销毁数 + 两个开关
- `Scripts/Prototypes/Destruction/destruction_demo.gd` — 主场景控制器（pipeline 装配 + 帧末批处理循环）

**Create — Tests:**
- `Scripts/Prototypes/Destruction/tests/test_block_damage.gd` — 重写（DBlock → Block，ratio 改名）
- `Scripts/Prototypes/Destruction/tests/test_damage_propagation.gd` — 伤害传递
- `Scripts/Prototypes/Destruction/tests/test_impact_watcher.gd` — impact_to_damage 纯函数

**Create — Scenes:**
- `Scenes/Prototypes/Destruction/destruction_demo.tscn` — 主场景（Camera2D + Ground + LevelHolder + DebugPanel + 武器系统集成入口）
- `Scenes/Prototypes/Destruction/grid_structure.tscn` — GridStructure PackedScene Prefab
- `Scenes/Prototypes/Destruction/scenes/brick_wall.tscn` — GridStructure 实例：10×10 砖墙
- `Scenes/Prototypes/Destruction/scenes/arch.tscn` — GridStructure 实例：拱门
- `Scenes/Prototypes/Destruction/scenes/house.tscn` — GridStructure 实例：三层小屋

---

## Task 0: 清理 DestructionPipeline（删 debris 队列 + 加 damage dispatch）

**Files:**
- Modify: `Scripts/Prototypes/Destruction/destruction_pipeline.gd`
- Modify: `Scripts/Prototypes/Destruction/tests/test_destruction_pipeline.gd`

**验证级别：** 第 4 层（自动化测试）

- [ ] **Step 0.1: 更新测试**

Edit `Scripts/Prototypes/Destruction/tests/test_destruction_pipeline.gd` — 删 debris_spawn 测试段，加 damage dispatch 测试：

```gdscript
# Scripts/Prototypes/Destruction/tests/test_destruction_pipeline.gd
# 纯算法测试 —— pipeline 的入队 / drain / 幂等性 / damage dispatch。
extends Node

const DestructionPipeline := preload("res://Scripts/Prototypes/Destruction/destruction_pipeline.gd")

func _ready() -> void:
	var p := DestructionPipeline.new()

	# 1) 入队 + 计数
	p.queue_damage_event({"target": "block_a", "amount": 10.0, "point": Vector2.ZERO, "source": "test"})
	p.queue_damage_event({"target": "block_b", "amount": 5.0, "point": Vector2.ZERO, "source": "test"})
	assert(p.damage_events.size() == 2, "damage_events 应有 2 项")

	# 2) 销毁队列幂等（同一对象重复入队只销毁一次）
	var fake_block := RefCounted.new()
	p.queue_block_destroy(fake_block)
	p.queue_block_destroy(fake_block)
	assert(p.block_destroy_queue.size() == 1, "重复入队应被去重")

	# 3) drain_damage_events 清空 + 返回有序快照
	var snap := p.drain_damage_events()
	assert(snap.size() == 2, "drain 应返回入队顺序 2 项")
	assert(p.damage_events.is_empty(), "drain 后队列应为空")

	# 4) drain_block_destroys 清空
	var snap2 := p.drain_block_destroys()
	assert(snap2.size() == 1, "drain block 应返回 1 项")
	assert(p.block_destroy_queue.is_empty(), "drain 后应为空")

	# 5) constraint_destroy 队列幂等 + drain
	var fake_constraint := RefCounted.new()
	p.queue_constraint_destroy(fake_constraint)
	assert(p.drain_constraint_destroys().size() == 1, "constraint 队列幂等 + drain")

	# 6) dispatch_damage_events 调用 take_damage（用假受体）
	var dummy := RefCounted.new()
	var received := []
	dummy.take_damage = func(amount, point, source): received.append(amount)
	p.queue_damage_event({"target": dummy, "amount": 15.0, "point": Vector2.ZERO, "source": "test"})
	p.dispatch_damage_events()
	assert(received.size() == 1, "dispatch 应调一次 take_damage")
	assert(absf(received[0] - 15.0) < 0.001, "dispatch 传入正确 amount, got %f" % received[0])
	# dispatch 后队列为空
	assert(p.damage_events.is_empty(), "dispatch 后 damage_events 应为空")

	print("[TEST destruction_pipeline] ALL PASS")
	get_tree().quit()
```

- [ ] **Step 0.2: 运行测试确认失败**

把 `_test_runner.tscn` 脚本指向 `test_destruction_pipeline.gd`。F6 运行。
期望：`Invalid call. Nonexistent function 'dispatch_damage_events'`。

- [ ] **Step 0.3: 改 pipeline 实现**

Edit `Scripts/Prototypes/Destruction/destruction_pipeline.gd`：

```gdscript
# Scripts/Prototypes/Destruction/destruction_pipeline.gd
# 单例：拓扑变更批处理。
# spec §4.4：所有 body/joint 销毁只能在 _physics_process 末尾、Rapier 完成本帧解算之后批量执行。
# 不在 contact callback 或碰撞回调中途直接 queue_free()。
#
# 3 个队列：
#  - damage_events             —— { target, amount, point, source }
#  - constraint_destroy_queue  —— Dictionary{instance_id: Constraint}
#  - block_destroy_queue       —— Dictionary{instance_id: Block}
#
# 销毁队列用 Dictionary 去重，保证幂等。
class_name DestructionPipeline
extends RefCounted

var damage_events: Array = []
var block_destroy_queue: Dictionary = {}
var constraint_destroy_queue: Dictionary = {}

func queue_damage_event(ev: Dictionary) -> void:
	damage_events.append(ev)

func queue_block_destroy(block) -> void:
	block_destroy_queue[block.get_instance_id()] = block

func queue_constraint_destroy(c) -> void:
	constraint_destroy_queue[c.get_instance_id()] = c

func drain_damage_events() -> Array:
	var snap := damage_events
	damage_events = []
	return snap

func drain_block_destroys() -> Array:
	var snap := block_destroy_queue.values()
	block_destroy_queue = {}
	return snap

func drain_constraint_destroys() -> Array:
	var snap := constraint_destroy_queue.values()
	constraint_destroy_queue = {}
	return snap

# 派发伤害事件：遍历 damage_events，对每个 target 调 take_damage。
# 约束：target 必须 1) 仍有效（is_instance_valid）且 2) 有 take_damage 方法。
# 已在 destroy queue 的 target 仍会被派发（take_damage 内部的 _queued_for_destroy guard 处理幂等）。
func dispatch_damage_events() -> void:
	for ev in drain_damage_events():
		var target = ev.target
		if is_instance_valid(target) and target.has_method("take_damage"):
			target.take_damage(ev.amount, ev.point, ev.source)
```

- [ ] **Step 0.4: 运行测试确认通过**

F6 → 期望输出 `[TEST destruction_pipeline] ALL PASS`。

- [ ] **Step 0.5: 提交**

```bash
git add Scripts/Prototypes/Destruction/destruction_pipeline.gd Scripts/Prototypes/Destruction/tests/test_destruction_pipeline.gd
git commit -m "refactor(destruction): remove debris queue, add dispatch_damage_events

Pipeline now handles damage dispatch internally instead of requiring a
separate damage_dispatcher module. Queue count reduced from 4 to 3.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.4"
```

---

## Task 1: Block 类 + 单测

**Files:**
- Create: `Scripts/Prototypes/Destruction/block.gd`
- Create: `Scripts/Prototypes/Destruction/tests/test_block_damage.gd`（覆盖旧的）

**验证级别：** 第 4 层（纯算法，不接 Rapier）

- [ ] **Step 1.1: 写失败测试**

```gdscript
# Scripts/Prototypes/Destruction/tests/test_block_damage.gd
# 验 Block 的血量、take_damage、销毁入队行为。不验 Constraint 传递。
extends Node

const Block := preload("res://Scripts/Prototypes/Destruction/block.gd")
const DestructionPipeline := preload("res://Scripts/Prototypes/Destruction/destruction_pipeline.gd")

func _ready() -> void:
	var pipeline := DestructionPipeline.new()

	# 1) 初始血量
	var b := Block.new()
	b.pipeline = pipeline
	b.initial_health = 100.0
	b.health = 100.0
	assert(b.health == 100.0, "初始血量 100")

	# 2) take_damage 扣血
	b.take_damage(30.0, Vector2.ZERO, "test")
	assert(b.health == 70.0, "扣 30 后血量 70, got %f" % b.health)

	# 3) 血量未归零 → 不入销毁队列
	assert(pipeline.block_destroy_queue.is_empty(), "血量 > 0 不入销毁队列")

	# 4) 致命伤 → 入队，且只入一次
	b.take_damage(80.0, Vector2.ZERO, "test")
	assert(b.health <= 0.0, "致命伤后 health <= 0")
	assert(pipeline.block_destroy_queue.size() == 1, "入销毁队列")
	b.take_damage(5.0, Vector2.ZERO, "test")  # 死后再打
	assert(pipeline.block_destroy_queue.size() == 1, "死后再打不会重复入队")

	# 5) damage_propagation_ratio 默认 0.3
	assert(absf(b.damage_propagation_ratio - 0.3) < 0.001, "默认传递比 0.3")

	# 6) connected_constraints 默认空数组
	assert(b.connected_constraints.is_empty(), "初始无连接约束")

	print("[TEST block_damage] ALL PASS")
	get_tree().quit()
```

- [ ] **Step 1.2: 运行测试确认失败**

把 `_test_runner_block.tscn` 脚本指向 `test_block_damage.gd`（若 runner 不存在则新建一个 `_test_runner_block.tscn`：根 Node + 挂此脚本）。F6。
期望：`Script does not inherit from Node` 或 preload 失败（block.gd 不存在）。

- [ ] **Step 1.3: 写 Block 最小实现**

Create `Scripts/Prototypes/Destruction/block.gd`：

```gdscript
# Scripts/Prototypes/Destruction/block.gd
# 体块 —— RigidBody2D 派生。spec §4.1。
#
# Body 参数（mass / friction / shape / damping）由 BlockFactory 配置，
# 本脚本只管数据 + 行为。
#
# take_damage 是统一伤害语言（ADR-0007）的实现。
# 外部（武器 DamageField / ImpactWatcher）都走这一个接口。
# 伤害传递：扣自己血后按 damage_propagation_ratio 传给所有相连 Constraint。
class_name Block
extends RigidBody2D

signal block_destroyed(position: Vector2)

@export var initial_health: float = 100.0
@export var damage_propagation_ratio: float = 0.3

var health: float = 100.0
var pipeline: DestructionPipeline = null
var connected_constraints: Array = []  # Constraint 对象

var _queued_for_destroy: bool = false

func _ready() -> void:
	health = initial_health

func take_damage(amount: float, point: Vector2, source) -> void:
	if _queued_for_destroy:
		return
	health -= amount
	# 伤害传递到所有相连 Constraint
	for c in connected_constraints:
		c.take_damage(amount * damage_propagation_ratio, point, source)
	if health <= 0.0:
		_queued_for_destroy = true
		if pipeline != null:
			pipeline.queue_block_destroy(self)
```

- [ ] **Step 1.4: 运行测试确认通过**

F6 → 期望 `[TEST block_damage] ALL PASS`。

注意：Block 继承 RigidBody2D，`new()` 创建的实例在测试中不挂入场景树，但不影响 take_damage（纯数据操作，不涉及 physics）。

- [ ] **Step 1.5: 提交**

```bash
git add Scripts/Prototypes/Destruction/block.gd Scripts/Prototypes/Destruction/tests/test_block_damage.gd
git commit -m "feat(destruction): add Block class with take_damage + tests

RigidBody2D-derived Block with health, damage_propagation_ratio,
and DestructionPipeline queue integration. Damage propagation loop
present but Constraint wiring deferred to Task 3.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.1, ADR-0007"
```

---

## Task 2: Constraint 类

**Files:**
- Create: `Scripts/Prototypes/Destruction/constraint.gd`

**验证级别：** 第 5 层（涉及 PinJoint2D 创建 + node_a/node_b 挂入场景树，必须 F6 smoke）

- [ ] **Step 2.1: 写 Constraint 实现**

Create `Scripts/Prototypes/Destruction/constraint.gd`：

```gdscript
# Scripts/Prototypes/Destruction/constraint.gd
# Constraint —— 一对相邻 Block 之间的约束封装。spec §4.2。
#
# 实现：单根 PinJoint2D + angular_limit_lower=angular_limit_upper=0 等效 weld。
# Rapier2D 原生支持 angular_limit，无需 godot-box2d 的 2× PinJoint 方案。
#
# 断裂路径（v1）：仅伤害路径。血量归零 → 入 constraint_destroy_queue → 帧末销毁。
# （v2 加应力路径：每帧检测 PinJoint 内部应力超 stress_threshold。）
class_name Constraint
extends RefCounted

var pin: PinJoint2D
var block_a: Block
var block_b: Block

var initial_health: float = 50.0
var health: float = 50.0
var pipeline: DestructionPipeline = null

var _queued_for_destroy: bool = false

# 装配：在两 block 共享边中点创建 PinJoint2D，angular_limit 锁死相对旋转。
# shared_center = 共享边中点世界坐标。
static func create(
	a: Block, b: Block,
	shared_center: Vector2,
	parent: Node
) -> Constraint:
	var c := Constraint.new()
	c.block_a = a
	c.block_b = b
	c.health = c.initial_health

	var pin := PinJoint2D.new()
	pin.global_position = shared_center
	pin.disable_collision = true
	pin.angular_limit_enabled = true
	pin.angular_limit_lower = 0.0
	pin.angular_limit_upper = 0.0
	parent.add_child(pin)
	# node_a / node_b 必须在 add_child 之后设（NodePath 解析依赖 in_tree）
	pin.node_a = a.get_path()
	pin.node_b = b.get_path()
	c.pin = pin
	return c

func take_damage(amount: float, point: Vector2, source) -> void:
	if _queued_for_destroy:
		return
	health -= amount
	if health <= 0.0:
		_queued_for_destroy = true
		if pipeline != null:
			pipeline.queue_constraint_destroy(self)

# 由 DestructionPipeline 帧末调用。
func destroy() -> void:
	if _queued_for_destroy:
		if is_instance_valid(pin):
			pin.queue_free()
		_queued_for_destroy = false  # 防重入
```

- [ ] **Step 2.2: Godot Editor 验证 parse**

在 Godot Editor 中打开项目，确认 `constraint.gd` 无 parse error（Editor 输出面板无红色报错）。

- [ ] **Step 2.3: 提交**

```bash
git add Scripts/Prototypes/Destruction/constraint.gd
git commit -m "feat(destruction): add Constraint class with single PinJoint

Single PinJoint2D with angular_limit=0 replaces the old godot-box2d
2x PinJoint workaround. Rapier2D natively supports angular_limit.
Damage-path breakage: health -> 0 queues constraint_destroy.
Stress path deferred to v2.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.2"
```

---

## Task 3: 伤害传递 + 单测

**Files:**
- Create: `Scripts/Prototypes/Destruction/tests/test_damage_propagation.gd`

**验证级别：** 第 4 层（纯算法，不接 PinJoint）

- [ ] **Step 3.1: 写测试**

```gdscript
# Scripts/Prototypes/Destruction/tests/test_damage_propagation.gd
# 验 Block.take_damage 内的伤害传递：按 damage_propagation_ratio 传递给所有相连 Constraint。
# 也验 Constraint.take_damage 致命伤入队。
extends Node

const Block := preload("res://Scripts/Prototypes/Destruction/block.gd")
const Constraint := preload("res://Scripts/Prototypes/Destruction/constraint.gd")
const DestructionPipeline := preload("res://Scripts/Prototypes/Destruction/destruction_pipeline.gd")

# 用伪 Constraint 收传递量 —— 不实例化 PinJoint2D。
class FakeConstraint extends RefCounted:
	var received_damage: float = 0.0
	var received_count: int = 0
	func take_damage(amount: float, point: Vector2, source) -> void:
		received_damage += amount
		received_count += 1

func _ready() -> void:
	var pipeline := DestructionPipeline.new()

	# Block 受 100 → 传递 100*0.3 = 30 到每条相连 Constraint
	var b := Block.new()
	b.pipeline = pipeline
	b.initial_health = 200.0
	b.health = 200.0
	b.damage_propagation_ratio = 0.3
	var c1 := FakeConstraint.new()
	var c2 := FakeConstraint.new()
	b.connected_constraints = [c1, c2]
	b.take_damage(100.0, Vector2.ZERO, "test")
	assert(absf(c1.received_damage - 30.0) < 0.001, "c1 应收 30, got %f" % c1.received_damage)
	assert(absf(c2.received_damage - 30.0) < 0.001, "c2 应收 30, got %f" % c2.received_damage)
	assert(c1.received_count == 1, "c1 应只被调一次")

	# Block 致死后再 take_damage 不再传递（early return）
	b.take_damage(200.0, Vector2.ZERO, "test")  # health <= 0，入队
	var prev := c1.received_damage  # = 30 + 60 = 90
	b.take_damage(50.0, Vector2.ZERO, "test")  # 死后再打
	assert(absf(c1.received_damage - prev) < 0.001, "Block 已死，不应再传递")

	# Constraint take_damage 致死入队
	var real_c := Constraint.new()
	real_c.pipeline = pipeline
	real_c.initial_health = 50.0
	real_c.health = 50.0
	real_c.take_damage(60.0, Vector2.ZERO, "test")
	assert(pipeline.constraint_destroy_queue.size() == 1, "致死应入 constraint_destroy_queue")

	print("[TEST damage_propagation] ALL PASS")
	get_tree().quit()
```

- [ ] **Step 3.2: 运行测试确认通过**

F6（用 `_test_runner_block.tscn` 挂本脚本）→ 期望 `[TEST damage_propagation] ALL PASS`。
block.gd 已含 for-loop 传递，本测试应直接通过。

- [ ] **Step 3.3: 提交**

```bash
git add Scripts/Prototypes/Destruction/tests/test_damage_propagation.gd
git commit -m "test(destruction): damage propagation + Constraint health

Covers Block.take_damage propagating to Constraints by ratio,
idempotent post-death behavior, and Constraint health-path queueing.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.1, ADR-0007"
```

---

## Task 4: BlockFactory

**Files:**
- Create: `Scripts/Prototypes/Destruction/block_factory.gd`

**验证级别：** 第 5 层（需 F6 看到 Block 作为 RigidBody2D 在地面上受重力落下、碰撞正常）

- [ ] **Step 4.1: 写 BlockFactory**

```gdscript
# Scripts/Prototypes/Destruction/block_factory.gd
# 工厂：创建 Block + 配 Body 参数 + 加 CollisionShape2D。
# 未来接对象池仅改本类内部，消费者（GridStructure）签名不变。
class_name BlockFactory
extends RefCounted

const Block := preload("res://Scripts/Prototypes/Destruction/block.gd")

# block_size 像素
static func create(
	pipeline: DestructionPipeline,
	pos: Vector2,
	block_size: float,
	initial_health: float = 100.0
) -> Block:
	var b := Block.new()
	b.global_position = pos
	b.initial_health = initial_health
	b.pipeline = pipeline
	# Body 参数（spec §4.1）
	b.freeze = false
	b.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC  # 仅未 freeze 时生效；freeze=true 才冻结
	b.mass = 0.00625  # density 1.0 @ 25px → mass ≈ 0.00625
	var mat := PhysicsMaterial.new()
	mat.friction = 0.6
	mat.bounce = 0.05
	b.physics_material_override = mat
	b.linear_damp = 0.05
	b.angular_damp = 0.1
	b.contact_monitor = true
	b.max_contacts_reported = 8  # ImpactWatcher 需要
	# Collision shape（正方形）
	var shape := RectangleShape2D.new()
	shape.size = Vector2(block_size, block_size)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	b.add_child(cs)
	# collision layers 由 GridStructure 在 add_child 后统一设（或在此设默认值）
	b.collision_layer = 4   # layer 3 = block（按项目实际 layer bit 调整）
	b.collision_mask = 4 | 1  # block + world（layer 1 = world）
	return b
```

> **单位注意**：mass 用 Godot 默认单位（质量·像素²）。`mass = density × area = 1.0 × 625 = 625`——不对。Rapier 用 SI 单位还是像素单位取决于 godot-rapier-physics 的配置。初值 `mass = 0.00625` 是一个试算值，Task 4 验证时调整到块在地面上有明显重量感即可。若不用 mass 直接 export，可改设 `gravity_scale` = 1。（**实现期 F6 确认后锁定初值。**）

- [ ] **Step 4.2: F6 smoke — 创建单个 Block 落在地面上**

创建临时场景 `Scenes/Prototypes/Destruction/spike/spike_block_factory.tscn`：
- 根 Node2D + 脚本 `spike_block_factory.gd`
- StaticBody2D 地面（CollisionShape2D 长条）→ y=0
- `_ready()` 中调 `BlockFactory.create()` 在 (0, -200) 创建一块，add_child

运行 F6：期望 Block 自由落下，碰到地面停住。无穿透、无飞出。

- [ ] **Step 4.3: 提交**

```bash
git add Scripts/Prototypes/Destruction/block_factory.gd
git commit -m "feat(destruction): add BlockFactory with physics params

Creates Block RigidBody2D with collision shape, density, friction,
restitution, and damping per spec §4.1. F6 smoke verified single
block falls under gravity and rests on ground.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.1"
```

---

## Task 5: ImpactWatcher + 单测

**Files:**
- Create: `Scripts/Prototypes/Destruction/impact_watcher.gd`
- Create: `Scripts/Prototypes/Destruction/tests/test_impact_watcher.gd`

**验证级别：** 算法部分第 4 层；触发部分第 5 层（在 Task 8 集成后 F6）

- [ ] **Step 5.1: 写失败测试（纯函数）**

```gdscript
# Scripts/Prototypes/Destruction/tests/test_impact_watcher.gd
extends Node
const ImpactWatcher := preload("res://Scripts/Prototypes/Destruction/impact_watcher.gd")

func _ready() -> void:
	# impact_to_damage(normal_impulse, threshold, coefficient)
	# J=2 阈值=2 → (2-2)*10 = 0（临界）
	assert(absf(ImpactWatcher.impact_to_damage(2.0, 2.0, 10.0) - 0.0) < 0.001,
		"临界冲击应给 0 伤害")
	# J=1 → 低于阈值不伤
	assert(ImpactWatcher.impact_to_damage(1.0, 2.0, 10.0) == 0.0,
		"低于阈值应给 0")
	# J=5 → (5-2)*10 = 30
	assert(absf(ImpactWatcher.impact_to_damage(5.0, 2.0, 10.0) - 30.0) < 0.001,
		"J=5, threshold 2, coef 10 → 30, got %f" % ImpactWatcher.impact_to_damage(5.0, 2.0, 10.0))
	# 负 J 防御
	assert(ImpactWatcher.impact_to_damage(-3.0, 2.0, 10.0) == 0.0, "负冲量应给 0")
	# 大 J 量级检查: J=100 → (100-2)*10 = 980
	assert(absf(ImpactWatcher.impact_to_damage(100.0, 2.0, 10.0) - 980.0) < 0.001,
		"J=100 → damage 980, got %f" % ImpactWatcher.impact_to_damage(100.0, 2.0, 10.0))

	print("[TEST impact_watcher] ALL PASS")
	get_tree().quit()
```

- [ ] **Step 5.2: 写实现**

```gdscript
# Scripts/Prototypes/Destruction/impact_watcher.gd
# 系统：监听接触冲量 → 超阈值转伤害事件入 damage_events 队列。
# spec §4.3：不在 contact callback 直接调 take_damage（避免物理解算中途改拓扑）。
#
# 实际接触检测由 Block._integrate_forces 完成（取 get_contact_impulse），
# 本类只负责换算 + 入队。
class_name ImpactWatcher
extends RefCounted

@export var impact_threshold: float = 2.0
@export var impact_coefficient: float = 10.0

var pipeline: DestructionPipeline = null
var enabled: bool = true

# 纯函数：冲量 → 伤害量
static func impact_to_damage(normal_impulse: float, threshold: float, coefficient: float) -> float:
	if normal_impulse <= threshold:
		return 0.0
	return (normal_impulse - threshold) * coefficient

# 由 Block._integrate_forces 调用。一次接触只调一次（instance_id 比较防双计数在 Block 侧完成）。
func on_contact(block_a: Block, block_b: Block, normal_impulse: float, point: Vector2) -> void:
	if not enabled:
		return
	var dmg := impact_to_damage(normal_impulse, impact_threshold, impact_coefficient)
	if dmg <= 0.0:
		return
	if pipeline == null:
		return
	pipeline.queue_damage_event({"target": block_a, "amount": dmg, "point": point, "source": "impact"})
	pipeline.queue_damage_event({"target": block_b, "amount": dmg, "point": point, "source": "impact"})
```

- [ ] **Step 5.3: 跑测试确认通过**

F6 → 期望 `[TEST impact_watcher] ALL PASS`。

- [ ] **Step 5.4: Block._integrate_forces 接 ImpactWatcher**

Edit `Scripts/Prototypes/Destruction/block.gd` —— 在文件末尾加：

```gdscript
# ImpactWatcher 引用（由 BlockFactory / GridStructure 注入）
var impact_watcher: ImpactWatcher = null

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if impact_watcher == null:
		return
	if not impact_watcher.enabled:
		return
	for i in state.get_contact_count():
		var other = state.get_contact_collider_object(i)
		if not (other is Block):
			continue
		# 防双计数：只处理 self.instance_id < other.instance_id 的对
		if self.get_instance_id() >= other.get_instance_id():
			continue
		var impulse: Vector2 = state.get_contact_impulse(i)
		var j_normal: float = impulse.length()
		var local_pos := state.get_contact_local_position(i)
		impact_watcher.on_contact(self, other as Block, j_normal, local_pos)
```

Update `BlockFactory.create` 签名加 `impact: ImpactWatcher` 参数并在最后注入：

```gdscript
static func create(
	pipeline: DestructionPipeline,
	pos: Vector2,
	block_size: float,
	impact: ImpactWatcher,
	initial_health: float = 100.0
) -> Block:
	...
	b.impact_watcher = impact
	...
```

- [ ] **Step 5.5: 提交**

```bash
git add Scripts/Prototypes/Destruction/impact_watcher.gd Scripts/Prototypes/Destruction/tests/test_impact_watcher.gd Scripts/Prototypes/Destruction/block.gd Scripts/Prototypes/Destruction/block_factory.gd
git commit -m "feat(destruction): ImpactWatcher + _integrate_forces integration

Pure impact_to_damage() unit-tested. on_contact() queues damage_events
for both blocks once per contact pair (instance_id guard prevents
double-counting). Block._integrate_forces feeds contact impulses to
ImpactWatcher per spec §4.3.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.3"
```

---

## Task 6: GridStructure + ConstraintVisualizer

**Files:**
- Create: `Scripts/Prototypes/Destruction/grid_structure.gd`
- Create: `Scripts/Prototypes/Destruction/constraint_visualizer.gd`

**验证级别：** 第 5 层（必须 F6 看到约束连线 + 块不散架）

- [ ] **Step 6.1: 写 ConstraintVisualizer**

```gdscript
# Scripts/Prototypes/Destruction/constraint_visualizer.gd
# 可视化：_draw() 根据约束血量画彩色连线。
class_name ConstraintVisualizer
extends Node2D

@export var enabled: bool = true
@export var healthy_color: Color = Color.GREEN
@export var warning_color: Color = Color.ORANGE
@export var critical_color: Color = Color.RED
@export var line_width: float = 2.0

var _blocks: Array = []
var _constraints: Array = []

func set_data(blocks: Array, constraints: Array) -> void:
	_blocks = blocks
	_constraints = constraints

func _process(_dt: float) -> void:
	if enabled:
		queue_redraw()

func _draw() -> void:
	if not enabled:
		return
	for c in _constraints:
		if not is_instance_valid(c) or not is_instance_valid(c.pin):
			continue
		var block_a: Block = c.block_a
		var block_b: Block = c.block_b
		if not is_instance_valid(block_a) or not is_instance_valid(block_b):
			continue
		var health_ratio := c.health / c.initial_health if c.initial_health > 0.0 else 0.0
		var col: Color
		if health_ratio > 0.5:
			col = healthy_color
		elif health_ratio > 0.3:
			col = warning_color
		else:
			col = critical_color
		draw_line(block_a.global_position - global_position,
			block_b.global_position - global_position,
			col, line_width)
```

- [ ] **Step 6.2: 写 GridStructure**

```gdscript
# Scripts/Prototypes/Destruction/grid_structure.gd
# 可复用 Prefab：扫描子节点 RigidBody2D → 邻居检测 → 建 PinJoint + Constraint。
# spec §4.6 / §4.11。
class_name GridStructure
extends Node2D

const Block := preload("res://Scripts/Prototypes/Destruction/block.gd")
const Constraint := preload("res://Scripts/Prototypes/Destruction/constraint.gd")
const ConstraintVisualizer := preload("res://Scripts/Prototypes/Destruction/constraint_visualizer.gd")

@export var block_size: float = 25.0
@export var constraint_health: float = 50.0
@export var auto_build: bool = true
@export var pipeline: DestructionPipeline = null
@export var impact_watcher: ImpactWatcher = null

var _blocks: Array = []
var _constraints: Array = []

@onready var _visualizer: ConstraintVisualizer = $ConstraintVisualizer

func _ready() -> void:
	if auto_build:
		build_constraints()

func build_constraints() -> void:
	# 1) 扫描子节点中的所有 Block（RigidBody2D attatched block.gd）
	_blocks.clear()
	for child in get_children():
		if child is Block:
			_blocks.append(child)
			# 确保 pipeline + impact_watcher 注入
			if pipeline != null and child.pipeline == null:
				child.pipeline = pipeline
			if impact_watcher != null and child.impact_watcher == null:
				child.impact_watcher = impact_watcher

	# 2) O(N²) 邻居检测
	var threshold := block_size * 1.05
	for i in _blocks.size():
		var a: Block = _blocks[i]
		for j in range(i + 1, _blocks.size()):
			var b: Block = _blocks[j]
			if a.global_position.distance_to(b.global_position) <= threshold:
				_attach_constraint(a, b)

	# 3) 通知 visualizer
	if _visualizer != null:
		_visualizer.set_data(_blocks, _constraints)

func _attach_constraint(a: Block, b: Block) -> void:
	var center := (a.global_position + b.global_position) * 0.5
	var c := Constraint.create(a, b, center, self)
	c.initial_health = constraint_health
	c.health = constraint_health
	c.pipeline = pipeline
	a.connected_constraints.append(c)
	b.connected_constraints.append(c)
	_constraints.append(c)

func clear() -> void:
	for c in _constraints:
		if c.pin != null and is_instance_valid(c.pin):
			c.pin.queue_free()
	_constraints.clear()
	for blk in _blocks:
		if is_instance_valid(blk):
			blk.queue_free()
	_blocks.clear()
	if _visualizer != null:
		_visualizer.set_data([], [])
```

- [ ] **Step 6.3: 创建 GridStructure.tscn**

在 Godot Editor 中创建 `Scenes/Prototypes/Destruction/grid_structure.tscn`：
- 根节点 `GridStructure`（Node2D），挂 `grid_structure.gd`
- 子节点 `ConstraintVisualizer`（Node2D），挂 `constraint_visualizer.gd`
- **必须**通过 Editor 创建 `.tscn`（自动生成 `uid="uid://..."`，参 memory `tscn_needs_uid_for_packedscene_refs`）

- [ ] **Step 6.4: F6 smoke — 2×2 小墙验证**

临时在场景中放 4 个 Block（2×2），挂 GridStructure，F6 看：
- ConstraintVisualizer 画出 4 条连线（2 横 + 2 竖）
- 四块一起落到地面，不散架
- 无抖动

- [ ] **Step 6.5: 提交**

```bash
git add Scripts/Prototypes/Destruction/grid_structure.gd Scripts/Prototypes/Destruction/constraint_visualizer.gd Scenes/Prototypes/Destruction/grid_structure.tscn
git commit -m "feat(destruction): GridStructure + ConstraintVisualizer

GridStructure scans child Blocks at _ready(), detects neighbors via
Euclidean distance threshold, and creates single-PinJoint Constraints
per pair. ConstraintVisualizer draws colored lines reflecting health.

F6 smoke: 2x2 wall stays rigid under gravity.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.6 §4.11"
```

---

## Task 7: 三个测试场景

**Files:**
- Create: `Scripts/Prototypes/Destruction/destruction_demo.gd`
- Create: `Scenes/Prototypes/Destruction/scenes/brick_wall.tscn`
- Create: `Scenes/Prototypes/Destruction/scenes/arch.tscn`
- Create: `Scenes/Prototypes/Destruction/scenes/house.tscn`
- Create: `Scenes/Prototypes/Destruction/destruction_demo.tscn`

**验证级别：** 第 5 层（每个场景 F6 看到结构站稳）

### Scene 文件说明

三个场景都是 `grid_structure.tscn` 的实例（PackedScene instance），在其下手工摆放 Block cube。场景结构：

```
GridStructure (root, grid_structure.tscn instance)
├── ConstraintVisualizer
├── Block (25×25 RigidBody2D) × N
└── ...
```

所有 cube 在编辑器中手动拖拽摆放。GridStructure 的 `auto_build=true` 保证 `_ready()` 自动建约束。

另外需一个 StaticBody2D 地面（长条 CollisionShape2D）放在这些场景中（也可统一放在 destruction_demo.tscn 中供所有场景共用）。

**Step 7.1: 创建 brick_wall.tscn**

- 10×10 Block，紧密排列，每块 25×25 px
- 底层落在 StaticBody2D 地面（y=0 处，segment 形碰撞体）
- 原点 (0, 0)

**Step 7.2: 创建 arch.tscn**

- 左柱：1×5 Block（宽 1 高 5），x 起点约 -75
- 右柱：1×5 Block，x 起点约 +75
- 横梁：7×1 Block，y 在柱顶（y ≈ -125），覆盖两柱
- 地面在下

**Step 7.3: 创建 house.tscn**

- 左墙：1×6 Block
- 右墙：1×6 Block，距左墙 7 个 block_size（175 px）
- 三层楼板：各 8×1 Block，y 分别约 -25, -75, -125
- 屋顶：8×1 Block，y 约 -150
- 地面在下

**Step 7.4: 创建 destruction_demo.tscn**

在 Godot Editor 中创建：
- 根 `Node2D`，挂 `destruction_demo.gd`
- `Camera2D` 子节点，zoom 适当（能看到完整砖墙），position 对场景中心
- `StaticBody2D` "Ground" → CollisionShape2D（长 segment, y=0）
- `Node2D` "StructureHolder" —— 场景切换时替换子节点

**Step 7.5: 写 destruction_demo.gd 控制器**

```gdscript
# Scripts/Prototypes/Destruction/destruction_demo.gd
# 主场景控制器：装配 pipeline / impact / 场景加载 / 帧末批处理。
extends Node2D

const DestructionPipeline := preload("res://Scripts/Prototypes/Destruction/destruction_pipeline.gd")
const ImpactWatcher := preload("res://Scripts/Prototypes/Destruction/impact_watcher.gd")

@onready var structure_holder: Node2D = $StructureHolder

var pipeline: DestructionPipeline
var impact: ImpactWatcher
var current_structure: GridStructure = null

func _ready() -> void:
	pipeline = DestructionPipeline.new()
	impact = ImpactWatcher.new()
	impact.pipeline = pipeline
	_load_scene("brick_wall")

func _load_scene(name: String) -> void:
	# 清理旧结构
	if current_structure != null:
		current_structure.clear()
		current_structure.queue_free()
		current_structure = null
	# 加载新场景
	var s := load("res://Scenes/Prototypes/Destruction/scenes/%s.tscn" % name) as PackedScene
	if s == null:
		return
	var inst := s.instantiate()
	structure_holder.add_child(inst)
	if inst is GridStructure:
		current_structure = inst as GridStructure
		current_structure.pipeline = pipeline
		current_structure.impact_watcher = impact

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Scene1"):
		_load_scene("brick_wall")
	elif event.is_action_pressed("Scene2"):
		_load_scene("arch")
	elif event.is_action_pressed("Scene3"):
		_load_scene("house")

func _physics_process(_dt: float) -> void:
	# 1) 派发伤害事件 → Block.take_damage / Constraint.take_damage
	pipeline.dispatch_damage_events()
	# 2) 帧末批处理
	# 2a) 销毁 Constraint
	for c in pipeline.drain_constraint_destroys():
		c.destroy()
	# 2b) 销毁 Block
	for blk in pipeline.drain_block_destroys():
		if is_instance_valid(blk):
			blk.queue_free()
	# 注：ImpactWatcher 的接触检测由每个 Block._integrate_forces 自动完成；
	# 伤害入 damage_events 队列，下一帧步骤 1 派发（避免本帧拓扑震荡）。
```

- [ ] **Step 7.6: 注册输入动作**

在 `project.godot` 的 `[input]` 段加（如在 Editor 中加 Input Map 更稳）：

```
Scene1={ "deadzone": 0.5, "events": [Object(InputEventKey,"physical_keycode":49,"script":null)] }
Scene2={ "deadzone": 0.5, "events": [Object(InputEventKey,"physical_keycode":50,"script":null)] }
Scene3={ "deadzone": 0.5, "events": [Object(InputEventKey,"physical_keycode":51,"script":null)] }
```

- [ ] **Step 7.7: F6 验证三个场景**

| 场景 | 期望 |
|---|---|
| 砖墙 | 100 块站稳，ConstraintVisualizer 画连线，不塌不抖 |
| 拱门 | 柱+梁站稳，两块柱顶与梁底有约束 |
| 小屋 | 墙+楼板+屋顶站稳 |

- [ ] **Step 7.8: 提交**

```bash
git add Scripts/Prototypes/Destruction/destruction_demo.gd Scenes/Prototypes/Destruction/destruction_demo.tscn Scenes/Prototypes/Destruction/scenes/ project.godot
git commit -m "feat(destruction): demo controller + 3 test scenes

destruction_demo.gd assembles pipeline + ImpactWatcher, runs frame-end
batch processing per spec §4.4. Three scenes (brick_wall, arch, house)
built as GridStructure instances with hand-placed cubes. Keys 1/2/3
hot-swap scenes. F6 verifies all structures stable under gravity.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.4 §4.6"
```

---

## Task 8: 武器系统集成 + 破坏验证

**Files:**
- Modify: `Scripts/Prototypes/Destruction/destruction_demo.gd`
- 可能需要修改：`Scripts/Prototypes/Weapon/weapon_demo.tscn` 或创建整合场景

**验证级别：** 第 5 层

- [ ] **Step 8.1: 整合武器系统到 demo 场景**

两种方案选一：
- (A) 把武器系统（Player + Weapon + Projectile）作为子节点加入 destruction_demo.tscn
- (B) 把结构场景加载到武器 demo 中

推荐 (A)：在 `destruction_demo.tscn` 中加入 Player + Weapon 子节点树（从 `weapon_demo.tscn` 复制），通过碰撞 layer 确保 projectile 能命中 block。

Block 的 collision_mask 已含 `projectile` layer——确保 projectile 的 collision_layer 匹配。核对 `weapon_demo.tscn` 中 projectile 的 collision_layer。

- [ ] **Step 8.2: F6 验证 T1-T3（武器驱动破坏）**

| # | 操作 | 期望 |
|---|---|---|
| T1 | 场景 1，武器向同一 Block 连续开火 | 该 Block 消失，相邻 Block 因 Constraint 断开部分掉落 |
| T2 | 场景 1，武器打穿一条竖线 | 上方 Block 部分下落（边缘的因 Constraint 仍能挂住） |
| T3 | 场景 1，爆炸命中墙面 | 中心块伤害最高，周围按距离衰减；可能整组塌（伤害传递让多个 Constraint 同时断） |

- [ ] **Step 8.3: F6 验证 T4-T6（拱门、小屋、冲击）**

| # | 操作 | 期望 |
|---|---|---|
| T4 | 场景 2，爆炸炸柱底 | 该柱塌；横梁一侧失去支撑自然掉落 |
| T5 | 场景 3，多次爆炸 | 整体倾斜塌陷 |
| T6 | 任意场景，高空掉 Block 砸下方 | normal impulse 高 → 下方块通过 take_damage + 伤害传递打散一片 |

T6 手动测试：在 demo 控制器加一个 debug 键（如 `B`）在鼠标上方 spawn 一个孤立 Block（无 Constraint），自由落体砸墙。

- [ ] **Step 8.4: 提交**

```bash
git add Scripts/Prototypes/Destruction/destruction_demo.gd Scenes/Prototypes/Destruction/destruction_demo.tscn
git commit -m "feat(destruction): integrate weapon system as damage source

Weapon system's RadialDamage/RadialBlast drive Block destruction via
ADR-0007 take_damage contract. F6 verifies T1-T6 per spec §5.1.
Single-direction dependency maintained: zero weapon imports in
destruction module.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.3 §5.1, ADR-0007"
```

---

## Task 9: DebugPanel

**Files:**
- Create: `Scripts/Prototypes/Destruction/debug_panel.gd`
- Modify: `Scenes/Prototypes/Destruction/destruction_demo.tscn` — 加 CanvasLayer 子树

**验证级别：** 第 5 层

- [ ] **Step 9.1: 写 DebugPanel**

```gdscript
# Scripts/Prototypes/Destruction/debug_panel.gd
# runtime 调参 + on-screen 统计 + 2 机制独立开关。spec §4.8。
extends CanvasLayer

@export var impact: ImpactWatcher

# 通过 destruction_demo 注入了 pipeline / structure 引用
var demo: Node = null

@onready var panel: Control = $Panel
@onready var fps_label: Label = $Panel/Stats/FpsLabel
@onready var block_count_label: Label = $Panel/Stats/BlockCountLabel
@onready var constraint_count_label: Label = $Panel/Stats/ConstraintCountLabel
@onready var per_frame_label: Label = $Panel/Stats/PerFrameLabel
@onready var sw_propagation: CheckBox = $Panel/Toggles/PropagationToggle
@onready var sw_impact: CheckBox = $Panel/Toggles/ImpactToggle

# 两个全局开关，由 Block / ImpactWatcher 读取
static var propagation_enabled: bool = true
static var impact_enabled: bool = true

var _prev_block_destroys: int = 0
var _prev_constraint_destroys: int = 0

func _ready() -> void:
	visible = true
	sw_propagation.toggled.connect(func(b: bool): propagation_enabled = b)
	sw_impact.toggled.connect(func(b: bool):
		impact_enabled = b
		if impact != null:
			impact.enabled = b
	)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("F1ToggleDebugPanel"):
		panel.visible = not panel.visible

func _process(_dt: float) -> void:
	if not panel.visible:
		return
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	if demo != null and demo.current_structure != null:
		var s := demo.current_structure
		block_count_label.text = "Blocks: %d" % s._blocks.size()
		var c_alive := 0
		for c in s._constraints:
			if is_instance_valid(c) and is_instance_valid(c.pin):
				c_alive += 1
		constraint_count_label.text = "Constraints: %d" % c_alive
	per_frame_label.text = "Frame destroy (B/C): %d / %d" % [_prev_block_destroys, _prev_constraint_destroys]
```

**伤害传递开关的实现方式**：不准备在 DebugPanel 中反向引用 Block。用一种更低侵入的方式——在 `Block.take_damage` 的 for-loop 前检查 `DebugPanel.propagation_enabled`（静态变量）。

Edit `block.gd` take_damage 的传递部分：

```gdscript
	# 伤害传递到所有相连 Constraint（可通过 DebugPanel 关闭）
	if DebugPanel.propagation_enabled:
		for c in connected_constraints:
			c.take_damage(amount * damage_propagation_ratio, point, source)
```

Block 顶部加 `const DebugPanel := preload("res://Scripts/Prototypes/Destruction/debug_panel.gd")`。（或者用 static var 直接通过类名访问，无需 preload——但 `DebugPanel` 是 `class_name`，Godot 会自动注册。如编译顺序出问题，回退到用 autoload 或信号。）

- [ ] **Step 9.2: 搭建 Panel UI**

在 `destruction_demo.tscn` 中加 CanvasLayer 子节点（"DebugPanelLayer"），挂 `debug_panel.gd`。其下结构：

```
DebugPanelLayer (CanvasLayer + debug_panel.gd)
└── Panel (Control)
    ├── Stats (VBoxContainer)
    │   ├── FpsLabel (Label)
    │   ├── BlockCountLabel (Label)
    │   ├── ConstraintCountLabel (Label)
    │   └── PerFrameLabel (Label)
    └── Toggles (VBoxContainer)
        ├── PropagationToggle (CheckBox, text="伤害传递", pressed=true)
        └── ImpactToggle (CheckBox, text="冲击伤害", pressed=true)
```

- [ ] **Step 9.3: F6 验证 T7（关闭伤害传递）**

| # | 操作 | 期望 |
|---|---|---|
| T7 | F1 显 Panel → 取消"伤害传递" → 爆炸命中墙面 | 中心块销毁，周围结构基本保留（验证伤害传递是否在起作用） |

同时验 F1 显隐、关闭冲击伤害 T6 不出伤。

- [ ] **Step 9.4: 提交**

```bash
git add Scripts/Prototypes/Destruction/debug_panel.gd Scripts/Prototypes/Destruction/block.gd Scenes/Prototypes/Destruction/destruction_demo.tscn
git commit -m "feat(destruction): debug panel with stats + 2 isolation toggles

F1 toggles HUD with FPS/Block/Constraint counts and per-frame destroy
deltas. Two checkboxes independently disable damage propagation and
impact damage for isolated debugging per spec §4.8.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.8"
```

---

## Task 10: 验收清单 + 性能基线 + 跨 spec 契约校验

**Files:** 无代码改动；纯验收 + 文档收尾。

- [ ] **Step 10.1: 跑全套自动化测试**

```
test_destruction_pipeline.gd  → ALL PASS
test_block_damage.gd          → ALL PASS
test_damage_propagation.gd    → ALL PASS
test_impact_watcher.gd        → ALL PASS
```

任一退化即停下来排查。

- [ ] **Step 10.2: 跨 spec 契约校验**

```bash
grep -nE "weapon|projectile|effect" Scripts/Prototypes/Destruction/*.gd
```

**期望：零匹配**（单向依赖 —— 破坏系统对武器系统零感知，ADR-0007）。

`Block.take_damage` / `Constraint.take_damage` 签名核对：
```
(amount: float, point: Vector2, source) -> void
```
—— 与 ADR-0007 §2 一致。

- [ ] **Step 10.3: 性能基线**

- 跑砖墙场景（10×10 = 100 block）→ FPS 稳 60
- 手动摆 20×20 = 400 block 墙 → FPS 稳 60
- 逐步加到 1000 block → 记录 FPS
- 大规模爆炸瞬间帧时间观察（连续触发爆炸 5 次）

- [ ] **Step 10.4: User F6 签字（必需）**

```
[ ] Scene 1：T1 武器射击同一 Block → 消失，相邻块掉落
[ ] Scene 1：T2 武器打穿竖线 → 上方部分下落
[ ] Scene 1：T3 爆炸 → 衰减 + 可能整组塌
[ ] Scene 2：T4 爆炸炸柱底 → 横梁一侧掉落
[ ] Scene 3：T5 多次爆炸 → 整体倾斜
[ ] 任意：T6 高空掉块 → 砸出冲击伤害链
[ ] Panel T7：关伤害传递重复 T3 → 周围结构基本保留
[ ] Panel：关冲击伤害 → T6 无伤害
[ ] Scene 1 (10×10) 稳 60fps
[ ] 1000 block 稳 60fps（或记录最好成绩）
[ ] F1 隐藏 / 显示 Panel
[ ] 数字键 1/2/3 切场景 + clear() 不留残块
```

- [ ] **Step 10.5: 提交签字**

```bash
git commit --allow-empty -m "chore(destruction): v1 prototype acceptance signoff

All checklist items confirmed by user. Spec
2026-05-24-destruction-prototype-design.md v1 success criteria 1-7 met."

git add docs/superpowers/plans/2026-05-26-destruction-prototype-plan.md
git commit -m "docs: destruction v1 implementation plan (Rapier2D edition)"
```

---

## 风险与回滚

| 风险 | 缓解 |
|---|---|
| Block mass 单位不确定（Rapier 用 SI 还是像素） | Task 4 F6 时实测调整 mass，不用 spec 里的理论值 |
| PinJoint angular_limit=0 仍有微幅旋转 | 极端力下可能有；F6 观察拱门横梁是否旋转；若可感，调高 angular_limit 软度或接受 |
| ImpactWatcher 双计数 | `instance_id <` 守卫防双计数；F6 观察每次接触是否触发 2 次伤害事件 |
| Block 销毁时其 Constraint 没清理 | Constraint.destroy() 用 `is_instance_valid(pin)` 防御；GridStructure 遍历时同样 filter |
| 武器 Projectile 与 Block 碰撞 layer 不匹配 | Task 8 集成时在 Godot Editor 核对 collision_layer/mask bit |
| DebugPanel static var 访问编译顺序 | Godot 的 `class_name` 全局注册应在 Block take_damage 被调用时已完成；如出问题改 autoload |

回滚顺序（每个 task 独立 commit，可逐 task revert）。

---

## 备注

- 所有 `block_size = 25.0` 像素。武器系统 PX_PER_M = 100，block = 0.25 m，与其他系统一致。
- 本计划严格遵循 TDD + frequent commits：每个 task 先红测试 → 实现 → 绿测试 → commit。
- 旧 godot-box2d 相关 plan（`docs/superpowers/plans/2026-05-25-destruction-prototype-plan.md`）已过期，本 plan 替代之。
