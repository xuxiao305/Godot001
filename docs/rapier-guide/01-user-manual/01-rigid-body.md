# 刚体（RigidBody2D）

## 本章要解决什么问题

你在 Godot 中放置了一个物体，你希望它：
- 静止不动，作为地板或墙壁
- 受重力影响自然下落
- 被代码精确控制位置，但不被物理引擎推动

这三个需求对应 RigidBody2D 的三种模式。本章会解释每种模式的含义、相互之间的区别，以及如何调校物体的物理行为。

---

## 刚体类型（body_type）

Rapier 中的刚体有四种基本模式，分别对应 Godot 的不同节点类型（StaticBody2D、CharacterBody2D、RigidBody2D）和配置。你可以把刚体模式理解为物体的"性格"：

| 模式 | 含义 | 生活类比 | 能受力吗 | 能碰撞吗 |
|------|------|----------|----------|----------|
| Static | 完全不动 | 地板、墙壁 | 不会 | 会（阻挡其他物体） |
| Kinematic | 只由代码控制 | 电梯、移动平台 | 不会 | 会（可以推走动态物体） |
| Dynamic | 完全由物理引擎模拟 | 掉落的箱子、滚动的球 | 会 | 会 |
| Rigid Linear | 动态但禁止旋转 | 只能平移的推箱子 | 会（仅线性） | 会 |

### Static：大地一样稳固

Static 刚体（Static Body）就像地面一样 -- 物理引擎假定它**永远不会移动**。因此引擎可以做大量优化：不计算它的受力、不更新它的速度、不需要做 CCD。

```
类比：桌球台上的库边（rail）。球会撞上去弹回来，
但库边本身纹丝不动。
```

何时使用：
- 地板、墙壁、天花板
- 不会移动的平台
- 装饰性碰撞（如柱子）

### Kinematic：我让你的位置，你别碰我的

Kinematic 刚体（Kinematic Body）是一个"不讲物理道理"的物体。它**完全由代码控制位置**，物理引擎不会对它施加力。但它会碰撞其他物体并产生接触信息。

```
类比：自动扶梯。电梯的台阶按预定的轨迹（代码）移动，
不会因为站了人而减速或停止。但站在上面的人（Dynamic Body）
会被带着走。
```

何时使用：
- 移动平台
- 角色控制器（CharacterBody2D 内部就是 Kinematic 模式）
- 传送带
- 任何需要精确位置控制的碰撞体

**注意**：在 Rapier 中，Kinematic 刚体使用 `position_based` 模式。这意味着它的位置在每一步开始时被设置，然后物理引擎将其他物体推开以适应该位置。

### Dynamic：让物理引擎全权负责

Dynamic 刚体（Dynamic Body）是"正常的"物理物体。你给它一个初始位置和速度，剩下的交给物理引擎：重力、碰撞、摩擦力都会自然地影响它的运动。

```
类比：台球。你击打后它会滚动，碰到库边会反弹，
碰到其他球会传递动量。你不直接控制它的运动轨迹 --
所有运动都是碰撞和摩擦的"副作用"。
```

何时使用：
- 可推动的箱子
- 滚动的球
- 掉落的碎片
- 需要物理交互的任何物体

### Rigid Linear：动态但禁止旋转

Rigid Linear 是 Dynamic 的变体。它受力和碰撞的影响，但**角速度始终为零** -- 物体不会旋转。

```
类比：冰壶。它在冰面上滑动，但始终保持相同的朝向。
```

内部实现：在 Rapier 中，Rigid Linear 同样是 Dynamic 类型，但 `angular_velocity` 被强制清零，惯性（inertia）也被设为零。

---

## 质量（mass）

### 质量不是重量

质量（Mass）在物理上衡量的是"改变速度的难易程度"，而不是"有多重"。一个 10kg 的物体比 1kg 的物体更难推动，也更容易把轻物体撞飞。

```
类比：推一辆自行车 vs 推一辆卡车。同样的力气，
自行车会迅速加速，卡车几乎纹丝不动。
```

在 Rapier 中：
- `mass` 必须大于 0
- 默认质量为 1.0
- 质量影响碰撞响应：更重的物体会把更轻的物体推得更远
- 你可以手动设置 `CENTER_OF_MASS`（质心偏移），或让引擎根据形状自动计算

```gdscript
# 设置质量（在 GDScript 中操作 RigidBody2D）
$RigidBody2D.mass = 5.0

# 自定义质心（例如让物体上半部分更重）
# 注意：这通常通过 PhysicsServer 直接操作
```

### 惯性（Inertia）

惯性是质量的"旋转版本"-- 衡量"改变旋转速度的难易程度"。惯性取决于质量分布：同样质量的圆环比圆盘更难转起来，因为质量分布在远离旋转轴的位置。

默认情况下 Rapier 会根据碰撞形状自动计算惯性。设置 `INERTIA = 0` 会让引擎重新使用自动计算。

---

## 阻尼（Damping）

### linear_damp 和 angular_damp

阻尼（Damping）就像物体在介质中运动时受到的阻力。`linear_damp` 减缓平移速度，`angular_damp` 减缓旋转速度。

```
类比：在水里挥手 vs 在空气里挥手。
水提供了更大的阻尼，手很快就停下来了。
```

- `linear_damp = 0.0`：无阻力，物体永远不停（太空中）
- `linear_damp = 1.0`：轻微阻力，适合大多数游戏场景
- `linear_damp = 10.0`：很大的阻力，物体很快减速（蜂蜜中）

> **注意**：以上阻尼值基于 Rapier 的默认行为。Godot 内置物理的默认阻尼值和衰减曲线不同，从内置物理迁移时需要重新调整阻尼参数。

在 Rapier 中：
- `linear_damp` 和 `angular_damp` 的默认值都是 0.0
- `linear_damping_mode` 和 `angular_damping_mode` 决定阻尼如何与 Area2D 的空间覆盖（Space Override）叠加
  - `COMBINE`：物体自己的阻尼 + Area 的阻尼
  - `REPLACE`：只用 Area 的阻尼，忽略物体自己的

### 阻尼模式

| 模式 | 含义 |
|------|------|
| COMBINE | 叠加：物体阻尼 + 空间默认阻尼 |
| REPLACE | 替换：仅使用物体自身的阻尼值 |

---

## 冻结与休眠（freeze vs sleep）

### freeze：手动冻结

`freeze` 是一个**手动控制**的开关。当你设置 `freeze = true`，物理引擎停止更新该物体的位置和速度。物体"凝固"在当前位置。

```
类比：你用手按住一个球。不管你用多大的力气推它，
它都不会动，因为它被按住了。
```

- freeze 是你主动做出的决定（"这个物体现在不应该动"）
- freeze_mode 决定物体被冻结（freeze = true）时的行为方式（STATIC 或 KINEMATIC），不影响正常状态下的刚体类型

### sleep：自动休眠

`sleep` 是物理引擎的**自动优化**。当一个 Dynamic 物体静置一段时间后（速度几乎为零），引擎会自动让它"睡着"-- 不再参与物理计算，直到被其他物体碰醒。

```
类比：桌上的一个苹果。它静止不动，没有外力施加，
物理引擎聪明地不去计算它，因为"什么都不做"就是正确结果。
```

相关属性：
- `can_sleep`：是否允许该物体自动休眠（默认 true）
- `sleeping`（状态）：当前是否处于休眠状态
- `activation_linear_threshold`：线性速度低于此阈值时认为静止
- `activation_angular_threshold`：角速度低于此阈值时认为静止
- `activation_time_until_sleep`：保持静止多少秒后进入休眠

**性能提示**：让`can_sleep = true`（默认），可以显著减少物理计算量。一堆静止的箱子不会消耗性能。

---

## CCD（Continuous Collision Detection，连续碰撞检测）

### 高速物体的隧穿问题

当物体移动速度非常快时，可能在一个物理帧内从障碍物的**一侧穿到另一侧**，从而"穿透"碰撞体。这称为隧穿效应（Tunneling）。

```
类比：一枚子弹穿过一张纸。如果纸只有 0.1mm 厚，
子弹在 1/60 秒内已经飞了 10 米，物理引擎来不 及检测
到子弹和纸在同一帧内重叠。
```

```
帧 N：  [子弹] ----->  [墙]
帧 N+1：[墙]  [子弹]  -> 子弹已经穿过墙了！
```

### CCD 的工作原理

Rapier 的 CCD 会在物体高速移动时，不只看当前位置，还会检测**运动轨迹**上是否被其他物体阻挡。如果有，就提前处理碰撞。

```
类比：与其只看两张照片（前一帧和后一帧），
CCD 会检查两帧之间拍摄的"录像"，确保没有遗漏任何碰撞。
```

- `ccd_enabled`：是否启用 CCD（默认 false）
- `soft_ccd_prediction`：预测距离，在物体接近碰撞时提前介入
- **子弹、快箭、飞刀等高速投射物必须开启 CCD**

---

## gravity_scale：每物体的重力倍率

`gravity_scale` 控制该物体受到多少重力影响。

```
类比：不同行星上的重力。重力倍率 1.0 = 地球，
0.5 = 月球，0.0 = 太空。
```

- 默认值：1.0
- 设置为 0.0 让物体不受重力（但仍然受其他力影响）
- 设置为负值让物体"上升"
- 如果物体处于 Area2D 的空间覆盖（Space Override）中，Area 的重力会替代默认重力

---

## 材质属性

### bounce（弹性/反弹系数）

控制碰撞后的反弹程度。0.0 = 完全不弹（黏土球），1.0 = 完全弹（理想弹球）。

### friction（摩擦系数）

控制表面粗糙度。0.0 = 冰面，1.0 = 橡胶。摩擦力影响物体在表面上的滑动行为。

### contact_skin（接触皮肤厚度）

Rapier 特有的参数。在物体表面额外加一层"皮肤"，帮助检测碰撞。增大该值可以减少抖动物体（特别是堆叠时），但会让物体看起来"浮"在表面上。

---

## 信号（Signals）

RigidBody2D 提供了丰富的碰撞信号，用于在碰撞发生时执行逻辑：

| 信号 | 触发时机 |
|------|----------|
| `body_entered` | 另一个身体进入碰撞 |
| `body_exited` | 另一个身体离开碰撞 |
| `body_shape_entered` | 另一个身体的特定形状进入碰撞 |
| `body_shape_exited` | 另一个身体的特定形状离开碰撞 |
| `area_entered` | 进入 Area2D |
| `area_exited` | 离开 Area2D |
| `sleeping_state_changed` | 休眠/唤醒状态改变 |

**注意**：Rapier 的 contact reporting（接触上报）需要显式开启。通过 `max_contacts_reported` 设置上报的最大接触点数量（默认为 0，即不上报任何接触细节）。

```gdscript
# 开启接触上报，最多报告 4 个接触点
$RigidBody2D.max_contacts_reported = 4

# 连接信号
$RigidBody2D.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node):
    print("碰到了: ", body.name)
```

---

## 力和冲量（Force vs Impulse）

### 两种施加方式

| 方式 | 含义 | 类比 |
|------|------|------|
| `apply_central_force` | 持续施加力（每帧累积） | 火箭发动机持续推进 |
| `apply_central_impulse` | 瞬间施加冲量（一次性） | 用锤子敲一下 |

力（Force）和冲量（Impulse）的根本区别在于时间：力是持续的，冲量是瞬间的。在物理引擎中，"瞬间"意味着在一帧内完成速度改变。

```
类比：
- Force = 推着购物车走（持续的推力）
- Impulse = 踢一脚足球（瞬间的爆发力）
```

Rapier 中对应的内部调用：
- `apply_central_impulse` -> `body_apply_impulse`（添加冲量到质心）
- `apply_impulse` -> `body_apply_impulse_at_point`（在指定位置添加冲量，同时产生转矩）
- `apply_torque_impulse` -> `body_apply_torque_impulse`（转矩冲量）
- `add_constant_central_force` -> `body_add_force`（添加持续力到质心）
- `add_constant_torque` -> `body_add_torque`（添加持续转矩）

---

## custom_integrator：自定义力积分

当 `custom_integrator = true`（即 `omit_force_integration`）时，物理引擎不再自动计算重力、阻尼。你需要通过 `_integrate_forces` 回调手动施加所有力和冲量。

```gdscript
# 在 RigidBody2D 上
func _integrate_forces(state: PhysicsDirectBodyState2D):
    # 手动施加自定义重力
    state.apply_central_force(Vector2(0, 980))
    # 手动施加自定义阻力
    state.linear_velocity *= 0.99
```

内部实现：Rapier 在 `omit_force_integration` 时会将 `gravity_scale` 设为 0，将模拟阻尼设为 0，完全依赖用户在回调中自行处理。

---

## 延伸阅读

- [Rapier 官方文档：Rigid Body](https://rapier.rs/docs/user_guides/2d/rigid_bodies)
- Godot 官方文档：RigidBody2D
- 本指南：[02-joints.md](02-joints.md) -- 如何连接两个刚体
- 本指南：[04-collision-shapes.md](04-collision-shapes.md) -- 给刚体加上形状
