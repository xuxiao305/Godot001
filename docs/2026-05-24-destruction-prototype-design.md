# 2D 物理动作冒险 — 体块化破坏框架原型设计

| 字段 | 值 |
|---|---|
| 日期 | 2026-05-26（grill-with-docs 对齐重写） |
| 状态 | Draft（待审） |
| 引擎 | Godot 4.x + Rapier2D（通过 godot-rapier-physics GDExtension） |
| 所属项目 | PlatformerPhysics |
| 文档定位 | 系列第 2A 个原型；家族 B（可破坏环境）核心；为后续"塌陷废墟逃脱" setpiece 奠基 |

**相关文档：**
- [项目总览.md](项目总览.md) §1 / §2.5 物理统一优先 / §3 引擎约束
- 术语精确定义见 [CONTEXT.md](CONTEXT.md)（Block / Constraint / 统一伤害语言 / 伤害传递 / 冲击伤害）
- 关键架构思想同源：[ADR-0001 内在发动机派](adr/0001-inner-engine-school.md)（角色物理本体论 → 推广到环境物理本体论）
- 跨 spec 契约：[ADR-0007 Effect 双通道 + 统一伤害语言 + 单向依赖](adr/0007-effect-dual-channel.md)
- 武器系统对接：[weapon-prototype-design.md](weapon-prototype-design.md)（通过 take_damage 契约调用本系统）

---

## 1. 背景

### 1.1 大项目背景

PlatformerPhysics 是个人技术 demo + 学习项目，**不发布完整游戏**。本原型对应 [项目总览.md](项目总览.md) §4 家族 B（可破坏环境）的核心子原型："分块破坏（约束断裂）"。

### 1.2 为什么先做这个

- 家族 B 是项目愿景"2D 神秘海域 setpiece"的核心 ——"塌陷废墟逃脱"、"被巨物压垮"、"爆炸轰开墙"全靠它
- Rapier2D 在这块"白送"（[项目总览.md §3](项目总览.md)），跑通成本低，学习价值高
- 与家族 D（武器/爆炸）通过 [ADR-0007](adr/0007-effect-dual-channel.md) 契约对接 —— 武器系统已可用，其 Effect（RadialDamage + RadialBlast）直接作为本原型的伤害源
- 与 3C 解耦：本原型作为独立沙盒 demo，不依赖角色（但可共用武器系统）

### 1.3 成功标准

| # | 标志 |
|---|---|
| 1 | 单面砖墙能被武器射击（点伤/爆炸）打穿缺口，上层失支撑时自然下落 |
| 2 | 拱门：炸掉一根柱子，房顶通过伤害传递 + ImpactWatcher 自然演化塌方（v1 仅伤害路径；应力路径断裂 defer v2，拱门塌方表现"横梁一侧掉一截"通过 F6 验收） |
| 3 | 自由翻滚的体块掉在其他体块上，能因冲击伤害打破下层 |
| 4 | 所有破坏行为来自统一双机制（Block 血量、Constraint 伤害路径、冲击伤害），无特例代码 |
| 5 | Block.take_damage 自然把伤害传递到周围 Constraint —— 一次 RadialDamage 既扣体块血又削弱约束（[ADR-0007](adr/0007-effect-dual-channel.md)） |
| 6 | 关键参数能在 runtime 用 debug 面板实时调 |
| 7 | 中等规模场景（~1000 体块）稳定 60fps，且架构能向大规模无痛升级 |

---

## 2. 设计哲学

### 2.1 核心理念

**结构稳定性从 Rapier2D 解算自然涌现，不显式建模。**

[ADR-0001 内在发动机派](adr/0001-inner-engine-school.md) 的环境推广版：

| 维度 | 角色侧（ADR-0001） | 环境侧（本原型） |
|---|---|---|
| 物理本体 | Dynamic body | Dynamic body（每个 Block） |
| 行为来源 | 力、冲量、摩擦、重力 | Constraint（Flex 单 PinJoint / Weld 单 PinJoint + lock_rotation，详见 §4.2）力、重力、冲量、摩擦 |
| 设计杠杆 | 发动机转速曲线、跳跃冲量 | Block 血量、Constraint 血量、冲击伤害系数 |
| 涌现结果 | setpiece 自然涌现，无特例 | 塌方/断裂自然涌现，无承重逻辑 |

具体例：用户场景"房顶 + 两柱"——

1. 一根柱子被炸碎 → 该柱 Block 逐个销毁
2. 其上方"房顶段"失去 Constraint 支撑 → 重力让该段下沉
3. 房顶中段的 Constraint 受拉力（一端下沉、一端被另一柱固定）
4. v2 应力路径：应力超阈值 → Constraint 自动断 → 房顶中段断开
5. 一侧塌、另一侧稳定

整个过程没有任何"承重逻辑"代码，全是 Rapier2D 解算的物理涌现。v1 仅通过伤害路径（伤害传递到 Constraint）和 ImpactWatcher 实现破坏，应力路径 defer 到 v2。

### 2.2 与项目方法学的一致性

- **物理统一优先（[项目总览 §2.5](项目总览.md)）**：所有结构行为走纯物理通道；不加魔法
- **范围克制（YAGNI）**：MVP 一种材质、一种 Block 尺寸、编辑器手动摆场景、不做性能优化
- **原型驱动**：独立 demo 跑通，不接 3C 角色
- **单向依赖（[ADR-0007](adr/0007-effect-dual-channel.md)）**：本系统对武器系统零感知；只暴露 take_damage 接口

### 2.3 破坏机制

| 机制 | 触发条件 | 直接效果 | 间接耦合 |
|---|---|---|---|
| **Block 销毁** | 血量 ≤ 0 | body 销毁、连到它的所有 Constraint 自动失效（pin 由 Rapier 自动 invalidate） | 邻居失去局部约束；视觉碎片 defer v2 |
| **Constraint 断裂（伤害路径）** | Constraint 血量 ≤ 0 | 该 Constraint 销毁，但两端 Block 保留 | 局部失去刚性，但块仍可独立 |
| **冲击伤害** | 接触点 normal impulse > 阈值 | 双方 Block 按 (impulse - 阈值) × 系数 扣血 | 可链式触发"销毁→碎块掉落→撞到下方→冲击伤害→新销毁" |

v2 增加：
| **Constraint 断裂（应力路径）** | PinJoint 内部应力 > stress_threshold | 该 Constraint 自动断 | 纯物理涌现，无代码干预 |

各机制独立但耦合：销毁会让邻居约束受力突变；冲击会扣 Block 血（触发 Block 销毁，并通过伤害传递削弱 Constraint）；Constraint 断裂不直接扣 Block 血。

### 2.4 跨 spec 契约（[ADR-0007](adr/0007-effect-dual-channel.md)）

本系统对外暴露 **统一伤害语言**：

```
Block.take_damage(amount: float, point: Vec2, source) -> void
Constraint.take_damage(amount: float, point: Vec2, source) -> void
```

**关键不变量**：
- 外部（武器、未来 AI、陷阱）只调用 take_damage；不知道 Constraint 的存在
- Block.take_damage 内部按 `damage_propagation_ratio = 0.3` 传递给所有相连 Constraint（详见 [ADR-0007](adr/0007-effect-dual-channel.md)）
- Constraint 有自己的血量，可以被"打弱"而不必直接打到应力阈值（v2 引入）

后果：外部一次 RadialDamage 命中一片 Block → 每个 Block 既扣自己血又削弱周围所有 Constraint → 自然形成"塌"而非"碎"的可能。

### 2.5 "物体 vs Block" 的演进路径

"物体（Structure）"在本框架里只是**关卡构造期**的概念（如"房子"、"柱子"、"桥"由编辑器手动摆 cube）。**运行期没有物体实体**，只有 Block + Constraint。

| 阶段 | 物理表示 | 视觉表示 | 说明 |
|---|---|---|---|
| **v1** | 始终是 N 个独立 Block + Constraint 网络 | 每个 Block 独立显示色块/sprite | **MVP 默认**：最简、最易调试 |
| **v2** | 同 v1（不变） | 可选：一组未被打扰的相连 Block 自动合并 sprite 覆盖 | 视觉升级，物理不变 |

v1 不做 visual merge（YAGNI）。

---

## 3. 范围

### 3.1 ✅ v1（MVP）必须包含

物体始终是 N 个独立 Block + Constraint；视觉每个 Block 独立显示。

- **Block**：等大正方形 RigidBody2D dynamic body，自由旋转，自带血量，实现 take_damage
- **Constraint**：相邻 Block 之间一根 PinJoint2D，**两种 kind（Flex / Weld，详见 §4.2）**，自带血量，实现 take_damage
- **伤害源**：对接已有武器系统 —— Effect 的 RadialDamage（伤害通道）+ RadialBlast（力通道）通过 take_damage 契约驱动破坏（单向依赖）
- **冲击伤害（ImpactWatcher）**：物体间碰撞 normal impulse 超阈值自动调用 Block.take_damage
- **Block 销毁**：血量归零 → 通过 DestructionPipeline 直接删除 body（相连 Constraint 自动失效）；掉落的碎块由物理引擎自然演化至 sleep
- **Constraint 断裂（伤害路径）**：自身血量 ≤ 0 → 通过 DestructionPipeline 销毁
- **伤害传递**：Block.take_damage 内部按 damage_propagation_ratio 传递给所有相连 Constraint
- **批量拓扑变更**：所有 body/joint 销毁在 _physics_process 末尾通过 DestructionPipeline 批处理
- **3 个测试场景**（GridStructure 编辑器手动摆 cube）：砖墙、拱门、三层小屋
- **Debug 面板**：runtime 调所有阈值与参数；屏显 FPS / 活跃 Block 数 / 活跃 Constraint 数 / 本帧销毁数；两个机制独立开关（伤害传递、冲击伤害）

### 3.2 🔴 v2（独立子原型，本文档不涉及）

- **真 FixedJoint2D**：fork godot-rapier-physics 在 2D 层暴露 FixedJoint → 替代 WeldConstraint 当前的 lock_rotation 方案 → 支持混合材质（per-pair 而非 per-body 的旋转锁定）
- **应力路径断裂**：fork rapier 暴露 reaction force → Constraint 应力超阈值自动断
- **视觉合并**：一组未被打扰的相连 Block 自动合并 sprite
- **物体状态机**：未破坏时单 compound body + 整体 sprite
- 接入 3C 角色（角色能站在 Block 上、被砸、推动）
- 多材质 / 各向异性约束（横纹 vs 纵纹）—— 需要 FixedJoint 前置
- 性能优化：Block 对象池、销毁分摊到多帧、spatial hash 邻居查找
- 编辑器关卡格式（Tiled / 自定义 .json）

### 3.3 ⚫ 明确不在本项目

- 真 Voronoi / 任意凸多边形切割（保持等大正方形 Block）
- 像素材料系统（Noita 风，[项目总览 §3](项目总览.md) 明示超出物理引擎时间预算）
- 逻辑承重图 / 结构分析（违反"物理统一优先"）

---

## 4. 详细规格

### 4.1 Block（体块）

**世界参数**：重力 9.8 m/s² 垂直向下；物理步长 1/60 s。

| 属性 | 值 | 备注 |
|---|---|---|
| Body Type | Dynamic | 全程不改 |
| Fixed Rotation | false | Block 要能自由翻滚 |
| Shape | Box，边长 = `block_size`（默认 25 px = 0.25 m @ 100 px/m） | 等大正方形 |
| Density | 1.0 → mass ≈ 0.1 kg | 原 spec 写 0.00625 是过轻的偷懒值（自重冲量低于 impact_threshold 才不会误伤 constraint）；ImpactWatcher first-contact 门（§4.3）加上后可用真实质量 0.1 |
| Friction | 0.6 | 砖石质感 |
| Restitution | 0.05 | 几乎不弹 |
| Linear Damping | 0.05 | 微阻尼避免漂移噪声 |
| Angular Damping | 0.1 | 翻滚有阻尼 |
| Collision Layer | `block` | 新增 |
| Collision Mask | `block` + `world` + `projectile` | v2 再加 `player` |
| `initial_health` | 100 | 可在材质参数包里覆盖 |
| `damage_propagation_ratio` | 0.3 | 传递给相连 Constraint 的比例（详见 [ADR-0007](adr/0007-effect-dual-channel.md)） |

**接口**：

```
take_damage(amount: float, point: Vec2, source):
    if _queued_for_destroy:
        return
    health -= amount
    for c in connected_constraints:
        c.take_damage(amount * damage_propagation_ratio, point, source)
    if health <= 0:
        _queued_for_destroy = true
        DestructionPipeline.queue_block_destroy(self)

signal block_destroyed(position)  # 预留信号占位，v1 暂无消费者
```

**关键**：
- take_damage 是**统一伤害语言**（[ADR-0007](adr/0007-effect-dual-channel.md)）的实现 —— 武器系统的 DamageField 直接调用此方法
- 传递给 Constraint 的比例 `damage_propagation_ratio` 是 Block 属性（v1 全局默认 0.3，未来可按材质覆盖）
- Block.take_damage **不**直接处理冲量；冲量由调用方（ForceField / 碰撞）独立施加

### 4.2 Constraint（约束）—— Flex / Weld 两种 kind

每对相邻 Block 之间一根 Constraint 封装，**带血量 + 伤害路径断裂**。v1 实装两种 kind 对应两种材质行为；由 GridStructure 的 `constraint_kind` 枚举（FLEX=0 / WELD=1，默认 WELD）选用。

#### 4.2.1 为什么不用最初 spec 设想的 "angular_limit=0 一根 pin = weld"

实测验证（本会话）：
- Rapier 的 `RevoluteJoint.limits([0, 0])` 是**软约束**（iterative PGS solver + corrective force），在 mass = 0.1 的堆叠墙下肉眼可见相对旋转
- 经典 Box2D **2-pin trick**（同对 body 两根 PinJoint）在 Rapier 也失效——多个 ImpulseJoint 共享 body pair 时被当作过约束系统，每次 iteration 互相破坏，宏观仍软
- 真正的 weld 在 Rapier 内核里是 `FixedJoint`（GenericJoint + LOCKED_AXES，单关节 3 DOF 全锁），但 **godot-rapier-physics 2D 层未暴露**——defer v2 fork

v1 折中：**Flex = 单 PinJoint，不锁旋转；Weld = 单 PinJoint + per-block `lock_rotation = true`**。lock_rotation 把 body 的 inertia_inverse 设 0，物理上根本算不出角加速度——绕过整个约束求解器、不依赖 solver 迭代收敛。代价是它是 body-level 的（块绑定 weld 期间所有方向都不能转，无法表达"对邻居 A 焊死、对邻居 B 铰链"的混合材质），这部分留给 v2 FixedJoint 解决。

#### 4.2.2 FlexConstraint

| 属性 | 值 | 备注 |
|---|---|---|
| Joint | 单 PinJoint2D | 仅锁位置；角度自由 |
| disable_collision | true | 邻居对之间无需碰撞 |
| `initial_health` | 50（默认；可被 GridStructure.constraint_health 覆盖） | 伤害路径断裂阈值 |

行为：两端 Block 可绕 pin 自由旋转。视觉上像绳网 / 木栅 / 织物——软体感。

#### 4.2.3 WeldConstraint

| 属性 | 值 | 备注 |
|---|---|---|
| Joint | 单 PinJoint2D | 同 Flex |
| disable_collision | true | 同上 |
| `initial_health` | 50（默认） | 同上 |
| **副作用 1** | `create` 时把 block_a/b 的 `lock_rotation = true` | 幂等（多次设 true 无害） |
| **副作用 2** | `destroy` 时若 Block.connected_constraints 全空 → 解锁 `lock_rotation = false` | 孤块得以自由翻滚 |

行为：bonded 期间两端 Block 物理上无法旋转，构成真刚体壳。失去最后一根 weld → 解锁，作为自由刚体下坠 + 翻滚。

#### 4.2.4 共享接口

```
take_damage(amount: float, point: Vec2, source):
    if _queued_for_destroy:
        return
    health -= amount
    if health <= 0:
        DestructionPipeline.queue_constraint_destroy(self)
```

duck-typed —— Block.connected_constraints 持的可以是任一 kind，take_damage 调用方不区分。

**断裂路径**：
- **伤害路径（v1）**：health ≤ 0 入销毁队列（两种 kind 都走）
- **应力路径（v2）**：fork godot-rapier-physics 暴露 `joint.impulses()` → Constraint 自检反力 → 超 stress_threshold 入销毁队列。**独立于伤害路径**，不经 ImpactWatcher

数据类：`class_name FlexConstraint extends RefCounted` / `class_name WeldConstraint extends RefCounted`。两类并行不继承共同基类（v1 简化；共享代码 ~25 行，未来若材质多了可重构）。

### 4.3 伤害源 — 武器系统 Effect（v1）

Block 系统本身不提供伤害源。v1 的伤害源由已有的武器系统提供（[weapon-prototype-design.md](weapon-prototype-design.md)）：

- **RadialDamage**：圆形 AOE，linear falloff 衰减，对范围内每个 body duck-typing 调 `take_damage(amount, point, source)`
- **RadialBlast**：圆形 AOE，linear falloff，对范围内每个 RigidBody2D 施加径向冲量 `apply_central_impulse`
- 两通道完全独立，同一 Effect 可同时挂两者（爆炸 = RadialDamage + RadialBlast）

武器 Demo 场景 (`weapon_demo.tscn`) 可直接作为破坏沙盒的入口：角色持武器对 Block 结构开火，子弹命中或爆炸触发 Effect → DamageField 调 Block.take_damage → 伤害传递到 Constraint → 破坏涌现。

若需要无角色的纯破坏沙盒，可在 demo 场景中加一个最小鼠标点击 spawn Effect 的 helper（不复刻 debug_input 的完整逻辑，直接复用武器系统的 Effect 实例化）。

**冲击伤害（ImpactWatcher）**：
- 通过 `_integrate_forces` + `get_contact_impulse()` 取 normal impulse `J`
- 仅处理 `other is Block` 的接触对（排除 ground/projectile/player 等）
- 若 `J > impact_threshold`（2 N·s）→ 双方 Block 各扣 `(J − threshold) × impact_coefficient`（系数 10）
- 伤害事件入 `damage_events` 队列，下一帧 _physics_process 开始时统一派发（不在 contact callback 内直接调 take_damage）
- ImpactWatcher 也走 Block.take_damage 接口 —— 自动享受伤害传递到 Constraint

**First-contact 门（v1 关键设计补充）**：

Block._integrate_forces 维护 `_prev_contact_ids: Dictionary`，仅当某对 (self, other) **上一帧不接触、本帧接触**时才上报到 ImpactWatcher；持续接触的后续帧全部跳过。**目的**：分离"外力（事件）"与"自重传递（稳态）"两种语义不同但 contact_impulse 信号相同的场景——

| 物理现象 | 信号来源 | 我们希望它扣血吗？ | 解法 |
|---|---|---|---|
| 外部冲击（debris 砸下、projectile 撞 block） | contact_impulse 瞬态尖峰 | 是（spec §4.3 原意） | first-contact 命中 → 触发 |
| 自重传递（堆叠墙的内部接触压力） | contact_impulse 稳态值 | 否（不是 "impact"） | 接触建立首帧后跳过 |
| 结构应力（重物压上去把柱子压垮） | **joint reaction force**（独立信号） | v2 才处理 | v2 应力路径，与 contact_impulse 路径完全不交叉 |

关键事实：**外力与应力在 Rapier 内部走不同 API**——`contact_impulse` 是接触面信号，`joint.impulses()` 是关节反力。两者不混淆。v1 只用前者实现伤害路径；v2 加后者实现应力路径，**不需要改 ImpactWatcher**。

注意原 spec 设的 `impact_threshold = 2` 是在 mass = 0.00625 的世界里校的——那时自重冲量天然低于阈值掩盖了误伤问题。mass 抬到 0.1 后，settling 期对角邻居（无 PinJoint 屏蔽）的角点接触能产生 J = 5~7，远超阈值；没有 first-contact 门的话，constraint_health 会被持续磨干。

### 4.4 批量拓扑变更（关键不变量）

所有改物理拓扑的操作（销毁 body、销毁 PinJoint）**只能**在 `_physics_process` 末尾、Rapier 完成本帧解算之后批量执行。不在 contact callback 或碰撞回调中途直接 `queue_free()`—— 否则 Rapier 内部数据结构在求解中途被破坏，行为未定义。

实现：单例 `DestructionPipeline` 维护 2 个队列 + 1 个事件队：
- `damage_events`（伤害事件队，含 ImpactWatcher + 武器 DamageField 产生的伤害）
- `constraint_destroy_queue`
- `block_destroy_queue`

`_physics_process` 顺序：
1. **派发** `damage_events` → 调用 `Block.take_damage` / `Constraint.take_damage` → 内部更新血量 + 传递 → 0 血进入相应 destroy queue
2. **扫所有接触点** 冲量 → 入 `damage_events`（下一帧处理）
3. **帧末批处理**：
   - 清 `constraint_destroy_queue` → 销毁 PinJoint
   - 清 `block_destroy_queue` → 销毁 body（自动断开剩余 PinJoint）

### 4.5 视觉碎片

v1 不做销毁特效（粒子/碎片飞溅）。Block 血量归零直接 `queue_free()` 删除，散落的孤块由物理引擎自然演化至 sleep。Block 销毁时预留 `block_destroyed` 信号占位（v1 无消费者，v2 接 GPU 粒子或其他视觉效果）。

**每块自带 Polygon2D Visual 子节点已实装**（spec §2.5 / §3.1 早就承诺的"独立色块"）：[BlockFactory.create](../Scripts/Prototypes/Destruction/block_factory.gd) 中 add 一个 25×25 半透明米灰方块（alpha 0.75），便于看出每块的位置；alpha 留出空间让 ConstraintVisualizer 的彩线（血量颜色）能透过来。B-key 调试落块改成 override 该 Visual 颜色为红区分。

### 4.6 场景构造（GridStructure）

三个测试场景全部通过 GridStructure Prefab 构造：在编辑器中手动摆放 cube 子节点 → `_ready()` 运行时自动扫描邻居建 Constraint。

**场景 1：砖墙**
- 10 × 10 Block，紧密排列，底层落在 static body 地面上

**场景 2：拱门**
- 两根柱：各 5 高 × 1 宽，柱中心距 6 个 block_size
- 一根横梁：1 高 × 7 宽，搁在两柱顶

**场景 3：三层小屋**
- 两侧墙各 6 高 × 1 宽
- 三层楼板各 1 高 × 8 宽，与两墙接触行建 Constraint
- 屋顶 1 高 × 8 宽

**为何运行时构建约束**：编辑器 tool 脚本开发调试困难、容易崩溃 Godot 编辑器。运行时 `_ready()` 扫描建约束完全规避此问题。

**邻居建 Constraint 算法**：

- **判定基准**：两 Block 中心点欧氏距离 ≤ `block_size × 1.05` 视为邻居
- **几何后果**：该阈值排除对角邻居。每个 Block 最多 4 个邻居（上下左右），不是 8 个。砖墙因此是"横平竖直的网格刚性"而非"任意方向都焊死的实体"——断裂面倾向于沿轴向，符合砖墙直觉
- **实现**：每个邻居对 = 1 根 PinJoint2D，pin 锚点在共享边中点；Weld kind 额外把两端 Block.lock_rotation 拨成 true（详见 §4.2）
- **算法**：MVP 用 O(N²) 枚举（构造期一次性开销，1000 块约 50 万次比较可忽略），规模升级后换 spatial hash

**Constraint 的生命周期不变量**：

- **构造期建立不走 DestructionPipeline**：GridStructure 在 `_ready()` 中直接创建 PinJoint + 注册 Constraint，不需要批处理
- **运行期只销毁、绝不新建**：DestructionPipeline 没有 `constraint_create_queue`。两块散落 Block 重新接触**不会自动焊上**；一旦 Constraint 断开，那对 Block 永远物理独立。破坏不可逆。
- **Block 销毁时连接的 Constraint 由物理引擎自动 invalidate**：销毁 body 时挂在其上的 PinJoint 自动失效。Constraint 遍历时通过 `is_instance_valid` 过滤清理。

### 4.7 输入

- 武器开火（Projectile 命中 / Effect 触发）：自然驱动破坏（走 ADR-0007 契约）
- `F1` 切换 debug 面板
- 数字键 `1` / `2` / `3` 切换场景（重新加载 .tscn，因 cube 是手动摆放的）

### 4.8 Debug 面板（runtime 调参）

可调：
- `block_initial_health`、`damage_propagation_ratio`
- `constraint_initial_health`
- `impact_threshold`、`impact_coefficient`
- `block_size`（切换后重载场景）

屏显：
- FPS、活跃 Block 数、活跃 Constraint 数
- 本帧：派发伤害事件数、销毁 Block 数、销毁 Constraint 数（伤害路径）
- 两个机制独立开关（debug）：关闭"伤害传递"、关闭"冲击伤害" —— 便于隔离调试

### 4.9 调参初值

| 参数 | 类内默认 | demo 期实测值 | 调参方向 |
|---|---|---|---|
| `block_size` | 25 px（0.25 m @ 100 px/m） | 25 | 越小越细腻、越吃性能 |
| `block_initial_health` | 100 | **5000**（brick_wall.tscn WallBuilder 覆盖） | 高 = 耐打；高 hp + 高 propagation_ratio 让 constraint 先断、block 后死，更符合"砖墙剥落"语义 |
| `constraint_initial_health` | 50 | **100**（brick_wall.tscn 根节点覆盖） | 高 = 难通过伤害断 |
| `damage_propagation_ratio` | 0.3 | 0.3 | 高 = Block 受伤更易带塌邻居 |
| `impact_threshold` / `coefficient` | 2 N·s / 10 | 2 / 10 | threshold 越低越脆，coef 越高越脆；first-contact 门（§4.3）让本组值在 mass=0.1 下不再误触发 |
| `mass`（Block） | 0.00625（spec 原值） | **0.1**（block_factory.gd） | 原 0.00625 是为压低自重冲量到 threshold 以下的偷懒值；first-contact 门加上后可用真实质量 |

类内默认（@export）是新建场景的兜底；实战推荐用 GridStructure.constraint_health / WallBuilder.block_health 在 Inspector 里逐场景覆盖（demo 期实测值就是这么校的）。

### 4.10 文件 / 模块划分

| 路径 | 职责 |
|---|---|
| `destruction/block.gd` | Block 状态机（血量、take_damage、伤害传递、销毁信号、`_prev_contact_ids` first-contact 门）—— class_name Block |
| `destruction/flex_constraint.gd` | FlexConstraint：单 PinJoint，不锁旋转 —— class_name FlexConstraint |
| `destruction/weld_constraint.gd` | WeldConstraint：单 PinJoint + per-block lock_rotation —— class_name WeldConstraint |
| `destruction/destruction_pipeline.gd` | 单例：3 队列 + damage_events + 帧末批处理 + 伤害派发 |
| `destruction/impact_watcher.gd` | 系统：监听接触冲量 → 转伤害事件入队（first-contact 过滤在 block.gd 一侧） |
| `destruction/block_factory.gd` | 工厂：创建 Block + 物理参数 + Visual Polygon2D 子节点（未来接对象池仅改内部） |
| `destruction/grid_structure.gd` | Prefab 脚本：扫描已有 cube → 按 constraint_kind 自动搭 Flex 或 Weld → 协调 visualizer |
| `destruction/wall_builder.gd` | 程序化生成 brick_wall / arch / house 三种 pattern 的 cube 布局 |
| `destruction/constraint_visualizer.gd` | 可视化：根据约束血量画彩色连线 |
| `destruction/debug_panel.gd` | runtime 调参 UI（F1 显隐 + 2 个机制开关） |
| `destruction/destruction_demo.gd` / `.tscn` | 主场景控制器 + 场景；集成 Player + Weapon 系统 |
| `destruction/grid_structure.tscn` | GridStructure PackedScene Prefab |
| `destruction/scenes/{brick_wall,arch,house}.tscn` | 三个测试场景实例（GridStructure + ConstraintVisualizer + WallBuilder） |

### 4.11 GridStructure Prefab —— 可复用约束组装 Prefab

**目标**：自包含 PackedScene Prefab，拖入场景后自动扫描已有 RigidBody2D cube 子节点，检测邻居关系并创建约束，配合可视化展示约束网络。

cube 在编辑器中手动摆好（或从别处导入），脚本负责"识别邻居 → 自动搭约束 → 可视化"。

#### 4.11.1 使用流程

1. 把 `grid_structure.tscn` 拖入场景
2. 在此节点下放入 RigidBody2D cube（手动拖拽或在编辑器中 copy-paste）
3. 在 Inspector 配置 `block_size`、`constraint_health` 等参数
4. 运行 —— `_ready()` 自动扫描子节点、建邻居约束、开始可视化

#### 4.11.2 邻居检测算法（见 §4.6）

- 两 cube 中心点欧氏距离 ≤ `block_size × 1.05` 视为邻居
- 排除对角（对角距离 ≈ block_size × √2 ≈ 1.414 × block_size）
- 每对邻居最多 4 个（上下左右），不是 8 个
- MVP 用 O(N²) 枚举（构造期一次性开销）

#### 4.11.3 Constraint 实现：单 PinJoint + 按 kind 决定旋转处理

详见 §4.2。简要：

| Kind | Joint 配置 | 旋转处理 |
|---|---|---|
| **Flex** | 单 PinJoint2D（disable_collision=true）；不依赖 angular_limit | 不锁——两端 Block 可绕 pin 自由旋转 |
| **Weld** | 同上 | `create` 时把 block_a/b 的 `lock_rotation = true`；`destroy` 时若该 Block.connected_constraints 全空则解锁 |

> **历史注**：spec 初稿曾写 "angular_limit_lower=upper=0 等效 weld"——实测在 Rapier 失效（软约束 + PGS solver 折半收敛）；2-pin Box2D trick 同样失效（过约束）。详见 §4.2.1。

#### 4.11.4 GridStructure 根节点脚本

`class_name GridStructure extends Node2D`

| Export 参数 | 类型 | 默认值 | 用途 |
|---|---|---|---|
| `block_size` | float | 25.0 | 邻居判定阈值 |
| `constraint_health` | float | 50.0 | 新建约束初始血量 |
| `auto_build` | bool | true | `_ready()` 时自动扫描并搭约束 |
| `constraint_kind` | int (enum) | WELD (1) | FLEX=0 / WELD=1，详见 §4.2 |
| `pipeline` | DestructionPipeline | null（运行时注入） | 注入，约束创建后注册到 pipeline |

**核心方法**：

```
_ready():
    if auto_build:
        build_constraints()

build_constraints():
    blocks := 扫描所有 RigidBody2D 子节点
    for each 邻居对 (a, b):
        创建 PinJoint2D（angular_limit=0，共享边中点）
        _constraints 记录 Constraint 对象
    通知 ConstraintVisualizer 更新数据（传入 _blocks, _constraints）
```

#### 4.11.5 ConstraintVisualizer 可视化脚本

`class_name ConstraintVisualizer extends Node2D`

在 `_draw()` 中用 `draw_line()` 画约束连线。

| Export 参数 | 类型 | 默认值 | 用途 |
|---|---|---|---|
| `enabled` | bool | true | 是否显示 |
| `healthy_color` | Color | GREEN | 血量 > 50% |
| `warning_color` | Color | ORANGE | 血量 30-50% |
| `critical_color` | Color | RED | 血量 < 30% |
| `line_width` | float | 2.0 | 连线宽度 |

**数据流**：`GridStructure` 构建完约束后调用 `set_data(blocks, constraints)`，visualizer 持有引用，每帧 `queue_redraw()` 更新颜色。

---

## 5. 测试与验证

### 5.1 功能验证（手动 demo）

| # | 操作 | 期望 |
|---|---|---|
| T1 | 场景 1，武器点伤同一 Block 直到血量归零 | 该 Block 消失，相邻 Block 因 Constraint 断开会部分掉落 |
| T2 | 场景 1，武器打穿一条竖线 | 上方 Block 部分下落（边缘的因 Constraint 仍能挂住） |
| T3 | 场景 1，爆炸范围伤害命中墙面 | 中心块伤害最高，周围按距离衰减；可能整组塌（伤害传递让多个 Constraint 同时断） |
| T4 | 场景 2，爆炸炸柱底 | 该柱塌；横梁一侧失去支撑自然掉落（应力路径 defer v2，此表现为预期行为） |
| T5 | 场景 3，多次爆炸 | 整体倾斜塌陷 |
| T6 | 任意场景，高空掉一个 Block 到下方 | 接触瞬间 normal impulse 高 → 下方块通过 take_damage + 伤害传递可能直接打散一片 |
| T7 | 关闭"伤害传递"开关，重复 T3 | 中心块销毁，但周围结构基本保留（验证伤害传递是否在起作用） |

### 5.2 性能验证

- 最大测试场景（~1000 block）稳定 60fps（基线机型：i5 / 集显）
- 大规模爆炸瞬间无明显卡顿（帧时间 < 16.6 ms）
- Debug 面板的活跃 Block 数 / 帧销毁数实时显示

### 5.3 架构验证

- 所有 body/joint 拓扑变更都通过 DestructionPipeline 走，不出现物理引擎异常
- Block 通过 BlockFactory 创建，未来接对象池仅改工厂内部，不动消费者
- 伤害传递和冲击伤害的开关能在 debug 面板独立关闭，便于隔离调试
- **跨 spec 契约验证**：Block.take_damage / Constraint.take_damage 签名与 [ADR-0007](adr/0007-effect-dual-channel.md) 一致；模块内无 `weapon` / `projectile` / `effect` import（单向依赖）

---

## 6. 后续步骤

v1 通过后：

1. **真 FixedJoint2D（v2 优先）**：fork godot-rapier-physics 在 2D 层加 `rapier_fixed_joint_2d.rs`（仿 `rapier_revolute_joint_2d.rs` 结构，构造 Rapier 的 GenericJoint + LOCKED_AXES 锁全 3 DOF）。**WeldConstraint 用 FixedJoint 替代 lock_rotation**：好处是 per-pair 约束（能表达"对邻居 A 焊死、对邻居 B 铰链"的混合材质，lock_rotation 是 body-level 一刀切做不到），且天然不过约束（单关节锁 3 DOF）。
2. **应力路径（v2）**：fork godot-rapier-physics 加 PinJoint / FixedJoint 的 `joint.impulses()` reaction force binding → Constraint 自检反力超 stress_threshold 自动断裂 → 拱门塌方等纯物理涌现完整还原。**与 ImpactWatcher 走完全独立路径**（contact_impulse vs joint reaction force，两套 API，互不混淆）；v1 时为弥补缺应力路径，结构通过冲击伤害链式传递近似"重物压垮"，但不是真应力测量。
3. **视觉合并**：一组未被打扰的相连 Block 自动合并 sprite 覆盖
4. **联动 A（3C）**：接 3C 角色 —— 角色能站在 Block 上、被砸、推动 → 联调到"塌陷追逐" setpiece 雏形
5. **材质扩展**：引入 Brick / Wood / Stone 等参数包；混合材质场景（一面墙部分 Flex 部分 Weld）—— 此时 1 的 FixedJoint 路径成为前置条件
6. **性能优化**：Constraint 邻居 O(N²) → spatial hash、Block 对象池
7. **视觉碎片 / 销毁特效**：Block 销毁时接 GPU 粒子或 sprite 碎片飞溅（block_destroyed 信号已预留）
