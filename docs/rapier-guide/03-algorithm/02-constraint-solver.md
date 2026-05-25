# 约束求解器（Constraint Solver）

> **前置需求**：建议先阅读 [01-rigid-body-dynamics.md](./01-rigid-body-dynamics.md) 了解速度和力的概念。
> **阅读目标**：理解约束的数学含义、迭代求解的直觉、以及 Rapier 中各种关节类型的工作原理。

---

## 1. 问题：如何描述"两个物体不能穿过对方"

两个物体碰撞后应该分开——这是"不能重叠"的约束。一扇门只能绕合页旋转——这是"只能转不能移"的约束。

物理引擎的核心挑战：**每一帧有数十上百个这样的"不能"规则同时生效，如何高效地找到让所有规则同时满足的解决方案？**

---

## 2. 什么是约束（Constraint）

### 2.1 日常类比

想象一家人吃年夜饭，围坐在一张大圆桌旁。桌子够大，但大家都想有足够的"肘子空间"。解决方案：

- 你先坐下，然后第二个人在你旁边坐下，你们稍微挤一挤
- 第三个人再坐下，前两个人发现自己被挤了，于是调整位置
- 第四个人坐下……一直如此

每个人调整时只考虑自己旁边的两个人，但经过**多轮调整**后，所有人都有大致均匀的空间。

**这就是约束求解器的工作方式——迭代调整，逐步逼近。**

### 2.2 约束的数学直觉

约束本质上是数学等式或不等式，描述了"某些相对运动不被允许"。

比如，"两个物体不能重叠" 意味着：物体 A 的表面和物体 B 的表面之间的距离 >= 0（或允许微小穿透）。

比如，"门只能旋转" 意味着：合页处的相对线速度 = 0（两个锚点锁定），但允许相对角速度。

### 2.3 约束的物理实现：施加冲量

约束求解不是通过"条件判断"来实现的（"如果穿透了，弹出去"——这会不稳定、会震荡）。而是：**计算一组冲量，分别施加到两个物体上，使得约束被满足**。

对于"不重叠"约束：在接触点施加一个法向冲量，把两个物体推开。
对于"门合页"约束：在锚点施加冲量抵消相对移动，但允许旋转。

---

## 3. 迭代求解：越多次越精确

### 3.1 为什么需要迭代

约束是相互耦合的：解决了一个约束，可能会破坏另一个。比如：
- 调整了物体 A 的位置来满足与 B 的约束 → A 与 C 的约束被破坏了
- 再调整 A 来满足与 C 的约束 → B 的约束又被破坏了……

**每迭代一次，整体误差就会减少一些。**经过足够多次迭代后，所有约束都"差不多"满意了。

### 3.2 Rapier 中的迭代参数

在 `IntegrationParameters` 中：

- `num_solver_iterations`（默认 4）：每个物理步的约束求解迭代次数。更多 = 更精确但更慢。
  - 4 次：大多数游戏场景足够
  - 8-12 次：大量堆叠物体、复杂关节链
  - 1-2 次：性能关键场景

- `num_internal_pgs_iterations`（默认 1）：每次迭代内部 PGS（Projected Gauss-Seidel）的细粒度迭代。高级设置，通常不需要改。

- `warmstart_coefficient`（默认 1.0）：使用上一帧的冲量作为本帧初始猜测。设为 1.0 几乎总是最好的选择。

### 3.3 岛屿（Island）对约束求解的意义

如 [01-rigid-body-dynamics.md](./01-rigid-body-dynamics.md) 第 6.3 节所述，`IslandManager` 在每帧将场景分割为相互隔离的"岛屿"。对于约束求解器，岛屿带来的关键收益是：

- **独立求解**：不同岛屿的约束互不影响，可以各自收敛，误差不会跨岛屿传播。
- **并行机会**：每个岛屿的约束求解完全独立，天然适合多线程并行。
- **更快的局部收敛**：把一个岛屿拆得越细，每个岛屿内的约束越少 → 相同迭代次数下收敛更快。反过来，一个关节把两个"本该独立的岛屿"连在一起 → 合并为一个岛屿 → 求解器必须同时处理更多约束。

### 3.4 接触约束中的摩擦与弹性恢复

接触约束（Contact Constraint）是约束求解器最常见的输入——每次碰撞检测产生一个或多个接触点，每个接触点生成两个约束分量：

**法向约束（Normal Constraint）**：防止穿透。沿接触面法线方向施加冲量，将两个物体推开。这是"不重叠"约束的直接实现。

**切向约束 / 摩擦（Friction）**：沿接触面切线方向施加冲量，阻止滑动。摩擦力的大小受库仑摩擦模型约束：`|摩擦力| <= 摩擦系数 * |法向力|`。如果切向速度小，施加静摩擦力（完全阻止滑动）；如果切向速度大，施加动摩擦力（减缓但不能完全阻止）。

- `friction` 参数：控制摩擦系数。0 = 完全光滑（冰块），1 = 标准值，更高 = 非常粗糙（砂纸）。默认值通常为 0.5。

**弹性恢复（Restitution）**：控制碰撞后的反弹程度。实现方式是在法向约束上叠加一个与接近速度成正比的额外冲量。

- `restitution` 参数：0 = 完全非弹性碰撞（粘在一起），1 = 完全弹性碰撞（以相同速度弹开）。默认值通常为 0.0。
- Rapier 中的 `restitution_velocity_threshold`：当接近速度低于此阈值时禁用弹性恢复，避免"静止物体微微颤动"的问题。

接触约束的完整求解逻辑见源码 `src/dynamics/solver/contact_constraint.rs`。

---

## 4. ImpulseJoint vs MultibodyJoint

### 4.1 ImpulseJoint（脉冲关节）

适用于**两个独立刚体之间**的约束。每次求解迭代通过施加冲量来满足约束。

支持的关节类型（均在 `src/dynamics/joint/` 下）：
- **FixedJoint**：完全锁定，两个物体变成一个（相对运动 = 0）
- **RevoluteJoint**（铰链/合页）：只允许绕一个轴旋转
- **PrismaticJoint**（滑动）：只允许沿一个轴平移
- **PinSlotJoint**：铰链 + 滑动 = 沿一个轴旋转和平移
- **RopeJoint**：限制最大距离（绳子）
- **SpringJoint**：弹簧连接——施加与距离成正比的力

使用 `ImpulseJointSet` 管理，通过 `ImpulseJointSet::insert(body1, body2, joint_builder, wake_up)` 创建。

### 4.2 MultibodyJoint（多体关节）

适用于**关节链**——比如机械臂、布娃娃的骨架。与 ImpulseJoint 的区别在于：

- MultibodyJoint 使用**简化的坐标系统**（关节角度、位移）来描述整条链
- 内部使用**正向运动学**（forward kinematics）和**逆向动力学**（inverse dynamics）
- 比多个 ImpulseJoint 串联更稳定、更精确，适合长关节链

使用 `MultibodyJointSet` 管理。

### 4.3 什么时候用哪个

| 场景 | 推荐 |
|---|---|
| 两个零件之间的单个铰链（如门） | ImpulseJoint - RevoluteJoint |
| 弹簧/弹性连接 | ImpulseJoint - SpringJoint |
| 长链条（如绳子、机械臂） | MultibodyJoint |
| 布娃娃骨架 | MultibodyJoint |

---

## 5. RevoluteJoint 的约束直觉

RevoluteJoint（铰链/合页）是最常用的关节类型——门、车轮、钟摆都用它。

它的约束方程表达：
1. **锚点约束**：两个物体在锚点处的相对位置 = 0。不管物体怎么转，锚点必须重合。
2. **轴向约束**：只允许绕一个轴旋转，其他旋转方向全部锁定。

在 2D 中只有一个旋转轴（Z），所以只需要锁定两个平移自由度（X, Y）——这三个约束用 `JointAxesMask::LOCKED_REVOLUTE_AXES` 常量控制。

`RevoluteJointBuilder::new()` → `.local_anchor1(...)` → `.local_anchor2(...)` → `.build()`

---

## 6. SpringJoint 的约束直觉

SpringJoint 不是硬约束——它施加的是与距离成正比的力，就像现实中的弹簧：

```
力 = -刚度 * (当前距离 - 静止长度) - 阻尼 * 当前伸缩速度
```

- **静止长度（rest_length）**：弹簧"想"保持的距离
- **刚度（stiffness）**：弹簧的强度，越大越硬
- **阻尼（damping）**：抑制震荡，越大越快地回到静止状态

在 Rapier 中，SpringJoint 实际是通过 `GenericJoint` 的 Motor 机制实现的（`src/dynamics/joint/spring_joint.rs`）。

---

## 7. Motor：覆盖在约束之上的目标驱动

Motor（电机/马达）是在关节约束上叠加的"目标驱动"——它让关节主动朝着某个目标角度或速度运动。

以 RevoluteJoint 为例，可以附加 Motor：
- `set_motor_velocity(target_vel, factor)`：让关节以 target_vel 的速度旋转（如驱动轮子）
- `set_motor_position(target_pos, stiffness, damping)`：让关节转到指定角度（如机械臂的精确控制）
- `set_motor(target_pos, target_vel, stiffness, damping)`：同时设位置和速度目标

Motor 使用弹簧阻尼模型达到目标：力 = -stiffness * (当前位置 - 目标位置) - damping * (当前速度 - 目标速度)。

可通过 `set_motor_max_force(max_force)` 限制电机的最大出力。

---

## 8. 软度参数：natural_frequency 和 damping_ratio

约束不是"绝对坚硬"的——Rapier 使用 SpringCoefficients 让约束有可调节的"软度"：

### 8.1 直觉理解

- **natural_frequency（自然频率）**：约束的"刚度"。可以想象成弹簧的硬度。
  - 值越高 = 约束越硬 = 违反约束后恢复越快 = 更少的穿透/漂移
  - 接触约束默认值：30 Hz（略软，避免弹跳）
  - 关节约束默认值：1,000,000 Hz（几乎是硬的）

- **damping_ratio（阻尼比）**：约束的"阻尼程度"。
  - 值越高 = 越"黏" = 更少的震荡
  - 关节约束小于 1.0 = 触发不足阻尼（underdamped）会震荡
  - 关节约束大于 1.0 = 过阻尼（overdamped）缓慢回到目标

### 8.2 类比：汽车悬挂

汽车悬挂也是弹簧阻尼系统：
- **natural_frequency 高** = 硬悬挂 = 赛车，路面颠簸直接传到车身
- **natural_frequency 低** = 软悬挂 = 豪华轿车，舒适但过弯侧倾大
- **damping_ratio 高** = 减震器硬 = 颠簸后立刻稳定，但路感硬
- **damping_ratio 低** = 减震器软 = 过个坑还要弹两下

### 8.3 ERP 和 CFM

从 `natural_frequency` 和 `damping_ratio`，Rapier 内部自动计算两个关键技术参数：

- **ERP（Error Reduction Parameter）**：约束每帧"修正"多少误差。值接近 1 = 完全修正，值接近 0 = 缓慢修正。
- **CFM（Constraint Force Mixing）**：允许约束有一定"柔软度"。0 = 完全刚性，正数 = 允许一些弹性。

计算逻辑在 `SpringCoefficients::erp()` 和 `SpringCoefficients::cfm_factor()` 中（`src/dynamics/integration_parameters.rs`）。

**日常规律**：
- `natural_frequency` 越大 → ERP 越大 → 约束越紧
- `damping_ratio` 越大 → CFM 越大 → 约束越柔软

> **注意**：阻尼比（damping_ratio）主要控制的是振荡衰减速度，而非单纯的"硬度"。damping_ratio > 1（过阻尼）意味着约束恢复到目标时不会来回震荡，但恢复速度变慢——这不等于"更软"，而是"不反弹地慢慢归位"。damping_ratio < 1（欠阻尼）意味着回到目标位置时会来回晃几次才稳定。实际调参时，先把 `natural_frequency` 调到满意的刚度，再调 `damping_ratio` 到所需的震荡抑制程度。

---

## 9. 延伸阅读

- 接触约束（Contact Constraint）和摩擦的求解细节：见源码 `src/dynamics/solver/contact_constraint.rs`
- 关节约束的详细数学推导：见源码 `src/dynamics/solver/joint_constraint.rs`
- 速度求解器的实现：见源码 `src/dynamics/solver/velocity_solver.rs`
- GenericJoint 的高级用法（自定义约束轴）：见 Rapier 官方文档
