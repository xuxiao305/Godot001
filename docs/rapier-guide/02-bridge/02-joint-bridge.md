# 02 -- 关节桥接 (Joint Bridge)

本章讲解 Godot 的各种关节类型如何映射到 Rapier 的 `GenericJoint` / `RevoluteJointBuilder` / `SpringJointBuilder` / `PinSlotJointBuilder`。核心桥接代码位于 `src/rapier_wrapper/joint.rs`。

## 关节类型总览 (2D)

| Godot 关节 (2D) | Rapier Builder | 对应函数 |
|---|---|---|
| `JointType::PIN` (PinJoint/RevoluteJoint) | `RevoluteJointBuilder` | `joint_create_revolute()` |
| `JointType::DAMPED_SPRING` | `SpringJointBuilder` | `joint_create_spring()` |
| `JointType::GROOVE` | `PinSlotJointBuilder` | `joint_create_pin_slot()` |

## RapierJointType -- 关节存储类型

所有关节在创建时都需要指定一个 `RapierJointType` 枚举，决定关节存储在 Rapier 的哪个容器中：

| 枚举值 | Rapier 存储容器 | 适用场景 | 使用建议 |
|---|---|---|---|
| `Impulse` | `ImpulseJointSet` | 大多数关节，使用冲量求解 | **默认选择** -- 几乎所有 2D 关节场景都用此类型，性能好且行为稳定 |
| `MultiBody` | `MultibodyJointSet` | 多体系统（正向动力学），支持 IK | 需要反向运动学 (IK) 或多体动力学链时使用（如机械臂、布娃娃） |
| `MultiBodyKinematic` | `MultibodyJointSet` (kinematic) | 多体系统（运动学），支持 IK | 需要运动学驱动 + IK 混合时使用（如动画驱动的布娃娃） |

当前插件的 2D 实现中，`RapierJointType` 由 joints 层在创建时传入。大多数情况下使用 `Impulse` 类型。

## 关节生命周期

```
create (创建)
  |-- 构造 RapierJoint 对象 (Godot 数据层)
  |-- 调用 PhysicsEngine::joint_create_*()
  |-- 锚点转换 (world -> local, 去掉 scale)
  |-- 调用 Rapier builder -> build() -> insert_joint()
  |
  v
change_params (修改参数)
  |-- Godot 调用 set_param() / set_flag()
  |-- 获取 mut joint handle
  |-- 调用 Rapier set_*() 方法
  |
  v
destroy (销毁)
  |-- PhysicsEngine::destroy_joint()
  |-- 从 ImpulseJointSet / MultibodyJointSet 中移除
```

## 1. PinJoint / RevoluteJoint (RevoluteJointBuilder)

### Godot 关节创建时的参数映射

在 `RapierRevoluteJoint::new()` 中：

```rust
// 关键: 将 world-space 锚点转为 local-space (去掉 scale)
let anchor_a = world_to_local_no_scale(&body_a.get_base().get_transform(), anchor_a);
let anchor_b = world_to_local_no_scale(&body_b.get_base().get_transform(), anchor_b);
let rapier_anchor_a = vector_to_rapier(anchor_a);
let rapier_anchor_b = vector_to_rapier(anchor_b);
```

### joint_create_revolute() 参数映射表 (2D)

| Godot 参数 / Flag | 桥梁层参数 | Rapier Builder 方法 | 说明 |
|---|---|---|---|
| anchor_a | `anchor_1` | `.local_anchor1(anchor_1)` | body A 本地坐标系下的锚点 |
| anchor_b | `anchor_2` | `.local_anchor2(anchor_2)` | body B 本地坐标系下的锚点 |
| `ANGULAR_LIMIT_ENABLED` flag | `angular_limit_enabled` | `.limits([lower, upper])` | 仅 flag=true 时设置 |
| `LIMIT_LOWER` param | `angular_limit_lower` | limits[0] | 弧度，最小角度 |
| `LIMIT_UPPER` param | `angular_limit_upper` | limits[1] | 弧度，最大角度 |
| `MOTOR_ENABLED` flag | `motor_enabled` | `.motor_velocity(...)` | 速度模式电机 |
| `MOTOR_TARGET_VELOCITY` param | `motor_target_velocity` | motor_velocity 参数 | 目标角速度 |
| motor position enabled | `motor_position_enabled` | `.motor_position(...)` | 位置模式电机 |
| motor target position | `motor_target_position` | motor_position 参数 | 目标角度 |
| motor stiffness | `motor_stiffness` | motor_position 参数 | 弹簧刚度 |
| motor damping | `motor_damping` | motor_position 参数 | 阻尼 |
| `disable_collision` | `disable_collision` | `.contacts_enabled(!disable_collision)` | 是否禁用两 body 间碰撞 |

> **内置参数说明**: `motor_max_force` 和 `motor_model` 在创建时内置为固定值，不从 Godot 参数传入：
> - `motor_max_force` = `Real::MAX` -- 电机的最大力，设为无穷大
> - `motor_model` = `MotorModel::ForceBased` -- 2D 使用 ForceBased 电机模型

### joint_create_revolute 关键代码 (2D)

```rust
let mut joint = RevoluteJointBuilder::new()
    .local_anchor1(anchor_1)
    .local_anchor2(anchor_2)
    .contacts_enabled(!disable_collision)
    .motor_max_force(Real::MAX)
    .motor_model(MotorModel::ForceBased);
if angular_limit_enabled {
    joint = joint.limits([angular_limit_lower, angular_limit_upper]);
}
if motor_enabled {
    joint = joint.motor_velocity(motor_target_velocity, 0.0)
} else if motor_position_enabled {
    joint = joint.motor_position(motor_target_position, motor_stiffness, motor_damping)
}
return physics_world.insert_joint(body_handle_1, body_handle_2, joint_type, joint);
```

**电机模型选择**：2D 使用 `MotorModel::ForceBased` 而非 `AccelerationBased`。ForceBased 在设计上更接近 Godot 的 PinJoint 电机行为。

> **已知不一致**: 创建时使用 `MotorModel::ForceBased`，但 `joint_change_revolute_params()` 中却切换为 `MotorModel::AccelerationBased`（见下方）。参数修改路径与初建路径共享同一函数体，当前实现未区分两者。这是一个已知的不一致，正在追踪修复。如果运行时遇到电机行为异常，可以检查此处。

### joint_change_revolute_params() -- 运行时修改参数

```rust
joint.set_motor_model(MotorModel::AccelerationBased); // 注意: 这里改为了 AccelerationBased
joint.set_motor_max_force(Real::MAX);
if angular_limit_enabled {
    joint.set_limits([angular_limit_lower, angular_limit_upper]);
} else {
    joint.data.limit_axes.remove(JointAxesMask::ANG_X);
}
```

注意：修改参数时使用的 `MotorModel` 与创建时不同 -- 改为 `AccelerationBased`。这是因为参数修改路径与初建路径共享同一函数，而某些情况下 AccelerationBased 的行为更合适。

### Softness 参数转换 (仅 2D PinJoint)

Godot 2D PinJoint 有 `SOFTNESS` 参数。如果 softness <= 0，表示使用硬约束：

```rust
if softness <= 0.0 {
    joint.data.softness.natural_frequency = 1.0e6; // 极高频率 -> 几乎硬
    joint.data.softness.damping_ratio = 1.0;
} else {
    let softness_clamped = softness.clamp(Real::EPSILON, 16.0);
    joint.data.softness.natural_frequency = 10_f32.powf(3.0 - softness_clamped * 0.2);
    joint.data.softness.damping_ratio = 10_f32.powf(-softness_clamped * 0.4375);
}
```

这个经验公式将 Godot 的 softness 值映射到自然频率和阻尼比：
- `natural_frequency = 10^(3.0 - softness * 0.2)` -- softness 越大，自然频率越低
- `damping_ratio = 10^(-softness * 0.4375)` -- softness 越大，阻尼比越小

## 2. DampedSpringJoint (SpringJointBuilder)

### Godot 参数映射

在 `RapierDampedSpringJoint2D::new()` 中：

```rust
// rest_length 由两个锚点之间的世界距离计算
let rest_length = (p_anchor_a - p_anchor_b).length();

// 锚点转换为 local space
let rapier_anchor_a = world_to_local_no_scale(&body_a.get_base().get_transform(), p_anchor_a);
let rapier_anchor_b = world_to_local_no_scale(&body_b.get_base().get_transform(), p_anchor_b);
```

### joint_create_spring() 参数映射表

| Godot 参数 | 桥梁层参数 | Rapier Builder 方法 | 说明 |
|---|---|---|---|
| anchor_a | `anchor_1` | `.local_anchor1(anchor_1)` | body A 本地锚点 |
| anchor_b | `anchor_2` | `.local_anchor2(anchor_2)` | body B 本地锚点 |
| `STIFFNESS` | `stiffness` | 见下方转换 | Godot 弹簧刚度 (N/m) |
| `DAMPING` | `damping` | 见下方转换 | Godot 阻尼系数 |
| `REST_LENGTH` | `rest_length` | `SpringJointBuilder::new(rest_length, ...)` | 弹簧自然长度 |
| -- (内置) | `spring_model` | `.spring_model(MotorModel::AccelerationBased)` | 固定使用 AccelerationBased |

### godot_spring_to_rapier_accel 转换公式

这是最关键的参数转换。Godot 使用 Hooke 定律式的 stiffness/damping 参数，而 Rapier 的 AccelerationBased 模型使用频率/阻尼比参数：

```rust
fn godot_spring_to_rapier_accel(stiffness: Real, damping: Real) -> (Real, Real) {
    // 1. Godot stiffness (N/m) -> angular frequency: omega = sqrt(k/m), assume m=1
    let omega = stiffness.sqrt();

    // 2. Godot damping coefficient -> damping ratio
    //    zeta = c / (2 * sqrt(k*m)), assume m=1
    let damping_ratio = if stiffness > 0.0 {
        damping / (2.0 * stiffness.sqrt())
    } else {
        0.0
    };

    // 3. Convert back to AccelerationBased format
    let rapier_stiffness = omega * omega;       // = k (same as Godot)
    let rapier_damping = 2.0 * damping_ratio * omega;  // = c (same as Godot, unit mass)
    (rapier_stiffness, rapier_damping)
}
```

**数学推导**：对于单位质量 (m=1) 的弹簧-阻尼系统：
- 运动方程：`m*x'' + c*x' + k*x = 0`，当 m=1 时变为 `x'' + c*x' + k*x = 0`
- 固有频率：`omega_n = sqrt(k)`
- 阻尼比：`zeta = c / (2*sqrt(k))`
- AccelerationBased 模型参数：`stiffness = omega_n^2 = k`, `damping = 2*zeta*omega_n = c`

因此对于 m=1 的情况，转换是恒等的。转换的目的是验证和规范化参数值，确保它们构成一个物理合理的阻尼系统。

### 创建代码

```rust
let (rapier_stiffness, rapier_damping) = Self::godot_spring_to_rapier_accel(stiffness, damping);
let joint = SpringJointBuilder::new(rest_length, rapier_stiffness, rapier_damping)
    .spring_model(MotorModel::AccelerationBased)
    .local_anchor1(anchor_1)
    .local_anchor2(anchor_2)
    .contacts_enabled(!disable_collision);
```

### joint_change_spring_params() -- 运行时修改

修改参数时使用 `motor_position` 接口重新设置弹簧属性：

```rust
joint.set_motor_position(JointAxis::LinX, rest_length, rapier_stiffness, rapier_damping);
joint.set_motor_model(JointAxis::LinX, MotorModel::AccelerationBased);
```

## 3. GrooveJoint (PinSlotJointBuilder)

### Godot 参数映射

在 `RapierGrooveJoint2D::new()` 中：

```rust
// 从两个 groove 端点计算轴向和长度
let point_a_1 = world_to_local_no_scale(&base_a.get_transform(), p_a_groove1);
let point_a_2 = world_to_local_no_scale(&base_a.get_transform(), p_a_groove2);
let axis = vector_normalized(point_a_2 - point_a_1);
let length = (point_a_2 - point_a_1).length();
let rapier_limits = vector_to_rapier(Vector2::new(0.0, length));
```

### joint_create_pin_slot() 参数映射表

| Godot 参数 | 桥梁层参数 | Rapier Builder 方法 | 说明 |
|---|---|---|---|
| groove_1, groove_2 | `axis` (计算得到) | `PinSlotJointBuilder::new(axis)` | 滑槽方向 |
| groove_1, groove_2 | `limits` (计算得到) | `.limits([0, length])` | 滑槽范围 |
| groove_1 | `anchor_1` | `.local_anchor1(anchor_1)` | 滑槽起点 (body A 本地) |
| anchor_b | `anchor_2` | `.local_anchor2(anchor_2)` | 销钉锚点 (body B 本地) |

### 创建代码

```rust
let joint = PinSlotJointBuilder::new(axis)
    .local_anchor1(anchor_1)
    .local_anchor2(anchor_2)
    .limits([limits.x, limits.y])
    .contacts_enabled(!disable_collision);
return physics_world.insert_joint(body_handle_1, body_handle_2, joint_type, joint);
```

### 设计说明

GrooveJoint 有一个独特之处：它没有运行时可修改的参数（`set_param` / `get_param` 不存在）。所有参数在创建时确定。这是 Godot 的 GrooveJoint2D API 的设计选择 -- Godot 原生 GrooveJoint2D 也不提供运行时修改 groove 端点或锚点的能力，因此 Rapier 桥接层无需实现这些功能。Rapier 本身的 `PinSlotJoint` 理论上支持运行时修改参数，只是当前桥接层选择不暴露。

## 关节通用操作

### 创建 (insert_joint)

所有关节创建最终都调用 `PhysicsWorld::insert_joint()`：

```rust
pub fn insert_joint(&mut self, body_handle_1, body_handle_2, joint_type, joint) -> JointHandle {
    match joint_type {
        RapierJointType::Impulse => {
            self.physics_objects.impulse_joint_set
                .insert(body_handle_1, body_handle_2, joint, true)
        }
        RapierJointType::MultiBody => {
            self.physics_objects.multibody_joint_set
                .insert(body_handle_1, body_handle_2, joint, true)
        }
        RapierJointType::MultiBodyKinematic => {
            self.physics_objects.multibody_joint_set
                .insert_kinematic(body_handle_1, body_handle_2, joint, true)
        }
    }
}
```

### disable_collision 控制

所有关节类型都支持 `disable_collision` 参数，映射为 Rapier 的 `.contacts_enabled(!disable_collision)`。当设为 `true` 时，关节连接的两个刚体之间不会产生碰撞。默认值在 `RapierJointBase` 中为 `true`。

### 销毁 (destroy_joint)

```rust
pub fn destroy_joint(&mut self, world_handle, joint_handle) {
    self.joint_wake_up_connected_rigidbodies(world_handle, joint_handle);
    physics_world.remove_joint(joint_handle);
}
```

销毁关节时会唤醒连接的刚体。

### recreate_joint -- 切换关节类型

当需要在 `Impulse` / `MultiBody` / `MultiBodyKinematic` 之间切换时，使用 `recreate_joint()`。它保留关节的 GenericJoint 数据，在移除后重新插入到新的容器中。

## 相关文档

- [00-architecture.md](00-architecture.md) -- 整体架构概览
- [01-body-bridge.md](01-body-bridge.md) -- 刚体桥接层
