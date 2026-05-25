# 3C 自管地面摩擦 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Box2D 内置 Coulomb 摩擦从 Player 上彻底关掉（`PhysicsMaterial.friction = 0`），并在 GDScript 里按 `F = -sign(vx)·μ·m·g` 自己算地面摩擦，根除"落地丢 vx / 卡墙 / 卡侧面"三类副作用。

**Architecture:** 新增 `GroundFriction` 纯静态 helper（RefCounted，仿 `EngineTorque` / `GroundCheck` 风格），仅在地面分支被调用，通过 `PhysicsDirectBodyState2D.get_contact_collider_object()` 读取当前接地 collider 的 `PhysicsMaterial.friction` 作为 μ。空中分支零改动（保 ADR-0004）。`_compute_engine_force_x(vx)` 签名扩展为 `_compute_engine_force_x(state)`，从 state 取 vx 并把摩擦合入地面力分支。

**Tech Stack:** Godot 4 + godot-box2d GDExtension；GDScript；纯函数测试（assert in `_ready`，仿 `test_engine_torque.gd`）。

**关键前置：** [FSM 重构](2026-05-24-3c-movement-fsm-refactor-design.md) **已完成**（`movement_state.gd`、`test_movement_state.gd`、`_compute_engine_force_x()` 均存在）。本计划直接在已重构的代码骨架上动刀。

**验证级别：** 物理输出会变 → **第 5 层（人工 F6 签字）必需**，按 memory `feedback_verify_each_edit`。

**相关文档：**
- 设计 spec：[2026-05-25-3c-custom-ground-friction-design.md](2026-05-25-3c-custom-ground-friction-design.md)
- ADR：[ADR-0011 角色摩擦自管派](adr/0011-custom-friction-over-box2d.md)
- 总览：[3C-prototype-design.md §4.2](3C-prototype-design.md)

---

## 文件清单

**Create:**
- `Scripts/Prototypes/3C/ground_friction.gd` — 新 helper（30 行，纯静态）
- `Scripts/Prototypes/3C/tests/test_ground_friction.gd` — `compute_force` 全覆盖单测

**Modify:**
- `Scenes/Prototypes/3C/player.tscn` — `PhysicsMaterial.friction` 0 → 0.0（关 Box2D 内置摩擦）
- `Scripts/Prototypes/3C/player.gd` — `_compute_engine_force_x` 签名改吃 `state`，地面分支 +摩擦一行
- `Scenes/Prototypes/3C/test_level.tscn` — `MatMud.friction` 10.0 → 2.0（避免"禁区"）

---

## Task 1: 新增 `GroundFriction` helper + 单测（TDD）

**Files:**
- Create: `Scripts/Prototypes/3C/tests/test_ground_friction.gd`
- Create: `Scripts/Prototypes/3C/ground_friction.gd`

### Step 1.1 写失败测试

Create `Scripts/Prototypes/3C/tests/test_ground_friction.gd`:

```gdscript
# Scripts/Prototypes/3C/tests/test_ground_friction.gd
# 纯函数测试 —— 在 _ready 时跑断言，全部通过则打印 PASS。
# 仅覆盖 compute_force；read_ground_mu 因 PhysicsDirectBodyState2D 无法 mock，靠人工 F6 覆盖。
extends Node

const GroundFriction := preload("res://Scripts/Prototypes/3C/ground_friction.gd")

static func _approx(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) < eps

func _ready() -> void:
	# 1) 正向跑动 + 默认材质（Walkway μ=1.0）
	assert(_approx(GroundFriction.compute_force(800.0, 1.0, 2500.0, 1.0), -2500.0),
		"Walkway 朝右跑应给 -2500 反向摩擦力")

	# 2) 反向跑动对称
	assert(_approx(GroundFriction.compute_force(-800.0, 1.0, 2500.0, 1.0), 2500.0),
		"Walkway 朝左跑应给 +2500 反向摩擦力")

	# 3) Ice μ=0.5
	assert(_approx(GroundFriction.compute_force(800.0, 1.0, 2500.0, 0.5), -1250.0),
		"Ice μ=0.5 应给 -1250")

	# 4) Mud 推荐值 μ=2.0
	assert(_approx(GroundFriction.compute_force(800.0, 1.0, 2500.0, 2.0), -5000.0),
		"Mud μ=2.0 应给 -5000")

	# 5) DEADBAND 正向
	assert(_approx(GroundFriction.compute_force(0.5, 1.0, 2500.0, 1.0), 0.0),
		"|vx|=0.5 < DEADBAND(1.0) 应返回 0")

	# 6) DEADBAND 负向
	assert(_approx(GroundFriction.compute_force(-0.5, 1.0, 2500.0, 1.0), 0.0),
		"|vx|=0.5 反向也应返回 0")

	# 7) μ=0 守卫
	assert(_approx(GroundFriction.compute_force(800.0, 1.0, 2500.0, 0.0), 0.0),
		"μ=0 应返回 0（不施加摩擦）")

	# 8) μ<0 守卫
	assert(_approx(GroundFriction.compute_force(800.0, 1.0, 2500.0, -1.0), 0.0),
		"μ<0 应返回 0（防御性兜底）")

	# 9) mass 线性
	assert(_approx(GroundFriction.compute_force(800.0, 2.0, 2500.0, 1.0), -5000.0),
		"mass=2 时摩擦应线性翻倍")

	print("[TEST ground_friction] ALL PASS")
	get_tree().quit()
```

### Step 1.2 跑测试确认失败（脚本不存在）

挂到一个临时场景或在 editor 里用脚本运行；预期：`preload` 失败 / `GroundFriction` 未定义。

### Step 1.3 写最小实现

Create `Scripts/Prototypes/3C/ground_friction.gd`:

```gdscript
# Scripts/Prototypes/3C/ground_friction.gd
# 自定义地面摩擦 —— Coulomb 模型 F = -sign(vx) · μ · m · g。
# 仅在地面分支调用。空中不应使用本模块（违反 ADR-0004 "空中无阻力"）。
# 设计：ADR-0011 角色摩擦自管派、docs/2026-05-25-3c-custom-ground-friction-design.md
class_name GroundFriction
extends RefCounted

const DEADBAND: float = 1.0  # px/s，低于此 |vx| 不施加摩擦（避免符号抖动）

# 找出最"地面"的 contact（n.y 最负 = 最朝上）并读其 PhysicsMaterial.friction。
# 调用方需保证 is_grounded 为真；若没有满足阈值的 contact 返回 0。
# 若 collider 未挂 PhysicsMaterial，兜底为 1.0（视作 Walkway 默认）。
static func read_ground_mu(state: PhysicsDirectBodyState2D, cos_theta_max: float) -> float:
	var mu := 0.0
	var min_ny := -cos_theta_max
	for i in state.get_contact_count():
		var n := state.get_contact_local_normal(i)
		if n.y < min_ny:
			min_ny = n.y
			var obj := state.get_contact_collider_object(i)
			if obj is PhysicsBody2D:
				var mat: PhysicsMaterial = obj.physics_material_override
				mu = mat.friction if mat != null else 1.0
	return mu

# 返回应施加的水平摩擦力（已带方向，加到 net force 上即可）。
# 公式：F = -sign(vx) · μ · m · g。
static func compute_force(vx: float, mass: float, g: float, mu: float) -> float:
	if absf(vx) < DEADBAND or mu <= 0.0:
		return 0.0
	return -signf(vx) * mu * mass * g
```

### Step 1.4 跑测试确认通过

Godot editor → 打开 `test_ground_friction.gd` 所在的临时 runner 场景 → F6 → 期望控制台输出：

```
[TEST ground_friction] ALL PASS
```

（与 `test_engine_torque.gd` 同一套运行约定。）

### Step 1.5 提交

```bash
git add Scripts/Prototypes/3C/ground_friction.gd Scripts/Prototypes/3C/tests/test_ground_friction.gd
git commit -m "feat(3c): add GroundFriction helper with Coulomb model

Pure static module computing F = -sign(vx)·μ·m·g for the ground branch.
Includes read_ground_mu() that walks contact list and picks the most
ground-like normal. Full unit test coverage of compute_force; read_ground_mu
deferred to F6 manual verification.

Refs: ADR-0011, docs/2026-05-25-3c-custom-ground-friction-design.md"
```

---

## Task 2: Player 关闭 Box2D 内置摩擦

**Files:**
- Modify: `Scenes/Prototypes/3C/player.tscn`

### Step 2.1 改 PhysicsMaterial.friction

打开 `Scenes/Prototypes/3C/player.tscn`，找到 `[sub_resource type="PhysicsMaterial" id="PlayerMat"]`（或类似 id），在其属性里加：

```diff
 [sub_resource type="PhysicsMaterial" id="PlayerMat"]
+friction = 0.0
```

若 sub_resource 块当前为空（默认 friction = 1.0，未显式写出），需要新增 `friction = 0.0` 一行。

> 操作可二选一：(a) 在 Godot Editor → Player.tscn → RigidBody2D → Physics Material Override → friction 设 0.0；(b) 直接编辑 .tscn 文件文本。两种方式效果等价。

### Step 2.2 验证 parse + import

在 Godot Editor 中重新打开 `player.tscn`，确认 inspector 显示 `Physics Material Override → Friction = 0.0`，无 import 错误。

### Step 2.3 提交

```bash
git add Scenes/Prototypes/3C/player.tscn
git commit -m "chore(3c): set Player PhysicsMaterial.friction = 0.0

Disables Box2D built-in Coulomb friction on the player body. Ground
friction will be re-applied in code via GroundFriction (next task).

Refs: ADR-0011"
```

---

## Task 3: `player.gd` 接入 `GroundFriction`

**Files:**
- Modify: `Scripts/Prototypes/3C/player.gd:9-12` (preload 区)
- Modify: `Scripts/Prototypes/3C/player.gd:95` (调用处)
- Modify: `Scripts/Prototypes/3C/player.gd:106-115` (`_compute_engine_force_x` 方法体)

### Step 3.1 添加 preload

在文件顶部 preload 列表里加一行：

```diff
 const EngineTorque := preload("res://Scripts/Prototypes/3C/engine_torque.gd")
 const JumpController := preload("res://Scripts/Prototypes/3C/jump_controller.gd")
 const InputBuffer := preload("res://Scripts/Prototypes/3C/input_buffer.gd")
 const MovementState := preload("res://Scripts/Prototypes/3C/movement_state.gd")
+const GroundFriction := preload("res://Scripts/Prototypes/3C/ground_friction.gd")
```

### Step 3.2 扩展 `_compute_engine_force_x` 签名

把 `_compute_engine_force_x(vx: float)` 改为 `_compute_engine_force_x(state: PhysicsDirectBodyState2D)`：在方法内部用 `state.linear_velocity.x` 取 vx，并在地面分支调用 `GroundFriction`。

改后的方法：

```gdscript
# 按当前状态选 ground/air 发动机配方，返回本帧水平力分量。
# 地面分支额外叠加自管 Coulomb 摩擦（ADR-0011）；空中分支零改动（ADR-0004）。
func _compute_engine_force_x(state: PhysicsDirectBodyState2D) -> float:
	var vx := state.linear_velocity.x
	var input_dir := Input.get_axis("Left", "Right")  # -1, 0, +1
	var v_target := input_dir * v_max
	var on_ground := MovementState.is_grounded_state(current_state)
	var f_max := f_max_ground if on_ground else f_max_air
	var f := EngineTorque.compute(vx, v_target, f_max, saturation_full)
	if on_ground:
		# 自管 Coulomb 摩擦（ADR-0011）。Player.PhysicsMaterial.friction = 0
		# 已关 Box2D 内置摩擦，这里独立按 F = -sign(vx)·μ·m·g 给出。
		var mu := GroundFriction.read_ground_mu(state, cos_theta_max)
		f += GroundFriction.compute_force(vx, mass, gravity_y, mu)
		# 主动刹车（§4.2，默认 f_active_brake = 0）—— 保留作为可选叠加
		if input_dir == 0.0 and absf(vx) > 0.01:
			f -= signf(vx) * f_active_brake
	return f
```

### Step 3.3 更新调用点

`_integrate_forces` 中原行：

```gdscript
force.x += _compute_engine_force_x(state.linear_velocity.x)
```

改为：

```gdscript
force.x += _compute_engine_force_x(state)
```

### Step 3.4 验证 parse + 场景 smoke load

Godot Editor 重新加载 `player.gd` —— 期望无 parse error；打开 `test_level.tscn` —— 期望 inspector 正常显示 Player3C，无 missing script 提示。

### Step 3.5 提交

```bash
git add Scripts/Prototypes/3C/player.gd
git commit -m "feat(3c): call GroundFriction in ground branch

Extends _compute_engine_force_x to accept the physics state (for contact
list access), reads ground μ from the most-ground-like contact's
PhysicsMaterial, and adds the computed friction force. Air branch
unchanged (preserves ADR-0004 'no air drag').

f_active_brake kept as optional additive brake (default 0).

Refs: ADR-0011, docs/2026-05-25-3c-custom-ground-friction-design.md §3.4"
```

---

## Task 4: 重新校准 Mud 摩擦（test_level）

**Files:**
- Modify: `Scenes/Prototypes/3C/test_level.tscn`

### Step 4.1 改 MatMud.friction

找到 `[sub_resource type="PhysicsMaterial" id="MatMud"]` 块（若当前 test_level 已删除/不存在 Mud 区，跳过本任务并在最后向 user 说明），改：

```diff
 [sub_resource type="PhysicsMaterial" id="MatMud"]
-friction = 10.0
+friction = 2.0
```

> 注：当前 `test_level.tscn` 仅有 `MatDefault (friction=0.4)`，未见独立 `MatIce` / `MatMud`。**若文件实际无 Mud 材质，则本 Task 改为：** 在 `test_level.tscn` 里新增两个 sub_resource 并把 Mud / Ice 区段的 `physics_material_override` 替换为它们。具体补丁待执行时按现状选择：
> - **(a) 已有 MatMud / MatIce**：按上述 diff 改 friction
> - **(b) 缺这两个材质**：在 user 执行 F6 前先和 user 确认是要补区段还是改用 MatDefault 模拟，避免越权扩张测试关

### Step 4.2 验证 import

Godot Editor 重新加载 `test_level.tscn`，inspector 检查 Mud 节点的 PhysicsMaterial → Friction = 2.0。

### Step 4.3 提交

```bash
git add Scenes/Prototypes/3C/test_level.tscn
git commit -m "tune(3c): recalibrate MatMud.friction 10.0 -> 2.0

With Player.friction = 0 and self-managed ground friction (ADR-0011),
μ=10 would require friction force 25000 vs engine f_max=8000 — player
becomes immobile ('禁区'). μ=2.0 gives ~675 px/s top speed (vs Walkway
~738 with μ=1.0) — 'slow but walkable'.

Refs: ADR-0011, docs/2026-05-25-3c-custom-ground-friction-design.md §3.5"
```

---

## Task 5: 回归测试 + 人工 F6 签字（验证级别 5）

### Step 5.1 跑已有自动化测试，确认无回归

- 跑 `Scripts/Prototypes/3C/tests/test_engine_torque.gd`：期望 `ALL PASS`
- 跑 `Scripts/Prototypes/3C/tests/test_input_buffer.gd`（若存在）：期望 `ALL PASS`
- 跑 `Scripts/Prototypes/3C/tests/test_movement_state.gd`：期望 `ALL PASS`
- 跑 `Scripts/Prototypes/3C/tests/test_ground_friction.gd`（本计划新增）：期望 `ALL PASS`

任一退化即停下来排查，不要绕过。

### Step 5.2 请 user 执行 F6 复测清单

把以下清单交给 user 在 `test_level.tscn` 里实测，并签字回收：

```
[ ] Wall 不再卡：朝右贴 Wall 起跳 → 自然下落到底
[ ] Stair 侧面不再卡：起跳撞 Stair3 侧面 → 自然下落
[ ] 落地保留 vx：从 PlatformA(y=420) 助跑跳到 Walkway(y=564)，水平速度明显保留
[ ] Walkway 减速感：松手能在 ~0.3s 内停下
[ ] Ice 比 Walkway 明显滑：松手要 ~0.6s 才停（若有 Ice 区段）
[ ] Mud（μ=2.0）能走但慢：顶速观感 ~675 px/s（若有 Mud 区段）
[ ] Walkway 极速：跑顶速 ~738 px/s（vs 改前 800，~8% 降低，接受）
[ ] f_active_brake 仍生效：Debug 面板把 brake 拖到 5000，松手停止时间应显著缩短
[ ] DynamicBox 互动不退化：推箱子手感无回归
[ ] 现有 Coyote / Buffer 行为无回归
```

### Step 5.3 user 签字后提交"验证完毕"标记

> 该步骤无代码改动；可选写一行 commit 标记 milestone：

```bash
git commit --allow-empty -m "chore(3c): verified custom ground friction via F6 signoff

All checklist items in 2026-05-25-3c-custom-ground-friction-plan.md
Step 5.2 confirmed by user. ADR-0011 promoted from Draft to Accepted."
```

并把 ADR-0011 的状态从 Draft 改为 Accepted（如果 ADR 文档使用 status 字段）。

---

## 风险与回滚

按 spec §6 风险表，最大可能问题是 **Mud μ=2.0 手感不对** 或 **极速 738 玩家不接受**。两者都通过 inspector 实时调节解决，无需回滚代码。

若发现根本性问题（比如 `read_ground_mu` 在多接触点边界闪烁严重），回滚顺序：
1. revert Task 3 (player.gd) → Box2D 摩擦仍是 0，玩家会"溜冰"但不卡墙
2. revert Task 2 (player.tscn `friction = 0.0` → 删掉这行) → 完全回到改前

Task 1 (新 helper + 测试) 和 Task 4 (Mud 调参) 可独立保留，无副作用。

---

## 备注：本计划与 spec §7 的顺序一致性

spec §7 要求"先 FSM 重构、后本设计"。**FSM 重构已在仓库里实施完成**（`movement_state.gd` 与 `_compute_engine_force_x()` 私有方法均存在），故本计划直接按已有骨架展开，无需再做 FSM 前置工作。
