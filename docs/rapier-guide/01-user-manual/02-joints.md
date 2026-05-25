# 关节（Joints）

## 本章要解决什么问题

两个物体独立运动很简单。但如果你想让它们**以特定方式连接在一起**呢？

例如：
- 一个钟摆，摆锤围绕固定点旋转
- 一个弹簧门，推开后自动弹回
- 一个抽屉，只能沿轨道滑动

关节（Joint）就是解决这些问题的工具。它在你指定的两个物理物体之间建立一种约束关系（Constraint），告诉物理引擎："这两个物体必须遵守某种运动规则"。

```
类比：关节就是在两个物体之间系了一根隐形的绳子。
不同类型的关节 = 不同类型的绳子。
```

---

## 关节的基本概念

### 什么是约束

约束（Constraint）是一种数学规则，描述了物体之间"允许怎么动、不允许怎么动"。比如"这两个点必须重合"就是一个约束。

```
类比：一根木棍两端钉在地上 = 两端位置被约束。
棍子可以旋转，但不能平移。
```

### 关节的类型

Rapier 2D 支持四种关节类型：

| 关节 | Godot 节点 | 功能 | 类比 |
|------|-----------|------|------|
| Pin（销钉关节） | PinJoint2D | 两个物体共享一个旋转点 | 图钉钉住一张纸 |
| DampedSpring（阻尼弹簧） | DampedSpringJoint2D | 两个点在弹性力下保持特定距离 | 弹簧连接两个物块 |
| Groove（滑槽关节） | GrooveJoint2D | 一个点在另一个物体的轨道上滑动 | 抽屉滑轨 |
| 自定义 IK | （底层 API） | 基于逆向运动学的复杂约束 | 机器人手臂 |

### 三种求解器模式

Rapier 的关节支持三种求解器模式（`RapierJointType`），决定约束如何被计算：

| 模式 | 含义 | 适用场景 |
|------|------|----------|
| Impulse | 基于冲量的约束求解器（Constraint Solver） | 默认模式，适合大多数关节 |
| MultiBody | 多体求解器，精度更高 | 复杂连接链（如一串珠子） |
| MultiBodyKinematic | 支持运动学物体的多体求解器 | 一端连接运动学刚体时使用 |

> **大多数情况下使用默认的 Impulse 模式即可，不需要手动修改。** MultiBody 和 MultiBodyKinematic 仅在复杂关节链或连接运动学刚体时才有必要。

### 与其他后端的关键区别

在 Rapier 中，关节是**直接使用内置 Rapier 关节类型**的，不像 godot-box2d 需要额外注册。这确保了：
- PinJoint、DampedSpringJoint、GrooveJoint 均可开箱即用
- 支持 `motor_position_enabled`（位置马达），godot-box2d 不支持

---

## PinJoint（销钉关节 / Revolute Joint）

### 它做什么

PinJoint 在两个物体之间创建一个共享的旋转点。两个物体只能围绕这个点旋转，不能分开。

```
类比：用图钉把两张纸钉在一起。两张纸可以绕图钉旋转，
但图钉的位置始终固定，两张纸不能分开。
```

在 Rapier 中，PinJoint 被映射为 Revolute Joint（旋转关节）。这是物理学中的标准关节类型。

### 锚点（Anchor）

关节需要两个锚点：`anchor_a`（在 A 物体上的连接点）和 `anchor_b`（在 B 物体上的连接点）。创建关节时，引擎会将这两个点拉到一起。

内部实现：Rapier 在创建 PinJoint 时，将世界坐标的 anchor 转换为物体局部坐标（使用 `world_to_local_no_scale`），确保缩放不影响关节位置。

### 角度限制（Angular Limits）

你可以限制两个物体之间的旋转角度范围：

- `angular_limit_lower`：最小允许角度（弧度）
- `angular_limit_upper`：最大允许角度（弧度）
- `angular_limit_enabled`：是否启用角度限制

```
类比：房门铰链。门只能从 0°（关闭）转到 90°（完全打开），
不能转一整圈。
```

```gdscript
# 设置角度限制（例如限制门只能开 90°）
$PinJoint2D.set_flag(PinJoint2D.FLAG_ANGULAR_LIMIT_ENABLED, true)
$PinJoint2D.set_param(PinJoint2D.PARAM_LIMIT_LOWER, 0.0)
$PinJoint2D.set_param(PinJoint2D.PARAM_LIMIT_UPPER, PI / 2.0)
```

### 速度马达（Velocity Motor）

速度马达让关节的旋转有持续的角速度。就像给关节装了一个马达：

- `motor_enabled`：是否启用马达
- `motor_target_velocity`：目标角速度（弧度/秒）

```
类比：电风扇的旋转轴。只要不关闭开关，
扇叶就会持续以固定速度旋转。
```

### 位置马达（Position Motor / Motor Position）

位置马达是 Rapier 的独特功能：你可以**直接指定关节应该旋转到的目标角度**，引擎会自动计算需要多大的力来实现。

- `motor_position_enabled`：是否启用位置马达
- `motor_target_position`：目标角度（弧度）
- `motor_stiffness`：刚度 -- 多大的力驱动向目标（类比弹簧硬度）
- `motor_damping`：阻尼 -- 接近目标时的减速程度

```
类比：舵机（Servo Motor）。你发送"转到 45°"指令，
舵机自己计算速度和力度，精确停到目标角度。
```

```gdscript
# 让关节转到 45° 并使用位置马达
$PinJoint2D.set_motor_position_options(
    deg_to_rad(45.0),  # target position
    100.0,             # stiffness（刚度）
    10.0,              # damping（阻尼）
    true               # enable
)
```

> godot-box2d 不支持 `motor_position_enabled`。如果你从 Box2D 迁移到 Rapier，这是一个重要的新增能力。

### softness（柔度）

PinJoint 的 `softness` 参数控制约束的"刚性程度"。值越小越硬（更精确但可能产生抖动），值越大越软（允许一定的误差）。

```gdscript
$PinJoint2D.set_param(PinJoint2D.PARAM_SOFTNESS, 0.1)
```

### max_force：关节最大力

`max_force` 限制关节能施加的最大力。默认是 `f32::MAX`（无限制）。降低此值可以让关节在外力过大时"断开"或"滑动"。

---

## DampedSpringJoint（阻尼弹簧关节）

### 它做什么

DampedSpringJoint 在两个物体的锚点之间建立一个弹簧连接。弹簧有自然的静止长度（rest_length），当两个锚点距离偏离这个长度时，弹簧施加力使它们恢复。

```
类比：一根弹簧两端各系一个小球。你把小球拉开后松手，
弹簧会把它们拉回来，但由于阻尼存在，它们不会永远震荡。
```

### 三个核心参数

弹簧的行为由三个参数完全决定：

| 参数 | 含义 | 类比 |
|------|------|------|
| `stiffness` | 刚度 -- 偏离静止长度时施加多大力 | 弹簧的"硬度"，汽车悬挂弹簧 vs 圆珠笔弹簧 |
| `damping` | 阻尼 -- 减速的程度 | 弹簧浸泡在油中还是空气中 |
| `rest_length` | 静止长度 -- 弹簧不受力时的自然长度 | 弹簧的原长 |

```
刚度决定"弹得多猛"，阻尼决定"弹多久才停"。
高刚度 + 低阻尼 = 不停震荡（秋千）
高刚度 + 高阻尼 = 迅速归位（汽车减震器）
低刚度 + 高阻尼 = 缓慢移动（棉花糖）
```

### 创建时的 rest_length 自动计算

Rapier 在创建 DampedSpringJoint 时，会自动计算两个锚点之间的初始距离作为 `rest_length`：

```rust
// 内部实现（示意）
let rest_length = (anchor_a - anchor_b).length();
```

默认初始值：
- `stiffness = 20.0`
- `damping = 1.0`

```gdscript
# 调整弹簧参数
$DampedSpringJoint2D.stiffness = 50.0   # 更硬的弹簧
$DampedSpringJoint2D.damping = 5.0     # 更快的减速
$DampedSpringJoint2D.rest_length = 100.0 # 100px 的静止长度
```

### 注意：length = maxLength

根据项目 memory 中的记录，在 godot-box2d 中，DampedSpringJoint 的 `length` 参数映射到 Box2D 的 `maxLength`（硬约束）。在 Rapier 中，弹簧是软约束（soft constraint），`rest_length` 就是真正的静止长度。

---

## GrooveJoint（滑槽关节）

### 它做什么

GrooveJoint 让物体 B 的一个点在物体 A 的**一条轨道**上滑动。轨道由两点定义，物体 B 的锚点只能在这两点之间的线段上移动。

```
类比：抽屉滑轨。抽屉只能沿着固定的轨道前后滑动，
不能左右偏移，也不能上下跳动。
```

### 轨道定义

轨道由两个点定义：
- `p_a_groove1`：轨道起点（在 A 物体的局部空间）
- `p_a_groove2`：轨道终点（在 A 物体的局部空间）

以及 B 物体上的锚点：
- `p_b_anchor`：B 物体上沿轨道滑动的点

内部实现：Rapier 使用 `joint_create_pin_slot`，其中：
- 轴向（axis）= `normalize(groove2 - groove1)`
- 限制（limits）= `(0, length)` -- 只能在轨道线段上滑动
- A 的锚点 = `groove1`（轨道的起点）

```
groove1 ●──────────────────────● groove2
              ↑ direction (axis)
        锚点 B 在这条线上滑动
```

```gdscript
# 创建一个水平滑槽
$GrooveJoint2D.length = 200.0  # 滑槽长度
```

---

## 通用关节属性

### disable_collisions_between_bodies

默认情况下，关节两端的物体之间**不会**互相碰撞（`disabled_collisions_between_bodies = true`）。这通常是期望的行为 -- 你不会希望弹簧两端的物体互相穿透。

如果你需要它们碰撞（比如做一条松垂的链子），可以设置为 false。

### max_force

所有关节都共享 `max_force` 属性。它限制了关节能施加的最大力，防止关节在有外力的极端情况下"过载"引起速度爆炸。

默认值为 `f32::MAX`（无限制）。

### RapierJointType（求解器模式）

通过底层 API 可以设置关节的求解器类型：
- `Impulse`（默认）：适合大多数情况
- `MultiBody`：精度更高，适合链条等复杂连接
- `MultiBodyKinematic`：当关节连接运动学刚体时使用

---

## 延伸阅读

- [Rapier 官方文档：Joints](https://rapier.rs/docs/user_guides/2d/joints)
- Godot 官方文档：PinJoint2D / DampedSpringJoint2D / GrooveJoint2D
- 参考：godot-box2d 关节限制（哪些关节在 Box2D 中不可用）
- 本指南：[01-rigid-body.md](01-rigid-body.md) -- 关节连接的是什么
