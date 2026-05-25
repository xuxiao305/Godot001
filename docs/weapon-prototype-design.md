# 武器原型设计 — Weapon × Projectile × Effect 三元组

| 字段 | 值 |
|---|---|
| 日期 | 2026-05-24（基于 grill Q1-Q11 重写） |
| 状态 | Draft（待审） |
| 引擎 | Godot 4.x + Box2D（通过 GDExtension） |
| 所属项目 | PlatformerPhysics |
| 文档定位 | 家族 D 武器/弹道核心；与家族 B（破坏）通过 [ADR-0007](adr/0007-effect-dual-channel.md) 契约对接 |

**相关文档：**
- [项目总览.md](项目总览.md)（§4 家族 D 武器/弹道；§6 路线图）
- [CONTEXT.md](CONTEXT.md)（Weapon/Projectile/Effect 三元组、DamageField、ForceField、Self-Splash Jump、Recoil、Direct/Ballistic Projectile）
- [3C-prototype-design.md](3C-prototype-design.md)（角色控制器，复用、不修改）
- [2026-05-24-destruction-prototype-design.md](2026-05-24-destruction-prototype-design.md)（破坏框架，通过 take_damage 契约对接）
- 关键 ADR：
  - [ADR-0007 Effect 双通道 + 统一伤害语言 + 单向依赖](adr/0007-effect-dual-channel.md)
  - [ADR-0008 自爆跳 ≠ 后坐力](adr/0008-self-splash-jump.md)
  - [ADR-0009 直射弹是高速物理 Projectile](adr/0009-direct-shot-is-physics-projectile.md)
  - [ADR-0010 Weapon × Projectile × Effect 三元组分解](adr/0010-weapon-projectile-effect-decomposition.md)

---

## 1. 背景

### 1.1 大项目背景

PlatformerPhysics 是个人技术 demo + 学习项目，**不发布完整游戏**。本原型对应 [项目总览.md](项目总览.md) §4 家族 D（武器/弹道）的核心子原型。

### 1.2 为什么现在做

- 武器是项目愿景"2D 神秘海域 setpiece"的核心交互方式之一
- Box2D 在弹道、爆炸径向冲击上"白送"（参见 [platformer-physics-tech-stack](../项目总览.md)）
- 与家族 B（破坏）通过 take_damage 契约对接，**两系统独立开发**：本原型 demo 中受体用普通 dynamic body（实现简单 take_damage），破坏系统独立 demo 中伤害源用鼠标 click
- 与 3C 解耦但保留物理可干预性：玩家被爆炸推飞（自爆跳）作为 [ADR-0008](adr/0008-self-splash-jump.md) 的核心涌现

### 1.3 成功标准

| # | 标志 |
|---|---|
| 1 | 鼠标瞄准 + 左键发射手枪直射弹（高速、CCD 防穿透） |
| 2 | 鼠标瞄准 + 右键发射火箭炮抛物线弹（受重力下坠） |
| 3 | 命中静态墙 → 爆炸视觉 + 推飞周围 dynamic body |
| 4 | 朝脚下开炮 → 自爆跳上 1-2 m 高（[ADR-0008](adr/0008-self-splash-jump.md) 涌现） |
| 5 | 受体（普通 dynamic body 实现 take_damage）被命中后日志打印伤害值与冲量 |
| 6 | 后坐力可独立开关；关闭后开枪仅有视觉，无角色位移 |
| 7 | 所有参数 runtime 可调；活跃 Projectile / Effect 数实时显示 |
| 8 | 三个对象（Weapon / Projectile / Effect）可独立替换：换 Effect 不动 Weapon |

---

## 2. 设计哲学

### 2.1 三元组架构（[ADR-0010](adr/0010-weapon-projectile-effect-decomposition.md)）

```
玩家输入 → Weapon → Projectile → Effect → Block / Constraint / Player / Enemy
            瞄准        飞行物理      双通道：
            触发        命中检测      DamageField + ForceField
            生成
```

每层独立替换、独立测试、独立调参。详见 [ADR-0010](adr/0010-weapon-projectile-effect-decomposition.md)。

### 2.2 Effect 双通道契约（[ADR-0007](adr/0007-effect-dual-channel.md)）

Effect 同时挂 DamageField（伤害通道）+ ForceField（物理力通道）。两通道独立：

| 例 | DamageField | ForceField |
|---|---|---|
| 火箭爆炸 | 径向 base=100, R=3, linear | 径向冲量 peak=12 N·s, R=3 |
| 手枪点伤 | 单点 50 | 单点定向 1 N·s |
| 推力炸药 | 无 | 径向冲量 |
| 毒气云 | 范围 dps=5 | 无 |

**单向依赖**：Effect 不知道接受者是 Block / Constraint / Player / Enemy，只调用其 `take_damage(amount, point, source)` 或 `apply_central_impulse(v)`。完整契约见 [ADR-0007](adr/0007-effect-dual-channel.md)。

### 2.3 与项目方法学的一致性

- **物理统一优先（[项目总览 §2.5](项目总览.md)）**：直射弹、抛物线弹都是物理 body，不用 hitscan（[ADR-0009](adr/0009-direct-shot-is-physics-projectile.md)）
- **范围克制（YAGNI）**：v1 = 2 武器 × 2 Projectile × 4 Effect 子组件；不预留弹药、武器切换、AI 等
- **原型驱动**：独立 demo 跑通，受体用简单 dynamic body，不依赖完整破坏框架

### 2.4 与 3C 的关系

- 角色复用 3C 的 [内在发动机派](CONTEXT.md) 控制器，**不**修改
- 后坐力作为外力冲量施加到角色 body，由 3C 自然消化
- 自爆跳是 ForceField `affect_player=true` 的自然涌现，无 3C 侧特例

---

## 3. 范围

### 3.1 ✅ v1（MVP）必须包含

**Weapon 类（共 2 个实例）：**
- **手枪**：cooldown=0.2 s, recoil=1 N·s, 生成直射弹
- **火箭炮**：cooldown=0.8 s, recoil=2 N·s, 生成抛物线弹

**Projectile 类（共 2 种参数化）：**
- **直射弹（Direct）**：gravity_scale=0, speed=120 m/s, lifetime=1.5 s（[ADR-0009](adr/0009-direct-shot-is-physics-projectile.md)）
- **抛物线弹（Ballistic）**：gravity_scale=1, speed=30 m/s, lifetime=3.0 s

**Effect 子组件（共 4 类）：**
- **PointDamage** —— 命中点单 body 扣血
- **DirectionalImpulse** —— 命中点单 body 沿弹道方向冲量
- **RadialDamage** —— AABB query 范围内多 body 按距离衰减扣血
- **RadialBlast** —— AABB query 范围内多 body 径向冲量

**典型组合：**
- 手枪 Effect = PointDamage(50) + DirectionalImpulse(1 N·s)
- 火箭炮 Effect = RadialDamage(base=100, R=3 m) + RadialBlast(peak=12 N·s, R=3 m)

**其他基础设施：**
- 鼠标瞄准（屏幕 → 世界坐标 → 方向向量）
- 瞄准辅助线（直线，长度 debug 可调）
- 后坐力开关（debug）
- 测试受体（普通 dynamic box，实现简单 take_damage 打印日志）
- 测试场地（地面 + 几堵静态墙 + 几个 dynamic box）+ **重置按钮 + arena 墙**（玩家被推飞出场可重置）
- Debug 面板：所有参数 runtime 调节 + 活跃 Projectile / Effect 数显示

### 3.2 🟡 v1.5（小代价加分项）

- 抛物线辅助线（含重力预测）
- 爆炸视觉：闪光 + expanding circle + 简易粒子
- 屏幕震动
- 多种 Effect 子组件组合（毒气、推力炸药等）作为材质包

### 3.3 🔴 v2+（独立子原型，本文档不涉及）

- 多种武器（霰弹、激光、钩爪枪、引力枪、粘性手雷）
- 跳弹 / 反射弹 / 穿透弹
- 爆炸 raycast 阻挡
- 子弹时间 / 慢镜头（Engine.time_scale，所有 Projectile 一起慢放）
- 拾取 / 切换武器 / 弹药系统
- AI 持武器

### 3.4 ⚫ 明确不在本项目

- Hitscan 弹（[ADR-0009](adr/0009-direct-shot-is-physics-projectile.md) 否决）
- IDamageable 接口/基类（[ADR-0007](adr/0007-effect-dual-channel.md) 选用 duck typing）
- Effect 直接调用 Constraint.take_damage（违反单向依赖；[ADR-0007 Path X](adr/0007-effect-dual-channel.md)）
- 玩家死亡（v1 无玩家血量；玩家只能被推飞，arena 兜底）

---

## 4. 详细规格

### 4.1 Weapon

**世界参数**：与 3C 同 —— 重力 25 m/s² 垂直向下；物理步长 1/60 s。

| 属性 | 默认 | 备注 |
|---|---|---|
| `projectile_scene` | 引用一个 Projectile 资源 | 决定生成什么 Projectile |
| `cooldown` | 0.2 s（手枪）/ 0.8 s（火箭炮） | 扣扳机最小间隔 |
| `recoil_impulse` | 1 N·s（手枪）/ 2 N·s（火箭炮） | 反向冲量，与自爆跳无关（[ADR-0008](adr/0008-self-splash-jump.md)） |
| `recoil_enabled` | true | debug 开关 |
| `muzzle_offset` | (0.5, 0.2) m | 相对角色中心；v1 不随瞄准旋转 |
| `aim_source` | mouse | 鼠标光标的世界坐标 |
| `projectile_initial_speed` | 120 m/s（直射）/ 30 m/s（抛物线） | 覆盖 Projectile 默认 |

**触发逻辑**：
1. 读鼠标位置 → 世界坐标
2. `direction = (鼠标世界坐标 − 枪口世界坐标).normalized()`
3. 若 `now − last_fire_time >= cooldown`：
   - 在 muzzle 位置实例化 `projectile_scene`，初速度 = `direction × projectile_initial_speed`
   - 若 `recoil_enabled`：给角色 `apply_central_impulse(−direction × recoil_impulse)`
4. 更新 `last_fire_time`

**测试**（独立）：mock `projectile_scene` 为日志类，验证 cooldown / muzzle / recoil。

### 4.2 Projectile

| 属性 | 直射弹 | 抛物线弹 | 备注 |
|---|---|---|---|
| Body Type | Dynamic | Dynamic | |
| Shape | Circle, r = 0.08 m | Circle, r = 0.08 m | 视觉简陋 |
| Density | 1.0 | 1.0 | mass ≈ 0.02 kg |
| Friction | 0 | 0 | |
| Restitution | 0 | 0 | v1 不跳弹 |
| Linear Damping | 0 | 0 | |
| `gravity_scale` | **0** | **1** | 关键差异（[ADR-0009](adr/0009-direct-shot-is-physics-projectile.md)） |
| CCD | **true** | true | 高速防穿透 |
| Collision Layer | `projectile` | `projectile` | |
| Collision Mask | `world` + `destructible` + `enemy` | 同 | **不**碰 `player`（避免自碰） |
| `max_lifetime` | 1.5 s | 3.0 s | 超时销毁 |
| `effect_scene` | 引用 Effect 资源 | 引用 Effect 资源 | 命中时实例化 |

**命中逻辑**：
1. 监听 `body_entered` 信号
2. 取碰撞点（contact world position）+ 法线
3. 在命中点实例化 `effect_scene`，传入 `(point, normal, source=self)`
4. 销毁自身（queue_free）

**测试**（独立）：手动 spawn 一个 Projectile + 给初速度，验证命中触发 Effect。

### 4.3 Effect（双通道）

Effect 是一个容器节点，**不是** Box2D body。生成时立即执行 query + apply + 销毁视觉。

**主类结构（伪码）**：

```
class Effect extends Node2D:
    var damage_fields: Array  # [PointDamage / RadialDamage / ...]
    var force_fields: Array   # [DirectionalImpulse / RadialBlast / ...]
    var visual_duration: float = 0.3

    func _ready():
        for df in damage_fields: df.apply(world, position, context)
        for ff in force_fields: ff.apply(world, position, context)
        start_visual()
        await visual_done
        queue_free()
```

**context** 至少包含：source（哪个 Projectile / 武器触发的）、normal（命中法线，可选）、direction（弹道方向，可选）。

### 4.4 Effect 子组件 — DamageField

#### PointDamage

| 属性 | 默认 | 备注 |
|---|---|---|
| `amount` | 50 | 单次伤害值 |

**算法**：
```
apply(world, center, ctx):
    body = world.query_point(center)  # 取一个最近 dynamic body
    if body and body.has_method("take_damage"):
        body.take_damage(amount, center, ctx.source)
```

#### RadialDamage

| 属性 | 默认 | 备注 |
|---|---|---|
| `base` | 100 | 中心处伤害 |
| `radius` | 3.0 m | 影响半径 |
| `falloff` | linear | (1 − d/R) |
| `max_bodies` | 50 | 单次查询上限 |

**算法**：
```
apply(world, center, ctx):
    bodies = world.query_aabb(center - radius, center + radius)[:max_bodies]
    for body in bodies:
        d = (body.position - center).length()
        if d > radius: continue
        if not body.has_method("take_damage"): continue
        amount = base * max(0, 1 - d / radius)
        body.take_damage(amount, body.position, ctx.source)
```

**关键**：调用 take_damage 时 Effect **不知道**对方是 Block、普通 dynamic body、还是未来的 Enemy。受体内部决定怎么扣血、是否转发到 Constraint。详见 [ADR-0007](adr/0007-effect-dual-channel.md)。

### 4.5 Effect 子组件 — ForceField

#### DirectionalImpulse

| 属性 | 默认 | 备注 |
|---|---|---|
| `magnitude` | 1 N·s | 冲量大小 |
| `direction_source` | from_context | 从 ctx 取弹道方向 |

**算法**：
```
apply(world, center, ctx):
    body = world.query_point(center)
    if body and body is RigidBody2D:
        body.apply_central_impulse(ctx.direction * magnitude)
```

#### RadialBlast

| 属性 | 默认 | 备注 |
|---|---|---|
| `peak_impulse` | 12 N·s | 中心处对 1 kg 物体冲量 |
| `radius` | 3.0 m | 影响半径 |
| `falloff` | linear | |
| `affect_player` | true | 自爆跳所需（[ADR-0008](adr/0008-self-splash-jump.md)） |
| `max_bodies` | 50 | |

**算法**：
```
apply(world, center, ctx):
    bodies = world.query_aabb(center - radius, center + radius)[:max_bodies]
    for body in bodies:
        if body is StaticBody: continue
        if not affect_player and body == player: continue
        delta = body.position - center
        d = delta.length()
        if d > radius: continue
        dir = delta.normalized()
        impulse = peak_impulse * max(0, 1 - d / radius)
        body.apply_central_impulse(dir * impulse)
```

**`affect_player=true` 是 [ADR-0008](adr/0008-self-splash-jump.md) 的核心 invariant** —— 自爆跳的物理来源；不是 bug。Debug 可关闭对比。

### 4.6 双路径对玩家的影响（[ADR-0008](adr/0008-self-splash-jump.md)）

**路径 A：后坐力（Recoil）**
- 由 Weapon 直接施加
- 量级：1-2 N·s → 反向速度 ≈ 0.8-1.5 m/s
- 表现：开枪后角色退一小步；空中开枪可微调位移
- Debug 可关闭

**路径 B：自爆跳（Self-Splash Jump）**
- 由 Effect 的 RadialBlast `affect_player=true` 涌现
- 量级：12 N·s 中心 → 衰减后 ≈ 7-10 m/s
- 表现：朝脚下开火箭炮 → 跳 1-2 m 高
- Debug 可关闭（`affect_player=false`）做对比

两条路径独立调参，详细物理量级计算见 [ADR-0008](adr/0008-self-splash-jump.md)。

### 4.7 与破坏系统的对接

通过 [ADR-0007](adr/0007-effect-dual-channel.md) 契约对接，本 spec **不**：
- import 任何 destruction spec 类型
- 假定 take_damage 内部如何处理
- 知道 Constraint 是否存在

测试时受体 = 普通 dynamic box + 简单 take_damage 打印日志即可。完整破坏框架接入是后续步骤（v2+）。

### 4.8 测试场景

最简关卡，验证三元组与双路径：

- 3C 角色 + 平地（沿用 3C 测试关卡基础）
- **arena 墙**：四面静态墙围出测试区，防止角色被推飞出场（替代角色死亡机制）
- **重置按钮**（debug 面板按钮 + 快捷键 `R`）：把角色 teleport 回原点
- 3 个空地上的 dynamic box（测试受体，实现简单 take_damage 打印）
- 1 堵静态墙（验证 Projectile 命中静态体 → 爆炸 + 墙不动）
- 1 个 dynamic box 站在角色脚下（验证自爆跳：朝脚下火箭炮 → 跳上去）
- 1 个朝上的天花板（验证朝上开枪 → 角色压地）

### 4.9 Debug 输入

- 鼠标左键：手枪（直射 + PointDamage + DirectionalImpulse）
- 鼠标右键：火箭炮（抛物线 + RadialDamage + RadialBlast）
- 键 `R`：重置角色位置
- 键 `F1`：切换 debug 面板
- 键 `Q`：在鼠标位置直接 spawn Effect（不通过开枪，独立测 Effect）

### 4.10 Debug 面板（runtime 调参）

**Weapon 参数（手枪 / 火箭炮各一组）：**
- `cooldown`、`recoil_impulse`、`recoil_enabled`、`projectile_initial_speed`、瞄准辅助线长度

**Projectile 参数：**
- `gravity_scale`、`max_lifetime`、CCD 开关

**Effect 子组件参数：**
- PointDamage: `amount`
- DirectionalImpulse: `magnitude`
- RadialDamage: `base`、`radius`、`max_bodies`
- RadialBlast: `peak_impulse`、`radius`、`affect_player`、`max_bodies`

**屏显**：
- FPS、活跃 Projectile 数、活跃 Effect 数
- 最近一次 Effect：position + 影响 body 数 + 总伤害 + 总冲量
- 角色当前速度（验证自爆跳 / 后坐力效果）

### 4.11 调参初值

| 参数 | 初值 | 调参方向 |
|---|---|---|
| 手枪 cooldown | 0.2 s | 越短越突突，越长越战术 |
| 火箭炮 cooldown | 0.8 s | 控制自爆跳频率 |
| 手枪 recoil_impulse | 1 N·s | 调到刚好"开枪感" |
| 火箭炮 recoil_impulse | 2 N·s | 与自爆跳无关 |
| 直射弹 initial_speed | 120 m/s | 视觉上瞬到 |
| 抛物线弹 initial_speed | 30 m/s | 抛出去有可读弧线 |
| 直射弹 max_lifetime | 1.5 s | 飞 180 m |
| 抛物线弹 max_lifetime | 3.0 s | 飞 90 m |
| PointDamage amount | 50 | 受体调试 |
| RadialDamage base | 100 | 中心威力 |
| RadialDamage / RadialBlast radius | 3.0 m | 波及范围 |
| RadialBlast peak_impulse | 12 N·s | 自爆跳跳高 ≈ 1.5 m |

所有初值真机调整。

### 4.12 文件 / 模块划分

| 路径 | 职责 |
|---|---|
| `weapon/weapon.gd` | Weapon 主类（瞄准 + 触发 + 生成 + 后坐力） |
| `weapon/projectile.gd` | Projectile 主类（飞行 body + 命中检测 + 触发 Effect） |
| `weapon/effect.gd` | Effect 主类（双通道容器 + 视觉） |
| `weapon/damage_fields/point_damage.gd` | DamageField 子类 |
| `weapon/damage_fields/radial_damage.gd` | DamageField 子类 |
| `weapon/force_fields/directional_impulse.gd` | ForceField 子类 |
| `weapon/force_fields/radial_blast.gd` | ForceField 子类 |
| `weapon/weapons/pistol.tscn` | 手枪资源（Weapon + 关联 Projectile + Effect） |
| `weapon/weapons/rocket_launcher.tscn` | 火箭炮资源 |
| `weapon/test_dummy.gd` | 测试受体（简单 dynamic box + take_damage 打印） |
| `weapon/debug_panel.gd` | runtime 调参 UI |
| `weapon/weapon_demo.tscn` | 主场景 |

---

## 5. 测试与验证

### 5.1 功能验证（手动 demo）

| # | 操作 | 期望 |
|---|---|---|
| T1 | 左键扣扳机 | 直射弹高速飞出，视觉接近瞬到，命中后 dummy 打印伤害 50 |
| T2 | 右键扣扳机 | 抛物线弹按弧线飞，命中后周围 dummy 都打印伤害与冲量，明显被推飞 |
| T3 | 右键打静态墙 | 爆炸视觉触发，墙不动，周围 dynamic 被推飞 |
| T4 | 朝脚下右键 | 自爆跳上 1-2 m 高（验证 [ADR-0008](adr/0008-self-splash-jump.md)） |
| T5 | 关闭 `affect_player`，朝脚下右键 | 仅有爆炸视觉与周围物体推飞，角色不动 |
| T6 | 关闭 `recoil_enabled`，连续左键 | 角色完全不位移，仅有视觉反馈 |
| T7 | 鼠标 click + 键 Q | 在 click 点直接生成 Effect，验证 Effect 独立可测 |
| T8 | 角色被推飞撞 arena 墙 | 不出场；按 R 重置回原点 |

### 5.2 架构验证

- Effect 不 import 任何 Weapon / Projectile 类型（grep 验证）
- DamageField 不 import 任何 Constraint 类型（grep 验证）
- 替换 Weapon 的 `projectile_scene` → 行为变化但其他代码不动
- 替换 Projectile 的 `effect_scene` → 行为变化但其他代码不动

### 5.3 性能验证

- 测试场景启动后稳定 60fps
- 连续高频开枪 30 秒 → 帧率不雪崩（Projectile 销毁正常）
- 高速直射弹打薄墙无穿透（CCD 工作）

---

## 6. 风险与未决问题

| 风险 | 缓解 |
|---|---|
| Box2D GDExt 不暴露 AABB query API | 退回到全局 body 列表 + 距离过滤（v1 规模可接受） |
| Box2D GDExt CCD 不可用 / 不可靠 | 子步细分 + raycast 校正（仍是物理弹，不退 hitscan） |
| 自爆跳过于强大，喧宾夺主 | 接受 —— 本原型目的就是验证物理统一；调参降冲量即可 |
| 后坐力让玩家"开枪 = 漂移"难控制 | v1 量级保守（1-2 N·s）；可关闭 |
| Effect 视觉时长与销毁时序竞态 | 视觉子节点独立 await，Effect 主体在 query 完成即可销毁 |

**未决问题（实现时定）：**
- Effect 子组件是 Resource 还是 Node（[ADR-0010](adr/0010-weapon-projectile-effect-decomposition.md) Open Question）
- DamageField 命中 player 是否调用 `player.take_damage`（v1 玩家无血量，跳过）
- 抛物线辅助线是否做（v1.5 项）

---

## 7. 后续步骤

v1 通过后：

1. **接入完整破坏框架**：把 dummy 换成 Block，验证伤害转发到 Constraint 的端到端链路（[ADR-0007 Path X](adr/0007-effect-dual-channel.md)）
2. **联动 3C 增强**：自爆跳作为新机动方式纳入设计语言
3. **武器扩展**：钩爪枪、霰弹、激光等新组合 —— 三元组架构应零修改支撑
4. **Effect 视觉升级**：粒子、屏幕震动、音效
5. **子弹时间**：Engine.time_scale，所有 Projectile 一起慢放（[ADR-0009](adr/0009-direct-shot-is-physics-projectile.md) 自然支持）
