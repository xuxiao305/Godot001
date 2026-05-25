# 0010 — Weapon × Projectile × Effect 三元组分解

## Context

武器原型 v1 起点是"开枪 → 击中 → 冲击 → 爆炸 → 炸碎"端到端链路。早期设计文档中"武器"是一个大类，内部混合：

- 瞄准（鼠标 → 世界坐标）
- 触发节流（cooldown）
- 生成飞行物体（projectile 实例化）
- 飞行物体的物理（body、寿命、命中检测）
- 命中后果（爆炸、伤害、推力）

混合带来的问题：

1. 新增武器类型（手枪、火箭炮、霰弹、毒气弹）每个都是"重新写一遍" —— 大量重复
2. 测试不可分 —— 不能单独测"爆炸如何影响场景"而不开枪
3. 调参面盘大 —— 武器参数膨胀到几十个
4. 与破坏 spec 的契约边界模糊（参见 [ADR-0007](0007-effect-dual-channel.md)）

用户在 grill Q1 中明确提出："能够将枪（瞄准+飞行道具生成器），子弹（飞行道具），伤害效果分解为3个类型的物体，方便后续的扩展和单独的测试。"

## Decision

**所有武器逻辑分解为三个正交对象：Weapon × Projectile × Effect。**

```
                ┌──────────────┐
   玩家输入 → │   Weapon     │ 瞄准 + 触发 + 生成
                └──────┬───────┘
                       │ instantiate(initial_velocity, muzzle_pos)
                       ▼
                ┌──────────────┐
                │  Projectile  │ 飞行物理 + 命中检测
                └──────┬───────┘
                       │ on hit → trigger(point, normal)
                       ▼
                ┌──────────────┐
                │    Effect    │ 双通道：DamageField + ForceField
                └──────────────┘
                       │
                       ▼
              Block / Constraint / Player / Enemy
```

### Weapon

| 职责 | 说明 |
|---|---|
| 瞄准 | 读取输入源（鼠标 / 摇杆 / AI），输出方向向量 |
| 触发 | cooldown 节流、弹药管理（v1 无限） |
| 生成 | 实例化 Projectile 资源，传初始 transform + velocity |
| 后坐力 | 给持枪者施加反向冲量（详见 [ADR-0008](0008-self-splash-jump.md)） |

| 关键属性 | 默认值 |
|---|---|
| `projectile_scene` | 引用一个 Projectile 资源 |
| `cooldown` | 0.4 s |
| `recoil_impulse` | 2 N·s |
| `muzzle_offset` | (0.5, 0.2) m |

### Projectile

| 职责 | 说明 |
|---|---|
| 物理飞行 | Box2D dynamic body（gravity_scale 决定是直射还是抛物线） |
| 命中检测 | body_entered 信号 + contact point |
| 触发 Effect | 命中时实例化 effect_scene 于命中点 |
| 寿命兜底 | max_lifetime 超时销毁 |

| 关键属性 | 默认值 |
|---|---|
| `effect_scene` | 引用一个 Effect 资源 |
| `initial_speed` | 武器在生成时传入，覆盖默认 |
| `gravity_scale` | 0（直射）或 1（抛物线） |
| `radius` | 0.08 m |
| `ccd_enabled` | true |
| `max_lifetime` | 直射 1.5 s / 抛物线 3.0 s |

### Effect

| 职责 | 说明 |
|---|---|
| 双通道 | 持有 N 个 DamageField + M 个 ForceField 子组件 |
| 应用 | 生成时立即对范围内 body 执行 query + apply |
| 视觉 | 短命视觉表现（圆形扩展 + 闪光），与物理逻辑解耦 |

详细架构参见 [ADR-0007](0007-effect-dual-channel.md)。

## Rationale

**为什么是三层而不是两层（"武器 + 后果"或"武器 + 子弹"）：**

- 两层无法表达"同一爆炸 Effect 由多种武器使用"（手雷投掷、火箭炮、定时炸药都产生同一爆炸）
- 两层无法表达"同一 Projectile 携带不同 Effect"（同一种弹头，毒气版/爆炸版/单纯撞击版）
- 三层每层有清晰物理意义：扣扳机 → 飞 → 炸

**为什么是这三层（不是别的切法）：**

- 时间维度上的天然边界：扣扳机瞬间 → 飞行过程 → 命中瞬间
- 每层各自有独立生命周期与作用域
- 切法与 Unity / Unreal 等引擎传统的"Weapon - Projectile - HitEffect"惯例一致 —— 玩家社区/讨论方便对齐

**为什么 Effect 不直接挂在 Projectile 上：**

- Projectile 可能未命中（飞超时），此时无 Effect 触发
- 同一 Projectile 可能命中多次（穿透弹未来加入），需要触发多次 Effect
- Effect 也可能由非 Projectile 触发（场景陷阱、定时炸药）

**为什么 Weapon 不直接挂 Effect（跳过 Projectile）：**

- 那就是 hitscan —— 已经在 [ADR-0009](0009-direct-shot-is-physics-projectile.md) 否决
- 即使 hitscan 武器，本项目也走"高速 Projectile（瞬到）"

## Consequences

### 对武器 spec

- §4 章节按 Weapon / Projectile / Effect 三段组织
- v1 至少做 1 个 Weapon × 2 个 Projectile × 4 个 Effect 子类 —— 形成 2 个典型组合（手枪、火箭炮）
- 调参 UI 按三层分组

### 对 v1 范围

最小可演示集：

| 组合 | Weapon | Projectile | Effect 子组件 |
|---|---|---|---|
| 手枪 | cooldown=0.2, recoil=1 N·s | Direct, speed=120, gravity_scale=0 | PointDamage(50) + 极小 DirectionalImpulse(1 N·s) |
| 火箭炮 | cooldown=0.8, recoil=2 N·s | Ballistic, speed=30, gravity_scale=1 | RadialDamage(base=100, R=3) + RadialBlast(peak=12 N·s, R=3) |

**4 个 Effect 子组件类**（v1 必须）：
- PointDamage —— 命中点单 body 扣血
- DirectionalImpulse —— 命中点单 body 沿弹道方向冲量
- RadialDamage —— 范围内多 body 按距离衰减扣血
- RadialBlast —— 范围内多 body 径向冲量

更多组合（霰弹、激光、毒气弹）通过新增子类即可，不改主架构。

### 对扩展

- 钩爪枪 = 新 Weapon + 新 Projectile（带绳关节）+ 无 Effect（命中只是物理 attach）
- 手雷 = 同一 Effect、不同 Weapon（投掷方式）
- 定时炸药 = 无 Weapon、无 Projectile、定时触发 Effect

### 单元测试与 demo

- Weapon 可单独测：mock projectile_scene，验证 cooldown / muzzle / recoil
- Projectile 可单独测：手动 spawn + 给 velocity，验证命中 + Effect 触发
- Effect 可单独测：鼠标 click → 在 click 点直接 spawn Effect（这也是 [ADR-0007 §Consequences](0007-effect-dual-channel.md) 中破坏 spec 独立 demo 的方式）

## Open Questions

- Effect 子组件是 Resource 还是 Node —— 实现时定（Resource 更轻、Node 更可见）
- 同一 Effect 是否支持视觉/音效作为第三类子组件（除 Damage/Force 外）—— v1 不做，视觉直接写在 Effect 主类
- Weapon 是否允许"无 Projectile"（如近战）—— v1 不做，未来再开 ADR
