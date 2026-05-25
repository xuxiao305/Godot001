# 武器原型 v1 实施计划（Weapon × Projectile × Effect 三元组）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在仓库里落地武器原型 v1，达成 spec §1.3 的 8 条成功标准（鼠标瞄准的手枪直射弹 + 火箭炮抛物线弹、自爆跳、后坐力开关、独立替换三元组、runtime 调参面板）。

**Architecture:** 严格按 [ADR-0010](../../../../../ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/adr/0010-weapon-projectile-effect-decomposition.md) 三层分解 —— Weapon 触发并实例化 Projectile，Projectile 命中后实例化 Effect，Effect 是双通道容器（DamageField + ForceField）按 [ADR-0007](../../../../../ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/adr/0007-effect-dual-channel.md) 对 dynamic body / take_damage 受体作用。Effect 通过 duck typing 调用 `take_damage(amount, point, source)`，**不** import 任何破坏/3C 类型 —— 单向依赖。

**Tech Stack:** Godot 4.6 + godot-box2d GDExtension；GDScript；纯函数测试沿用 `tests/test_engine_torque.gd` 的 `_ready` 断言风格；范围查询用 Godot 原生 `PhysicsShapeQueryParameters2D + CircleShape2D + intersect_shape`（已在 `Scripts/Demos/demo_level.gd:109` 验证 `intersect_point` 可用，shape 版同源 API）。

**单位约定：** 沿用 3C 的 1 m = 100 px。spec §4 中所有 m / m·s / N·s 数值在 export 默认值里乘以 `PX_PER_M = 100.0`，与 [player.gd:8](../../../Scripts/Prototypes/3C/player.gd) 保持一致。

**验证级别：** 物理输出（自爆跳、推飞、CCD 防穿透、recoil 量级）→ **第 5 层（人工 F6 签字）必需**，按 memory `feedback_verify_each_edit`。纯函数（falloff、cooldown、impulse 计算）走第 4 层自动化测试。

**相关文档：**
- 设计 spec：[weapon-prototype-design.md](../../../../../ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/weapon-prototype-design.md)
- ADR：
  - [0007 Effect 双通道](../../../../../ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/adr/0007-effect-dual-channel.md)
  - [0008 自爆跳 ≠ 后坐力](../../../../../ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/adr/0008-self-splash-jump.md)
  - [0009 直射弹 = 高速物理弹](../../../../../ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/adr/0009-direct-shot-is-physics-projectile.md)
  - [0010 三元组分解](../../../../../ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/adr/0010-weapon-projectile-effect-decomposition.md)
- 复用：[player.gd](../../../Scripts/Prototypes/3C/player.gd)、[test_level.tscn](../../../Scenes/Prototypes/3C/test_level.tscn)

**关键架构决策（spec §6 Open Questions 在本计划中落定）：**
- **Effect 子组件 = Node**（非 Resource）：可在 .tscn 里挂为 Effect 主节点的子节点直接编辑参数，Debug 面板可遍历 children 调参。spec §6 Open Question 1 落定。
- **`take_damage(amount: float, point: Vector2, source: Node) -> void`** —— source 参数类型 = Node（最朴素，duck typing），ADR-0007 Open Question 落定。
- **碰撞层位**：在 `project.godot` 显式声明 4 层 —— `1 = world`、`2 = player`、`3 = destructible`、`4 = projectile`。Projectile mask = 1 + 3（不碰 player，避免自碰；spec §4.2）。

---

## 文件清单

**Create（脚本）:**
- `Scripts/Prototypes/Weapon/weapon.gd` — Weapon 主类
- `Scripts/Prototypes/Weapon/projectile.gd` — Projectile 主类
- `Scripts/Prototypes/Weapon/effect.gd` — Effect 主类（双通道容器 + 视觉）
- `Scripts/Prototypes/Weapon/damage_fields/point_damage.gd`
- `Scripts/Prototypes/Weapon/damage_fields/radial_damage.gd`
- `Scripts/Prototypes/Weapon/force_fields/directional_impulse.gd`
- `Scripts/Prototypes/Weapon/force_fields/radial_blast.gd`
- `Scripts/Prototypes/Weapon/test_dummy.gd` — 受体（dynamic box + take_damage 打印）
- `Scripts/Prototypes/Weapon/weapon_demo.gd` — 主场景控制器（重置、Q 键 spawn Effect、统计活跃数）
- `Scripts/Prototypes/Weapon/weapon_debug_panel.gd` — runtime 调参 UI
- `Scripts/Prototypes/Weapon/tests/test_falloff.gd` — RadialDamage / RadialBlast 衰减函数单测
- `Scripts/Prototypes/Weapon/tests/test_test_dummy.gd` — 受体单测
- `Scripts/Prototypes/Weapon/tests/test_runner.tscn` — 运行单测的临时场景

**Create（场景）:**
- `Scenes/Prototypes/Weapon/projectiles/direct_projectile.tscn`
- `Scenes/Prototypes/Weapon/projectiles/ballistic_projectile.tscn`
- `Scenes/Prototypes/Weapon/effects/pistol_hit_effect.tscn`
- `Scenes/Prototypes/Weapon/effects/rocket_explosion_effect.tscn`
- `Scenes/Prototypes/Weapon/weapons/pistol.tscn`
- `Scenes/Prototypes/Weapon/weapons/rocket_launcher.tscn`
- `Scenes/Prototypes/Weapon/test_dummy.tscn`
- `Scenes/Prototypes/Weapon/weapon_demo.tscn`

**Modify:**
- `project.godot` — 加碰撞层名 + 4 个 Input Action（Fire1、Fire2、Reset、SpawnEffect）

---

## Task 1: 项目基建（碰撞层 + Input Map + 目录骨架）

**Files:**
- Modify: `project.godot`

### Step 1.1 在 project.godot 加 Input 与 layer_names

打开 `project.godot`，在已有 `[input]` 段里追加四个 Action（不要破坏现有 `Left/Right/Jump`）：

```ini
Fire1={
"deadzone": 0.5,
"events": [Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"button_mask":0,"position":Vector2(0, 0),"global_position":Vector2(0, 0),"factor":1.0,"button_index":1,"canceled":false,"pressed":false,"double_click":false,"script":null)
]
}
Fire2={
"deadzone": 0.5,
"events": [Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"button_mask":0,"position":Vector2(0, 0),"global_position":Vector2(0, 0),"factor":1.0,"button_index":2,"canceled":false,"pressed":false,"double_click":false,"script":null)
]
}
Reset={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":82,"key_label":0,"unicode":114,"location":0,"echo":false,"script":null)
]
}
SpawnEffect={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":81,"key_label":0,"unicode":113,"location":0,"echo":false,"script":null)
]
}
```

> **推荐 alternative：** 在 Godot Editor → Project Settings → Input Map 里手工添加 4 个 action（Fire1 = Mouse Left, Fire2 = Mouse Right, Reset = R, SpawnEffect = Q），保存即可，避免手抄 InputEvent 结构体出错。

然后在 `[layer_names]` 段（若没有则新建）声明 4 个 2D 物理层：

```ini
[layer_names]

2d_physics/layer_1="world"
2d_physics/layer_2="player"
2d_physics/layer_3="destructible"
2d_physics/layer_4="projectile"
```

### Step 1.2 验证 import + 4 个 action 可用

在 Godot Editor 中 Project → Project Settings → Input Map 看到 Fire1/Fire2/Reset/SpawnEffect；Layer Names → 2D Physics 看到 4 个名字。

### Step 1.3 提交

```bash
git add project.godot
git commit -m "feat(weapon): add input map + collision layer names for weapon prototype

- Input actions: Fire1 (LMB), Fire2 (RMB), Reset (R), SpawnEffect (Q)
- 2D physics layer names: 1=world, 2=player, 3=destructible, 4=projectile

Refs: docs/superpowers/plans/2026-05-25-weapon-prototype-plan.md Task 1"
```

---

## Task 2: TestDummy 受体（TDD）

**Files:**
- Create: `Scripts/Prototypes/Weapon/tests/test_test_dummy.gd`
- Create: `Scripts/Prototypes/Weapon/tests/test_runner.tscn`
- Create: `Scripts/Prototypes/Weapon/test_dummy.gd`
- Create: `Scenes/Prototypes/Weapon/test_dummy.tscn`

TestDummy 是普通 `RigidBody2D` + 一个 `take_damage` 方法，命中后累计 hp 并打印日志。它是 spec §1.3 验收 #5（"受体被命中后日志打印伤害值与冲量"）与 §4.7 的"普通 dynamic body 实现简单 take_damage"。

### Step 2.1 写失败测试

Create `Scripts/Prototypes/Weapon/tests/test_test_dummy.gd`:

```gdscript
# Scripts/Prototypes/Weapon/tests/test_test_dummy.gd
# 受体纯函数测试 —— 验证 take_damage 累计与初始 hp。
# 不验证物理（冲量受体走 Box2D apply_central_impulse，无需测）。
extends Node

const TestDummy := preload("res://Scripts/Prototypes/Weapon/test_dummy.gd")

func _ready() -> void:
	var d := TestDummy.new()
	d.max_hp = 100.0
	d._ready()  # 手工触发 hp 初始化

	# 1) 初始 hp = max_hp
	assert(d.hp == 100.0, "init hp should equal max_hp")

	# 2) take_damage 累计扣血
	d.take_damage(30.0, Vector2.ZERO, null)
	assert(_approx(d.hp, 70.0), "after 30 damage hp should be 70, got %f" % d.hp)

	# 3) 多次扣
	d.take_damage(50.0, Vector2.ZERO, null)
	assert(_approx(d.hp, 20.0), "after 80 total hp should be 20, got %f" % d.hp)

	# 4) 过量扣 → hp clamp >= 0
	d.take_damage(999.0, Vector2.ZERO, null)
	assert(d.hp == 0.0, "hp should clamp to 0, got %f" % d.hp)

	# 5) hp 归零后再扣不再变
	d.take_damage(10.0, Vector2.ZERO, null)
	assert(d.hp == 0.0, "hp should stay at 0 after death")

	d.free()
	print("[TEST test_dummy] ALL PASS")
	get_tree().quit()

static func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.001
```

Create `Scripts/Prototypes/Weapon/tests/test_runner.tscn`（用于跑当前 Task 的测试脚本；后续 Task 会切换它挂的 script）:

```gdscript
[gd_scene format=3 uid="uid://dweapontest001"]

[ext_resource type="Script" path="res://Scripts/Prototypes/Weapon/tests/test_test_dummy.gd" id="1"]

[node name="TestRunner" type="Node"]
script = ExtResource("1")
```

### Step 2.2 跑测试确认失败

Godot Editor → 打开 `Scripts/Prototypes/Weapon/tests/test_runner.tscn` → F6。预期：`preload` 报错 / `TestDummy` 未定义。

### Step 2.3 写最小实现

Create `Scripts/Prototypes/Weapon/test_dummy.gd`:

```gdscript
# Scripts/Prototypes/Weapon/test_dummy.gd
# 武器原型 v1 受体 —— 普通 dynamic body 实现简单 take_damage。
# 完整破坏框架（Block + Constraint）由家族 B 独立 demo 验证（ADR-0007 单向依赖）。
# duck typing：实现 take_damage(amount, point, source) 即可被 DamageField 命中。
class_name WeaponTestDummy
extends RigidBody2D

@export var max_hp: float = 100.0
var hp: float = 0.0

func _ready() -> void:
	hp = max_hp

# DamageField 调用入口（ADR-0007 统一伤害语言）。
func take_damage(amount: float, point: Vector2, source: Node) -> void:
	var before := hp
	hp = maxf(0.0, hp - amount)
	var src_name := "<null>" if source == null else source.name
	print("[TestDummy %s] dmg=%.1f hp %.1f → %.1f @%s by %s" % [name, amount, before, hp, point, src_name])
```

### Step 2.4 创建 TestDummy 场景

Create `Scenes/Prototypes/Weapon/test_dummy.tscn`:

```gdscript
[gd_scene format=3 uid="uid://dwpndummy001"]

[ext_resource type="Script" uid="" path="res://Scripts/Prototypes/Weapon/test_dummy.gd" id="1"]

[sub_resource type="PhysicsMaterial" id="DummyMat"]
friction = 0.4

[sub_resource type="RectangleShape2D" id="DummyShape"]
size = Vector2(40, 40)

[node name="TestDummy" type="RigidBody2D"]
collision_layer = 4
collision_mask = 5
physics_material_override = SubResource("DummyMat")
script = ExtResource("1")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("DummyShape")

[node name="ColorRect" type="ColorRect" parent="."]
offset_left = -20.0
offset_top = -20.0
offset_right = 20.0
offset_bottom = 20.0
color = Color(0.85, 0.25, 0.25, 1)
```

> **碰撞位说明**：`collision_layer = 4`（bit 3 = destructible）、`collision_mask = 5`（bit 1 world + bit 3 destructible），即受体属于 destructible 层，与 world 和其他 destructible 互撞，**不**主动碰 projectile / player（projectile 自己 mask 含 destructible 即可命中本体）。

> **uid 提示**：tscn 文件头里的 `uid` 字段（如 `uid="uid://dwpndummy001"`）按 memory `tscn_needs_uid_for_packedscene_refs` 必填，否则后续 `ext_resource` 引用会失败。后续每个新建 .tscn 都同理。

### Step 2.5 跑测试确认通过

F6 `test_runner.tscn`，控制台预期：

```
[TEST test_dummy] ALL PASS
```

### Step 2.6 提交

```bash
git add Scripts/Prototypes/Weapon/test_dummy.gd Scripts/Prototypes/Weapon/tests/test_test_dummy.gd Scripts/Prototypes/Weapon/tests/test_runner.tscn Scenes/Prototypes/Weapon/test_dummy.tscn
git commit -m "feat(weapon): add WeaponTestDummy receiver + test

Plain dynamic body implementing take_damage(amount, point, source)
via duck typing. Used as v1 receiver per spec §4.7 — full Block /
Constraint integration belongs to destruction prototype (family B).

Refs: ADR-0007 unified damage language, docs/.../weapon-prototype-design.md §4.7"
```

---

## Task 3: DamageField 子组件（PointDamage + RadialDamage）+ 衰减纯函数测试

**Files:**
- Create: `Scripts/Prototypes/Weapon/tests/test_falloff.gd`
- Create: `Scripts/Prototypes/Weapon/damage_fields/point_damage.gd`
- Create: `Scripts/Prototypes/Weapon/damage_fields/radial_damage.gd`

DamageField 的 `apply(world, center, ctx)` 直接接受 `direct_space_state`，不易在 `_ready` 里 mock；所以**把衰减公式拆为静态纯函数 `compute_falloff(distance, radius)` 并跑单测；apply 整段留 Task 11 的 F6 验证**。

### Step 3.1 写衰减纯函数失败测试

Create `Scripts/Prototypes/Weapon/tests/test_falloff.gd`:

```gdscript
# Scripts/Prototypes/Weapon/tests/test_falloff.gd
# 纯函数测试 —— 线性衰减 f(d, R) = max(0, 1 - d/R)。
# RadialDamage / RadialBlast 共用同一公式（spec §4.4 / §4.5 都写 linear）。
extends Node

const RadialDamage := preload("res://Scripts/Prototypes/Weapon/damage_fields/radial_damage.gd")

func _ready() -> void:
	# 1) 中心 = 1.0（满）
	assert(_approx(RadialDamage.compute_falloff(0.0, 3.0), 1.0), "d=0 should be 1.0")
	# 2) 半距 = 0.5
	assert(_approx(RadialDamage.compute_falloff(1.5, 3.0), 0.5), "d=R/2 should be 0.5")
	# 3) 边界 = 0
	assert(_approx(RadialDamage.compute_falloff(3.0, 3.0), 0.0), "d=R should be 0")
	# 4) 超出 = 0（clamp）
	assert(_approx(RadialDamage.compute_falloff(5.0, 3.0), 0.0), "d>R should be 0")
	# 5) R<=0 守卫
	assert(_approx(RadialDamage.compute_falloff(1.0, 0.0), 0.0), "R=0 should be 0")
	assert(_approx(RadialDamage.compute_falloff(1.0, -1.0), 0.0), "R<0 should be 0")

	print("[TEST falloff] ALL PASS")
	get_tree().quit()

static func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.001
```

把 `test_runner.tscn` 的 `script` 临时指向这个文件，F6 跑一次，确认 `preload` 失败 / `RadialDamage` 未定义。

### Step 3.2 写 PointDamage

Create `Scripts/Prototypes/Weapon/damage_fields/point_damage.gd`:

```gdscript
# Scripts/Prototypes/Weapon/damage_fields/point_damage.gd
# DamageField 子组件 —— 命中点最近一个 dynamic body 单点扣血。
# ADR-0007：duck typing 调用 take_damage(amount, point, source)。
class_name PointDamage
extends Node2D

@export var amount: float = 50.0

# space_state: PhysicsDirectSpaceState2D（由 Effect 主类从 world 获取后传入）
# center: 命中点世界坐标
# ctx: { "source": Node }
func apply(space_state: PhysicsDirectSpaceState2D, center: Vector2, ctx: Dictionary) -> void:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = center
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var hits := space_state.intersect_point(q, 1)
	if hits.is_empty():
		return
	var body := hits[0].get("collider") as Node
	if body == null or not body.has_method("take_damage"):
		return
	body.take_damage(amount, center, ctx.get("source"))
```

### Step 3.3 写 RadialDamage + 衰减公式

Create `Scripts/Prototypes/Weapon/damage_fields/radial_damage.gd`:

```gdscript
# Scripts/Prototypes/Weapon/damage_fields/radial_damage.gd
# DamageField 子组件 —— 圆形范围内对所有 take_damage 受体按线性衰减扣血。
# 范围查询：CircleShape2D + intersect_shape（Godot 原生 API，已在 demo_level.gd 验证）。
# ADR-0007：duck typing，不接触 Constraint。
class_name RadialDamage
extends Node2D

const PX_PER_M: float = 100.0

@export var base: float = 100.0
@export var radius: float = 3.0 * PX_PER_M  # 3 m 默认（spec §4.4）
@export var max_bodies: int = 50

# 衰减纯函数 —— 同 spec §4.4 linear falloff。
static func compute_falloff(distance: float, r: float) -> float:
	if r <= 0.0:
		return 0.0
	return clampf(1.0 - distance / r, 0.0, 1.0)

func apply(space_state: PhysicsDirectSpaceState2D, center: Vector2, ctx: Dictionary) -> void:
	var circle := CircleShape2D.new()
	circle.radius = radius
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = circle
	q.transform = Transform2D(0.0, center)
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var hits := space_state.intersect_shape(q, max_bodies)
	var source: Node = ctx.get("source")
	for hit in hits:
		var body := hit.get("collider") as Node
		if body == null or not body.has_method("take_damage"):
			continue
		var d: float = (body.global_position - center).length() if body is Node2D else 0.0
		var amt := base * compute_falloff(d, radius)
		if amt <= 0.0:
			continue
		body.take_damage(amt, body.global_position if body is Node2D else center, source)
```

### Step 3.4 F6 跑测试确认通过

将 `test_runner.tscn` `script` 指回 `test_falloff.gd`，F6，预期：

```
[TEST falloff] ALL PASS
```

### Step 3.5 提交

```bash
git add Scripts/Prototypes/Weapon/damage_fields/ Scripts/Prototypes/Weapon/tests/test_falloff.gd Scripts/Prototypes/Weapon/tests/test_runner.tscn
git commit -m "feat(weapon): add PointDamage + RadialDamage with linear falloff

- PointDamage: intersect_point + duck typing take_damage call
- RadialDamage: intersect_shape (CircleShape2D) + linear falloff
- Pure falloff function unit-tested; apply() left for F6 verification

Refs: ADR-0007 single-direction dependency, spec §4.4"
```

---

## Task 4: ForceField 子组件（DirectionalImpulse + RadialBlast）

**Files:**
- Create: `Scripts/Prototypes/Weapon/force_fields/directional_impulse.gd`
- Create: `Scripts/Prototypes/Weapon/force_fields/radial_blast.gd`

衰减纯函数与 RadialDamage 同（Task 3 已覆盖），本任务不再单独写单测；apply 行为留 Task 11 F6（自爆跳是核心验收）。

### Step 4.1 写 DirectionalImpulse

Create `Scripts/Prototypes/Weapon/force_fields/directional_impulse.gd`:

```gdscript
# Scripts/Prototypes/Weapon/force_fields/directional_impulse.gd
# ForceField 子组件 —— 命中点最近一个 RigidBody2D 沿弹道方向施加冲量。
# direction 来自 ctx.direction（Projectile 命中时由 linear_velocity.normalized() 提供）。
class_name DirectionalImpulse
extends Node2D

const PX_PER_M: float = 100.0

@export var magnitude: float = 1.0 * PX_PER_M  # 1 N·s 默认（spec §4.5）

func apply(space_state: PhysicsDirectSpaceState2D, center: Vector2, ctx: Dictionary) -> void:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = center
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var hits := space_state.intersect_point(q, 1)
	if hits.is_empty():
		return
	var body := hits[0].get("collider") as RigidBody2D
	if body == null:
		return
	var dir: Vector2 = ctx.get("direction", Vector2.ZERO)
	if dir == Vector2.ZERO:
		return
	body.apply_central_impulse(dir.normalized() * magnitude)
```

### Step 4.2 写 RadialBlast

Create `Scripts/Prototypes/Weapon/force_fields/radial_blast.gd`:

```gdscript
# Scripts/Prototypes/Weapon/force_fields/radial_blast.gd
# ForceField 子组件 —— 圆形范围内对所有 dynamic body 按 (1 - d/R) 线性衰减施径向冲量。
# affect_player = true 是自爆跳的物理来源（ADR-0008 核心 invariant）。
# Debug 可关，仅用于 A/B 验证；产品默认 true。
class_name RadialBlast
extends Node2D

const PX_PER_M: float = 100.0
const RadialDamage := preload("res://Scripts/Prototypes/Weapon/damage_fields/radial_damage.gd")

@export var peak_impulse: float = 12.0 * PX_PER_M  # 12 N·s 默认（spec §4.5）
@export var radius: float = 3.0 * PX_PER_M
@export var affect_player: bool = true             # ADR-0008 invariant，默认 true
@export var max_bodies: int = 50

func apply(space_state: PhysicsDirectSpaceState2D, center: Vector2, ctx: Dictionary) -> void:
	var circle := CircleShape2D.new()
	circle.radius = radius
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = circle
	q.transform = Transform2D(0.0, center)
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var hits := space_state.intersect_shape(q, max_bodies)
	for hit in hits:
		var body := hit.get("collider") as RigidBody2D
		if body == null:
			continue
		if not affect_player and body.is_in_group("player"):
			continue
		var delta := body.global_position - center
		var d := delta.length()
		var f := RadialDamage.compute_falloff(d, radius)
		if f <= 0.0:
			continue
		var dir := delta.normalized() if d > 0.001 else Vector2.UP
		body.apply_central_impulse(dir * peak_impulse * f)
```

> **player 识别**：通过 `body.is_in_group("player")` 判定。Player3C 在 [player.tscn](../../../Scenes/Prototypes/3C/player.tscn) 需加入 `"player"` group —— **在 Task 9 创建 weapon_demo.tscn 时统一处理**（不在 3C 自己的场景里加，避免污染 3C 现有测试关）。

### Step 4.3 验证 parse

Godot Editor 编辑器自动 import，看 Output 无 parse error；用 FileSystem 双击 `radial_blast.gd` / `directional_impulse.gd` 各打开一次确认。

### Step 4.4 提交

```bash
git add Scripts/Prototypes/Weapon/force_fields/
git commit -m "feat(weapon): add DirectionalImpulse + RadialBlast ForceField components

- DirectionalImpulse: single body along ctx.direction
- RadialBlast: AABB query + linear falloff radial impulse
- affect_player flag = ADR-0008 invariant for self-splash jump (default true)
- Reuses RadialDamage.compute_falloff (shared linear falloff)

Refs: ADR-0007 dual-channel, ADR-0008 self-splash jump, spec §4.5"
```

---

## Task 5: Effect 主类（双通道容器 + 视觉）

**Files:**
- Create: `Scripts/Prototypes/Weapon/effect.gd`
- Create: `Scenes/Prototypes/Weapon/effects/pistol_hit_effect.tscn`
- Create: `Scenes/Prototypes/Weapon/effects/rocket_explosion_effect.tscn`

Effect 是 Node2D 容器，`_ready` 时对所有子节点中的 `*Damage` / `*Blast` / `*Impulse` 调用 `apply(...)`，跑视觉 tween，然后 `queue_free`。

### Step 5.1 写 Effect 主类

Create `Scripts/Prototypes/Weapon/effect.gd`:

```gdscript
# Scripts/Prototypes/Weapon/effect.gd
# 双通道容器（DamageField + ForceField），ADR-0007。
# 子节点用 duck typing 匹配：has_method("apply") 即视为子组件。
# 视觉：白圆闪 → 半透淡出 → queue_free（与物理 apply 并行）。
class_name Effect
extends Node2D

@export var visual_duration: float = 0.3
@export var visual_radius_px: float = 50.0
@export var visual_color: Color = Color(1, 0.8, 0.4, 0.9)

# context 由触发者（Projectile / 鼠标 spawn）调用 trigger() 时传入。
# direction = 弹道方向（DirectionalImpulse 需要）；normal = 命中面法线（可选）；source = Projectile 节点（受体打印用）。
var _ctx: Dictionary = {}

# Projectile / weapon_demo 在 instantiate + add_child 之后调用一次此方法。
# 必须先 add_child（取得 world_2d）再 trigger。
func trigger(center: Vector2, ctx: Dictionary) -> void:
	global_position = center
	_ctx = ctx
	var space_state := get_world_2d().direct_space_state
	# 让所有挂着 apply(space_state, center, ctx) 的子组件各跑一遍。
	for child in get_children():
		if child.has_method("apply"):
			child.apply(space_state, center, _ctx)
	_start_visual()

func _start_visual() -> void:
	# 简易视觉：一个 ColorRect（圆形 mask 用 draw 更简单）—— 这里用自绘 + tween。
	queue_redraw()
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, visual_duration)
	t.tween_callback(queue_free)

func _draw() -> void:
	# 自绘一个圆（避免额外子节点）。半径在 visual_duration 内不变，靠 modulate 淡出。
	draw_circle(Vector2.ZERO, visual_radius_px, visual_color)
```

### Step 5.2 创建 pistol_hit_effect.tscn

Create `Scenes/Prototypes/Weapon/effects/pistol_hit_effect.tscn`:

```gdscript
[gd_scene format=3 uid="uid://dwpnfxpistol01"]

[ext_resource type="Script" path="res://Scripts/Prototypes/Weapon/effect.gd" id="1"]
[ext_resource type="Script" path="res://Scripts/Prototypes/Weapon/damage_fields/point_damage.gd" id="2"]
[ext_resource type="Script" path="res://Scripts/Prototypes/Weapon/force_fields/directional_impulse.gd" id="3"]

[node name="PistolHitEffect" type="Node2D"]
script = ExtResource("1")
visual_radius_px = 12.0
visual_duration = 0.12
visual_color = Color(1, 1, 0.4, 0.9)

[node name="PointDamage" type="Node2D" parent="."]
script = ExtResource("2")
amount = 50.0

[node name="DirectionalImpulse" type="Node2D" parent="."]
script = ExtResource("3")
magnitude = 100.0
```

### Step 5.3 创建 rocket_explosion_effect.tscn

Create `Scenes/Prototypes/Weapon/effects/rocket_explosion_effect.tscn`:

```gdscript
[gd_scene format=3 uid="uid://dwpnfxrocket01"]

[ext_resource type="Script" path="res://Scripts/Prototypes/Weapon/effect.gd" id="1"]
[ext_resource type="Script" path="res://Scripts/Prototypes/Weapon/damage_fields/radial_damage.gd" id="2"]
[ext_resource type="Script" path="res://Scripts/Prototypes/Weapon/force_fields/radial_blast.gd" id="3"]

[node name="RocketExplosionEffect" type="Node2D"]
script = ExtResource("1")
visual_radius_px = 300.0
visual_duration = 0.35
visual_color = Color(1, 0.5, 0.2, 0.7)

[node name="RadialDamage" type="Node2D" parent="."]
script = ExtResource("2")
base = 100.0
radius = 300.0

[node name="RadialBlast" type="Node2D" parent="."]
script = ExtResource("3")
peak_impulse = 1200.0
radius = 300.0
affect_player = true
```

> **量级换算**：spec 默认值 12 N·s × 100 px/m = 1200 (px·kg/s 单位)。视觉 / 影响半径 3 m × 100 px/m = 300 px。

### Step 5.4 验证 import

Godot Editor → FileSystem 双击两个 .tscn 各打开一次，inspector 应正常显示子节点（PointDamage / DirectionalImpulse / 或 RadialDamage / RadialBlast）。无 missing dependency 警告。

### Step 5.5 提交

```bash
git add Scripts/Prototypes/Weapon/effect.gd Scenes/Prototypes/Weapon/effects/
git commit -m "feat(weapon): add Effect dual-channel container + 2 effect scenes

Effect.trigger(center, ctx) walks children with apply() method and dispatches
each. Visual = self-drawn circle with alpha tween. pistol_hit_effect bundles
PointDamage(50) + DirectionalImpulse(1 N·s); rocket_explosion_effect bundles
RadialDamage(100, R=3m) + RadialBlast(12 N·s, R=3m, affect_player=true).

Refs: ADR-0007 dual-channel, ADR-0010 effect as composition, spec §4.3"
```

---

## Task 6: Projectile 类 + Direct / Ballistic 两个场景

**Files:**
- Create: `Scripts/Prototypes/Weapon/projectile.gd`
- Create: `Scenes/Prototypes/Weapon/projectiles/direct_projectile.tscn`
- Create: `Scenes/Prototypes/Weapon/projectiles/ballistic_projectile.tscn`

### Step 6.1 写 Projectile 主类

Create `Scripts/Prototypes/Weapon/projectile.gd`:

```gdscript
# Scripts/Prototypes/Weapon/projectile.gd
# 飞行物理 + 命中检测 + 触发 Effect。
# 高速直射弹 + 抛物线弹同一类，差异由 gravity_scale / initial_speed / max_lifetime 决定（ADR-0009 §Decision）。
# CCD 在 .tscn 里通过 continuous_cd = 2 (CCD_MODE_CAST_SHAPE) 打开。
class_name Projectile
extends RigidBody2D

@export var effect_scene: PackedScene
@export var max_lifetime: float = 1.5

var _age: float = 0.0
var _hit_handled: bool = false  # 防止同帧多 body_entered 触发多个 Effect

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= max_lifetime:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if _hit_handled:
		return
	_hit_handled = true
	# 命中点 = projectile 当前位置（精度足够；CCD 命中点可由 contact 取，v1 不做）
	var hit_point := global_position
	# 弹道方向 = 当前速度方向（命中瞬间）
	var dir := linear_velocity.normalized() if linear_velocity.length_squared() > 0.0 else Vector2.RIGHT
	_spawn_effect(hit_point, dir)
	queue_free()

func _spawn_effect(point: Vector2, direction: Vector2) -> void:
	if effect_scene == null:
		return
	var fx := effect_scene.instantiate() as Effect
	if fx == null:
		push_warning("Projectile.effect_scene is not an Effect: %s" % effect_scene)
		return
	# 必须先挂到 scene tree 才能 get_world_2d()
	get_tree().current_scene.add_child(fx)
	fx.trigger(point, {"source": self, "direction": direction})
```

### Step 6.2 创建 direct_projectile.tscn

Create `Scenes/Prototypes/Weapon/projectiles/direct_projectile.tscn`:

```gdscript
[gd_scene format=3 uid="uid://dwpnprojdir01"]

[ext_resource type="Script" path="res://Scripts/Prototypes/Weapon/projectile.gd" id="1"]
[ext_resource type="PackedScene" uid="uid://dwpnfxpistol01" path="res://Scenes/Prototypes/Weapon/effects/pistol_hit_effect.tscn" id="2"]

[sub_resource type="PhysicsMaterial" id="ProjMat"]
friction = 0.0
bounce = 0.0

[sub_resource type="CircleShape2D" id="ProjShape"]
radius = 8.0

[node name="DirectProjectile" type="RigidBody2D"]
collision_layer = 8
collision_mask = 5
gravity_scale = 0.0
linear_damp = 0.0
mass = 0.02
continuous_cd = 2
physics_material_override = SubResource("ProjMat")
script = ExtResource("1")
effect_scene = ExtResource("2")
max_lifetime = 1.5

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("ProjShape")

[node name="ColorRect" type="ColorRect" parent="."]
offset_left = -10.0
offset_top = -2.0
offset_right = 10.0
offset_bottom = 2.0
color = Color(1, 0.9, 0.3, 1)
```

> **碰撞位**：`collision_layer = 8`（bit 4 = projectile）、`collision_mask = 5`（bit 1 world + bit 3 destructible）。**不**碰 player（bit 2），实现 spec §4.2 "Mask 不含 player"。
> **continuous_cd = 2** 是 `RigidBody2D.CCD_MODE_CAST_SHAPE`（高速防穿透；按 ADR-0009 直射弹必需）。
> **mass = 0.02** = 0.02 kg（spec §4.2 默认）。

### Step 6.3 创建 ballistic_projectile.tscn

Create `Scenes/Prototypes/Weapon/projectiles/ballistic_projectile.tscn`:

```gdscript
[gd_scene format=3 uid="uid://dwpnprojbal01"]

[ext_resource type="Script" path="res://Scripts/Prototypes/Weapon/projectile.gd" id="1"]
[ext_resource type="PackedScene" uid="uid://dwpnfxrocket01" path="res://Scenes/Prototypes/Weapon/effects/rocket_explosion_effect.tscn" id="2"]

[sub_resource type="PhysicsMaterial" id="ProjMat"]
friction = 0.0
bounce = 0.0

[sub_resource type="CircleShape2D" id="ProjShape"]
radius = 10.0

[node name="BallisticProjectile" type="RigidBody2D"]
collision_layer = 8
collision_mask = 5
gravity_scale = 1.0
linear_damp = 0.0
mass = 0.02
continuous_cd = 2
physics_material_override = SubResource("ProjMat")
script = ExtResource("1")
effect_scene = ExtResource("2")
max_lifetime = 3.0

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("ProjShape")

[node name="ColorRect" type="ColorRect" parent="."]
offset_left = -10.0
offset_top = -10.0
offset_right = 10.0
offset_bottom = 10.0
color = Color(0.9, 0.3, 0.1, 1)
```

> **gravity_scale = 1**：抛物线弹受默认世界重力 —— 注意：3C 的 Player 把 `gravity_scale = 0` 自管重力（`gravity_y` export），而 Projectile 用世界默认 Box2D 重力。Box2D 默认重力是 Godot 项目设置里的值。若 demo 场景需要与 3C 重力一致（25 m/s²），**在 weapon_demo.tscn 里检查 project 默认重力或调 projectile 的 `gravity_scale` 来匹配**（Task 9 验收若发现抛物线下坠手感不对再调）。

### Step 6.4 验证 parse + import

打开两个 .tscn，inspector 显示 `continuous_cd = Cast Shape`（值 2）、`gravity_scale` 分别为 0/1、`effect_scene` 已绑定。

### Step 6.5 提交

```bash
git add Scripts/Prototypes/Weapon/projectile.gd Scenes/Prototypes/Weapon/projectiles/
git commit -m "feat(weapon): add Projectile + direct/ballistic scenes

Single class differentiated by tscn params: Direct (gravity_scale=0, CCD,
1.5s lifetime), Ballistic (gravity_scale=1, CCD, 3.0s lifetime). Both on
projectile layer, mask = world + destructible (no player self-collision).
On body_entered: instantiates effect_scene at hit point, passes direction
from current linear_velocity.

Refs: ADR-0009 physics-projectile (not hitscan), ADR-0010 layer 2 of triad,
spec §4.2"
```

---

## Task 7: Weapon 类（瞄准 + cooldown + 生成 + 后坐力）

**Files:**
- Create: `Scripts/Prototypes/Weapon/weapon.gd`

### Step 7.1 写 Weapon 主类

Create `Scripts/Prototypes/Weapon/weapon.gd`:

```gdscript
# Scripts/Prototypes/Weapon/weapon.gd
# 瞄准（鼠标）+ 触发节流（cooldown）+ 生成 Projectile + 后坐力。
# 挂在持枪者（Player3C）下；持枪者作为 wielder 在 wielder_path 指明。
# 后坐力 = 给 wielder 施加反向冲量（与自爆跳无关，ADR-0008）。
class_name Weapon
extends Node2D

const PX_PER_M: float = 100.0

@export var projectile_scene: PackedScene
@export var fire_action: StringName = &"Fire1"       # InputMap action
@export var cooldown: float = 0.2
@export var projectile_initial_speed: float = 120.0 * PX_PER_M  # px/s
@export var muzzle_offset: Vector2 = Vector2(50.0, 20.0)        # 0.5 m, 0.2 m
@export var recoil_impulse: float = 1.0 * PX_PER_M              # 1 N·s 默认（手枪）
@export var recoil_enabled: bool = true
@export var wielder_path: NodePath
@export var aim_line_length: float = 200.0  # 视觉辅助线，Debug 可调

var _last_fire_time: float = -1000.0
var _wielder: RigidBody2D

func _ready() -> void:
	if wielder_path != NodePath():
		_wielder = get_node(wielder_path) as RigidBody2D

func _physics_process(_dt: float) -> void:
	if Input.is_action_pressed(fire_action):
		_try_fire()
	queue_redraw()  # 瞄准辅助线每帧重画

func _try_fire() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_fire_time < cooldown:
		return
	if projectile_scene == null or _wielder == null:
		return
	var muzzle := _muzzle_world()
	var dir := _aim_direction(muzzle)
	if dir == Vector2.ZERO:
		return
	# 1) Spawn Projectile
	var proj := projectile_scene.instantiate() as RigidBody2D
	if proj == null:
		push_warning("Weapon.projectile_scene is not RigidBody2D")
		return
	get_tree().current_scene.add_child(proj)
	proj.global_position = muzzle
	proj.linear_velocity = dir * projectile_initial_speed
	# 2) 后坐力
	if recoil_enabled and recoil_impulse > 0.0:
		_wielder.apply_central_impulse(-dir * recoil_impulse)
	_last_fire_time = now

func _muzzle_world() -> Vector2:
	# v1：muzzle_offset 是 wielder 局部偏移（不随瞄准旋转）—— spec §4.1。
	return _wielder.global_position + muzzle_offset

func _aim_direction(muzzle: Vector2) -> Vector2:
	var mouse := get_global_mouse_position()
	var v := mouse - muzzle
	if v.length_squared() < 0.0001:
		return Vector2.ZERO
	return v.normalized()

func _draw() -> void:
	# 瞄准辅助线（v1 = 直线，长度 aim_line_length）—— spec §4.10 Debug 项
	if _wielder == null:
		return
	# 注意：_draw 在 Weapon 局部坐标系，muzzle / 方向需转 local
	var muzzle_local := to_local(_muzzle_world())
	var dir := _aim_direction(_muzzle_world())
	if dir == Vector2.ZERO:
		return
	var end_local := muzzle_local + dir * aim_line_length
	draw_line(muzzle_local, end_local, Color(1, 1, 1, 0.5), 1.0)
```

### Step 7.2 验证 parse

Godot Editor 打开 `weapon.gd`，确认无 parse error。Weapon 还不能 F6 跑（需 Pistol/Rocket .tscn 配合）—— 留 Task 8/9。

### Step 7.3 提交

```bash
git add Scripts/Prototypes/Weapon/weapon.gd
git commit -m "feat(weapon): add Weapon main class (aim + cooldown + spawn + recoil)

Reads mouse for aim direction, throttles by cooldown, spawns projectile_scene
at muzzle with initial_speed*direction, applies reverse recoil impulse to
wielder if enabled. Recoil is independent of self-splash (ADR-0008) and can
be toggled at runtime via debug panel.

Refs: ADR-0008 recoil != self-splash, ADR-0010 layer 1 of triad, spec §4.1"
```

---

## Task 8: Pistol + Rocket Launcher 武器资源

**Files:**
- Create: `Scenes/Prototypes/Weapon/weapons/pistol.tscn`
- Create: `Scenes/Prototypes/Weapon/weapons/rocket_launcher.tscn`

把 Weapon 脚本 + projectile_scene 引用打包成两种武器资源，方便挂到 Player 下并独立调参。

### Step 8.1 创建 pistol.tscn

Create `Scenes/Prototypes/Weapon/weapons/pistol.tscn`:

```gdscript
[gd_scene format=3 uid="uid://dwpnwpnpist01"]

[ext_resource type="Script" path="res://Scripts/Prototypes/Weapon/weapon.gd" id="1"]
[ext_resource type="PackedScene" uid="uid://dwpnprojdir01" path="res://Scenes/Prototypes/Weapon/projectiles/direct_projectile.tscn" id="2"]

[node name="Pistol" type="Node2D"]
script = ExtResource("1")
projectile_scene = ExtResource("2")
fire_action = &"Fire1"
cooldown = 0.2
projectile_initial_speed = 12000.0
muzzle_offset = Vector2(50, 20)
recoil_impulse = 100.0
recoil_enabled = true
aim_line_length = 200.0
```

> 12000 px/s = 120 m/s。

### Step 8.2 创建 rocket_launcher.tscn

Create `Scenes/Prototypes/Weapon/weapons/rocket_launcher.tscn`:

```gdscript
[gd_scene format=3 uid="uid://dwpnwpnrkt01"]

[ext_resource type="Script" path="res://Scripts/Prototypes/Weapon/weapon.gd" id="1"]
[ext_resource type="PackedScene" uid="uid://dwpnprojbal01" path="res://Scenes/Prototypes/Weapon/projectiles/ballistic_projectile.tscn" id="2"]

[node name="RocketLauncher" type="Node2D"]
script = ExtResource("1")
projectile_scene = ExtResource("2")
fire_action = &"Fire2"
cooldown = 0.8
projectile_initial_speed = 3000.0
muzzle_offset = Vector2(50, 20)
recoil_impulse = 200.0
recoil_enabled = true
aim_line_length = 200.0
```

> 3000 px/s = 30 m/s；200 px·kg/s = 2 N·s。

### Step 8.3 验证 import

打开两个 .tscn，确认 inspector 里 projectile_scene 已绑定、cooldown / initial_speed 与上述一致，wielder_path 暂空（在 Task 9 里挂到 Player 下时再设）。

### Step 8.4 提交

```bash
git add Scenes/Prototypes/Weapon/weapons/
git commit -m "feat(weapon): add Pistol + RocketLauncher tscn presets

Pistol: Fire1, cd=0.2s, speed=120 m/s, recoil=1 N·s, direct projectile
RocketLauncher: Fire2, cd=0.8s, speed=30 m/s, recoil=2 N·s, ballistic projectile

Refs: spec §3.1 v1 MVP combinations"
```

---

## Task 9: 测试场景 weapon_demo.tscn + arena + reset 控制器

**Files:**
- Create: `Scripts/Prototypes/Weapon/weapon_demo.gd`
- Create: `Scenes/Prototypes/Weapon/weapon_demo.tscn`

场景内容（spec §4.8）：
- 复用 Player3C（加 `"player"` group + 挂 Pistol + RocketLauncher 子节点）
- 平地 + arena 四面墙（防止角色被推飞出场）
- 3 个 dynamic TestDummy（验受体 take_damage + 推飞）
- 1 堵静态墙（验证 Projectile 命中静态体）
- 1 个站在角色脚下的 dynamic box（验证自爆跳跳上去）
- 1 个朝上的天花板（验证朝上开枪 → 角色压地）
- WeaponDemoController：监听 Reset 键 teleport 角色回原点；监听 SpawnEffect 键在鼠标位置直接 spawn 一次 RocketExplosionEffect（spec §4.9 键 Q）；统计活跃 Projectile / Effect 数（供 Debug 面板读）

### Step 9.1 写 weapon_demo.gd

Create `Scripts/Prototypes/Weapon/weapon_demo.gd`:

```gdscript
# Scripts/Prototypes/Weapon/weapon_demo.gd
# 主场景控制器：reset、Q 键 spawn Effect、活跃数统计。
class_name WeaponDemo
extends Node2D

@export var player_path: NodePath
@export var player_spawn: Vector2 = Vector2(400, 400)
@export var standalone_effect_scene: PackedScene  # 键 Q 在鼠标位置 spawn

var _player: RigidBody2D

func _ready() -> void:
	_player = get_node(player_path) as RigidBody2D
	if _player and not _player.is_in_group("player"):
		_player.add_to_group("player")  # affect_player=false 用 group 识别

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("Reset"):
			_reset_player()
		elif event.is_action_pressed("SpawnEffect"):
			_spawn_standalone_effect()

func _reset_player() -> void:
	if _player == null:
		return
	_player.linear_velocity = Vector2.ZERO
	_player.angular_velocity = 0.0
	_player.global_position = player_spawn

func _spawn_standalone_effect() -> void:
	if standalone_effect_scene == null:
		return
	var fx := standalone_effect_scene.instantiate() as Effect
	if fx == null:
		return
	add_child(fx)
	fx.trigger(get_global_mouse_position(), {"source": self, "direction": Vector2.RIGHT})

# Debug 面板读 —— 全场 Projectile 与 Effect 节点数（含子树）。
func count_active_projectiles() -> int:
	return get_tree().get_nodes_in_group("projectile").size()

func count_active_effects() -> int:
	return get_tree().get_nodes_in_group("effect").size()
```

> 计数走 group：在 `Projectile._ready` 加 `add_to_group("projectile")`、`Effect._ready` 加 `add_to_group("effect")`。

### Step 9.2 给 Projectile / Effect 加 group

修改 `Scripts/Prototypes/Weapon/projectile.gd` 的 `_ready`：

```gdscript
func _ready() -> void:
	add_to_group("projectile")
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
```

修改 `Scripts/Prototypes/Weapon/effect.gd` —— 加一个 `_ready` 注册到 group（保留原有 trigger 方法不变）：

```gdscript
func _ready() -> void:
	add_to_group("effect")
```

### Step 9.3 创建 weapon_demo.tscn

> **手写大段 .tscn 容易出错；建议用 Godot Editor 拼接然后保存。** 必须保证 .tscn 文件头 `uid` 已写、所有 `ext_resource` 都用 `uid="uid://..."`（memory `tscn_needs_uid_for_packedscene_refs`）。

最终场景树应包含：

```
WeaponDemo (Node2D, script = weapon_demo.gd)
├── CameraFollow (Camera2D, script = res://Scripts/Prototypes/3C/camera_follow.gd, target_path = ../Player3C)
├── Player3C (instance of res://Scenes/Prototypes/3C/player.tscn)
│   ├── Pistol (instance of pistol.tscn, wielder_path = "..")
│   └── RocketLauncher (instance of rocket_launcher.tscn, wielder_path = "..")
├── Ground (StaticBody2D, collision_layer = 1, big rectangle below)
├── ArenaWallLeft / Right / Top (StaticBody2D × 3, layer = 1, 把测试区围起来)
├── StaticWall (StaticBody2D 一堵, layer = 1, 用作 T3 验证)
├── Ceiling (StaticBody2D, layer = 1, 在角色头顶 5 m, 用作"朝上开枪压地"验证)
├── Dummy1 / Dummy2 / Dummy3 (instance of test_dummy.tscn, 散布在地面上)
├── FloorDummy (instance of test_dummy.tscn, 站在角色脚下供自爆跳验证)
└── DebugPanel (将在 Task 10 加)
```

> Player3C 需在 inspector 里勾 "Groups" → 加 `player`，作为后备（weapon_demo.gd `_ready` 也会兜底加）。
> 主场景 `WeaponDemo` 节点的 `player_path` 设 `Player3C`，`standalone_effect_scene` 拖入 `rocket_explosion_effect.tscn`，`player_spawn` 设 `(400, 400)` 或合适位置。
> Pistol / RocketLauncher 挂到 Player3C 下后，在 inspector 里把 `wielder_path` 设为 `..`（指向 Player3C）。

### Step 9.4 验证场景 smoke run

F6 `weapon_demo.tscn`，仅做"无 crash + 角色能动 + 按 R 能回原点"的 smoke check —— 物理验收交 Task 11。

### Step 9.5 提交

```bash
git add Scripts/Prototypes/Weapon/projectile.gd Scripts/Prototypes/Weapon/effect.gd Scripts/Prototypes/Weapon/weapon_demo.gd Scenes/Prototypes/Weapon/weapon_demo.tscn
git commit -m "feat(weapon): add weapon_demo scene + reset + standalone effect spawn

WeaponDemo controller: R = teleport player back to spawn, Q = spawn
rocket explosion at mouse (verifies Effect independently of weapons).
Projectile / Effect register to groups for runtime active-count display.
Scene wires Player3C + Pistol + RocketLauncher + arena walls + dummies
per spec §4.8.

Refs: spec §4.8 test scene, §4.9 debug input"
```

---

## Task 10: WeaponDebugPanel（runtime 调参 + 活跃数显示）

**Files:**
- Create: `Scripts/Prototypes/Weapon/weapon_debug_panel.gd`
- Modify: `Scenes/Prototypes/Weapon/weapon_demo.tscn`（加 DebugPanel 子节点）

参照 [3C debug_panel.gd](../../../Scripts/Prototypes/3C/debug_panel.gd) 的 SLIDER_SPECS + 实时 READOUT 模式；这里要绑的对象更复杂（Pistol、RocketLauncher、Effect 默认参数），用 NodePath 暴露多个对象。

### Step 10.1 写 WeaponDebugPanel

Create `Scripts/Prototypes/Weapon/weapon_debug_panel.gd`:

```gdscript
# Scripts/Prototypes/Weapon/weapon_debug_panel.gd
# F1 切换可见；runtime 调 Weapon / Projectile / Effect 子组件参数。
# 仿 Scripts/Prototypes/3C/debug_panel.gd 同款滑条 + readout 风格。
class_name WeaponDebugPanel
extends CanvasLayer

@export var pistol_path: NodePath
@export var rocket_path: NodePath
@export var pistol_effect_scene_path: String = "res://Scenes/Prototypes/Weapon/effects/pistol_hit_effect.tscn"
@export var rocket_effect_scene_path: String = "res://Scenes/Prototypes/Weapon/effects/rocket_explosion_effect.tscn"
@export var demo_path: NodePath  # WeaponDemo (for active counts)

var _pistol: Weapon
var _rocket: Weapon
var _demo: WeaponDemo
var _value_labels: Dictionary = {}

const PISTOL_SLIDERS := [
	["cooldown", "Pistol cooldown (s)", 0.05, 1.0],
	["recoil_impulse", "Pistol recoil (px·kg/s)", 0.0, 1000.0],
	["projectile_initial_speed", "Pistol speed (px/s)", 1000.0, 20000.0],
]
const ROCKET_SLIDERS := [
	["cooldown", "Rocket cooldown (s)", 0.1, 2.0],
	["recoil_impulse", "Rocket recoil (px·kg/s)", 0.0, 2000.0],
	["projectile_initial_speed", "Rocket speed (px/s)", 500.0, 8000.0],
]

func _ready() -> void:
	if pistol_path != NodePath():
		_pistol = get_node(pistol_path) as Weapon
	if rocket_path != NodePath():
		_rocket = get_node(rocket_path) as Weapon
	if demo_path != NodePath():
		_demo = get_node(demo_path) as WeaponDemo
	_build_ui()
	visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		visible = not visible

func _process(_dt: float) -> void:
	if not visible:
		return
	if _demo != null:
		if _value_labels.has("active_projectiles"):
			_value_labels["active_projectiles"].text = "active projectiles: %d" % _demo.count_active_projectiles()
		if _value_labels.has("active_effects"):
			_value_labels["active_effects"].text = "active effects: %d" % _demo.count_active_effects()
	# Pistol/Rocket recoil 开关与 affect_player 复选框由 toggle 自身回写

func _build_ui() -> void:
	var root := PanelContainer.new()
	root.position = Vector2(10, 10)
	root.custom_minimum_size = Vector2(360, 700)
	add_child(root)
	var vbox := VBoxContainer.new()
	root.add_child(vbox)

	var title := Label.new()
	title.text = "[F1] Weapon Debug Panel"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	# 实时数值
	for key in ["active_projectiles", "active_effects"]:
		var l := Label.new(); l.text = "%s: ..." % key; vbox.add_child(l); _value_labels[key] = l

	# Pistol
	_add_section(vbox, "Pistol")
	for spec in PISTOL_SLIDERS:
		_add_slider_for(vbox, _pistol, spec[0], spec[1], spec[2], spec[3])
	_add_toggle_for(vbox, _pistol, "recoil_enabled", "Pistol recoil enabled")

	# Rocket
	_add_section(vbox, "Rocket Launcher")
	for spec in ROCKET_SLIDERS:
		_add_slider_for(vbox, _rocket, spec[0], spec[1], spec[2], spec[3])
	_add_toggle_for(vbox, _rocket, "recoil_enabled", "Rocket recoil enabled")

	# Effect 默认 .tscn 是 PackedScene → 每次 instantiate 后才能改；
	# v1 简化：rocket_explosion_effect 的 affect_player 在场景里编辑保存。
	# 想运行时切，挂一个常驻 RocketExplosionEffect template 节点也可（未来 v1.5）。
	var hint := Label.new()
	hint.text = "(Effect params: edit .tscn directly; v1)"
	hint.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(hint)
func _add_section(parent: Control, name: String) -> void:
	var l := Label.new()
	l.text = "--- %s ---" % name
	l.add_theme_font_size_override("font_size", 14)
	parent.add_child(l)

func _add_slider_for(parent: Control, target: Object, prop: String, label_text: String, lo: float, hi: float) -> void:
	if target == null:
		return
	var row := HBoxContainer.new(); parent.add_child(row)
	var l := Label.new(); l.text = label_text; l.custom_minimum_size = Vector2(140, 0); row.add_child(l)
	var v := Label.new(); v.custom_minimum_size = Vector2(60, 0); row.add_child(v)
	var s := HSlider.new(); s.min_value = lo; s.max_value = hi; s.step = (hi - lo) / 1000.0
	s.value = target.get(prop)
	s.custom_minimum_size = Vector2(140, 0)
	v.text = "%.2f" % s.value
	s.value_changed.connect(func(val):
		target.set(prop, val); v.text = "%.2f" % val)
	row.add_child(s)

func _add_toggle_for(parent: Control, target: Object, prop: String, label_text: String) -> void:
	if target == null:
		return
	var cb := CheckBox.new()
	cb.text = label_text
	cb.button_pressed = target.get(prop)
	cb.toggled.connect(func(on): target.set(prop, on))
	parent.add_child(cb)
```

### Step 10.2 把 DebugPanel 加入 weapon_demo.tscn

在 Godot Editor 打开 `weapon_demo.tscn` → 右键 WeaponDemo → Add Child → CanvasLayer → 把 `weapon_debug_panel.gd` 拖到 script 槽 → 在 inspector 设：
- `pistol_path` → `../Player3C/Pistol`
- `rocket_path` → `../Player3C/RocketLauncher`
- `demo_path` → `..`（即 WeaponDemo 本身）

保存场景。

### Step 10.3 F6 smoke 验证

F6 `weapon_demo.tscn` → F1 切换面板 → 拖 Pistol cooldown 滑条到 1.0 → 确认按 LMB 间隔变长。

### Step 10.4 提交

```bash
git add Scripts/Prototypes/Weapon/weapon_debug_panel.gd Scenes/Prototypes/Weapon/weapon_demo.tscn
git commit -m "feat(weapon): add WeaponDebugPanel (F1 toggle, sliders, active counts)

Runtime sliders for Pistol/Rocket cooldown, recoil, speed; toggles for
recoil_enabled. Displays active projectile/effect counts via group
queries. Effect sub-component params edited via .tscn in v1 (per spec
§6 v1.5 scope hint).

Refs: spec §4.10 debug panel"
```

---

## Task 11: 验收（spec §1.3 成功标准 + §5.1 T1-T8 人工 F6 签字）

无代码改动；按 spec §5.1 表逐条人工 F6 验收，验证级别 5（按 memory `feedback_verify_each_edit`）。

### Step 11.1 跑全部自动化测试

把 `test_runner.tscn` 的 script 依次切换到：

- `Scripts/Prototypes/Weapon/tests/test_test_dummy.gd` → F6，预期 `[TEST test_dummy] ALL PASS`
- `Scripts/Prototypes/Weapon/tests/test_falloff.gd` → F6，预期 `[TEST falloff] ALL PASS`

再跑 3C 原有测试确认无回归（武器 spec 强调 3C 不改）：

- `Scripts/Prototypes/3C/tests/test_engine_torque.gd`
- `Scripts/Prototypes/3C/tests/test_input_buffer.gd`
- `Scripts/Prototypes/3C/tests/test_movement_state.gd`

任一退化即停下来排查。

### Step 11.2 请 user 执行 F6 复测清单（spec §5.1）

把以下清单交给 user 在 `weapon_demo.tscn` 里 F6 实测并签字：

```
[ ] T1 鼠标 LMB → 手枪直射弹高速飞出（视觉接近瞬到），命中 Dummy → 控制台打印 dmg=50
[ ] T2 鼠标 RMB → 火箭炮抛物线弹按弧线飞，命中后周围 Dummy 都打印伤害值并明显被推飞
[ ] T3 RMB 打 StaticWall → 爆炸视觉触发，墙不动，周围 dynamic 被推飞
[ ] T4 朝脚下 RMB → 角色跳上 1-2 m 高（验证自爆跳 ADR-0008）
[ ] T5 Debug 面板把 rocket_explosion_effect 的 affect_player 改 false（编辑 .tscn 或临时挂常驻节点），朝脚下 RMB → 仅周围物体推飞，角色不动
[ ] T6 Debug 面板关闭 Pistol recoil_enabled，连续 LMB → 角色完全不位移，仅视觉
[ ] T7 按 Q → 鼠标位置直接 spawn RocketExplosionEffect（独立验 Effect）
[ ] T8 角色被推飞撞 arena 墙 → 不出场；按 R 回原点
[ ] CCD：连续 LMB 朝薄墙最高速打 → 无穿透
[ ] 性能：连续高频开火 30 秒 → 帧率不雪崩，活跃数正常回收
[ ] 三元组独立性：把 Pistol 的 projectile_scene 临时换成 ballistic_projectile → 行为变化但 Pistol 其他参数无关联调整需求
```

### Step 11.3 架构验证（grep）

跑以下 grep 命令，期望全部输出为空（spec §5.2）：

```bash
# Effect 不应 import 任何 Weapon / Projectile 类型
grep -rn "Weapon\|Projectile" Scripts/Prototypes/Weapon/effect.gd Scripts/Prototypes/Weapon/damage_fields/ Scripts/Prototypes/Weapon/force_fields/

# DamageField 不应 import 任何 Constraint 类型（v1 仓库内尚无 destruction 代码，但确认不会偶然引入）
grep -rn "Constraint" Scripts/Prototypes/Weapon/damage_fields/
```

若有输出，立刻停下来查看是否是真实违规（注释里出现的 ADR 引用名可接受；类名 import / cast / preload 不可接受）。

### Step 11.4 user 签字后提交"验证完毕"标记

```bash
git commit --allow-empty -m "chore(weapon): verified weapon prototype v1 via F6 signoff

All §5.1 T1-T8 checklist items in docs/superpowers/plans/2026-05-25-weapon-prototype-plan.md
Step 11.2 confirmed by user. ADRs 0007/0008/0009/0010 demonstrated in
running demo. Ready for destruction-prototype integration (family B)."
```

---

## 风险与回滚（spec §6 + 实施补充）

| 风险 | 缓解 |
|---|---|
| godot-box2d 不支持 `continuous_cd = CCD_MODE_CAST_SHAPE` | T11 CCD 验收失败 → 子步细分：把 `projectile_initial_speed` 砍半 + max_lifetime 翻倍（仍是物理弹，绝不退 hitscan，按 ADR-0009） |
| godot-box2d 范围查询 `intersect_shape` 返回空 | 先在 `_try_pick_body` 同款风格里手测；若确认 GDExt 缺，退到 `get_tree().get_nodes_in_group("destructible") + 距离过滤`（v1 体量可接受） |
| 自爆跳量级过强 | Debug 面板调小 RadialBlast.peak_impulse 即可；不改架构 |
| 后坐力过大让玩家"开枪 = 漂移" | 关 recoil_enabled 或调小 recoil_impulse |
| Effect 视觉与销毁时序竞态 | spec §6 已警示；现实现走 tween 回调 queue_free，单一时间线无竞态 |
| 抛物线弹下坠手感不对（世界默认重力 ≠ 25 m/s²）| T11 F6 时若发现，调 BallisticProjectile.gravity_scale 或设 `project.godot` 物理重力 |
| **spec §4.10 要求 "Effect 子组件参数 runtime 可调"，v1 妥协为 .tscn 编辑后重启** | Debug 面板已加 hint 提示。v1.5 增量：WeaponDemo 挂常驻 EffectTemplate 节点（visible=false / process_mode=disabled），Projectile.duplicate(true) 该 template；Debug 面板直接编辑 template 的子节点。本计划不展开 |

回滚顺序（若某个 Task 验收不过且需重做）：每个 Task 各自一个 commit，逐个 revert 即可。Effect 子组件与 Effect 主类之间通过 has_method("apply") duck typing 连接 —— 删 / 加任一子组件不影响其他。

---

## 自检对照表（spec §1.3 成功标准 ↔ Task 映射）

| spec § | 标志 | 实现 Task |
|---|---|---|
| 1.3 #1 | LMB 手枪直射弹（CCD） | Task 6 + 8 + 11 |
| 1.3 #2 | RMB 火箭炮抛物线弹（重力下坠） | Task 6 + 8 + 11 |
| 1.3 #3 | 命中静态墙 → 爆炸视觉 + 推飞 | Task 5 + 6 + 9 + 11 |
| 1.3 #4 | 朝脚下 → 自爆跳 1-2 m | Task 4 RadialBlast.affect_player + 11 |
| 1.3 #5 | 受体打印伤害与冲量 | Task 2 TestDummy + 11 |
| 1.3 #6 | 后坐力可开关 | Task 7 recoil_enabled + Task 10 toggle |
| 1.3 #7 | runtime 调参 + 活跃数显示 | Task 10 + Task 9 group 计数 |
| 1.3 #8 | 三对象独立替换 | Task 5/6/7 文件结构 + Task 11 §5.2 grep + 手测换 projectile_scene |
