# Rapier 架构全景

> **前置需求**：无。本章是算法篇的入口，所有概念将在此首次介绍。
> **阅读目标**：理解 Rapier 三层架构的分工，以及一帧物理模拟的完整执行流程。

---

## 1. 问题：物理引擎到底在做什么

游戏中的物理对象（角色、箱子、子弹）需要"自主运动"——受重力下落、碰到墙壁反弹、被绳子牵引。物理引擎的任务是：**给定所有对象的当前位置和速度，计算它们在下一个瞬间（通常 1/60 秒后）的新位置和新速度**。

一个粗暴的方法：把每对物体都拿来检测是否碰撞。如果有 1000 个物体，就需要检查约 50 万对——这不可行。

更重要的是，物理引擎不只是"检测碰撞"，它还需要**解决碰撞**——两个物体撞到一起后，要算出把它们推开需要多大的力，以及这个力如何改变它们的运动。

Rapier 将这些问题拆分成三个独立模块，各司其职。

---

## 2. 三层架构

```
+--------------------------------------------------+
|  pipeline (物理管线)                               |
|  PhysicsPipeline::step()                          |
|  - 协调 dynamics 和 geometry 的调用顺序            |
|  - 管理子步（substep）和 CCD                       |
|  - 触发事件（碰撞开始/结束）                        |
+--------------------------------------------------+
        |                            |
        v                            v
+--------------------+    +------------------------+
|  dynamics (动力学)  |    |  geometry (几何)        |
|  - 刚体位置/速度    |    |  - 碰撞体形状管理        |
|  - 质量/惯性        |    |  - Broad Phase (快速剔除)|
|  - 力/冲量          |    |  - Narrow Phase (精确计算)|
|  - 约束求解器       |    |  - 接触点数据            |
|  - 关节 (Joint)    |    |  - 碰撞过滤             |
|  - 睡眠管理         |    |  - 交互图 (Interaction  |
+--------------------+    |    Graph)               |
                           +------------------------+
```

### 2.1 dynamics（动力学）模块

负责"物体为什么会动"。核心概念：

- **RigidBody**（刚体）：不可形变的物理物体，有位置、速度、质量等属性
- **RigidBodySet**：所有刚体的容器
- **ImpulseJointSet** / **MultibodyJointSet**：关节集合，约束两个物体之间的相对运动
- **IslandManager**：将有关联的物体分组（岛屿），独立求解
- **solver/**：约束求解器，把碰撞和关节转化为推力和拉力

源文件位置：`src/dynamics/`

### 2.2 geometry（几何）模块

负责"物体在哪里碰到了谁"。核心概念：

- **Collider**（碰撞体）：附着在刚体上的几何形状（球、盒子、多边形等）
- **BroadPhaseBvh**：用 AABB 树快速排除不可能碰撞的物体对
- **NarrowPhase**：对 Broad Phase 筛选出的候选对做精确形状检测（GJK/EPA 算法）
- **InteractionGraph**：跟踪哪些碰撞体对之间目前在接触
- **InteractionGroups**：基于位掩码的碰撞过滤系统

源文件位置：`src/geometry/`

### 2.3 pipeline（管线）模块

负责"把 dynamics 和 geometry 串起来，按正确顺序执行"。核心概念：

- **PhysicsPipeline**：物理模拟的总调度器，提供 `step()` 方法
- **PhysicsHooks**：允许用户在碰撞检测中插入自定义逻辑（过滤、修改接触）
- **EventHandler**：碰撞事件（Started/Stopped）的回调接口

源文件位置：`src/pipeline/`

---

## 3. PhysicsPipeline::step() 执行流程

每一帧，调用一次 `PhysicsPipeline::step()`（源文件 `src/pipeline/physics_pipeline.rs`），内部按以下顺序执行：

### 3.1 处理用户修改

```
handle_user_changes_to_rigid_bodies()
handle_user_changes_to_colliders()
```

将用户在帧间对刚体/碰撞体的修改（移动位置、修改质量、禁用/启用）反映到内部状态中。同时处理待唤醒的物体、待连接的关节。

### 3.2 碰撞检测

```
detect_collisions()
  -> broad_phase.update()       // 更新 AABB 树
  -> narrow_phase.compute_contacts()  // 精确接触点计算
  -> narrow_phase.compute_intersections() // 传感器碰撞体交叉检测
```

先做 Broad Phase（快速剔除），再做 Narrow Phase（精确计算接触点和穿透深度）。

### 3.3 构建岛屿并求解约束

```
build_islands_and_solve_velocity_constraints()
  -> islands.update_islands()   // 将有交互的物体分组
  -> IslandSolver::init_and_solve()  // 对每个岛屿独立求解
```

"岛屿"（Island）指被关节或接触连接在一起的一组物体。不同岛屿之间没有互动，可以独立求解（甚至并行）。

约束求解器内部（`src/dynamics/solver/island_solver.rs`）：
1. **初始化**：计算 solver body 数据、初始化接触约束和关节约束
2. **迭代求解**：默认 4 次迭代（`num_solver_iterations`），每次迭代都让约束更精确
3. **写回**：将求解的冲量写回刚体速度和接触点数据

### 3.4 CCD（连续碰撞检测）

源码：`src/dynamics/ccd/ccd_solver.rs` + `src/dynamics/ccd/toi_entry.rs`

#### 3.4.1 激活判断

每帧开始时，对所有 `ccd_enabled = true` 的刚体调用 `is_moving_fast()`（`rigid_body_components.rs`）：

```
max_point_velocity * dt > ccd_thickness / 10
```

- `max_point_velocity` = 线速度 + 角速度 × 质心到最远碰撞点的距离
- `ccd_thickness` = 该刚体所有附着形状的 `ccd_thickness()` 最小值（通常为形状的最小维度）
- 满足条件的刚体标记 `ccd_active = true`，后续只对这些刚体做 CCD

#### 3.4.2 运动钳制（单步路径，`max_ccd_substeps == 1`）

```
run_ccd_motion_clamping()
  ├─ update_ccd_active_flags()          // 标记高速刚体
  ├─ ccd_solver.predict_impacts_at_next_positions()
  └─ ccd_solver.clamp_motions()         // 按 TOI 钳制 next_position
```

**`predict_impacts_at_next_positions()`** 分三个阶段：

1. **初始 TOI 收集**（phase 1）
   - 对每个 CCD-active 刚体，计算从当前位置到 `next_position` 的 swept AABB
   - 通过 BVH Broad Phase（`intersect_aabb_conservative`）找出候选碰撞对
   - 对每个候选对调用 `TOIEntry::try_from_colliders()` → parry 的 `cast_shapes_nonlinear()` 做非线性形状投射
   - 将 TOI 放入 BinaryHeap（最小 TOI 优先出堆）

2. **重扫循环**（phase 2，resweep loop）
   - 每次弹堆取出最早 TOI
   - "冻结"该 TOI 涉及的刚体（记录在 frozen HashMap 中，后续 TOI 计算时将其运动停在 TOI 时刻）
   - 对刚冻结的刚体的碰撞体，重新做 Broad Phase 查询，与邻接碰撞体重算 TOI
   - 新 TOI 推入堆中
   - 目的：冻结一个刚体后，其邻接刚体的 TOI 可能变化（变晚或消失），需迭代收敛

3. **传感器交叉事件**（phase 3）
   - 对传感器碰撞体（sensor），检测交叉状态是否在时间步内出现又消失
   - 如果传感器被"隧道穿越"，补发 `CollisionEvent::Started` + `CollisionEvent::Stopped`

**`clamp_motions()`**：
```rust
let min_toi = (ccd_thickness * 0.15 / max_point_velocity).min(dt);
let new_pos = ccd_vels.integrate(toi.max(min_toi), &pos, &local_com);
rb.pos.next_position = new_pos;
```

将刚体的 `next_position` 钳制到 TOI 时刻的位置。注意安全下限 `min_toi`：保证刚体至少移动 `ccd_thickness * 0.15` 的距离，不会精确停在表面（留给下一帧的接触求解器处理间隙）。

#### 3.4.3 子步分裂路径（`max_ccd_substeps > 1`）

在约束求解前额外执行 `find_first_impact()`，找到最早 TOI：

```
while 剩余时间 > 0:
  toi = find_first_impact()       // 用 force-integrated velocity 预测
  sub_dt = min(toi, 剩余时间)
  integrate_forces_and_velocities(sub_dt)
  solve_velocity_constraints(sub_dt)
  run_ccd_motion_clamping(sub_dt)
  advance_to_final_positions(sub_dt)
  剩余时间 -= sub_dt
```

每次子步的 dt 都根据最早 CCD 碰撞时间动态截断，高碰撞密度场景下比单步路径更精确。

### 3.5 推进位置

```
advance_to_final_positions()
```

将求解器算出的 `next_position` 确认为最终位置，同步更新附着碰撞体的位置。

### 3.6 子步循环

如果启用了多步 CCD（`max_ccd_substeps > 1`），以上步骤 3.2-3.5 会在一个 while 循环中执行多次。每次子步的 dt 根据 CCD 预测的首个碰撞时间（TOI）动态调整。

---

## 4. 与 Godot 的同步

godot-rapier-physics 作为一个 PhysicsServer2D 后端插件工作。Godot 每帧调用一次物理步进：

- Godot 的 `PhysicsServer2D` API（如 `body_set_state`, `area_set_shape`）被转发到 `rapier_wrapper` 层
- `rapier_wrapper` 将这些调用翻译为 Rapier 的 API 调用
- Godot 每帧结束时，从 Rapier 读取所有刚体的最新位置/旋转，同步回 Godot 的 `Transform2D`
- 碰撞事件（body_entered / body_exited）通过 `EventHandler` 从 Rapier 转发到 Godot 的信号系统

关键桥接文件：`src/rapier_wrapper/physics_world.rs`, `src/rapier_wrapper/body.rs`, `src/rapier_wrapper/collider.rs`

---

## 5. 核心数据结构速查

| 数据结构 | 模块 | 用途 |
|---|---|---|
| `RigidBodySet` | dynamics | 所有刚体的容器，支持按 Handle 索引 |
| `RigidBody` | dynamics | 单个刚体：位置、速度、质量、类型、睡眠状态 |
| `ColliderSet` | geometry | 所有碰撞体的容器 |
| `Collider` | geometry | 单个碰撞体：形状、摩擦、弹性、碰撞过滤 |
| `ImpulseJointSet` | dynamics | 所有脉冲关节的集合（Hinge, Slider, Spring 等） |
| `MultibodyJointSet` | dynamics | 多体关节集合（用于机器人关节链） |
| `IslandManager` | dynamics | 管理岛屿分组和活跃状态 |
| `BroadPhaseBvh` | geometry | 基于 BVH 树的 Broad Phase 实现 |
| `NarrowPhase` | geometry | Narrow Phase 碰撞检测和接触图维护 |
| `IntegrationParameters` | dynamics | 模拟参数：步长、迭代次数、长度单位等 |
| `PhysicsPipeline` | pipeline | 物理管线调度器（临时工作内存，不含持久数据） |

---

## 6. 延伸阅读

- 刚体动力学的数学推导：见 [01-rigid-body-dynamics.md](./01-rigid-body-dynamics.md)
- 约束求解器的工作原理：见 [02-constraint-solver.md](./02-constraint-solver.md)
- 碰撞检测的算法细节：见 [04-collision-detection.md](./04-collision-detection.md)
- SPH 流体模拟：见 [03-fluid-sph.md](./03-fluid-sph.md)
