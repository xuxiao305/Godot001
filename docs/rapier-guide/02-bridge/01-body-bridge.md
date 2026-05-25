# 01 -- 刚体桥接 (Body Bridge)

本章讲解 Godot 的 `RapierBody`（位于 Godot 数据层）如何将参数映射到 Rapier 的 `RigidBody`（位于 Rapier 数据层）。核心桥接代码位于 `src/rapier_wrapper/body.rs` 的 `PhysicsEngine` impl 块中。

## 整体数据流

```
Godot: body_create(rid, body_type, position, rotation, activation_params)
  |
  v
RapierBody: 存储 mode, can_sleep, ccd_enabled 等状态
  |
  v
PhysicsEngine::body_create()
  |-- match body_type -> RigidBodyBuilder
  |-- 设置 activation thresholds
  |-- 插入 RigidBodySet
  |
  v
Rapier: RigidBody 进入物理世界
```

## body_create 参数映射

`PhysicsEngine::body_create()` 是刚体创建的核心函数。它接收 Godot 传来的参数，构建 Rapier 的 `RigidBody`。

### 函数签名

```rust
pub fn body_create(
    &mut self,
    world_handle: WorldHandle,          // 物理世界句柄
    pos: Vector,                        // Rapier 向量 (已转换)
    rot: Rotation,                      // Rapier 旋转 (已转换)
    body_type: BodyType,                // 刚体类型枚举
    activation_angular_threshold: Real, // 角速度休眠阈值
    activation_linear_threshold: Real,  // 线速度休眠阈值
    activation_time_until_sleep: Real,  // 静止多长时间后休眠
) -> RigidBodyHandle
```

### 参数映射表

| Godot 参数 | 桥梁层参数 | Rapier 目标 | 说明 |
|---|---|---|---|
| `BodyMode::RIGID` / `RIGID_LINEAR` | `BodyType::Dynamic` | `RigidBodyBuilder::dynamic()` | 受力/碰撞影响，可被脚本移动 |
| `BodyMode::KINEMATIC` | `BodyType::Kinematic` | `RigidBodyBuilder::kinematic_position_based()` | 仅脚本移动，不受力影响 |
| `BodyMode::STATIC` | `BodyType::Static` | `RigidBodyBuilder::fixed()` | 固定不动 |
| `position` (Godot Vector2) | `pos` (rapier Vector) | `RigidBody.set_position()` | 已通过 `vector_to_rapier()` 转换 |
| `rotation` (Godot float) | `rot` (rapier Rotation) | `RigidBody.set_position()` | 已通过 `angle_to_rapier()` 转换 |
| activation angular threshold | `activation_angular_threshold` | `SolverShape.angular_threshold` | 角速度低于此值开始进入休眠倒计时 |
| activation linear threshold | `activation_linear_threshold` | `SolverShape.normalized_linear_threshold` | 线速度低于此值开始进入休眠倒计时 |
| activation time until sleep | `activation_time_until_sleep` | `SolverShape.time_until_sleep` | 静止持续时间超过此值则休眠 |

### BodyType 枚举映射

```rust
pub enum BodyType {
    Dynamic,   // -> RigidBodyType::Dynamic
    Kinematic, // -> RigidBodyType::KinematicPositionBased
    Static,    // -> RigidBodyType::Fixed
}
```

**设计选择说明**：Kinematic 映射为 `kinematic_position_based()` 而非 `kinematic_velocity_based()`。这意味着每次设置 kinematic body 的位置时，Rapier 不会自动计算速度（velocity-based 会从位置差分算速度）。这样与 Godot 的行为一致 -- Godot 的 `PHYSICS_SERVER2D_BODY_MODE_KINEMATIC` 是由脚本控制位置，而非由速度驱动。

### body_create 关键代码

```rust
let mut rigid_body: RigidBody;
match body_type {
    BodyType::Dynamic => {
        rigid_body = RigidBodyBuilder::dynamic().build();
    }
    BodyType::Kinematic => {
        rigid_body = RigidBodyBuilder::kinematic_position_based().build();
    }
    BodyType::Static => {
        rigid_body = RigidBodyBuilder::fixed().build();
    }
}
let activation = rigid_body.activation_mut();
activation.angular_threshold = activation_angular_threshold;
activation.normalized_linear_threshold = activation_linear_threshold;
activation.time_until_sleep = activation_time_until_sleep;
set_rigid_body_properties_internal(&mut rigid_body, pos, rot, true, true);
physics_world.physics_objects.rigid_body_set.insert(rigid_body)
```

## body_change_mode -- 运行时切换类型

Godot 允许在运行时通过 `body_set_mode()` 切换刚体类型。桥接层通过 `body_change_mode()` 调用 Rapier 的 `set_body_type()`：

```rust
match body_type {
    BodyType::Dynamic => body.set_body_type(RigidBodyType::Dynamic, wakeup),
    BodyType::Kinematic => body.set_body_type(RigidBodyType::KinematicPositionBased, wakeup),
    BodyType::Static => body.set_body_type(RigidBodyType::Fixed, wakeup),
}
```

当切换到 Static 时，还会主动 `force_sleep()` 并清理所有活动列表注册。

## 位置/变换设置 -- freeze 的实现

`set_rigid_body_properties_internal()` 是设置刚体位置的核心函数。它的关键判断逻辑实现了 "freeze" 行为：

```rust
fn set_rigid_body_properties_internal(
    rigid_body: &mut RigidBody,
    pos: Vector,
    rot: Rotation,
    teleport: bool,
    wake_up: bool,
) {
    if rigid_body.is_dynamic() || rigid_body.is_fixed() || teleport {
        rigid_body.set_position(Pose::from_parts(pos, rot), wake_up);
    } else {
        rigid_body.set_next_kinematic_position(Pose::from_parts(pos, rot));
    }
}
```

**关键区别**：

- `set_position()` -- 立即生效。对 Dynamic body 使用，会触发 wake_up；对 Static body 也使用此方法。
- `set_next_kinematic_position()` -- 在下一个 step 开始时生效。仅对 Kinematic body（通过 `kinematic_position_based()` 创建的）使用。此时 `is_dynamic()` 返回 false，`is_fixed()` 返回 false。

**为什么 Kinematic 使用 `set_next_kinematic_position`？** 因为 `kinematic_position_based()` 模式的设计就是让用户设置 "希望到达的位置"，然后在 step 内部通过速度计算到达该位置。这与 Godot freeze 的语义一致 -- freeze 后物体保持当前位置不动，但不参与物理计算。不过在当前实现中，freeze 并未直接映射到 Rapier 的 freeze 功能 -- Godot 的 freeze 是通过将 body 设为 Static 模式实现的（见 `body_change_mode` -> `BodyMode::STATIC`）。

## body_set_transform 与 teleport 参数

当用户调用 `body_set_state(TRANSFORM, ...)` 时，参数中包含一个 `teleport` 标志。如果 `teleport = true`，即使 body 是 Kinematic，也会使用 `set_position()` 而非 `set_next_kinematic_position()`，确保位置立即生效。这用于处理"传送"场景（如角色瞬移），避免 kinematic body 产生巨大的中间速度。

## 质量属性设置

`body_set_mass_properties()` 处理质量和惯性：

| Godot 参数 | Rapier 目标 | 说明 |
|---|---|---|
| `mass` | `MassProperties` | 设置质量；2D 下若 inertia=0 则自动 `lock_rotations(true)` |
| `inertia` | `MassProperties` | 转动惯量，通过 `angle_to_rapier()` 转换 |
| `center_of_mass` | `MassProperties.local_com` | 质心偏移，通过 `vector_to_rapier()` 转换 |
| `wake_up` | `set_additional_mass_properties(wake_up)` | 是否在设置质量属性后唤醒刚体 |
| `force_update` | `recompute_mass_properties_from_colliders()` | 强制从碰撞体重新计算质量（用于施加 Instant 力后的重算） |

特殊处理：在设置质量前，会将所有 collider 的 density 设为 0，防止 collider 的密度影响手动设置的质量。

## 休眠/唤醒管理

### can_sleep 控制

`body_set_can_sleep()` 是一个关键函数。它通过将激活阈值设为负值来禁用休眠：

```rust
if !can_sleep {
    activation.angular_threshold = -1.0;
    activation.normalized_linear_threshold = -1.0;
} else {
    activation.angular_threshold = activation_angular_threshold;
    activation.normalized_linear_threshold = activation_linear_threshold;
    activation.time_until_sleep = activation_time_until_sleep;
}
```

阈值设为 -1.0 意味着速度永远不会低于阈值，因此 body 永远不会休眠。这是标准的 Rapier 做法 -- Rapier 文档推荐的禁用休眠方式。

### wake_up_connected_rigidbodies 链式唤醒

几乎所有修改 body 状态的操作（设置速度、施加力、改变模式等）都会调用 `body_wake_up_connected_rigidbodies()`。这个函数遍历与当前刚体通过 impulse joints 连接的所有刚体，将它们全部唤醒：

```rust
fn body_wake_up_connected_rigidbodies(&mut self, world_handle, body_handle) {
    for (rb1, rb2, ..) in physics_world.physics_objects
        .impulse_joint_set.attached_joints(body_handle) {
        rb1.wake_up(true);
        rb2.wake_up(true);
    }
}
```

这确保了当一个刚体被外力影响时，通过关节连接的其他刚体也会被唤醒参与模拟。

## 力与冲量

所有力/冲量函数都通过 `wake_up = true` 参数调用 Rapier API，确保施加力后刚体被唤醒。注意 `add_force_at_point` 和 `apply_impulse_at_point` 使用的是相对于质心 (center of mass) 的位置计算。

## 材料更新 (Material)

`body_update_material()` 更新碰撞体上的物理材质属性：

| Godot 属性 | Rapier 目标 | 说明 |
|---|---|---|
| `friction` | `Collider.set_friction()` | 摩擦系数 |
| `restitution` (bounce) | `Collider.set_restitution()` | 弹性系数 |
| `collision_layer` | `InteractionGroups.memberships` | 碰撞层 |
| `collision_mask` | `InteractionGroups.filter` | 碰撞掩码 |
| `contact_skin` | `Collider.set_contact_skin()` | 接触面厚度 (Rapier 独有的"幽灵碰撞"保护) |
| `dominance` | `RigidBody.set_dominance_group()` | 支配组 (用于解决刚体堆叠冲突) |
| `soft_ccd` | `RigidBody.set_soft_ccd_prediction()` | 软性 CCD 预测距离 |

该项更新也会同步更新流体耦合边界的 `interaction_groups`。

## 与 Godot 数据层的交互

Godot 数据层的 `RapierBody` 类维护了额外的状态缓存（如 `linear_velocity`, `constant_force`, `center_of_mass` 等），当刚体尚未在 Rapier 中创建（`!is_valid()`）时，这些值被缓存在状态中，在刚体进入空间时批量应用（通过 `set_space_after()` 方法）。

```rust
// set_space_after() 中的批量应用逻辑:
if self.state.linear_velocity != Vector::default() {
    self.set_linear_velocity(self.state.linear_velocity, physics_engine);
}
if self.state.constant_force != Vector::default() {
    self.set_constant_force(self.state.constant_force, physics_engine);
}
// ... 等等
```

这种延迟应用模式允许 Godot 侧在刚体进入物理空间之前就设置各种属性，简化了初始化顺序。

## 相关文档

- [00-architecture.md](00-architecture.md) -- 整体架构概览
- [02-joint-bridge.md](02-joint-bridge.md) -- 关节桥接层
- [04-shape-bridge.md](04-shape-bridge.md) -- 形状桥接层
