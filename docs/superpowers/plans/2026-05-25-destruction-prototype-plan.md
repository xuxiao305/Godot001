# 体块化破坏框架 v1 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Godot 4 + godot-box2d 上实现"Block + Constraint + 三机制（销毁 / 双路径断裂 / 冲击）"的破坏沙盒，跑通 3 个手搓场景（砖墙 / 拱门 / 三层小屋），验证设计哲学"结构稳定性从 Box2D 解算涌现"。

**Architecture:** 单例 `DestructionPipeline` 集中调度拓扑变更（4 队列：damage_events / constraint_destroy / block_destroy / debris_spawn），帧末统一批处理。Block 是 RigidBody2D + 自带血量与 take_damage；Constraint 是封装 *2× PinJoint2D*（spec 原写 weld，但本项目 godot-box2d 不支持 WeldJoint2D —— 见 [[godot-box2d-joints-not-registered]]）—— 两 pin 分别放在共享边两端，几何上锁死位移 + 相对旋转，效果等价 weld；同时自带血量与 take_damage。系统层 ConstraintBreaker / ImpactWatcher / DamageDispatcher 都只读取或入队，不直接动 Box2D 拓扑。

**Tech Stack:** Godot 4.6 + godot-box2d GDExtension（PhysicsServer2D 后端）；GDScript；纯函数测试沿用 `test_engine_torque.gd` 风格（`_ready` 跑断言 → `print PASS` → `get_tree().quit()`）。

**关键设计 deviation（必读）：**
1. **weld → 2× PinJoint2D**：godot-box2d 不注册 `WeldJoint2D` 节点类（见 memory [[godot-box2d-joints-not-registered]]）。本计划用两根 PinJoint2D 平行放在共享边两端模拟"焊接"（单 pin 只锁平移、不锁相对旋转；双 pin 锁两个自由度 = 等价 weld）。这两根 pin 在拓扑上是**同一 Constraint**，绑成一组，断裂时一起销毁。
2. **物理路径反作用力 → 需 spike 决定**：Godot/Box2D 没有暴露 `b2Joint::GetReactionForce`，spec §4.2 的"反作用力扫描"无法照搬。**Task 0 是 spike**，根据结果在三种 fallback 之间二选一：
   - (a) 通过 godot-box2d 私有 API 拿到 reaction force（理想）
   - (b) 用"两体相对加速度 × 等效质量"作为应力代理
   - (c) v1 仅保留**伤害路径**，把物理路径推迟到 v1.5（接受 spec 偏离）

**验证级别（参 memory `feedback_verify_each_edit`）：**
- 纯算法 task（pipeline 队列、damage 转发计算、ImpactWatcher 阈值）：**第 4 层（自动化测试）**
- 涉及 Box2D 拓扑、joint 装配、场景构造的 task：**第 5 层（人工 F6 签字）必需**
- 每个 Implementer subagent prompt 必须显式带上"先按上述层级跑验证，不通过不交付"

**相关文档：**
- Spec：[2026-05-24-destruction-prototype-design.md](d:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/2026-05-24-destruction-prototype-design.md)
- 项目总览：[项目总览.md](d:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/项目总览.md)
- 跨 spec 契约：[ADR-0007 Effect 双通道 + 单向依赖](d:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/adr/0007-effect-dual-channel.md)
- 内在发动机派环境推广：[ADR-0001](d:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/adr/0001-inner-engine-school.md)
- 术语：[CONTEXT.md](d:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/CONTEXT.md)（Block / Constraint / 统一伤害语言 / 伤害转发 / 冲击伤害）

---

## 文件结构

模块根目录 `Scripts/Prototypes/Destruction/`（沿用 `Scripts/Prototypes/3C/` 的 PascalCase 子目录约定）。场景根目录 `Scenes/Prototypes/Destruction/`。

**Create — Scripts:**
- `Scripts/Prototypes/Destruction/destruction_pipeline.gd` — 单例：4 队列 + 帧末批处理调度
- `Scripts/Prototypes/Destruction/block.gd` — RigidBody2D 派生 Block（血量、take_damage、伤害转发、销毁信号）
- `Scripts/Prototypes/Destruction/constraint.gd` — RefCounted Constraint 封装（持有 2× PinJoint2D + 血量 + 反作用力代理 + take_damage）
- `Scripts/Prototypes/Destruction/constraint_breaker.gd` — 系统：每帧扫描所有 Constraint 的应力代理（物理路径）
- `Scripts/Prototypes/Destruction/damage_dispatcher.gd` — 系统：派发 damage_events 队列 → take_damage
- `Scripts/Prototypes/Destruction/impact_watcher.gd` — 系统：监听 Box2D 接触冲量 → 转伤害事件入队
- `Scripts/Prototypes/Destruction/debris_spawner.gd` — 系统：销毁瞬间生成纯视觉碎片
- `Scripts/Prototypes/Destruction/block_factory.gd` — 工厂：创建 Block（未来接对象池仅改内部）
- `Scripts/Prototypes/Destruction/level_builder.gd` — 工厂：3 个测试场景程序构造 + 邻居自动建 Constraint
- `Scripts/Prototypes/Destruction/debug_input.gd` — Debug 鼠标输入（LMB 点伤 / RMB 范围）—— v2+ 删除
- `Scripts/Prototypes/Destruction/debug_panel.gd` — runtime 调参 UI + on-screen 统计

**Create — Tests（纯函数，沿用 `test_engine_torque.gd` 风格，挂在临时 runner 场景跑 F6）:**
- `Scripts/Prototypes/Destruction/tests/test_destruction_pipeline.gd`
- `Scripts/Prototypes/Destruction/tests/test_block_damage.gd`
- `Scripts/Prototypes/Destruction/tests/test_damage_forwarding.gd`
- `Scripts/Prototypes/Destruction/tests/test_impact_watcher.gd`
- `Scripts/Prototypes/Destruction/tests/test_radial_falloff.gd`

**Create — Scenes:**
- `Scenes/Prototypes/Destruction/destruction_demo.tscn` — 主场景（Camera2D + DestructionPipeline 单例挂载点 + LevelBuilder + DebugInput + DebugPanel）
- `Scenes/Prototypes/Destruction/_test_runner.tscn` — 跑 tests/*.gd 的临时容器（仿 3C/tests 用法）

**Modify:**
- `project.godot` — 注册输入动作 `DebugLMB`、`DebugRMB`、`F1ToggleDebugPanel`、`Scene1`、`Scene2`、`Scene3`；新增 collision layer `block`（如不存在）
- （可选）`project.godot` AutoLoad —— 若 DestructionPipeline 决定走 autoload 单例形式，需登记 `DestructionPipeline=*res://Scripts/Prototypes/Destruction/destruction_pipeline.gd`

---

## Task 0: Spike — 决定 Constraint 物理路径策略

**Files:**
- Create: `Scripts/Prototypes/Destruction/spike/spike_pin_reaction.tscn`
- Create: `Scripts/Prototypes/Destruction/spike/spike_pin_reaction.gd`
- Output: `docs/superpowers/plans/2026-05-25-destruction-prototype-plan-spike0.md`（spike 决议笔记，merged 后可删）

**目标：** 在 PinJoint2D 上验证三种策略可行性，选一种作为 v1 的物理路径实现。**本 task 必须 user F6 签字后才进下一 task。**

### Step 0.1 搭一个最小 spike 场景

Create `Scenes/Prototypes/Destruction/spike/spike_pin_reaction.tscn`：
- 一根 static body（地面）
- 一个 dynamic RigidBody2D（Body A，质量 1.0），坐标 (0, -50)
- 一个 dynamic RigidBody2D（Body B，质量 1.0），坐标 (40, -50)
- 一根 PinJoint2D 连接 A 与 B，pin 点在 (20, -50)

挂上脚本 `spike_pin_reaction.gd`：每 0.1 秒往 B 上施加一个递增的水平 impulse（每步 +5 N·s），直到 pin 看起来"撑不住"或测出可读应力。同时 print 三组数据：

```
[spike] frame=N
  Body A vel=(vx,vy)  Body B vel=(vx,vy)
  rel_accel_along_pin_axis = ...
  pin.node.has_method("get_reaction_force") = bool
  pin.node.get("constraint_force") = <whatever Godot/box2d exposes>
  applied_impulse_so_far = ...
```

**重要：** 不要把 spike 脚本挂到正式模块里，spike 目录可独立删除。

### Step 0.2 调研 Godot/godot-box2d 是否暴露反作用力

- 在 Godot inspector 检查 PinJoint2D 的所有 property
- `grep -r "reaction" addons/godot-box2d/` —— 已知结果：无匹配（执行时再印证一次）
- 在 GDScript 试探：`pin.call("get_reaction_force", 60.0)` / `pin.get("reaction_force")` —— 看是否非 null
- 翻 `d:/GoDot/Source/godot-master/scene/2d/physics/joints/pin_joint_2d.h` 看暴露的 method list

### Step 0.3 验证策略 (a)（私有 API）

若 Step 0.2 发现可读 reaction，记下 API 形式，跳到 Step 0.5 写决议。

### Step 0.4 验证策略 (b)（应力代理）

代理公式：每帧记录 `prev_vA`、`prev_vB`；下一帧 `aA = (vA - prev_vA) / dt`，`aB = (vB - prev_vB) / dt`；项目到两 body 中心连线方向 `n`：

```
sigma_proxy = abs(mass_A * (aA·n)) + abs(mass_B * (aB·n))
```

`sigma_proxy` 单位是力（N）。物理直觉：两 body 都在被强行拉/推，所有"非 pin 的力"被 pin 反作用力顶住。

在 spike 场景里：
- 让两 body 静态挂着 → `sigma_proxy ≈ mass * g`（pin 撑住自重）
- 给 B 施 50 N·s impulse → `sigma_proxy` 应瞬时跳起来
- 把 pin 删了 → 两 body 自由解算 → `sigma_proxy → 0`（pin 不再做功）

若数值有量级一致性 + 信号清晰，策略 (b) 可用。注意：proxy 只在**两 body 同时 awake** 时有意义；sleeping body 会让代理失真——这是已知缺陷，调参时给阈值留余量即可。

### Step 0.5 写决议笔记（必须）

Create `docs/superpowers/plans/2026-05-25-destruction-prototype-plan-spike0.md`：

```markdown
# Spike 0 决议 — Constraint 物理路径策略

**结论：** 选 (a) / (b) / (c)（圈一个）

**证据：**
- (a) 是否可行：...（粘 spike print 关键片段）
- (b) 数值是否合理：...（粘 spike print + 量级分析）
- 若 (c)：列出 spec §3.1 中受影响的成功标准（T4 拱门塌方主要受影响）

**对计划的修订：**
- Task 6 ConstraintBreaker 的实现按本结论走，详见 Step 6.x
- 若选 (c)：spec §3.1 成功标准 T4 改"手动 F6 验收时容忍" + 在 v1.5 plan 中开 follow-up
```

### Step 0.6 user F6 签字

把 spike 场景跑给 user 看一遍 + 决议笔记 review，**得到明确"OK 按 X 路线继续"的回复后**才进 Task 1。

### Step 0.7 提交

```bash
git add Scripts/Prototypes/Destruction/spike/ docs/superpowers/plans/2026-05-25-destruction-prototype-plan-spike0.md
git commit -m "spike(destruction): decide constraint physics-path strategy

PinJoint2D reaction-force not natively exposed in godot-box2d. Spike
compared (a) private-API probe, (b) relative-acceleration proxy,
(c) drop physics-path for v1. Decision: <X> — see spike0 note."
```

---

## Task 1: DestructionPipeline 单例 + 队列单测

**Files:**
- Create: `Scripts/Prototypes/Destruction/destruction_pipeline.gd`
- Create: `Scripts/Prototypes/Destruction/tests/test_destruction_pipeline.gd`

**验证级别：** 第 4 层（自动化测试足够，本 task 全是纯算法）。

### Step 1.1 写失败测试

Create `Scripts/Prototypes/Destruction/tests/test_destruction_pipeline.gd`:

```gdscript
# Scripts/Prototypes/Destruction/tests/test_destruction_pipeline.gd
# 纯算法测试 —— pipeline 的入队 / 派发 / 幂等性。
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

	# 5) constraint_destroy 与 debris_spawn 同理
	var fake_constraint := RefCounted.new()
	p.queue_constraint_destroy(fake_constraint)
	assert(p.drain_constraint_destroys().size() == 1, "constraint 队列幂等 + drain")

	p.queue_debris_spawn({"pos": Vector2(1, 2), "vel": Vector2.ZERO, "ang_vel": 0.0})
	assert(p.drain_debris_spawns().size() == 1, "debris 队列 drain")

	print("[TEST destruction_pipeline] ALL PASS")
	get_tree().quit()
```

### Step 1.2 跑测试确认失败

把 `_test_runner.tscn` 的脚本指向 `test_destruction_pipeline.gd`（runner 场景 = 单个 Node + Script，参 3C/tests/ 用法）。F6 运行：期望 `Identifier "DestructionPipeline" not declared`。

### Step 1.3 写最小实现

Create `Scripts/Prototypes/Destruction/destruction_pipeline.gd`:

```gdscript
# Scripts/Prototypes/Destruction/destruction_pipeline.gd
# 单例：拓扑变更批处理。
# spec §4.4：所有 body/joint 销毁与创建只能在 _physics_process 末尾批量执行；
# 不在 Box2D 解算或 contact callback 中途改拓扑。
#
# 4 个队列：
#  - damage_events       —— { target, amount, point, source }
#  - constraint_destroy_queue
#  - block_destroy_queue
#  - debris_spawn_queue  —— { pos, vel, ang_vel }
#
# 销毁队列用 Dictionary{instance_id: object} 去重，保证幂等。
class_name DestructionPipeline
extends RefCounted

var damage_events: Array = []
var block_destroy_queue: Dictionary = {}
var constraint_destroy_queue: Dictionary = {}
var debris_spawn_queue: Array = []

func queue_damage_event(ev: Dictionary) -> void:
	damage_events.append(ev)

func queue_block_destroy(block) -> void:
	block_destroy_queue[block.get_instance_id()] = block

func queue_constraint_destroy(c) -> void:
	constraint_destroy_queue[c.get_instance_id()] = c

func queue_debris_spawn(d: Dictionary) -> void:
	debris_spawn_queue.append(d)

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

func drain_debris_spawns() -> Array:
	var snap := debris_spawn_queue
	debris_spawn_queue = []
	return snap
```

> 注：`get_instance_id()` 在 `RefCounted.new()` 上返回唯一 int，可用于 dict key。测试里 `fake_block` 是 RefCounted 实例，本就支持。

### Step 1.4 跑测试确认通过

F6 → 期望控制台：

```
[TEST destruction_pipeline] ALL PASS
```

### Step 1.5 提交

```bash
git add Scripts/Prototypes/Destruction/destruction_pipeline.gd Scripts/Prototypes/Destruction/tests/test_destruction_pipeline.gd Scenes/Prototypes/Destruction/_test_runner.tscn
git commit -m "feat(destruction): add DestructionPipeline + queue tests

4-queue batching scheduler with idempotent destroy queues. All
topology mutations route through this single point per spec §4.4.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.4"
```

---

## Task 2: Block（数据 + take_damage 雏形）+ 单测

**Files:**
- Create: `Scripts/Prototypes/Destruction/block.gd`
- Create: `Scripts/Prototypes/Destruction/tests/test_block_damage.gd`

**验证级别：** 第 4 层。本 task 不接 PinJoint2D（那是 Task 3 的事），只验数据流。

### Step 2.1 写失败测试

Create `Scripts/Prototypes/Destruction/tests/test_block_damage.gd`:

```gdscript
# Scripts/Prototypes/Destruction/tests/test_block_damage.gd
# 验 Block 的血量、take_damage、信号、入队行为。不验 PinJoint2D。
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
	assert(b.health == 100.0, "初始血量")

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

	# 5) damage_to_constraint_ratio 默认 0.3
	assert(absf(b.damage_to_constraint_ratio - 0.3) < 0.001, "默认转发比 0.3")

	print("[TEST block_damage] ALL PASS")
	get_tree().quit()
```

### Step 2.2 跑测试确认失败

### Step 2.3 写最小实现

Create `Scripts/Prototypes/Destruction/block.gd`:

```gdscript
# Scripts/Prototypes/Destruction/block.gd
# 体块 —— RigidBody2D 派生。spec §4.1。
#
# Body 参数（density / friction / restitution / damping）由 BlockFactory
# 配置 sub_resource，本脚本只管数据 + 行为。
#
# take_damage 是统一伤害语言（ADR-0007）的实现，外部（debug 输入 / 武器 /
# ImpactWatcher）都走这一个接口。Path X 转发（向 Constraint）在 Task 5 接上。
class_name DBlock
extends RigidBody2D

signal block_destroyed(position: Vector2, lin_vel: Vector2, ang_vel: float)

@export var initial_health: float = 100.0
@export var damage_to_constraint_ratio: float = 0.3

var health: float = 100.0
var pipeline: DestructionPipeline = null
var connected_constraints: Array = []  # 元素是 Constraint（Task 3 引入）；本 task 留空数组

var _queued_for_destroy: bool = false

func _ready() -> void:
	health = initial_health

func take_damage(amount: float, point: Vector2, source) -> void:
	if _queued_for_destroy:
		return
	health -= amount
	# Path X 转发到 Constraint —— Task 5 接上，本 task 保留 hook
	for c in connected_constraints:
		c.take_damage(amount * damage_to_constraint_ratio, point, source)
	if health <= 0.0:
		_queued_for_destroy = true
		if pipeline != null:
			pipeline.queue_block_destroy(self)
```

> 注：`class_name DBlock` 而非 `Block`，因为 Godot 内置 `Block` 类名可能冲突（保险起见加 D 前缀代表 Destruction）。

### Step 2.4 跑测试确认通过

### Step 2.5 提交

```bash
git add Scripts/Prototypes/Destruction/block.gd Scripts/Prototypes/Destruction/tests/test_block_damage.gd
git commit -m "feat(destruction): add DBlock with take_damage + tests

RigidBody2D-derived Block with health, take_damage, and queueing into
DestructionPipeline. Path X forwarding hook present but Constraint
wiring deferred to Task 5.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.1, ADR-0007"
```

---

## Task 3: Constraint 物理装配（2× PinJoint2D 封装）+ F6 smoke

**Files:**
- Create: `Scripts/Prototypes/Destruction/constraint.gd`
- Create: `Scenes/Prototypes/Destruction/spike/spike_two_pin_weld.tscn`
- Create: `Scenes/Prototypes/Destruction/spike/spike_two_pin_weld.gd`

**验证级别：** 第 5 层（人工 F6 必需）—— 必须看到"两个 block 通过双 pin 黏在一起、互不旋转"才算过。

### Step 3.1 写 Constraint 类骨架（先不接 take_damage，只验装配）

Create `Scripts/Prototypes/Destruction/constraint.gd`:

```gdscript
# Scripts/Prototypes/Destruction/constraint.gd
# Constraint —— 一对相邻 Block 之间的"焊接"约束封装。
# 实现：2× PinJoint2D 平行放在共享边两端（spec 原本是 weld，
# godot-box2d 不支持 WeldJoint2D —— [[godot-box2d-joints-not-registered]]）。
# 两根 pin 是同一 Constraint 的物理实现，断裂时一起销毁。
#
# spec §4.2：自带血量 + 双路径断裂 + take_damage。
# Task 3 只搭物理装配；血量与 take_damage 在 Task 4 加。
class_name DConstraint
extends RefCounted

var pin_a: PinJoint2D
var pin_b: PinJoint2D
var block_a: DBlock
var block_b: DBlock

# Task 4 才用到：
var initial_health: float = 50.0
var health: float = 50.0
var max_reaction_force: float = 200.0
var max_reaction_torque: float = 30.0
var pipeline: DestructionPipeline = null

var _queued_for_destroy: bool = false

# 装配：在 block_a / block_b 共享边的两端各放一根 PinJoint2D。
# share_edge_p1 / p2 是世界坐标下共享边的两端点。
static func create(
	a: DBlock, b: DBlock,
	share_edge_p1: Vector2, share_edge_p2: Vector2,
	parent: Node
) -> DConstraint:
	var c := DConstraint.new()
	c.block_a = a
	c.block_b = b
	c.pin_a = _make_pin(share_edge_p1, a, b, parent)
	c.pin_b = _make_pin(share_edge_p2, a, b, parent)
	c.health = c.initial_health
	return c

static func _make_pin(world_pos: Vector2, a: DBlock, b: DBlock, parent: Node) -> PinJoint2D:
	var pin := PinJoint2D.new()
	pin.global_position = world_pos
	pin.node_a = a.get_path()
	pin.node_b = b.get_path()
	pin.disable_collision = true  # 已经焊住，碰撞算两次没意义
	parent.add_child(pin)
	# node_a / node_b 必须在 add_child 之后设（pin 的 NodePath 解析依赖 in_tree）
	pin.node_a = a.get_path()
	pin.node_b = b.get_path()
	return pin

# Task 4 实现 take_damage、destroy；本 task 仅占位
func destroy() -> void:
	if _queued_for_destroy:
		return
	_queued_for_destroy = true
	if is_instance_valid(pin_a):
		pin_a.queue_free()
	if is_instance_valid(pin_b):
		pin_b.queue_free()
```

### Step 3.2 搭 spike 场景验装配

Create `Scenes/Prototypes/Destruction/spike/spike_two_pin_weld.tscn`：
- 一个 static body 当地面，水平横放
- 两个 32×32 的 RigidBody2D（左 Body A，右 Body B），紧贴左右放在地面上方
- 一个空 Node2D root 挂 `spike_two_pin_weld.gd`，在 `_ready()` 里调 `DConstraint.create(a, b, top_corner, bottom_corner, self)`

`spike_two_pin_weld.gd`：

```gdscript
extends Node2D

const DConstraint := preload("res://Scripts/Prototypes/Destruction/constraint.gd")

@onready var body_a: RigidBody2D = $BodyA
@onready var body_b: RigidBody2D = $BodyB

func _ready() -> void:
	# 共享边是两 body 接触的那条竖边
	var top_corner := (body_a.global_position + body_b.global_position) * 0.5 + Vector2(0, -16)
	var bottom_corner := (body_a.global_position + body_b.global_position) * 0.5 + Vector2(0, +16)
	# DConstraint.create 的 a/b 参数类型是 DBlock，spike 里我们传 RigidBody2D —— 临时把
	# DConstraint.create 改成接 RigidBody2D（或者 spike 直接手搓两根 PinJoint2D，避开类型耦合）。
	# 这里走"手搓两根 pin"路径，避免污染 DConstraint 接口：
	var pin1 := PinJoint2D.new()
	pin1.global_position = top_corner
	add_child(pin1)
	pin1.node_a = body_a.get_path()
	pin1.node_b = body_b.get_path()
	pin1.disable_collision = true

	var pin2 := PinJoint2D.new()
	pin2.global_position = bottom_corner
	add_child(pin2)
	pin2.node_a = body_a.get_path()
	pin2.node_b = body_b.get_path()
	pin2.disable_collision = true
```

### Step 3.3 user F6 验证

把场景跑给 user，预期：

- 两 body 像一整块一样落到地面、不分家、不相对旋转
- 拖动 / 施力 Body A，Body B 同步跟随；倾斜 ≈ 0（双 pin 锁旋转）
- 单 pin 对照实验（注释掉 pin2）：两 body 会相对绕 pin1 自由旋转 —— 印证"双 pin 才等价 weld"

若 user 反馈"双 pin 仍有可感旋转"，调整 pin1/pin2 在共享边上的间距（越远旋转刚度越强）。

### Step 3.4 把 DConstraint.create 参数与 spike 收敛

Spike 通过后，确认 `DConstraint.create` 签名最终采用 `DBlock` 还是 `RigidBody2D`。统一为 `DBlock`（Task 9 LevelBuilder 创建的就是 DBlock）。若 spike 用了 RigidBody2D，在本 step 把 spike 脚本里的 RigidBody2D 改成 DBlock（spike 场景里的两个 RigidBody2D 节点也换 script 为 `block.gd`）。

### Step 3.5 提交

```bash
git add Scripts/Prototypes/Destruction/constraint.gd Scenes/Prototypes/Destruction/spike/spike_two_pin_weld.tscn Scenes/Prototypes/Destruction/spike/spike_two_pin_weld.gd
git commit -m "feat(destruction): DConstraint 2-pin weld substitute + spike

godot-box2d ships no WeldJoint2D, so each Constraint = 2× PinJoint2D
placed at the two ends of the shared edge (locks translation + relative
rotation = weld-equivalent). Spike scene F6-verified rigidity.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.2,
      memory: godot-box2d-joints-not-registered"
```

---

## Task 4: Constraint take_damage + 销毁入队 + 单测

**Files:**
- Modify: `Scripts/Prototypes/Destruction/constraint.gd:30-40`（在 destroy 上方加 take_damage）
- Create: 在 `tests/test_damage_forwarding.gd` 里加 constraint take_damage 段（Task 5 同文件统一）

为减少散件，本 task 的测试合并到 Task 5 的 `test_damage_forwarding.gd`。本 task 仅改实现 + 加签 commit。

### Step 4.1 在 constraint.gd 加 take_damage

Edit `Scripts/Prototypes/Destruction/constraint.gd` —— 在 `destroy()` 之前插入：

```gdscript
func take_damage(amount: float, point: Vector2, source) -> void:
	if _queued_for_destroy:
		return
	health -= amount
	if health <= 0.0:
		_queued_for_destroy = true
		if pipeline != null:
			pipeline.queue_constraint_destroy(self)
```

> 物理路径断裂（reaction force 超阈值）由 Task 6 的 ConstraintBreaker 触发，不在本类内部。

### Step 4.2 自检 parse + 留待 Task 5 的统一测试覆盖

Godot Editor 重载 `constraint.gd`，无 parse error。本 task 不单独跑测试，签入即可。

### Step 4.3 提交

```bash
git add Scripts/Prototypes/Destruction/constraint.gd
git commit -m "feat(destruction): DConstraint.take_damage health path

Damage-path breakage: health -> 0 queues constraint_destroy. Physics
path (reaction-force) deferred to Task 6 per spike0 decision.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.2"
```

---

## Task 5: 伤害转发（Path X）+ 单测

**Files:**
- Modify: `Scripts/Prototypes/Destruction/block.gd` —— `take_damage` 中的 Path X for-loop 已存在；本 task 验它真的被走到
- Create: `Scripts/Prototypes/Destruction/tests/test_damage_forwarding.gd`

**验证级别：** 第 4 层。

### Step 5.1 写失败测试

Create `Scripts/Prototypes/Destruction/tests/test_damage_forwarding.gd`:

```gdscript
# Scripts/Prototypes/Destruction/tests/test_damage_forwarding.gd
# 验 Block.take_damage 内的 Path X：按 damage_to_constraint_ratio 转发到所有相连 Constraint。
# 也验 Constraint.take_damage 致命伤入队。
extends Node

const DBlock := preload("res://Scripts/Prototypes/Destruction/block.gd")
const DConstraint := preload("res://Scripts/Prototypes/Destruction/constraint.gd")
const DestructionPipeline := preload("res://Scripts/Prototypes/Destruction/destruction_pipeline.gd")

# 用一个伪 Constraint 收转发量 —— 不实例化 PinJoint2D。
class FakeConstraint extends RefCounted:
	var received_damage: float = 0.0
	var received_count: int = 0
	func take_damage(amount: float, point: Vector2, source) -> void:
		received_damage += amount
		received_count += 1

func _ready() -> void:
	var pipeline := DestructionPipeline.new()

	# Path X：Block 受 100 → 转发 100*0.3 = 30 到每条相连 Constraint
	var b := DBlock.new()
	b.pipeline = pipeline
	b.initial_health = 200.0
	b.health = 200.0
	b.damage_to_constraint_ratio = 0.3
	var c1 := FakeConstraint.new()
	var c2 := FakeConstraint.new()
	b.connected_constraints = [c1, c2]
	b.take_damage(100.0, Vector2.ZERO, "test")
	assert(absf(c1.received_damage - 30.0) < 0.001, "c1 应收 30，got %f" % c1.received_damage)
	assert(absf(c2.received_damage - 30.0) < 0.001, "c2 应收 30，got %f" % c2.received_damage)
	assert(c1.received_count == 1, "c1 应只被调一次")

	# Block 致死后再 take_damage 不再转发（早 return）
	b.take_damage(200.0, Vector2.ZERO, "test")  # 现在 health <= 0，入队
	var prev := c1.received_damage  # = 30 + 60 = 90
	b.take_damage(50.0, Vector2.ZERO, "test")  # 死后再打
	assert(absf(c1.received_damage - prev) < 0.001, "Block 已死，不应再转发")

	# Constraint take_damage 致死入队
	var real_c := DConstraint.new()
	real_c.pipeline = pipeline
	real_c.initial_health = 50.0
	real_c.health = 50.0
	real_c.take_damage(60.0, Vector2.ZERO, "test")
	assert(pipeline.constraint_destroy_queue.size() == 1, "致死应入 constraint_destroy_queue")

	print("[TEST damage_forwarding] ALL PASS")
	get_tree().quit()
```

### Step 5.2 跑测试确认失败 / 修 block.gd 至通过

`block.gd` 已有 for-loop 转发，本 step 应该一次过。若失败，原因可能是 `_queued_for_destroy` early-return 没在转发前生效 —— 检查现行 `take_damage` 实现顺序：转发应在 health 扣完后、入队前；死后再打的 early-return 必须在最前面（已在 Task 2 写了 `if _queued_for_destroy: return`）。

### Step 5.3 提交

```bash
git add Scripts/Prototypes/Destruction/tests/test_damage_forwarding.gd
git commit -m "test(destruction): Path X damage forwarding + Constraint health

Covers Block.take_damage forwarding to Constraints by ratio, idempotent
post-death behavior, and Constraint health-path queueing.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.1, ADR-0007 Path X"
```

---

## Task 6: ConstraintBreaker（物理路径，按 Spike 0 决议）

**Files:**
- Create: `Scripts/Prototypes/Destruction/constraint_breaker.gd`

**验证级别：** 第 5 层（涉及物理量纲，需要 F6 看数值合理）。

**前置：** Task 0 必须已签字。本 task 的具体实现按 spike0 结论的 (a)/(b)/(c) 之一走。

### Step 6.1 写实现（分支按 spike0 决议）

Create `Scripts/Prototypes/Destruction/constraint_breaker.gd`:

```gdscript
# Scripts/Prototypes/Destruction/constraint_breaker.gd
# 系统：每帧扫描所有 Constraint 的"应力"，超阈值入 destruction_pipeline.constraint_destroy_queue。
#
# 应力的具体计算：见 Spike 0 决议（docs/2026-05-25-destruction-prototype-plan-spike0.md）。
#  - (a) 私有 API 读 reaction_force/torque：实现 _stress_via_api
#  - (b) 相对加速度代理：实现 _stress_via_accel_proxy（需缓存上帧速度）
#  - (c) 不实现物理路径：scan() 是空操作，本类仅作占位
#
# 本骨架按 (b) 写 —— 若 spike0 选 (a)，把 _stress 实现替换成 API 调用。
class_name ConstraintBreaker
extends RefCounted

var pipeline: DestructionPipeline = null
var active_constraints: Array = []  # DConstraint

var _prev_vel_cache: Dictionary = {}  # block.instance_id -> Vector2

func register(c: DConstraint) -> void:
	active_constraints.append(c)

func scan(dt: float) -> void:
	# 清理无效 Constraint（block 已销毁、pin 已 freed）
	active_constraints = active_constraints.filter(func(c):
		return is_instance_valid(c.pin_a) and is_instance_valid(c.pin_b) \
			and is_instance_valid(c.block_a) and is_instance_valid(c.block_b))
	for c in active_constraints:
		var sigma := _stress(c, dt)
		if sigma > c.max_reaction_force:
			if pipeline != null:
				pipeline.queue_constraint_destroy(c)

# 应力代理（spike0 策略 (b)）。
func _stress(c: DConstraint, dt: float) -> float:
	var va: Vector2 = c.block_a.linear_velocity
	var vb: Vector2 = c.block_b.linear_velocity
	var prev_va: Vector2 = _prev_vel_cache.get(c.block_a.get_instance_id(), va)
	var prev_vb: Vector2 = _prev_vel_cache.get(c.block_b.get_instance_id(), vb)
	_prev_vel_cache[c.block_a.get_instance_id()] = va
	_prev_vel_cache[c.block_b.get_instance_id()] = vb
	if dt <= 0.0:
		return 0.0
	var aa := (va - prev_va) / dt
	var ab := (vb - prev_vb) / dt
	var n := (c.block_b.global_position - c.block_a.global_position).normalized()
	if n == Vector2.ZERO:
		return 0.0
	var fa := absf(c.block_a.mass * aa.dot(n))
	var fb := absf(c.block_b.mass * ab.dot(n))
	return fa + fb
```

> 若 spike0 选 (a)：`_stress` 内改用 `c.pin_a.get_reaction_force(1.0/dt).length() + c.pin_b.get_reaction_force(1.0/dt).length()`（或 spike 验出的实际 API 形式）。
> 若 spike0 选 (c)：本 task 改为只 commit 一个空骨架 `func scan(dt): pass`，并在 README/此 plan 末尾标记"物理路径推迟 v1.5"。

### Step 6.2 F6 烟雾验证（手搭一根挂重物的 Constraint）

新建 spike 场景 `spike/spike_breaker.tscn`：
- 一个 static body 顶上挂一个 DBlock A
- DBlock A 下面挂 DBlock B（用 DConstraint 双 pin 连接）
- 给 B 一个大向下 impulse / 直接挂质量 5

主脚本 `_physics_process` 里调 `breaker.scan(get_physics_process_delta_time())`，print `sigma` 与是否触发销毁。

预期：
- 静态挂着，sigma ≈ B.mass × g（小数值）
- 给 B 加大向下 impulse → sigma 飙升 → 超阈值 → pipeline.constraint_destroy_queue 出现 1 项

若数值不可信 / 反复回落，回到 Task 0 spike0 重评 (b) → 改选 (c)。

### Step 6.3 提交

```bash
git add Scripts/Prototypes/Destruction/constraint_breaker.gd Scenes/Prototypes/Destruction/spike/spike_breaker.tscn Scenes/Prototypes/Destruction/spike/spike_breaker.gd
git commit -m "feat(destruction): ConstraintBreaker per spike0 strategy

Per-frame stress scan over active constraints; exceeded threshold
queues constraint_destroy. Stress formula implements spike0 choice
<a/b/c>. F6 smoke verified hanging-block snap scenario.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.2,
      docs/2026-05-25-destruction-prototype-plan-spike0.md"
```

---

## Task 7: ImpactWatcher（冲击伤害）+ 单测

**Files:**
- Create: `Scripts/Prototypes/Destruction/impact_watcher.gd`
- Create: `Scripts/Prototypes/Destruction/tests/test_impact_watcher.gd`

**验证级别：** 算法部分第 4 层；触发部分第 5 层（实际 contact callback 触发在 Task 9 整合后 F6）。

### Step 7.1 写失败测试（仅算法 = 伤害换算函数）

Create `Scripts/Prototypes/Destruction/tests/test_impact_watcher.gd`:

```gdscript
extends Node
const ImpactWatcher := preload("res://Scripts/Prototypes/Destruction/impact_watcher.gd")

func _ready() -> void:
	# threshold=2, coefficient=10
	# J=2 → (2-2)*10 = 0 (临界)
	assert(absf(ImpactWatcher.impact_to_damage(2.0, 2.0, 10.0) - 0.0) < 0.001,
		"临界冲击应给 0 伤害")
	# J=1 → 阈值以下不伤
	assert(ImpactWatcher.impact_to_damage(1.0, 2.0, 10.0) == 0.0,
		"低于阈值应给 0")
	# J=5 → (5-2)*10 = 30
	assert(absf(ImpactWatcher.impact_to_damage(5.0, 2.0, 10.0) - 30.0) < 0.001,
		"J=5 阈值 2 系数 10 应给 30, got %f" % ImpactWatcher.impact_to_damage(5.0, 2.0, 10.0))
	# 负 J 防御
	assert(ImpactWatcher.impact_to_damage(-3.0, 2.0, 10.0) == 0.0, "负冲量应给 0")

	print("[TEST impact_watcher] ALL PASS")
	get_tree().quit()
```

### Step 7.2 写实现

Create `Scripts/Prototypes/Destruction/impact_watcher.gd`:

```gdscript
# Scripts/Prototypes/Destruction/impact_watcher.gd
# 系统：监听 Box2D 接触冲量，超阈值 → 入 damage_events 队列。
# spec §4.3：不在 contact callback 直接调 take_damage（避免拓扑中途变更）。
#
# 双块碰撞各扣 (J - threshold) × coef 血量。
class_name ImpactWatcher
extends RefCounted

@export var impact_threshold: float = 2.0
@export var impact_coefficient: float = 10.0

var pipeline: DestructionPipeline = null

# 纯函数（用于单测）
static func impact_to_damage(normal_impulse: float, threshold: float, coefficient: float) -> float:
	if normal_impulse <= threshold:
		return 0.0
	return (normal_impulse - threshold) * coefficient

# 由 DBlock 的 body_entered / RigidBody2D contact_monitor 路径调用，
# 或由 _integrate_forces(state) 中遍历 state.get_contact_count() 取 impulse 时调用。
# 具体集成点在 Task 9 接 LevelBuilder/DBlock 时定。
func on_contact(block_a: DBlock, block_b: DBlock, normal_impulse: float, point: Vector2) -> void:
	var dmg := impact_to_damage(normal_impulse, impact_threshold, impact_coefficient)
	if dmg <= 0.0:
		return
	if pipeline == null:
		return
	# 注意：双方都扣血。同一次接触 callback 在 Box2D 里通常对 A↔B 各回调一次；
	# 这里只在一次回调里同时给 A 和 B 入队，避免双计数。
	pipeline.queue_damage_event({"target": block_a, "amount": dmg, "point": point, "source": "impact"})
	pipeline.queue_damage_event({"target": block_b, "amount": dmg, "point": point, "source": "impact"})
```

> 把"双计数"问题落到一个明确不变量：ImpactWatcher 是单例 / 一份实例，由 contact 路径调用 `on_contact(A, B, J, p)` —— 调用方负责"同一对接触只调一次"。RigidBody2D contact_monitor signals 在每帧每对接触发一次 `body_entered` —— 满足这点。

### Step 7.3 跑测试确认通过

### Step 7.4 提交

```bash
git add Scripts/Prototypes/Destruction/impact_watcher.gd Scripts/Prototypes/Destruction/tests/test_impact_watcher.gd
git commit -m "feat(destruction): ImpactWatcher + threshold/coef tests

Pure impact_to_damage() unit-tested; on_contact() queues damage_events
for both blocks once per contact pair (no double-counting). Integration
into DBlock contact_monitor wiring is in Task 9.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.3"
```

---

## Task 8: DebrisSpawner（纯视觉碎片）

**Files:**
- Create: `Scripts/Prototypes/Destruction/debris_spawner.gd`

**验证级别：** 第 5 层（视觉效果，F6 看）。

### Step 8.1 写实现

Create `Scripts/Prototypes/Destruction/debris_spawner.gd`:

```gdscript
# Scripts/Prototypes/Destruction/debris_spawner.gd
# 系统：在 Block 销毁位置生成 N 个短命 sprite 碎片。
# 纯视觉 —— 不进 Box2D，手动 integration，仅受重力，1.0s 后 alpha 渐隐。
class_name DebrisSpawner
extends Node2D

@export var debris_count: int = 4
@export var debris_lifetime: float = 1.0
@export var debris_color: Color = Color(0.7, 0.5, 0.3, 1.0)
@export var debris_size: float = 4.0
@export var gravity_y: float = 980.0  # 像素 / s²，与 Godot 物理像素重力一致即可

var _debris: Array = []  # [{pos, vel, ang, age}]

func spawn(at: Vector2, base_vel: Vector2, base_ang_vel: float) -> void:
	for i in debris_count:
		var jitter := Vector2(randf_range(-100, 100), randf_range(-150, -50))
		_debris.append({
			"pos": at,
			"vel": base_vel + jitter,
			"ang": randf() * TAU,
			"ang_vel": base_ang_vel + randf_range(-5, 5),
			"age": 0.0,
		})

func _process(delta: float) -> void:
	var alive: Array = []
	for d in _debris:
		d.age += delta
		if d.age >= debris_lifetime:
			continue
		d.vel.y += gravity_y * delta
		d.pos += d.vel * delta
		d.ang += d.ang_vel * delta
		alive.append(d)
	_debris = alive
	queue_redraw()

func _draw() -> void:
	for d in _debris:
		var alpha := 1.0 - (d.age / debris_lifetime)
		var col := debris_color
		col.a *= alpha
		# 用旋转过的小矩形描成"碎块"
		var local := Transform2D(d.ang, d.pos - global_position)
		draw_set_transform_matrix(local)
		draw_rect(Rect2(-debris_size * 0.5, -debris_size * 0.5, debris_size, debris_size), col)
		draw_set_transform_matrix(Transform2D.IDENTITY)
```

### Step 8.2 F6 smoke（接到 Task 9 主场景后再验）

本 task 暂不单独 spike；在 Task 9 主场景挂上 DebrisSpawner，让 pipeline.drain_debris_spawns 流到 `spawn()` 时验。

### Step 8.3 提交

```bash
git add Scripts/Prototypes/Destruction/debris_spawner.gd
git commit -m "feat(destruction): DebrisSpawner with non-physical sprite particles

Manual-integration debris (no Box2D), gravity + alpha fadeout. Will be
fed by DestructionPipeline.drain_debris_spawns in main scene wiring.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.5"
```

---

## Task 9: BlockFactory + LevelBuilder + 砖墙场景 + pipeline 帧末批处理接入

**Files:**
- Create: `Scripts/Prototypes/Destruction/block_factory.gd`
- Create: `Scripts/Prototypes/Destruction/level_builder.gd`
- Create: `Scenes/Prototypes/Destruction/destruction_demo.tscn`
- Create: `Scripts/Prototypes/Destruction/destruction_demo.gd`（主场景控制器）

**验证级别：** 第 5 层。

### Step 9.1 BlockFactory

Create `Scripts/Prototypes/Destruction/block_factory.gd`:

```gdscript
# Scripts/Prototypes/Destruction/block_factory.gd
# 工厂：创建 DBlock + 配 Body 参数 + 加 CollisionShape2D。
# 未来接对象池仅改本类内部，消费者（LevelBuilder）签名不变。
class_name BlockFactory
extends RefCounted

const DBlock := preload("res://Scripts/Prototypes/Destruction/block.gd")

static func create(
	pipeline: DestructionPipeline,
	pos: Vector2,
	block_size: float,
	initial_health: float = 100.0
) -> DBlock:
	var b := DBlock.new()
	b.position = pos
	b.initial_health = initial_health
	b.pipeline = pipeline
	# Body 参数（spec §4.1）
	b.mass = 0.0625  # density 1.0 @ 0.25m
	b.physics_material_override = PhysicsMaterial.new()
	b.physics_material_override.friction = 0.6
	b.physics_material_override.bounce = 0.05
	b.linear_damp = 0.05
	b.angular_damp = 0.1
	b.contact_monitor = true
	b.max_contacts_reported = 8  # 用于 ImpactWatcher
	# Collision shape
	var shape := RectangleShape2D.new()
	shape.size = Vector2(block_size, block_size)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	b.add_child(cs)
	return b
```

> 若 spec 中的 block_size 是米（0.25 m），但 Godot 2D 默认像素—— 在本项目里统一以**像素**为单位。0.25 m 在常规缩放下约 25-32 px。我们把 spec 的 `block_size` 解释成像素初值 = 32（小但可见，匹配 32×32 砖块），后续 Debug 面板可调。

### Step 9.2 LevelBuilder（先只做 Scene 1 砖墙）

Create `Scripts/Prototypes/Destruction/level_builder.gd`:

```gdscript
# Scripts/Prototypes/Destruction/level_builder.gd
# 程序化构造测试场景。MVP 3 个：砖墙、拱门、三层小屋。
# 本 task 只接砖墙；Task 11 加另外两个。
class_name LevelBuilder
extends Node2D

const BlockFactory := preload("res://Scripts/Prototypes/Destruction/block_factory.gd")
const DBlock := preload("res://Scripts/Prototypes/Destruction/block.gd")
const DConstraint := preload("res://Scripts/Prototypes/Destruction/constraint.gd")

@export var block_size: float = 32.0
@export var pipeline: DestructionPipeline
@export var breaker: ConstraintBreaker

var _blocks: Array = []
var _constraints: Array = []

func clear() -> void:
	for b in _blocks:
		if is_instance_valid(b):
			b.queue_free()
	for c in _constraints:
		if c.pin_a != null and is_instance_valid(c.pin_a):
			c.pin_a.queue_free()
		if c.pin_b != null and is_instance_valid(c.pin_b):
			c.pin_b.queue_free()
	_blocks.clear()
	_constraints.clear()

func build_brick_wall(rows: int = 10, cols: int = 10, origin: Vector2 = Vector2.ZERO) -> void:
	# 1) 生成 Block
	var grid: Array = []  # grid[row][col] -> DBlock
	for r in rows:
		var row: Array = []
		for c in cols:
			var pos := origin + Vector2(c * block_size, -r * block_size)
			var b := BlockFactory.create(pipeline, pos, block_size)
			add_child(b)
			row.append(b)
			_blocks.append(b)
		grid.append(row)
	# 2) 邻居 Constraint（spec §4.6：欧氏距离 ≤ block_size * 1.05；排除对角）
	# O(N²) 枚举：100 块 ~ 1 万次比较，可忽略
	var threshold: float = block_size * 1.05
	for i in _blocks.size():
		for j in range(i + 1, _blocks.size()):
			var a: DBlock = _blocks[i]
			var b: DBlock = _blocks[j]
			if a.position.distance_to(b.position) <= threshold:
				_attach_constraint(a, b)

func _attach_constraint(a: DBlock, b: DBlock) -> void:
	# 共享边两端 = 两 block 中心连线垂直方向 ± block_size/2
	var center := (a.position + b.position) * 0.5
	var axis := (b.position - a.position).normalized()
	var perp := Vector2(-axis.y, axis.x) * (block_size * 0.5)
	var p1 := center + perp
	var p2 := center - perp
	var c := DConstraint.create(a, b, p1, p2, self)
	c.pipeline = pipeline
	a.connected_constraints.append(c)
	b.connected_constraints.append(c)
	if breaker != null:
		breaker.register(c)
	_constraints.append(c)
```

### Step 9.3 主场景 destruction_demo.tscn + controller

Create `Scenes/Prototypes/Destruction/destruction_demo.tscn`（Godot Editor 手搓即可）：
- 根 Node2D 名 `Demo`，挂 `destruction_demo.gd`
- 子 Camera2D，position (160, -160)，zoom (2,2) 之类（看场景适配）
- 子 StaticBody2D `Ground`，CollisionShape2D 是个长 segment，y = 0
- 子 Node2D `LevelHolder` —— LevelBuilder 会 `add_child` 到这里
- 子 Node2D `Debris` —— 挂 `DebrisSpawner` 脚本
- 注意 .tscn 文件头：必须含 `uid="uid://..."`（见 memory [[tscn_needs_uid_for_packedscene_refs]]）—— Editor 保存时会自动写

Create `Scripts/Prototypes/Destruction/destruction_demo.gd`:

```gdscript
# Scripts/Prototypes/Destruction/destruction_demo.gd
# 主场景控制器：装配 pipeline / breaker / impact / level_builder，
# 在 _physics_process 末尾按 spec §4.4 顺序执行批处理。
extends Node2D

const DestructionPipeline := preload("res://Scripts/Prototypes/Destruction/destruction_pipeline.gd")
const ConstraintBreaker := preload("res://Scripts/Prototypes/Destruction/constraint_breaker.gd")
const ImpactWatcher := preload("res://Scripts/Prototypes/Destruction/impact_watcher.gd")
const LevelBuilder := preload("res://Scripts/Prototypes/Destruction/level_builder.gd")
const DBlock := preload("res://Scripts/Prototypes/Destruction/block.gd")
const DConstraint := preload("res://Scripts/Prototypes/Destruction/constraint.gd")

@onready var level_holder: Node2D = $LevelHolder
@onready var debris_spawner: DebrisSpawner = $Debris

var pipeline: DestructionPipeline
var breaker: ConstraintBreaker
var impact: ImpactWatcher
var builder: LevelBuilder

func _ready() -> void:
	pipeline = DestructionPipeline.new()
	breaker = ConstraintBreaker.new()
	breaker.pipeline = pipeline
	impact = ImpactWatcher.new()
	impact.pipeline = pipeline

	builder = LevelBuilder.new()
	builder.pipeline = pipeline
	builder.breaker = breaker
	level_holder.add_child(builder)
	_load_scene(1)

func _load_scene(idx: int) -> void:
	builder.clear()
	match idx:
		1:
			builder.build_brick_wall(10, 10, Vector2(-160, -32))
		# 2, 3 在 Task 11 加

func _physics_process(dt: float) -> void:
	# 1) 派发上帧入队的 damage_events
	for ev in pipeline.drain_damage_events():
		var t = ev.target
		if is_instance_valid(t) and t.has_method("take_damage"):
			t.take_damage(ev.amount, ev.point, ev.source)
	# 2) 物理路径扫描（按 spike0 决议）
	breaker.scan(dt)
	# 3) 帧末批处理
	# 3a) 销毁 Constraint
	for c in pipeline.drain_constraint_destroys():
		c.destroy()
	# 3b) 销毁 Block（发信号 → debris spawn 入队）
	for blk in pipeline.drain_block_destroys():
		if is_instance_valid(blk):
			pipeline.queue_debris_spawn({"pos": blk.global_position, "vel": blk.linear_velocity, "ang_vel": blk.angular_velocity})
			blk.queue_free()
	# 3c) 生成视觉碎片
	for d in pipeline.drain_debris_spawns():
		debris_spawner.spawn(d.pos, d.vel, d.ang_vel)

	# 接触冲量入 damage_events（spec §4.3：下一帧处理）
	# RigidBody2D.contact_monitor 信号路径在 _on_block_body_entered 里调 impact.on_contact()
	# 本 task 暂不接 contact_monitor 信号（涉及为每个 block connect signal），先用 _physics_process 取每个 block 的 state 接触遍历
	# —— 推迟到 Step 9.5 接 ImpactWatcher

func queue_external_damage(target: DBlock, amount: float, point: Vector2, source) -> void:
	pipeline.queue_damage_event({"target": target, "amount": amount, "point": point, "source": source})
```

### Step 9.4 F6 验"砖墙能站住"

跑 destruction_demo.tscn：
- 期望：10×10 砖墙站在地面上，不掉、不抖、各块横平竖直
- 若大面积抖动 / 掉散 —— 检查 Constraint 是否真的建上了（在 LevelBuilder 末尾 print `_constraints.size()`，10×10 网格应有 180 条 constraint = 90 横 + 90 竖）
- 若塌一半 —— 检查双 pin 装配是否正确（pin 位置在共享边端点，不在中心）

### Step 9.5 接 ImpactWatcher contact signal

在 BlockFactory.create 末尾加：

```gdscript
b.body_entered.connect(_on_block_contact.bind(b))
```

但 `_on_block_contact` 函数得放在 BlockFactory 之外的某个常驻系统里（factory 是 RefCounted）。**重构方案：** 让主场景 `destruction_demo.gd` 在 BlockFactory.create 之后立即 connect：

```gdscript
# 在 LevelBuilder._attach_constraint 或 BlockFactory.create 之后由 demo 主动 connect 不方便。
# 改：在 LevelBuilder.build_brick_wall 末尾，统一 connect 所有 block：
for b in _blocks:
	b.body_entered.connect(_on_block_body_entered.bind(b))
```

LevelBuilder 上的 `_on_block_body_entered`：

```gdscript
@export var impact: ImpactWatcher

func _on_block_body_entered(other: Node, self_block: DBlock) -> void:
	if not (other is DBlock):
		return  # 只关心 block↔block 碰撞
	# normal_impulse 在 contact callback 里取不到——RigidBody2D 信号没暴露 impulse。
	# 替代：在主场景 `_physics_process` 顶部遍历每个 block 的 PhysicsDirectBodyState2D
	# get_contact_count / get_contact_impulse 拿到 impulse。
	# 本 step 仅 connect signal 占位，真实 impulse 读取放到 Step 9.6。
	pass
```

### Step 9.6 接 contact impulse —— 用 _integrate_forces

在 `block.gd` 加：

```gdscript
@export var impact_watcher: ImpactWatcher = null  # 由 BlockFactory 注入

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if impact_watcher == null:
		return
	for i in state.get_contact_count():
		var other = state.get_contact_collider_object(i)
		if not (other is DBlock):
			continue
		# 防止双计数：只在 self.instance_id < other.instance_id 时处理
		if self.get_instance_id() >= other.get_instance_id():
			continue
		var impulse: Vector2 = state.get_contact_impulse(i)
		var j_normal: float = impulse.length()  # 单一接触的 impulse 模长（近似 normal impulse）
		impact_watcher.on_contact(self, other, j_normal, state.get_contact_local_position(i))
```

更新 BlockFactory.create 接 `impact_watcher`：

```gdscript
static func create(pipeline, pos, block_size, impact: ImpactWatcher, initial_health := 100.0) -> DBlock:
	...
	b.impact_watcher = impact
	...
```

LevelBuilder.build_brick_wall 调用相应签名变更。

### Step 9.7 提交

```bash
git add Scripts/Prototypes/Destruction/block_factory.gd Scripts/Prototypes/Destruction/level_builder.gd Scripts/Prototypes/Destruction/destruction_demo.gd Scenes/Prototypes/Destruction/destruction_demo.tscn
git commit -m "feat(destruction): wire pipeline + brick wall scene + impact contact

LevelBuilder builds Scene 1 (10x10 brick wall) procedurally with
auto-detected adjacency (Euclidean dist threshold, axis-only neighbors).
destruction_demo controller runs the spec §4.4 frame-end batch order.
Per-block _integrate_forces feeds normal impulses into ImpactWatcher.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.4 §4.6"
```

---

## Task 10: DebugInput（LMB 点伤 / RMB 范围）+ F6 验 T1-T3

**Files:**
- Create: `Scripts/Prototypes/Destruction/debug_input.gd`
- Create: `Scripts/Prototypes/Destruction/tests/test_radial_falloff.gd`
- Modify: `project.godot` —— 注册 `DebugLMB`、`DebugRMB`

**验证级别：** 算法第 4 层；触发第 5 层（F6 验 T1-T3）。

### Step 10.1 注册输入

Edit `project.godot` `[input]` 段加：

```
DebugLMB={
"deadzone": 0.5,
"events": [Object(InputEventMouseButton,"button_index":1,"pressed":true,"script":null)]
}
DebugRMB={
"deadzone": 0.5,
"events": [Object(InputEventMouseButton,"button_index":2,"pressed":true,"script":null)]
}
F1ToggleDebugPanel={
"deadzone": 0.5,
"events": [Object(InputEventKey,"physical_keycode":4194332,"script":null)]
}
Scene1={ "deadzone": 0.5, "events": [Object(InputEventKey,"physical_keycode":49,"script":null)] }
Scene2={ "deadzone": 0.5, "events": [Object(InputEventKey,"physical_keycode":50,"script":null)] }
Scene3={ "deadzone": 0.5, "events": [Object(InputEventKey,"physical_keycode":51,"script":null)] }
```

> 实际 keycode 数字以 Godot Editor → Input Map 里录制为准；上面是参考值。手搓时若不确定，直接在 Editor UI 加更稳。

### Step 10.2 写 radial falloff 测试

Create `Scripts/Prototypes/Destruction/tests/test_radial_falloff.gd`:

```gdscript
extends Node
const DebugInput := preload("res://Scripts/Prototypes/Destruction/debug_input.gd")

func _ready() -> void:
	# linear falloff: 1 - r/R, clamp >= 0
	assert(absf(DebugInput.linear_falloff(0.0, 1.5) - 1.0) < 0.001, "中心系数 1.0")
	assert(absf(DebugInput.linear_falloff(0.75, 1.5) - 0.5) < 0.001, "半径中点系数 0.5")
	assert(absf(DebugInput.linear_falloff(1.5, 1.5) - 0.0) < 0.001, "边缘系数 0.0")
	assert(absf(DebugInput.linear_falloff(2.0, 1.5) - 0.0) < 0.001, "超半径系数 0.0")
	assert(absf(DebugInput.linear_falloff(-0.5, 1.5) - 1.0) < 0.001, "负距离 clamp")
	print("[TEST radial_falloff] ALL PASS")
	get_tree().quit()
```

### Step 10.3 写实现

Create `Scripts/Prototypes/Destruction/debug_input.gd`:

```gdscript
# Scripts/Prototypes/Destruction/debug_input.gd
# Debug 鼠标输入（spec §4.3）—— 纯 debug，不是武器系统。
# LMB：点伤；RMB：范围伤害 + 径向冲量（debug 简版，linear falloff）。
class_name DebugInput
extends Node2D

const DBlock := preload("res://Scripts/Prototypes/Destruction/block.gd")

@export var point_damage: float = 50.0
@export var radial_damage_base: float = 200.0
@export var radial_damage_radius: float = 48.0  # 像素（spec 1.5m ≈ 48 px @ 32px/m）
@export var radial_impulse_base: float = 5.0  # N·s

@export var pipeline: DestructionPipeline = null
@export var level_holder: Node2D = null  # 用于遍历活跃 block

static func linear_falloff(r: float, R: float) -> float:
	if R <= 0.0:
		return 0.0
	var k := 1.0 - r / R
	return clampf(k, 0.0, 1.0)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var world_pos := get_global_mouse_position()
	if event.button_index == MOUSE_BUTTON_LEFT:
		_lmb_point_damage(world_pos)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_rmb_radial(world_pos)

func _lmb_point_damage(at: Vector2) -> void:
	# 找最近 block
	var nearest: DBlock = null
	var best := INF
	for child in level_holder.get_children():
		if not (child is DBlock):
			continue
		var d := child.global_position.distance_to(at)
		if d < best:
			best = d
			nearest = child
	if nearest != null and best < 32.0:  # 命中半径 = 一格大小
		pipeline.queue_damage_event({"target": nearest, "amount": point_damage, "point": at, "source": "debug_lmb"})

func _rmb_radial(at: Vector2) -> void:
	for child in level_holder.get_children():
		if not (child is DBlock):
			continue
		var d := child.global_position.distance_to(at)
		if d > radial_damage_radius:
			continue
		var k := linear_falloff(d, radial_damage_radius)
		var dmg := radial_damage_base * k
		var imp := radial_impulse_base * k
		# 走 pipeline（damage 入队，下一帧 dispatcher 派发）
		pipeline.queue_damage_event({"target": child, "amount": dmg, "point": child.global_position, "source": "debug_rmb"})
		# 冲量直接施加 —— 不入队，spec §4.3 明示
		var dir: Vector2 = (child.global_position - at).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2(1, 0)
		child.apply_impulse(dir * imp)
```

> 注：在 LevelBuilder 中 add_child 到 self（LevelBuilder 本身是 Node2D 挂在 LevelHolder 下面）。所以"遍历活跃 block"要遍历 LevelBuilder 的 children，不是 level_holder 的 children。**修正：** demo controller 把 `debug_input.level_holder` 改成指向 `builder`（LevelBuilder 实例）。

### Step 10.4 把 DebugInput 挂到 demo 场景

在 destruction_demo.tscn 加 `DebugInput` 子节点（Node2D + 脚本），demo controller `_ready` 末尾：

```gdscript
$DebugInput.pipeline = pipeline
$DebugInput.level_holder = builder
```

### Step 10.5 F6 验 T1 / T2 / T3

| # | 操作 | 期望 |
|---|---|---|
| T1 | LMB 同一位置 2 次 | 该 Block 消失，留视觉碎片 |
| T2 | LMB 打穿一条竖线 | 上方 Block 部分下落（边缘的因 Constraint 仍能挂住） |
| T3 | RMB 中心范围伤害 | 中心块伤害最高，周围按距离衰减；可能整组塌（Path X 让多个 Constraint 同时受伤断） |

若 T3 没"塌"只"碎"—— 大概率 spike0 选了 (c) 或代理阈值偏高，调 `max_reaction_force` 或 `damage_to_constraint_ratio` 在 inspector 实时调。

### Step 10.6 提交

```bash
git add Scripts/Prototypes/Destruction/debug_input.gd Scripts/Prototypes/Destruction/tests/test_radial_falloff.gd project.godot Scenes/Prototypes/Destruction/destruction_demo.tscn Scripts/Prototypes/Destruction/destruction_demo.gd
git commit -m "feat(destruction): debug LMB/RMB input + radial falloff tests

LMB single-target point damage; RMB radial (queued damage + immediate
impulse per spec §4.3). Linear falloff unit-tested. F6 confirms T1-T3.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.3 §4.7"
```

---

## Task 11: Scene 2（拱门）+ Scene 3（三层小屋）+ 场景切换 + F6 验 T4-T6

**Files:**
- Modify: `Scripts/Prototypes/Destruction/level_builder.gd` —— 加 `build_arch()` 与 `build_house()`
- Modify: `Scripts/Prototypes/Destruction/destruction_demo.gd` —— 在 `_unhandled_input` 里接 Scene1/2/3 按键，调 `_load_scene(n)`

**验证级别：** 第 5 层。

### Step 11.1 build_arch（拱门）

在 LevelBuilder 加：

```gdscript
# 拱门：两根柱（5 高 × 1 宽），柱中心距 6 block_size；横梁 1 高 × 7 宽搁顶。
func build_arch(origin: Vector2 = Vector2.ZERO) -> void:
	var col_h := 5
	var col_w := 1
	var span := 6  # 柱中心距 in blocks
	var beam_w := 7
	# 左柱
	_place_rect(origin, col_w, col_h)
	# 右柱
	_place_rect(origin + Vector2(span * block_size, 0), col_w, col_h)
	# 横梁（高 1，宽 7），起点：左柱顶左移 3 block，y = -5*block_size
	var beam_origin := origin + Vector2(-3 * block_size, -col_h * block_size)
	_place_rect(beam_origin, beam_w, 1)
	# 邻居建 Constraint（全场枚举，spec §4.6）
	_build_all_adjacency_constraints()

func _place_rect(origin: Vector2, w: int, h: int) -> void:
	for r in h:
		for c in w:
			var pos := origin + Vector2(c * block_size, -r * block_size)
			var b := BlockFactory.create(pipeline, pos, block_size, impact_watcher)
			add_child(b)
			_blocks.append(b)

func _build_all_adjacency_constraints() -> void:
	var threshold := block_size * 1.05
	for i in _blocks.size():
		for j in range(i + 1, _blocks.size()):
			var a: DBlock = _blocks[i]
			var b: DBlock = _blocks[j]
			if a.position.distance_to(b.position) <= threshold:
				_attach_constraint(a, b)
```

并把 `build_brick_wall` 里的"邻居构造"也抽到 `_build_all_adjacency_constraints()`，避免代码重复。

### Step 11.2 build_house（三层小屋）

```gdscript
# 三层小屋：两侧墙各 6 高 × 1 宽；三层楼板各 1 高 × 8 宽（含两墙位置）；屋顶 1 高 × 8 宽。
func build_house(origin: Vector2 = Vector2.ZERO) -> void:
	var wall_h := 6
	var floor_w := 8
	# 左墙
	_place_rect(origin, 1, wall_h)
	# 右墙
	_place_rect(origin + Vector2((floor_w - 1) * block_size, 0), 1, wall_h)
	# 三层楼板（y = -1, -3, -5 个 block）
	for row in [1, 3, 5]:
		_place_rect(origin + Vector2(0, -row * block_size), floor_w, 1)
	# 屋顶
	_place_rect(origin + Vector2(0, -wall_h * block_size), floor_w, 1)
	_build_all_adjacency_constraints()
```

### Step 11.3 场景切换

destruction_demo.gd：

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Scene1"):
		_load_scene(1)
	elif event.is_action_pressed("Scene2"):
		_load_scene(2)
	elif event.is_action_pressed("Scene3"):
		_load_scene(3)

func _load_scene(idx: int) -> void:
	builder.clear()
	match idx:
		1: builder.build_brick_wall(10, 10, Vector2(-160, -32))
		2: builder.build_arch(Vector2(-96, -32))
		3: builder.build_house(Vector2(-128, -32))
```

### Step 11.4 F6 验 T4 / T5 / T6

| # | 操作 | 期望 |
|---|---|---|
| T4 | Scene2，RMB 炸柱底 | 该柱塌；房顶按物理拉扯演化（中段断 / 一侧塌） |
| T5 | Scene3，多次 RMB 范围 | 整体倾斜塌陷 |
| T6 | 任意场景，高空掉 Block 到下方 | 接触瞬间 normal impulse 高 → 下方块通过 take_damage + 伤害转发可能直接打散一片 |

T6 要先手动制造"高空掉块"—— 在 demo controller 加一个 `_input` 处理：按 `B` 在鼠标位置上方 200 px 生成一个孤立 DBlock（无 Constraint），让它自由落下砸到墙。

```gdscript
# debug spawn falling block —— 测 T6
if event.is_action_pressed("ui_focus_next"):  # Tab 键临时占用，或注册 SpawnFalling
	var pos := get_global_mouse_position() + Vector2(0, -200)
	var b := BlockFactory.create(pipeline, pos, builder.block_size, impact)
	level_holder.add_child(b)
```

T4 若不"塌"只"碎"—— 大概率是 spike0 选 (c)（无物理路径），柱底炸碎后顶上一段失 Constraint 后会自由落，但和邻居仍有 pin 拉住 → 表现为"挂着掉一截"。这是 spike0 选 (c) 的已知后果，在 spike0 决议里有说明 → 接受。

### Step 11.5 提交

```bash
git add Scripts/Prototypes/Destruction/level_builder.gd Scripts/Prototypes/Destruction/destruction_demo.gd
git commit -m "feat(destruction): scenes 2/3 (arch, 3-story house) + scene switch

Adds build_arch and build_house with shared adjacency-constraint
construction. Keys 1/2/3 hot-swap scenes. F6 confirms T4-T6 to the
degree allowed by spike0 physics-path choice.

Refs: docs/2026-05-24-destruction-prototype-design.md §4.6"
```

---

## Task 12: DebugPanel（runtime 调参 + 屏显统计 + 3 机制开关）+ F6 验 T7

**Files:**
- Create: `Scripts/Prototypes/Destruction/debug_panel.gd`
- Modify: `Scenes/Prototypes/Destruction/destruction_demo.tscn` —— 加 DebugPanel CanvasLayer

**验证级别：** 第 5 层（UI + 隔离调试效果）。

### Step 12.1 Panel 骨架

Create `Scripts/Prototypes/Destruction/debug_panel.gd`:

```gdscript
# Scripts/Prototypes/Destruction/debug_panel.gd
# spec §4.8 —— runtime 调参 + on-screen 统计 + 3 机制独立开关。
# 用最低成本实现：CanvasLayer + Control + 一堆 SpinBox/CheckBox。
extends CanvasLayer

@export var demo: Node  # destruction_demo 主控
@export var impact: ImpactWatcher
@export var breaker: ConstraintBreaker
@export var debug_input: DebugInput

@onready var panel: Control = $Panel
@onready var fps_label: Label = $Panel/Stats/FpsLabel
@onready var block_count_label: Label = $Panel/Stats/BlockCountLabel
@onready var constraint_count_label: Label = $Panel/Stats/ConstraintCountLabel
@onready var per_frame_label: Label = $Panel/Stats/PerFrameLabel

@onready var sw_forwarding: CheckBox = $Panel/Toggles/ForwardingToggle
@onready var sw_physics_path: CheckBox = $Panel/Toggles/PhysicsPathToggle
@onready var sw_impact: CheckBox = $Panel/Toggles/ImpactToggle

# 在 demo controller 里读这些开关：
var forwarding_enabled: bool = true
var physics_path_enabled: bool = true
var impact_enabled: bool = true

var _prev_destroy_count_block: int = 0
var _prev_destroy_count_constraint: int = 0

func _ready() -> void:
	visible = true
	sw_forwarding.toggled.connect(func(b): forwarding_enabled = b)
	sw_physics_path.toggled.connect(func(b): physics_path_enabled = b)
	sw_impact.toggled.connect(func(b): impact_enabled = b)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("F1ToggleDebugPanel"):
		panel.visible = not panel.visible

func _process(_dt: float) -> void:
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	block_count_label.text = "Blocks: %d" % demo.builder._blocks.size()
	var c_count := 0
	for c in demo.builder._constraints:
		if is_instance_valid(c.pin_a):
			c_count += 1
	constraint_count_label.text = "Constraints: %d" % c_count
	# per-frame destroy: 由 demo controller 在批处理时记录到一个公共 dict
	per_frame_label.text = "Frame destroys (B/C): %d / %d" % [demo.frame_destroyed_blocks, demo.frame_destroyed_constraints]
```

### Step 12.2 demo controller 接 3 个开关

在 `destruction_demo.gd` 改：

```gdscript
@onready var debug_panel: CanvasLayer = $DebugPanel

var frame_destroyed_blocks: int = 0
var frame_destroyed_constraints: int = 0
```

- Path X 转发：在 block.gd 里把 `for c in connected_constraints: c.take_damage(...)` 包一层 `if debug_panel != null and debug_panel.forwarding_enabled: ...`
  - 但 block.gd 是模型层，**不应**反向引用 debug_panel。**改：** 给 DBlock 加一个 `static var path_x_enabled: bool = true`，让 debug_panel 切它。
- ConstraintBreaker 物理路径：在 `breaker.scan(dt)` 前加 `if debug_panel.physics_path_enabled:` 守卫
- ImpactWatcher：在 block.gd `_integrate_forces` 中加 `if not ImpactWatcher.enabled: return` 守卫（同上，加 `static var enabled`）

### Step 12.3 Panel UI 元素

在 destruction_demo.tscn 加 CanvasLayer → Control（Panel）→ 子树：
- VBoxContainer "Stats" 子：4 个 Label
- VBoxContainer "Toggles" 子：3 个 CheckBox
- VBoxContainer "Tweaks" 子：以 inspector 拖入这些 export 变量的 SpinBox 替代（简化：只把数值打到 Label，先不做 SpinBox 双向绑定，调参靠 inspector）

> **简化决定：** spec 列了 11 个可调参数。本 task 仅落屏显统计 + 3 个开关 + F1 显隐。可调参数全部走 inspector（在 DebugInput / Constraint 默认值的 export 上调）。如果 user 体感需要 in-game SpinBox，开 follow-up。

### Step 12.4 F6 验 T7（关闭"伤害转发"重复 T3）

| # | 操作 | 期望 |
|---|---|---|
| T7 | F1 显 Panel → 取消勾"ForwardingToggle" → 重复 T3 | 中心块销毁，但周围结构基本保留（验证 Path X 是否在起作用） |

也顺便验：
- 关掉"PhysicsPathToggle" → spike0 选 (a)/(b) 时拱门塌方退化为只剩伤害路径
- 关掉"ImpactToggle" → T6 高空掉块砸不出伤害

### Step 12.5 提交

```bash
git add Scripts/Prototypes/Destruction/debug_panel.gd Scripts/Prototypes/Destruction/destruction_demo.gd Scripts/Prototypes/Destruction/block.gd Scripts/Prototypes/Destruction/impact_watcher.gd Scenes/Prototypes/Destruction/destruction_demo.tscn
git commit -m "feat(destruction): debug panel with stats + 3 isolation switches

F1 toggles a HUD with FPS/Block/Constraint counts and per-frame destroy
deltas. Three checkboxes independently disable damage forwarding,
physics-path breakage, and impact damage—isolated debugging for T7.
Runtime tweaks remain on inspector (export vars).

Refs: docs/2026-05-24-destruction-prototype-design.md §4.8"
```

---

## Task 13: 验收清单 + 性能基线 + 跨 spec 契约校验

**Files:**
- Modify: `docs/superpowers/plans/2026-05-25-destruction-prototype-plan.md` —— 在末尾追加 user F6 签字清单回收
- 无代码改动；本 task 是验收 + 文档收尾

### Step 13.1 跑全套自动化测试

```
test_destruction_pipeline.gd  → ALL PASS
test_block_damage.gd          → ALL PASS
test_damage_forwarding.gd     → ALL PASS
test_impact_watcher.gd        → ALL PASS
test_radial_falloff.gd        → ALL PASS
```

任一退化即停下来排查。

### Step 13.2 跨 spec 契约校验

```bash
grep -nE "weapon|projectile|effect" Scripts/Prototypes/Destruction/
```

**期望：零匹配**（单向依赖 —— 破坏系统对武器系统零感知，ADR-0007 §"对破坏 spec 的简化"）。

`Block.take_damage` / `DConstraint.take_damage` 签名核对：

```
(amount: float, point: Vector2, source) -> void
```

—— 与 ADR-0007 §2 一致。

### Step 13.3 性能基线

- 跑 Scene 3（三层小屋，~50 block）→ FPS 应稳 60
- 跑 Scene 1（10×10 = 100 block）→ FPS 应稳 60
- 把砖墙改成 14×14 = 196 block（手动调 demo_load）→ 看是否还稳 60；记录到 panel 截图
- 大规模范围伤害瞬间帧时间观察：随手按 RMB 连发 5 次，看是否有 > 16.6ms 帧（panel 加一个"max frame time last 1s"会更直观，做不做随时间）

### Step 13.4 user F6 签字（必需）

请 user 实测以下清单并签字：

```
[ ] Scene 1：T1 LMB×2 同位置 → 块消失 + 碎片
[ ] Scene 1：T2 LMB 打穿竖线 → 上方部分下落
[ ] Scene 1：T3 RMB 中心 → 衰减 + 可能整组塌
[ ] Scene 2：T4 RMB 炸柱底 → 塌（spike0 (c) 路线下：挂着掉一截也算 pass）
[ ] Scene 3：T5 多次 RMB → 整体倾斜
[ ] 任意：T6 高空掉块 → 砸出冲击伤害链
[ ] Panel T7：关 ForwardingToggle 重复 T3 → 周围结构基本保留
[ ] Panel：关 PhysicsPathToggle / ImpactToggle 隔离调试 OK
[ ] Scene 1 (10×10) 稳 60fps
[ ] Scene 3 稳 60fps
[ ] F1 隐藏 / 显示 Panel
[ ] 数字键 1/2/3 切场景 + clear() 不留尸
```

### Step 13.5 标记 milestone

```bash
git commit --allow-empty -m "chore(destruction): v1 prototype acceptance signoff

All checklist items in 2026-05-25-destruction-prototype-plan.md Step
13.4 confirmed by user. Spec 2026-05-24-destruction-prototype-design.md
v1 (MVP) section §3.1 success criteria 1-7 met to the extent allowed
by spike0 decision."
```

---

## 后续步骤（v1.5 开 follow-up plan）

按 spec §3.2：

- **视觉合并层（阶段 B）**：一组未被打扰的相连 Block 自动用合并 sprite 覆盖
- **Block 销毁瞬间径向冲量**："溅射感"
- **GPU 粒子碎片**
- **材质枚举（参数包）**
- **如 spike0 选 (c)：补回物理路径** —— 调研其他代理（例如挂上 ContactImpulse 阈值替代）

按 spec §6：

- Constraint 邻居 O(N²) → spatial hash
- Block 对象池
- 接武器系统（删除本 spec 的 debug 输入）
- 接 3C 角色

---

## 风险与回滚

| 风险 | 缓解 |
|---|---|
| Spike 0 选 (c)，T4 塌方表现不达期望 | 在 spike0 决议里就标记接受，v1.5 follow-up 补 |
| 双 pin 装配仍有可感旋转 | 调 pin 在共享边上的距离（间距越大刚度越强） |
| Scene 3 (~50 block) 帧率掉 | 检查 contact_monitor + max_contacts_reported 设置是否过高 |
| ImpactWatcher 双计数 | 已通过 `instance_id <` 守卫；F6 观察"每次接触触发 2 次伤害事件"现象，如发现立即排查 |
| Block 销毁时其连接 Constraint 没清理 | ConstraintBreaker.scan 里有 `is_instance_valid(pin_a/pin_b)` filter；F6 看是否报 freed instance access 错误 |

回滚顺序：
1. revert Task 13（签字 commit）
2. revert Task 12（panel） —— 内核仍可玩
3. revert Task 11（额外场景） —— 只剩砖墙
4. revert Task 10（debug input） —— 没法手动触发伤害，但 ImpactWatcher 路径仍可被高空掉块触发
5. revert Task 9（场景+pipeline 接入） —— 回到纯 lib 状态，单测仍跑过
6. revert Task 0 spike → 完全删除

---

## 备注

- 计划里的所有 spec 像素/米单位换算：spec 写 0.25 m，本计划取 32 px（约 32px/m 缩放）。所有"米"参数（半径 1.5m → 48 px、阈值 200 N → 数值原样，因为 Box2D 在 godot-box2d 里用像素 SI 还是米 SI 取决于 addon 单位约定）—— **Task 0 spike 时顺便确认单位**，若发现 godot-box2d 用像素-牛顿混合体系，本计划所有阈值在 Task 12 之前先在 inspector 调一遍。
- 本计划严格遵循 superpowers/writing-plans 的 "DRY, YAGNI, TDD, frequent commits" 原则：每个 task 都是 TDD（先红测试 → 实现 → 绿测试 → commit），每个 commit 都是可独立验证的进度切片。
