# Rapier 2D Physics 开发指南 — 设计规格

## 目标

系统性学习 godot-rapier-physics 和 rapier-master 源码，编写一份教学导向的开发使用指南，包含具有目录结构的多份独立文档。

## 受众与定位

三份文档，三种受众，渐进式深入：

| 文档 | 目标读者 | 教到什么程度 |
|------|----------|-------------|
| 用户手册 | Godot 使用者，可不懂物理 | "这个属性调大会怎样，什么时候用它" |
| 桥接文档 | 想了解胶水层的开发者 | "Godot 的 damping 参数怎么换算成 Rapier 的 damping ratio" |
| 算法文档 | 想理解物理引擎原理的开发者 | "为什么 velocity solver 要迭代多次？收敛是什么意思？" |

## 写作原则（适用于全部三份文档）

### 渐进式展开

每章先讲"这个东西解决什么问题" → 用生活类比建立直觉 → 落到 Rapier 怎么实现的。

### 大白话优先

避免"雅可比矩阵"、"Gauss-Seidel 迭代"等术语直接砸脸。先用人话解释一遍概念，再引入术语。术语出现后可以用括号标注英文原名。

### 类比与举例

用日常经验解释物理概念：
- Impulse solver → "就像打台球，球杆击球瞬间给一个很大的力，之后球自由滚动"
- SPH 流体 → "把液体想象成很多粒子，每个粒子用磁铁互相吸着，吸太近就弹开"
- Constraint → "像用一根看不见的绳子把两个物体连起来，绳子长度可设，超过就拉回来"

### 代码引用克制

只贴关键参数映射处的简短代码片段（3-5 行），不贴完整 Rust 实现。桥接文档中可适当增加代码片段但控制在 10 行以内。

### 中英混合规则

- 描述、说明、算法解释 → 中文
- API 名称、属性名、枚举值 → 保持英文原文
- 方法签名 → `body_create(world_handle, pos, rot, body_type, ...)` 取英文
- 关键术语首次出现标注英文：约束求解器（Constraint Solver）

### 可扩展

每章结尾留"延伸阅读"占位，用户后续可自行补充更深内容。

## 目录结构

```
docs/rapier-guide/
├── README.md                          # 总索引：三份文档的定位与导航
├── 01-user-manual/                    # 用户手册
│   ├── 00-overview.md                 # 概述：RapierPhysicsServer2D 是什么、如何启用
│   ├── 01-rigid-body.md               # 刚体：body_type, mass, damping, freeze, CCD, signals
│   ├── 02-joints.md                   # 约束：PinJoint, DampedSpring, Groove 的属性/用法
│   ├── 03-fluids.md                   # 流体：Fluid2D 粒子系统配置与效果
│   ├── 04-collision-shapes.md         # 碰撞形状（简略）：Circle, Rectangle, Capsule, Segment 等
│   └── 05-space-queries.md            # 空间查询（简略）：intersect_point/ray/shape
├── 02-bridge/                         # 中层桥接文档
│   ├── 00-architecture.md             # 架构总览：Singleton → PhysicsEngine → PhysicsWorld 层级
│   ├── 01-body-bridge.md              # 刚体映射：Godot body params → Rapier RigidBody builder
│   ├── 02-joint-bridge.md             # 约束映射：每种 joint 的 Godot→Rapier 参数转换表
│   ├── 03-fluid-bridge.md             # 流固耦合：Salva pipeline 与 Rapier world 的集成
│   └── 04-shape-bridge.md             # 形状映射（简略）
└── 03-algorithm/                      # 底层算法文档
    ├── 00-rapier-architecture.md      # Rapier 引擎架构：dynamics/geometry/pipeline 三层
    ├── 01-rigid-body-dynamics.md      # 刚体动力学：质量属性、速度积分、休眠管理
    ├── 02-constraint-solver.md        # 约束求解器：ImpulseJoint, MultibodyJoint, 求解迭代
    ├── 03-fluid-sph.md                # SPH 流体：粒子动力学、密度/压力/粘性/表面张力
    └── 04-collision-detection.md      # 碰撞检测（简略）：broad phase / narrow phase / CCD
```

## 各文档内容大纲

### 文档 1：用户手册（01-user-manual）

#### 00-overview.md — 概述
- Rapier 是什么（开源 Rust 物理引擎，Godot 通过 GDExtension 调用）
- 如何安装/启用 RapierPhysicsServer2D
- 与 godot-box2d 的关系（都是 PhysicsServer2D 后端，可切换）
- 本项目使用 Rapier 的原因（流体支持、更现代的约束系统）

#### 01-rigid-body.md — 刚体
- `body_type`：Static / Kinematic / Dynamic 三者的区别和生活类比（地面 vs 电梯 vs 球）
- `mass`：质量不是重量，是"改变速度的难易程度"
- `linear_damp` / `angular_damp`：阻尼 = "空气阻力"，像在水里挥手
- `freeze` vs `freeze_mode`：冻结的区别（sleep 是自动的，freeze 是手动的）
- `can_sleep` / `sleeping`：休眠机制 — 静止不动的物体会被引擎跳过计算
- CCD（Continuous Collision Detection）：防高速穿透，子弹必须开
- gravity_scale：个体重力缩放
- Signals：body_entered, body_exited, body_shape_entered 等

#### 02-joints.md — 约束
- PinJoint（= RevoluteJoint）：像图钉把一个点钉住，可设角度限位和马达
  - `angular_limit_lower/upper`：转动的范围
  - `motor_enabled` + `motor_target_velocity`：让它自动转
  - `motor_position_enabled` + `motor_target_position`：转到指定角度
- DampedSpringJoint：像弹簧连接两点
  - `stiffness`：弹簧硬度，越大拉得越紧
  - `damping`：弹簧抖动衰减，防止弹个不停
  - `length`：弹簧自然长度（超过就开始拉/压）
- GrooveJoint：像槽轨，一个物体沿固定轴滑动
  - `axis`：滑动方向
  - `limits`：滑动范围

#### 03-fluids.md — 流体
- Fluid2D 是什么：粒子系统模拟液体/气体
- 基本配置：`density`（密度），粒子生成
- 流体效果一览：
  - Elasticity：弹性，粒子碰撞的软硬
  - Surface Tension（Akinci / He / WCSPH）：表面张力，"水珠聚拢"的力
  - Viscosity（Artificial / DFSPH / XSPH）：粘稠度，"蜂蜜 vs 水"
- 性能注意事项：粒子数上限、与刚体的交互

#### 04-collision-shapes.md — 碰撞形状（简略）
- CircleShape, RectangleShape, CapsuleShape, SegmentShape
- ConvexPolygonShape, ConcavePolygonShape
- WorldBoundaryShape（无限大平面/半空间）
- SeparationRayShape（射线，用于检测）
- 选型建议：性能排序、凸 vs 凹

#### 05-space-queries.md — 空间查询（简略）
- intersect_point：点击检测
- intersect_ray：射线检测（子弹、视线）
- intersect_shape：形状重叠检测
- 碰撞层与掩码（collision_layer / collision_mask）

### 文档 2：桥接文档（02-bridge）

#### 00-architecture.md — 架构总览
- 双层架构图：Godot Data Layer ↔ Rapier Data Layer
- Singleton 管理：rid → object 映射
- PhysicsEngine → PhysicsWorld → PhysicsObjects 的层级关系
- 数据流：Godot 调用 → servers 层 → rapier_wrapper → rapier API

#### 01-body-bridge.md — 刚体映射
- body_create 参数映射表：Godot body_type/position/rotation → Rapier RigidBodyBuilder
- BodyType 枚举：Dynamic / Kinematic / Static → Rapier RigidBodyType
- 激活阈值映射：activation_angular_threshold / activation_linear_threshold
- sleep 状态管理：休眠唤醒链（wake_up_connected_rigidbodies）
- freeze 的实现：set_next_kinematic_position 函数的特殊处理

#### 02-joint-bridge.md — 约束映射
- 每个 Joint 类型列出 Godot 参数 → Rapier builder 参数对照表
- Revolute/Pin：local_anchor → anchor, motor_model → AccelerationBased vs ForceBased
- DampedSpring：Godot stiffness/damping → Rapier AccelerationBased 参数的换算公式
- Groove：axis/limits → GenericJoint + prismatic 轴
- Joint 生命周期：create → change_params → destroy 的完整链路

#### 03-fluid-bridge.md — 流固耦合
- Salva（Rapier 的流体伴侣库）与 Rapier 的集成方式
- FluidsPipeline 结构：liquid_world + coupling
- FluidEffect 类型枚举：每种效果的 Salva solver 映射
- 粒子数组转换：Godot Vector[] → salva::math::Vector[]
- 粒子半径、密度、interaction_groups 的传递链

#### 04-shape-bridge.md — 形状映射（简略）
- Godot shape → Rapier SharedShape 的转换
- 凸包回退：create polygon using convex hull as fallback
- Shape handle 管理：PhysicsEngine.shapes Arena

### 文档 3：算法文档（03-algorithm）

#### 00-rapier-architecture.md — Rapier 引擎架构
- 三层结构概述：
  - dynamics：刚体、约束、求解器
  - geometry：碰撞检测、broad/narrow phase
  - pipeline：物理步进、积分、事件
- PhysicsPipeline::step() 的执行流程概览
- 与 Godot 物理帧的同步机制

#### 01-rigid-body-dynamics.md — 刚体动力学
- 质量与惯性张量：mass 不是重量，"改变运动状态的难度"
- Velocity：linear_velocity / angular_velocity 的含义
- 速度积分：position = position + velocity * dt（半隐式 Euler）
- Force vs Impulse：持续力（重力）vs 瞬间冲量（碰撞）
- Damping 的数学：v = v * (1 - damping * dt)，指数衰减
- Sleeping 机制：island 检测、激活阈值、wake-up 传播

#### 02-constraint-solver.md — 约束求解器
- 约束是什么：数学方程描述"两个物体的某种相对运动是不允许的"
- Solver 迭代：每次迭代逼近一点，多次迭代 = 更精确的约束满足
- ImpulseJoint vs MultibodyJoint 的算法区别
- Revolute/Pin joint 的约束方程（只允许旋转，禁止平移）
- DampedSpring 的约束方程（距离维持）
- Motor：在约束上叠加目标速度/位置
- Softness 参数：natural_frequency 和 damping_ratio 的含义

#### 03-fluid-sph.md — SPH 流体
- SPH（Smoothed Particle Hydrodynamics）核心思想：把连续流体离散成粒子
- 密度计算：每个粒子的密度 = 周围粒子贡献的加权和
- 压力：密度高于 rest_density → 产生排斥力
- 粘性：速度差异 → 粒子互相拉扯
- 表面张力：粒子表面区域 → 额外内聚力
- 三种 Viscosity 方法对比：Artificial（简单快）vs DFSPH（稳）vs XSPH（平滑）
- 三种 Surface Tension 方法对比：Akinci vs He vs WCSPH
- Elasticity：粒子间的弹簧力

#### 04-collision-detection.md — 碰撞检测（简略）
- Broad Phase：用 AABB（轴对齐包围盒）快速剔除不可能碰撞的物体对
- Narrow Phase：对可能碰撞的物体对做精确形状检测（GJK/EPA 算法简述）
- Contact Points：碰撞点、法线、穿透深度
- CCD：Continuous Collision Detection 处理高速物体穿透

## 实现策略

### 源码研究顺序

1. 先读 godot-rapier-physics 的 `src/nodes/` — 了解暴露给 Godot 的 API 形态
2. 读 `src/servers/` — 了解 Godot PhysicsServer2D 接口实现
3. 读 `src/rapier_wrapper/` — 了解 wrapper 层的参数转换
4. 读 rapier-master `crates/rapier2d/` — 了解 Rapier 引擎本体
5. 读 rapier-master `src/dynamics/`、`src/geometry/`、`src/pipeline/` — 核心算法

### 写作顺序

每读完一个层级，同步写出三份文档的对应章节。例如读完 body 相关代码后：
1. 先写用户手册 `01-rigid-body.md`
2. 再写桥接文档 `01-body-bridge.md`
3. 最后写算法文档 `01-rigid-body-dynamics.md`

### 文档间交叉引用

- 用户手册中引用桥接文档："想知道底层怎么换算的？见 [桥接文档 §body](./../02-bridge/01-body-bridge.md)"
- 桥接文档引用算法文档："Solver 迭代次数如何影响精度？见 [约束求解器](./../03-algorithm/02-constraint-solver.md)"

## 不在本次范围的

- 3D 物理全部模块
- 性能基准测试数据（后续可加）
- 与 godot-box2d 的对比评测
- Godot 编辑器的可视化配置教程（只写 API 层面的属性说明）

## 交付物

- `docs/rapier-guide/README.md`
- `docs/rapier-guide/01-user-manual/` 6 个 .md 文件
- `docs/rapier-guide/02-bridge/` 5 个 .md 文件
- `docs/rapier-guide/03-algorithm/` 5 个 .md 文件
- 共 17 个文件
