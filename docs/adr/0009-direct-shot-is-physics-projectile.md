# 0009 — 直射弹是高速物理 Projectile（gravity_scale=0），不是 hitscan

## Context

武器原型 v1 支持两种 Projectile：

- **抛物线弹（Ballistic）** —— 普通 dynamic body，受重力，火箭/手雷类
- **直射弹（Direct）** —— 视觉上是直线，手枪/激光类

直射弹的常见两种工程实现：

| 路径 | 实现 | 优点 | 缺点 |
|---|---|---|---|
| **A. Hitscan** | 开火瞬间 raycast 命中、立即触发 Effect | 性能好、无穿透问题、瞄哪打哪 | 与物理体系外置、无飞行过程、不能被慢放/偏转 |
| **B. 高速物理弹** | Box2D dynamic body + `gravity_scale = 0` + 高初速 + CCD | 与物理体系同一本体论 | 性能略差、需 CCD 处理高速穿透、瞄准点 ≠ 命中点（有飞行时间） |

行业惯例：Quake、CS 用 hitscan；Half-Life 部分武器用物理弹；GTA、Hunt: Showdown 全用物理弹（含初速、下坠、风偏）。

本项目背景：
- 项目愿景是 setpiece 驱动，物理统一是 [项目总览 §2.5](../项目总览.md) 硬约束
- 已规划"子弹时间"作为未来玩法（武器 spec §3.2）—— hitscan 无法慢放
- [ADR-0001 内在发动机派](0001-inner-engine-school.md) 要求场景物理事件能影响一切 dynamic body
- v1 规模小（~200 体块），性能不是主约束

## Decision

**直射弹采用路径 B：高速物理 Projectile + `gravity_scale = 0`。**

参数（v1 起始）：

| 属性 | 值 | 备注 |
|---|---|---|
| Body Type | Dynamic | 与抛物线弹同 |
| `gravity_scale` | 0 | 不受重力 |
| `linear_damping` | 0 | 不衰减 |
| `initial_speed` | 120 m/s | 高速，视觉上接近瞬发 |
| CCD | true | 高速防穿透 |
| `max_lifetime` | 1.5 s | 飞 180 m 强制销毁 |

视觉表现：sprite 拉长成短线（运动方向），玩家几乎感觉不到飞行时间。

## Rationale

**为什么不用 hitscan：**

1. **破坏物理统一**：hitscan 命中后再触发 Effect = 把"飞行 → 命中"两阶段塌缩成一帧事件。一旦未来加风、力场、磁场、子弹时间等机制，需要专门为 hitscan 弹写特例 —— 违反 ADR-0001 哲学
2. **子弹时间不可用**：项目路线图明确写了"子弹时间"作为吸引力玩法。hitscan 弹根本没有"在飞"的状态可慢放
3. **偏转/反射不可用**：未来"盾牌反弹子弹"、"力场偏转子弹"无法套用 hitscan
4. **视觉一致性**：所有 Projectile 都是物理体 → 视觉上"看到子弹在飞"是统一感官

**为什么物理弹的代价可接受：**

1. **性能**：120 m/s × 60 Hz = 每步 2 m 位移，CCD 在小质量物体上 Box2D 设计期就有方案
2. **瞄准点 ≠ 命中点**：在 ~30 m 内目标，飞行时间 ~0.25 s，玩家几乎不感知；远距离再调（未来武器分级）
3. **复杂度**：与抛物线弹共享同一个 Projectile 类型，只是参数不同 —— 单一类型胜过两套代码路径

**为什么 `gravity_scale = 0` 而不是 1：**

- `= 1` 时 120 m/s 水平初速、25 m/s² 重力 → 30 m 距离落差 ≈ 0.78 m。视觉上有明显下坠 ≠ 直射弹
- `= 0` 时纯线性，符合"直射"语义
- 抛物线弹用 `= 1`，两者通过 gravity_scale 一行参数差异化，零额外架构

**为什么不混合（"短距 hitscan、长距物理"）：**

- 分支即特例代码 —— 同样违反统一原则
- v1 一种实现就够；混合方案在性能瓶颈出现后再考虑

## Consequences

### 对武器 spec

- §4.2 Projectile 表统一两种 Projectile，差异仅参数（gravity_scale、initial_speed、视觉长度）
- 不引入 hitscan 子类型，不引入 `is_hitscan` 标志

### 对未来扩展

- **子弹时间**：Engine.time_scale 调小即可 —— 所有 Projectile（含直射弹）一起慢放
- **风/力场偏转**：未来 EnvForceField 一视同仁作用于所有 Projectile body
- **盾牌反弹**：复用 Box2D restitution + collision filter，无新代码
- **激光武器**：未来若需要"真瞬发感"，再开 ADR 决定是否破例

### 对 CONTEXT.md

- 引入"直射弹（Direct Projectile）"、"抛物线弹（Ballistic Projectile）"术语
- 明确 ban "hitscan"、"瞬发弹"、"激光"作为本项目直射弹的指代

### 性能监控点

- Debug 面板需显示 "活跃 Projectile 数"
- 若实测中高速弹 CCD 仍漏检 → 退到子步细分 + raycast 校正（仍是物理弹，不退回 hitscan）

## Open Questions

- 直射弹初速 120 m/s 是否够 —— 真机调
- 直射弹寿命 1.5 s 是否够（180 m 在测试关卡是否够覆盖）—— 真机调
- 是否需要"穿透多目标"开关 —— v1 不做，未来武器特性
- 子弹时间机制具体放在哪一阶段实现 —— 不在 v1，路线图后续
