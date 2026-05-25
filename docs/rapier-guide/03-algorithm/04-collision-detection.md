# 04 -- 碰撞检测

> **前置阅读：** [00-rapier-architecture.md](./00-rapier-architecture.md)
> **目标：** 理解 Rapier 如何判断两个物体是否碰撞，以及碰撞信息的含义。

---

## 1. 概述

上一章讲到，`PhysicsPipeline::step()` 执行流程的第二阶段是 `detect_collisions()`。这个阶段是整个物理引擎的信息来源 -- 它回答一个问题：**哪些物体碰到了哪些物体？**

粗暴的解法是 O(n^2) 遍历所有物体对。1000 个物体需要检查约 50 万对，这对于实时游戏完全不可行。

Rapier 采用工业标准的**两阶段检测**策略：

```
所有碰撞体 (1000 个)
       |
       v
[Broad Phase]  ---> 候选对 (~50 对)
       |
       v
[Narrow Phase] ---> 精确接触点 (~10 对真正碰撞)
       |
       v
[Contact Points] ---> 约束求解器
```

源文件：`src/pipeline/collision_pipeline.rs` 的 `detect_collisions()` 方法调度全过程。

---

## 2. Broad Phase -- 粗检测

### 2.1 问题

如何从 1000 个物体中快速排除 950 对不可能碰撞的组合？

### 2.2 核心概念：AABB

**AABB**（Axis-Aligned Bounding Box，轴对齐包围盒）是用一个与坐标轴平行的最小矩形框包裹住整个碰撞体。

```
    +----------+  <-- AABB 包围盒
    |   /  \   |
    |  /    \  |  <-- 实际形状（多边形）
    |  \    /  |
    |   \  /   |
    +----------+
```

AABB 的好处：判断两个 AABB 是否重叠只需要 4 次比较（比较 min/max 的 x, y 坐标），极其廉价。如果两个物体的 AABB 都不重叠，它们的实际形状必然不碰撞。

### 2.3 BVH 树加速

直接比较所有 AABB 对仍然是 O(n^2)。Rapier 使用 **BVH**（Bounding Volume Hierarchy，包围体层次结构）树来加速。

可以类比为一个**停车场分区系统**：

- 你把停车场分成 A 区和 B 区
- 如果 A 区的所有车和 B 区的所有车之间距离都很远，那就跳过 A-B 区之间所有车对
- 只在可能重叠的分区内做细粒度检查

BVH 树是一个二叉树，叶子节点存单个碰撞体的 AABB，内部节点存子节点 AABB 的并集。遍历时：如果两个内部节点的 AABB 不重叠，整棵子树都被跳过。

Rapier 实现：`BroadPhaseBvh`（`src/geometry/broad_phase_bvh.rs`），内部使用 `parry::partitioning::Bvh`。

### 2.4 更新流程

每帧的 `broad_phase.update()` 做三件事：

1. **插入/更新**：将移动或新增的碰撞体的新 AABB 更新到 BVH 树中
2. **增量优化**：使用 `BvhOptimizationStrategy::SubtreeOptimizer` 定期重建部分子树，防止树质量退化
3. **遍历找对**：遍历 BVH 树，输出 AABB 重叠的碰撞体对

输出是一组 `BroadPhasePairEvent`（AddPair / RemovePair），告诉 Narrow Phase 哪些对需要精确检测。

### 2.5 prediction_distance

BVH 遍历时使用扩大的 AABB（加上 `prediction_distance`）。这个距离基于物体速度预测下一帧可能的移动范围 -- 想象一个高速子弹，它当前 AABB 和墙壁 AABB 可能还没重叠，但下一帧一定会撞上。prediction_distance 确保 Broad Phase 不会漏掉这类即将发生的碰撞。

---

## 3. Narrow Phase -- 精确检测

### 3.1 问题

Broad Phase 说 "这两个物体的包围盒重叠了"，但它们真的碰到了吗？碰到的具体位置在哪？穿透了多深？

类比：停车场的管理员告诉你 A 区 3 号位和 B 区 7 号位的车保险杠范围有重叠，但你需要**交警拿尺子量两辆车的实际距离和碰撞点**。

### 3.2 GJK 算法直觉

GJK（Gilbert-Johnson-Keerthi）是 Narrow Phase 的核心算法。它的思路非常巧妙：

**不直接判断两个形状是否重叠，而是判断它们的 Minkowski 差是否包含原点。**

Minkowski 差的直观理解：把形状 B 的所有点取反，然后对形状 A 的每个点，加上取反后的 B。如果 A 和 B 重叠，原点一定在 Minkowski 差里面。

GJK 是一个迭代算法：它在 Minkowski 差中逐步构建一个单纯形（2D 中是三角形），每次迭代让单纯形更接近原点。如果单纯形包围了原点，说明 A 和 B 重叠。

```
A 和 B 不重叠：                     A 和 B 重叠：
                                   
   A           B                    A + B 的 Minkowski 差
  +--+       +--+                       /\
  |  |       |  |                      /  \
  +--+       +--+                   origin  \
                                         \  /
                                          \/
                                  Minkowski 差包含原点！
```

### 3.3 EPA 算法

GJK 只回答 "是否重叠"。如果重叠了，还需要知道**穿透深度**和**接触法线**。EPA（Expanding Polytope Algorithm）从 GJK 的结果继续迭代，向外扩展单纯形，找到 Minkowski 差边界上离原点最近的点，从而算出穿透深度和法线方向。

### 3.4 Rapier 中的实现

`NarrowPhase`（`src/geometry/narrow_phase.rs`）管理整个精确检测流程：

- `query_dispatcher`：根据两个碰撞体的形状类型（球-球、盒子-多边形、多边形-多边形等）选择合适的算法，由 `parry::query` 提供
- `compute_contacts()`：对 Broad Phase 输出的每对碰撞体运行 GJK/EPA，生成接触点
- `compute_intersections()`：对传感器（sensor）碰撞体做重叠检测（不需要接触点，只需要知道是否重叠）

Narrow Phase 维护两张图：
- **contact_graph**（`InteractionGraph<ColliderHandle, ContactPair>`）：存储真正碰撞的碰撞体对及其接触数据
- **intersection_graph**（`InteractionGraph<ColliderHandle, IntersectionPair>`）：存储传感器碰撞体的重叠状态

---

## 4. Contact Points -- 接触点

### 4.1 接触点包含什么信息

Narrow Phase 计算出每个碰撞对的**接触流形**（Contact Manifold）。一个接触流形包含以下关键数据（`src/geometry/contact_pair.rs` -- `ContactManifoldData`）：

| 字段 | 含义 |
|---|---|
| `normal` | 接触法线方向（从 collider2 指向 collider1），告诉求解器应该往哪个方向推开 |
| `solver_contacts` | 接触点数组，每个点包含位置、穿透深度、摩擦、弹性等 |
| `rigid_body1 / rigid_body2` | 关联的刚体句柄 |

每个接触点（`SolverContactGeneric`）：

| 字段 | 含义 |
|---|---|
| `point` | 世界空间中的接触点坐标 |
| `dist` | 两个原始接触点沿法线的距离。**负数 = 穿透深度** |
| `friction` | 该接触点的有效摩擦系数 |
| `restitution` | 该接触点的有效弹性系数 |
| `tangent_velocity` | 期望的切向相对速度（用于模拟传送带等效果） |
| `warmstart_impulse` | 上一帧求解的法向冲量（用于热启动加速收敛） |

### 4.2 接触点如何被求解器使用

约束求解器拿到这些接触点后：

1. **法向约束**：沿 `normal` 方向推开物体，推力大小取决于 `dist`（穿透越深，推力越大）
2. **摩擦约束**：沿切向施加摩擦力，大小取决于 `friction` 系数
3. **弹性**：如果 `restitution > 0`，碰撞是弹性的，求解器在法向施加额外速度
4. **热启动**：用上一帧的 `warmstart_impulse` 作为初始值，减少迭代次数

### 4.3 接触流形组织

一个碰撞对可能有多个接触流形（例如两个盒子的面-面碰撞可能产生一个 4 点流形）。`ContactPair` 包含 `manifolds: Vec<ContactManifold>`。可以通过 `ContactPair::find_deepest_contact()` 找到穿透最深的接触点。

---

## 5. CCD -- 连续碰撞检测

### 5.1 问题：隧道穿越

普通碰撞检测是"离散的"--每帧检查一次位置。如果物体速度足够快，一帧内移动的距离超过障碍物厚度，它可能直接穿过：

```
Frame N:      Frame N+1:
  []              |
  []  |           |  []  <-- 子弹穿墙而过！
  []  |           |  []
      |           |
   墙壁            墙壁
```

这就是 **tunneling**（隧道穿越）问题。

### 5.2 CCD 的解决方案

CCD（Continuous Collision Detection，连续碰撞检测）不再只检查两个离散位置，而是**沿着物体的运动轨迹做形状投射**（shape cast）：

```
Frame N:
  []---
  []  --->  TOI (Time of Impact)
  []---     运动被钳制到碰撞点
      |
   墙壁
```

源文件：`src/dynamics/ccd/ccd_solver.rs` -- `CCDSolver`。

工作流程：

1. **检测高速物体**：找出运动速度超过阈值的刚体
2. **预测碰撞时间（TOI）**：对每个高速物体的运动轨迹做 shape cast，找到首次碰撞的时间点
3. **钳制运动**：将物体运动截断到碰撞点之前，防止穿透
4. **下一帧正常处理**：被钳制的物体在下一帧由普通碰撞检测接管，作为已接触的物体处理

### 5.3 使用建议

通过 `RigidBodyBuilder::ccd_enabled(true)` 启用。只对**真正需要**的物体开启：

- 高速子弹/投射物
- 小而快的物体（容易穿过薄墙）
- 游戏性关键物体（绝对不能穿墙的）

CCD 比普通碰撞检测更昂贵，因为 shape cast 本质上是在做多次 Narrow Phase 检测。

---

## 6. Collision Filtering -- 碰撞过滤

### 6.1 问题

不是所有物体都应该互相碰撞。玩家发射的子弹不应该伤害玩家自己；敌人之间可能不需要互相碰撞。

### 6.2 Rapier 的位掩码系统

Rapier 使用 `InteractionGroups`（`src/geometry/interaction_groups.rs`）来控制碰撞过滤：

```rust
pub struct InteractionGroups {
    pub memberships: Group,  // 我属于哪些组（最多 32 个）
    pub filter: Group,       // 我愿意和哪些组的物体碰撞
    pub test_mode: InteractionTestMode,  // And 或 Or 模式
}
```

`Group` 是一个 u32 位掩码，每一位代表一个碰撞组。32 个组对应 Godot 的 32 个 collision layer。

### 6.3 判断规则

两个碰撞体 A 和 B 是否可以交互，取决于：

**And 模式**（默认，更严格）：双向必须同时匹配
```
(A.memberships & B.filter) != 0  AND  (B.memberships & A.filter) != 0
```

**Or 模式**：单向匹配即可
```
(A.memberships & B.filter) != 0  OR  (B.memberships & A.filter) != 0
```

如果双方 test_mode 不一致，**And 优先**。

### 6.4 实际例子

```rust
// 玩家：属于 group 1，与 group 2（敌人）碰撞
let player = InteractionGroups::new(Group::GROUP_1, Group::GROUP_2, Or);

// 敌人：属于 group 2，与 group 1（玩家）碰撞
let enemy = InteractionGroups::new(Group::GROUP_2, Group::GROUP_1, Or);

// 玩家子弹：属于 group 1，与 group 2 碰撞
let player_bullet = InteractionGroups::new(Group::GROUP_1, Group::GROUP_2, Or);
// 敌人子弹：属于 group 2，与 group 1 碰撞
let enemy_bullet = InteractionGroups::new(Group::GROUP_2, Group::GROUP_1, Or);
```

这样配置后：
- 玩家子弹击中敌人（玩家子弹 filter 包含 GROUP_2，敌人 memberships 是 GROUP_2）
- 玩家子弹不会击中玩家（玩家子弹 filter 不包含 GROUP_1，玩家 memberships 是 GROUP_1）
- 敌人之间不碰撞（敌人 filter 不包含 GROUP_2）

### 6.5 Godot 侧的映射

godot-rapier-physics 将 Godot 的 `collision_layer` 和 `collision_mask` 直接映射（`src/rapier_wrapper/collider.rs:283-287`）：

- `collision_layer` -> `InteractionGroups.memberships`（我属于哪些层）
- `collision_mask` -> `InteractionGroups.filter`（我与哪些层碰撞）
- 固定使用 `InteractionTestMode::Or`（与 Godot 原生的单向匹配语义一致）

---

## 7. 一帧碰撞检测总览

```
detect_collisions()
  |
  |-- broad_phase.update()          // BVH 树：更新 AABB，输出候选对
  |       |
  |       |-- 插入/更新碰撞体 AABB 到 BVH 树
  |       |-- 增量优化树结构
  |       |-- 遍历找 AABB 重叠对 -> BroadPhasePairEvent
  |
  |-- narrow_phase.register_pairs() // 注册新的碰撞对到 interaction graph
  |
  |-- narrow_phase.compute_contacts() // GJK/EPA 精确检测
  |       |
  |       |-- 碰撞过滤检查（InteractionGroups）
  |       |-- PhysicsHooks::filter_contact_pair() 用户回调
  |       |-- 形状-形状精确检测（GJK/EPA）
  |       |-- 生成接触点 -> ContactPair
  |       |-- 触发 CollisionEvent::Started/Stopped
  |
  |-- narrow_phase.compute_intersections() // 传感器重叠检测
```

---

## 8. 延伸阅读

- 约束求解器如何使用接触点：见 [02-constraint-solver.md](./02-constraint-solver.md)
- 刚体动力学基础：见 [01-rigid-body-dynamics.md](./01-rigid-body-dynamics.md)
- Godot 碰撞层配置实践：见 `project.godot` 中的 `layer_names/2d_physics`
- Rapier Narrow Phase 源码：`src/geometry/narrow_phase.rs`
- Rapier CCD 源码：`src/dynamics/ccd/ccd_solver.rs`
- Rapier 碰撞过滤源码：`src/geometry/interaction_groups.rs`
- godot-rapier-physics 碰撞层映射：`src/rapier_wrapper/collider.rs`
