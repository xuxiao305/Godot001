# 0011 — 角色摩擦自管派（Custom Friction over Box2D）

## Context

3C 原型 v1（[ADR-0001](0001-inner-engine-school.md)）采用"内在发动机派"——所有运动由 force/impulse 演化，不写 `linear_velocity`。但实测暴露 Box2D Coulomb 摩擦模型对角色控制的三类系统性副作用：

| 症状 | 机制 |
|---|---|
| **落地丢横向速度**：从高处带 vx 落地，vx 一帧内被抹光 | 落地法向冲量 `J_n = m·vy_落地` 巨大；摩擦冲量上限 = μ·J_n 同样巨大，足以一帧抹掉整个 vx |
| **空中贴墙卡住**：按方向键贴垂直墙面，重力被摩擦平衡 | 推墙力 = 反作用 `N`；垂直摩擦上限 = μ·N，可超过重力 → 静摩擦撑住玩家 |
| **撞阶梯/平台侧面卡住** | 同上，任何水平面外的接触都可能卡 |

根因：**Coulomb 模型把法向冲量与切向冲量通过单一 μ 强耦合**。这适合刚体堆叠（箱子叠箱子），但不适合"角色对地形的连续操作"——角色想要的是"地面有摩擦感、墙不黏、落地不丢动量"的解耦行为。

## Decision

**Player 对 Box2D 摩擦系数设为 0**（`Player.tscn` 的 `PhysicsMaterial.friction = 0.0`）。Box2D 合成 μ = √(0 × μ_surface) = 0，所有 Box2D 内置摩擦失效。

**地面摩擦在 GDScript 里按 Coulomb 模型自己算**，仅在 `is_grounded` 分支生效：

```
F_friction = -sign(vx) · μ_surface · m · g
```

`μ_surface` 通过 `PhysicsDirectBodyState2D.get_contact_collider_object()` 读取当前接地 collider 的 `PhysicsMaterial.friction`。空中分支不调用本模块（保持 [ADR-0004](0004-air-control-model.md) "空中无阻力"语义）。

## Rationale

- **根因消除胜过症状缓解**：前一轮考虑过"落地补偿器 + 卡墙补偿器"两段补丁式方案，但每出现一个新症状（坡卡、堆叠卡）都要加一个补偿器，本质是与物理引擎"打地鼠"。自管摩擦一次斩断三类问题
- **与 ADR-0001 哲学一致**：发动机派的核心是"角色运动由代码全权决定"。把摩擦也交给代码，是 ADR-0001 的逻辑延伸——物理引擎从此只负责碰撞解算 / 重力 / 法向约束，不再背着代码偷偷算切向力
- **可扩展性**：将来加 wall slide / wall jump / 坡面专属摩擦 / 滑铲，都可以在 `GroundFriction` 模块里自然扩展，不会和 Box2D 摩擦"协调"
- **材质语义保留**：每个 `StaticBody2D` 的 `PhysicsMaterial.friction` 数值意义不变（Ice 0.5 / Walkway 1.0 / Mud 2.0），只是由我们消费而非 Box2D。Inspector 工作流零变化

## Consequences

### 正面

- **落地保留 vx**：合成 μ=0 → 落地不再有切向摩擦冲量 → 横向动量自然穿透
- **卡墙/卡侧面消失**：空中任何接触都不产生摩擦 → 重力始终主导垂直运动
- **`f_active_brake` 失去主要用途**：原本作为"无地面阻尼时的应急刹车"的补丁，现在被真摩擦取代，保留 export 作为可选叠加（默认 0，不引入回归）
- **新 helper 模块**：`Scripts/Prototypes/3C/ground_friction.gd`，纯静态，可单测

### 负面 / 待办

- **极速降约 8%**：Walkway μ=1.0 时极速从 800 px/s 降到 ~738 px/s（Coulomb 平衡）。v1 接受；如果手感不对再调 `v_max` 或 `f_max_ground`
- **坡面摩擦未处理**：当前 `compute_force` 用水平 vx 和 `g` 直接算，未做坡面投影。v1 测试关无真斜坡（只有阶梯方盒），暴露面 = 0；引入真斜坡时本模块需要扩展
- **多接触面材质选择**：玩家同时踩在 Walkway+Ice 边界时，目前选 `n.y` 最负的那个 contact 的 μ。可能闪烁。v1 不处理
- **Mud μ=10 不再可用**：μ × g > f_max_ground 时发动机无法克服摩擦，玩家完全走不动。Mud 推荐重新校准到 μ=2.0（"慢但能走"）

## Alternatives Considered

| 方案 | 否决理由 |
|---|---|
| **A：降 Player.friction 到 0.01**（保留 Box2D 算） | Box2D 合成 μ = √(0.01 × μ_surface) 把材质差异从 1:2:20 压缩到 1:1.4:4.5，Ice/Walkway/Mud 几乎同质 |
| **B：双补偿器**（Landing + WallAntiStick） | 补丁思维，每出新症状要加新补偿器；不解决根因；最终代码量未必比 C 少 |
| **C（采用）：Player.friction = 0 + 自写地面摩擦** | 根因消除；与 ADR-0001 哲学一致；扩展性最好 |
| **C-lite：仅 Player.friction = 0，不写自定义摩擦** | Ice/Walkway/Mud 材质差异全部失效；松手只能靠 `f_active_brake` 一刀切。等于放弃材质设计 |

## References

- 设计 spec：`docs/2026-05-25-3c-custom-ground-friction-design.md`
- 实现：`Scripts/Prototypes/3C/ground_friction.gd`、`Scripts/Prototypes/3C/player.gd`、`Scenes/Prototypes/3C/player.tscn`
- 相关：[ADR-0001 内在发动机派](0001-inner-engine-school.md)、[ADR-0004 空中控制](0004-air-control-model.md)
