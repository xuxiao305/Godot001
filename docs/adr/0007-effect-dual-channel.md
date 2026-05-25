# 0007 — Effect 双通道（DamageField + ForceField）+ 统一伤害语言 + 单向依赖

## Context

PlatformerPhysics 同时在写两份原型 spec：

- **武器原型**（weapon-explosion-prototype-design）—— 开枪、子弹、爆炸
- **破坏原型**（2026-05-24-destruction-prototype-design）—— 体块、约束、塌方

二者在"爆炸如何影响场景"上各自定义了语义：

| 概念 | 武器 spec | 破坏 spec |
|---|---|---|
| 爆炸算法 | AABB query + 径向冲量（peak_impulse = 12 N·s, R = 3 m, linear falloff） | AABB query + 径向冲量（impulse_base = 5 N·s, R = 1.5 m）+ 直接 take_damage（base = 200） |
| 破坏物概念 | "焊接组合箱"（4-8 块 + weld joint） | "Block + Constraint" 通用框架 |
| 谁负责把"爆炸"翻译成"约束断裂" | weld joint reaction_force 阈值 | 同左，叠加血量系统 |

冲突点：

1. 同一个"爆炸"在两边参数完全不同
2. 破坏 spec 的 ImpactWatcher 是单独路径，武器 spec 没接入
3. 破坏 spec 的"Block 有血量"概念在武器 spec 缺失
4. 武器 spec 写完后，破坏 spec 完成时如果改动接口，武器 spec 要联动

若不立 contract，两 spec 必然出现"我以为你管，结果都没管"或"两边都管，行为冲突"。

## Decision

**确立 Effect 双通道架构 + 统一伤害语言 + 单向依赖原则**，作为跨 spec 的硬契约。

### 1. Effect 是双通道容器

任何命中事件（爆炸、单点伤害、毒气、推力）统一表达为一个 **Effect**，挂载两类子组件：

- **DamageField（伤害通道）** —— 对范围内每个实现 `take_damage` 的物理体调用其 take_damage 方法
- **ForceField（物理力通道）** —— 对范围内每个 dynamic body apply impulse / force

两通道独立、可单独使用：

| 例 | DamageField | ForceField |
|---|---|---|
| 火箭爆炸 | 径向（base = 100, R = 3 m, linear falloff） | 径向冲量（peak = 12 N·s, R = 3 m） |
| 手枪点伤 | 单点（damage = 50） | 无（或微小推力） |
| 推力炸药 | 无 | 径向冲量（peak = 20 N·s, R = 2 m） |
| 毒气云 | 范围（持续 dps = 5） | 无 |
| 后坐力 | 无 | 单点反向冲量（2 N·s） |

### 2. 统一伤害语言

所有可受损物理体（Block、Constraint、未来的 Enemy / Player）实现同名方法：

```
take_damage(amount: float, point: Vec2, source: DamageSource) -> void
```

DamageField 通过 duck typing 调用，**不**引入 `IDamageable` 接口/基类（YAGNI）。新增受损类型不需要改 DamageField。

### 3. 单向依赖（Effect 不知道破坏内部）

DamageField 命中一个 Block 后：

- 调用 `block.take_damage(amount, point, source)`
- **不**直接接触 Constraint
- Block 内部决定如何处理（扣自己血、按比例转发给相连 Constraint 等）

详细：参见 [destruction spec §4.1 §4.2](../2026-05-24-destruction-prototype-design.md)（Path X：Block 内部转发伤害到 Constraint）。

后果：武器系统从不 import 破坏系统的 Constraint 类型；删除武器系统不影响破坏系统编译/运行。反过来则不成立 —— 破坏系统也独立于武器（ImpactWatcher 路径仍可触发破坏）。

## Rationale

**为什么是双通道，不是单通道（"伤害 = 物理力的一种"或"物理力 = 伤害的副作用"）：**

- 物理力通道是 Box2D 原生事件（apply_impulse 是已有 API）；伤害通道是项目自定语义（take_damage）。强行统一会让其中一个失去自然表达
- 两通道有真实独立用例（毒气只有伤害无力；气浪只有力无伤害）
- 双通道仍然单一接口（Effect.apply(world, center)），调用方无感
- 双通道允许 ForceField **唯一**对 player 施力（自爆跳通过此路径，详见 [ADR-0008](0008-self-splash-jump.md)），DamageField 暂无 player 受体（v1 无玩家血量）

**为什么是 duck typing 不是接口：**

- v1 受损类型只有 Block、Constraint 两种，未来加 Enemy 也好加
- Godot/GDScript 对 duck typing 友好；接口/基类反而增加耦合
- 任何"是 duck typed 还是接口"的争议，等真有 3 种以上受体时再处理 —— YAGNI

**为什么是单向依赖：**

- 武器与破坏在路线图上是不同家族（D vs B），独立开发节奏
- 破坏系统是更基础的层（家族 B），武器是上层使用者（家族 D）
- 单向依赖保证：破坏 spec 可以独立 demo（用鼠标 click 触发伤害源），不依赖武器
- 反之不可 —— 武器需要"能受伤的东西"才能验收

**为什么是 Path X（Block 转发给 Constraint），不是 Path Y（Effect 直接 take_damage on Constraint）：**

- Path Y 要求 DamageField 知道 Constraint 是什么 → 违反单向依赖
- Path Y 要求 AABB query 返回 Constraint 节点（Box2D joint 不是 body，AABB 拿不到）
- Path X 让"哪些约束被这次伤害削弱"这件事由 Block 自己决定 —— 正确的关注点划分
- Path X 自然支持 ImpactWatcher 路径：碰撞冲击 → block.take_damage → 转发到 Constraint，统一

## Consequences

### 跨 spec 强制要求

1. **武器 spec** 不得包含 `take_damage on Constraint` 的直接调用
2. **武器 spec** 不得 import 任何破坏 spec 的私有类型；只可调用 take_damage / apply_impulse
3. **破坏 spec** 不得依赖任何武器 spec 类型
4. **破坏 spec** 必须实现：`Block.take_damage`、`Constraint.take_damage`、`Block` 内部转发逻辑

### 对武器 spec 的简化

- Effect 不再 hard-code "破坏物"概念
- 同一 Effect 可作用于 Block、未来的 Enemy、Player（部分）—— 无需 spec 联动

### 对破坏 spec 的简化

- 删除自己的"爆炸"实现（与武器 spec 重复定义）—— 改为暴露 take_damage 接口，让 DamageField 来打
- ImpactWatcher 路径保留（碰撞冲击 → take_damage），与武器 spec 完全解耦

### 调试入口

破坏 spec 独立 demo 时，提供 "鼠标点击 = 在该点生成一次简单 Effect" 的调试输入。武器 spec 独立 demo 时，可用普通 dynamic box（实现简单 take_damage 收到时打印日志）做受体测试。

## Open Questions

- DamageField 的 falloff 函数（linear / quadratic）是 Effect 资源属性 vs 全局参数 —— 实现时定
- `take_damage(amount, point, source)` 的 source 参数类型 —— 可能是 enum、可能是字符串、可能直接是发射源节点；实现时定
- Block 转发到 Constraint 的比例 `damage_to_constraint_ratio` 是 Block 属性 vs 全局参数 —— v1 全局，实现时可能升级到材质属性
- 未来 Enemy 加入后，DamageField 是否需要"阵营过滤"（friendly fire 开关）—— v1 不做，待 D 家族完整时设计
