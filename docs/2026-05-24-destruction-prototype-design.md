# 2D 物理动作冒险 — 体块化破坏框架原型设计

| 字段 | 值 |
|---|---|
| 日期 | 2026-05-24（基于跨 spec 对齐 grill 重写） |
| 状态 | Draft（待审） |
| 引擎 | Godot 4.x + Box2D（通过 GDExtension） |
| 所属项目 | PlatformerPhysics |
| 文档定位 | 系列第 2A 个原型；家族 B（可破坏环境）核心；为后续"塌陷废墟逃脱" setpiece 奠基 |

**相关文档：**
- [项目总览.md](项目总览.md) §1 / §2.5 物理统一优先 / §3 引擎约束
- 术语精确定义见 [CONTEXT.md](CONTEXT.md)（Block / Constraint / 统一伤害语言 / 伤害转发 / 冲击伤害）
- 关键架构思想同源：[ADR-0001 内在发动机派](adr/0001-inner-engine-school.md)（角色物理本体论 → 推广到环境物理本体论）
- 跨 spec 契约：[ADR-0007 Effect 双通道 + 统一伤害语言 + 单向依赖](adr/0007-effect-dual-channel.md)
- 武器系统对接：[weapon-prototype-design.md](weapon-prototype-design.md)（独立开发，通过 take_damage 契约调用本系统）

---

## 1. 背景

### 1.1 大项目背景

PlatformerPhysics 是个人技术 demo + 学习项目，**不发布完整游戏**。本原型对应 [项目总览.md](项目总览.md) §4 家族 B（可破坏环境）的核心子原型："分块破坏（约束断裂）"。

### 1.2 为什么先做这个

- 家族 B 是项目愿景"2D 神秘海域 setpiece"的核心 ——"塌陷废墟逃脱"、"被巨物压垮"、"爆炸轰开墙"全靠它
- Box2D 在这块"白送"（[项目总览.md §3](项目总览.md)），跑通成本低，学习价值高
- 与家族 D（武器/爆炸）通过 [ADR-0007](adr/0007-effect-dual-channel.md) 契约对接 —— **本原型完全独立开发**：伤害源用鼠标 click（debug 输入），不依赖武器 spec
- 与 3C 解耦：本原型作为独立沙盒 demo，不依赖角色

### 1.3 成功标准

| # | 标志 |
|---|---|
| 1 | 单面砖墙能被左键点出洞、右键炸开缺口，上层失支撑时自然下落 |
| 2 | 拱门：炸掉一根柱子，房顶按"承重失衡 → 一侧塌 / 中段断"的物理直觉演化，**无需逻辑判定** |
| 3 | 自由翻滚的体块掉在其他体块上，能因冲击伤害打破下层 |
| 4 | 所有破坏行为来自统一三机制（血量、约束断裂阈值、冲击伤害），无特例代码 |
| 5 | Block.take_damage 自然把伤害转发到周围 Constraint —— 一次 RadialDamage 既扣体块血又削弱约束（[ADR-0007 Path X](adr/0007-effect-dual-channel.md)） |
| 6 | 关键参数能在 runtime 用 debug 面板实时调 |
| 7 | 小规模场景（~200 体块）稳定 60fps，且架构能向中/大规模无痛升级 |

---

## 2. 设计哲学

### 2.1 核心理念

**结构稳定性从 Box2D 解算自然涌现，不显式建模。**

[ADR-0001 内在发动机派](adr/0001-inner-engine-school.md) 的环境推广版：

| 维度 | 角色侧（ADR-0001） | 环境侧（本原型） |
|---|---|---|
| 物理本体 | Dynamic body | Dynamic body（每个 Block） |
| 行为来源 | 力、冲量、摩擦、重力 | Constraint（weld）力、重力、冲量、摩擦 |
| 设计杠杆 | 发动机转速曲线、跳跃冲量 | Block 血量、Constraint 断裂阈值、冲击伤害系数 |
| 涌现结果 | setpiece 自然涌现，无特例 | 塌方/断裂自然涌现，无承重逻辑 |

具体例：用户场景"房顶 + 两柱"——

1. 一根柱子被打穿 → 该柱 Block 逐个销毁
2. 其上方"房顶段"失去 Constraint 支撑 → 重力让该段下沉
3. 房顶中段的 Constraint 受拉力（一端下沉、一端被另一柱固定）
4. 反作用力超阈值 → Constraint 断 → 房顶中段断开
5. 一侧塌、另一侧稳定

整个过程没有任何"承重逻辑"代码，全是 Box2D 解算 + 阈值断裂的物理涌现。

### 2.2 与项目方法学的一致性

- **物理统一优先（[项目总览 §2.5](项目总览.md)）**：所有结构行为走纯物理通道；不加魔法
- **范围克制（YAGNI）**：MVP 一种材质、一种 Block 尺寸、硬编码场景、不做性能优化
- **原型驱动**：独立 demo 跑通，不接 3C 角色，不耦合武器系统
- **单向依赖（[ADR-0007](adr/0007-effect-dual-channel.md)）**：本系统对武器系统零感知；只暴露 take_damage 接口

### 2.3 三机制独立 / 耦合矩阵

| 机制 | 触发条件 | 直接效果 | 间接耦合 |
|---|---|---|---|
| **Block 销毁** | 血量 ≤ 0 | body 销毁、连到它的所有 Constraint 自动失效、生成视觉碎片 | 邻居失去局部约束 |
| **Constraint 断裂** | 物理路径：weld 反作用力/扭矩 > 阈值；伤害路径：Constraint 血量 ≤ 0 | 该 Constraint 销毁，但两端 Block 保留 | 局部失去刚性，但块仍可独立 |
| **冲击伤害** | 接触点 normal impulse > 阈值 | 双方 Block 按 (impulse - 阈值) × 系数 扣血 | 可链式触发"销毁→碎块掉落→撞到下方→冲击伤害→新销毁" |

三机制独立但耦合：销毁会让邻居约束受力突变（可能触发物理路径断裂）；冲击会扣 Block 血（可能触发 Block 销毁，并通过伤害转发削弱 Constraint）；Constraint 断裂不直接扣 Block 血。

### 2.4 跨 spec 契约（[ADR-0007](adr/0007-effect-dual-channel.md)）

本系统对外暴露 **统一伤害语言**：

```
Block.take_damage(amount: float, point: Vec2, source: DamageSource) -> void
Constraint.take_damage(amount: float, point: Vec2, source: DamageSource) -> void
```

**关键不变量**：
- 外部（武器、未来 AI、陷阱）只调用 take_damage；不知道 Constraint 的存在
- Block.take_damage 内部按 `damage_to_constraint_ratio = 0.3` 转发给所有相连 Constraint（[Path X](adr/0007-effect-dual-channel.md)）
- Constraint 有自己的血量，可以被"打弱"而不必直接打到反作用力阈值

后果：外部一次 RadialDamage 命中一片 Block → 每个 Block 既扣自己血又削弱周围所有 Constraint → 自然形成"塌"而非"碎"的可能。

### 2.5 "物体 vs Block" 的演进路径

"物体（Structure）"在本框架里只是**关卡构造期**的概念（如"房子"、"柱子"、"桥"由 LevelBuilder 拼出来）。**运行期没有物体实体**，只有 Block + Constraint。但"物体"在物理与视觉上的表示并非一步到位 —— 按三阶段演进，按需升级：

| 阶段 | 物理表示 | 视觉表示 | 触发升级条件 |
|---|---|---|---|
| **v1 = A** | 始终是 N 个独立 Block + Constraint 网络 | 每个 Block 独立显示色块/sprite | **MVP 默认**：最简、最易调试 |
| **v1.5 = B** | 同 v1（不变） | 一组未被打扰的相连 Block 自动被一张"合并 sprite"覆盖；任意 Block 被打扰（销毁、移位 > 阈值、解除 sleep）后该组退回各 Block 独立显示 | v1 拼接缝隙的视觉感官不可接受时 |
| **v2+ = C** | 未受伤时为单个 compound body（多 fixture 拼）+ 整体 sprite；累计伤害 > 阈值时一次性销毁整体并 spawn N 个 Block + Constraint | 切换到 v1.5 的合并 sprite 方案 | 大规模场景的未破坏物体 CPU 开销不可接受时 |

**为什么不一步到位到 C？** 详细论述参见早期版本 §2.4 —— C 引入"物体状态机"，破坏物理统一性；未破坏阶段的"局部伤害"表现模糊；YAGNI。

---

## 3. 范围

### 3.1 ✅ v1（MVP）必须包含

**对应 §2.5 演进路径阶段 A**：物体始终是 N 个独立 Block + Constraint；视觉每个 Block 独立显示。

- **Block**：等大正方形 Box2D dynamic body，自由旋转，自带血量，实现 take_damage
- **Constraint**：相邻 Block 之间的 weld joint，自带血量 + 反作用力 / 扭矩断裂阈值，实现 take_damage
- **Debug 伤害源**：左键点伤、右键范围爆炸（**纯 debug 输入**，简单调用 take_damage，不实例化完整 Effect —— 武器系统的 Effect 双通道在 [weapon spec](weapon-prototype-design.md) 独立开发）
- **冲击伤害（ImpactWatcher）**：物体间碰撞 normal impulse 超阈值自动调用 Block.take_damage
- **Block 销毁**：血量归零 → 销毁 body + 生成纯视觉碎片
- **Constraint 断裂（双路径）**：
  - 物理路径：反作用力超阈值 → 销毁
  - 伤害路径：自身血量 ≤ 0 → 销毁
- **伤害转发（Path X）**：Block.take_damage 内部按比例转发到所有相连 Constraint
- **批量拓扑变更**：所有 body/joint 销毁与创建在 physics_process 末尾批处理（避免在 Box2D 解算中途改拓扑）
- **3 个测试场景**（程序构建）：砖墙、拱门、三层小屋
- **Debug 面板**：runtime 调所有阈值与伤害参数；屏显 FPS / 活跃 Block 数 / 活跃 Constraint 数 / 本帧销毁数

### 3.2 🟡 v1.5（小代价加分项）

**对应 §2.5 演进路径阶段 B**：物理仍始终是 Block + Constraint；视觉加合并 sprite 层。

- **视觉合并层（阶段 B）**：一组未被打扰的相连 Block 自动用合并 sprite 覆盖；被打扰后退回独立显示
- Block 销毁瞬间给周围一个小径向冲量（"溅射感"）
- 视觉碎片用 GPU 粒子系统替代 sprite
- 材质枚举（仅作参数包，不引入复杂逻辑）—— 为未来 Brick / Wood / Stone 等留接口

### 3.3 🔴 v2+（独立子原型，本文档不涉及）

- **物体状态机（阶段 C）**：单 compound body 未破坏时态
- **接入武器系统**：把 debug 伤害源换成 [weapon spec](weapon-prototype-design.md) 的真实 Projectile + Effect
- 接入 3C 角色（角色能站在 Block 上、被砸、推动）
- 多材质 / 各向异性约束（横纹 vs 纵纹）
- 性能优化：Block 对象池、销毁分摊到多帧、spatial hash 邻居查找
- 编辑器关卡格式（Tiled / 自定义 .json / Godot scene tree）

### 3.4 ⚫ 明确不在本项目

- 真 Voronoi / 任意凸多边形切割（保持等大正方形 Block）
- 像素材料系统（Noita 风，[项目总览 §3](项目总览.md) 明示超出 Box2D 时间预算）
- 逻辑承重图 / 结构分析（违反"物理统一优先"）

---

## 4. 详细规格

### 4.1 Block（体块）

**世界参数**：重力 9.8 m/s² 垂直向下（Box2D 默认）；物理步长 1/60 s。

| 属性 | 值 | 备注 |
|---|---|---|
| Body Type | Dynamic | 全程不改 |
| Fixed Rotation | false | Block 要能自由翻滚 |
| Shape | Box，边长 = `block_size`（默认 0.25 m） | 等大正方形 |
| Density | 1.0 → mass ≈ 0.0625 kg @ 0.25m | Box2D 单位 |
| Friction | 0.6 | 砖石质感 |
| Restitution | 0.05 | 几乎不弹 |
| Linear Damping | 0.05 | 微阻尼避免漂移噪声 |
| Angular Damping | 0.1 | 翻滚有阻尼 |
| Collision Layer | `block` | 新增 |
| Collision Mask | `block` + `world` + `projectile` | v2+ 再加 `player` |
| `initial_health` | 100 | 可在材质参数包里覆盖 |
| `damage_to_constraint_ratio` | 0.3 | 转发给相连 Constraint 的比例（[Path X](adr/0007-effect-dual-channel.md)） |

**接口**：

```
take_damage(amount: float, point: Vec2, source: DamageSource):
    health -= amount
    for c in connected_constraints:
        c.take_damage(amount * damage_to_constraint_ratio, point, source)
    if health <= 0:
        DestructionPipeline.queue_block_destroy(self)

signal block_destroyed(position, linear_velocity, angular_velocity)  # 给 DebrisSpawner
```

**关键**：
- take_damage 是**统一伤害语言**（[ADR-0007](adr/0007-effect-dual-channel.md)）的实现 —— 武器系统的 DamageField 直接调用此方法
- 转发到 Constraint 的比例 `damage_to_constraint_ratio` 是 Block 属性（v1 全局默认 0.3，未来可按材质覆盖）
- Block.take_damage **不**直接处理冲量；冲量由调用方（ForceField / 碰撞）独立施加

### 4.2 Constraint（约束）

每对相邻 Block 之间一条 Box2D weld joint 封装，**带血量 + 双路径断裂**。

| 属性 | 值 | 备注 |
|---|---|---|
| Joint Type | Weld | 完全刚性 |
| Stiffness | 硬约束（无柔性） | 不做软关节 |
| `max_reaction_force` | 200 N | 物理路径断裂阈值 |
| `max_reaction_torque` | 30 N·m | 物理路径断裂阈值 |
| `initial_health` | 50 | 伤害路径断裂阈值 |

**接口**：

```
take_damage(amount: float, point: Vec2, source: DamageSource):
    health -= amount
    if health <= 0:
        DestructionPipeline.queue_constraint_destroy(self)
```

**双路径断裂**：
- **物理路径**：每帧 ConstraintBreaker 扫描 reaction_force / reaction_torque，超阈值入销毁队列
- **伤害路径**：health ≤ 0 入销毁队列

两路径都通过同一个 `constraint_destroy_queue` 销毁，幂等。

Box2D weld joint 本身无内置"破坏阈值"——由用户代码每帧查询反作用力实现（伪码，具体 API 名实现期对照 GDExtension 文档；Box2D C++ 原生 API 是 `b2Joint::GetReactionForce(inv_dt)`）：

```
# ConstraintBreaker 在 _physics_process 末尾统一扫描
for c in active_constraints:
    rf = c.joint.get_reaction_force(inv_dt)
    rt = c.joint.get_reaction_torque(inv_dt)
    if rf.length() > c.max_reaction_force or abs(rt) > c.max_reaction_torque:
        DestructionPipeline.queue_constraint_destroy(c)
```

### 4.3 Debug 伤害源（v1）

⚠️ **明确范围**：本节是**纯 debug 输入**，目的是让本原型作为独立 demo 可玩。**不是**武器系统的 Effect 实现 —— 真正的 Effect 双通道在 [weapon spec](weapon-prototype-design.md) 独立开发。两个系统通过 [ADR-0007](adr/0007-effect-dual-channel.md) 的 take_damage 契约对接。

**左键点伤**：
- 鼠标位置 → 单点 query → 命中最近 Block → `block.take_damage(50, mouse_pos, debug)`

**右键范围伤害（debug 简版）**：
- 鼠标位置为中心，半径 `R = 1.5 m`
- AABB query 取范围内所有 Block
- 每块伤害 = `damage_base × max(0, 1 − r/R)`（damage_base = 200，linear falloff）
- 每块径向冲量 = `impulse_base × max(0, 1 − r/R)`，方向 = `normalize(block.pos − center)`（impulse_base = 5 N·s，linear falloff）
- 实现顺序：
  1. `block.take_damage(damage, block.position, debug)` —— 走伤害通道（含 Path X 转发到 Constraint）
  2. `block.body.apply_impulse(dir × impulse)` —— 直接施加，**不入队**（冲量只改 body 速度状态，不改拓扑，与 §4.4 不变量不冲突）
- 若 Block 在 take_damage 后被 queue 销毁，本帧仍施加冲量是无害的（body 还活着，下帧帧末才销毁），且能让"刚断裂的块带速度飞出去"，视觉更对

接入武器系统后（v2+），此节删除 —— 由 [weapon spec](weapon-prototype-design.md) 的 RadialDamage + RadialBlast 替代。

**冲击伤害（ImpactWatcher）**：
- 通过 Box2D contact callback 拿到 normal impulse `J`
- 若 `J > impact_threshold`（2 N·s）→ 双方 Block 各扣 `(J − threshold) × impact_coefficient`（系数 10）
- 实现：把伤害事件入 `damage_events` 队列，**不**在 contact callback 内直接调 take_damage（避免在 Box2D 解算中途改拓扑）
- 下一帧 _physics_process 开始时统一派发

**关键**：ImpactWatcher 也走 Block.take_damage 接口 —— 自动享受伤害转发到 Constraint。一块从高空掉下的 Block 砸到下层 → 下层 Block 扣血 + 周围 Constraint 削弱 → 可能直接打散一组。

### 4.4 批量拓扑变更（关键不变量）

所有改 Box2D 拓扑的操作（销毁 body、销毁 joint、创建 joint、创建 body）**只能**在 `_physics_process` 末尾批量执行；不在解算或 contact callback 中途改。否则 Box2D 行为未定义。

实现：单例 `DestructionPipeline` 维护 4 个队列：
- `damage_events`
- `constraint_destroy_queue`
- `block_destroy_queue`
- `debris_spawn_queue`

`_physics_process` 顺序：
1. **派发** `damage_events` → 调用 `Block.take_damage` / `Constraint.take_damage` → 内部更新血量 + 转发 → 0 血进入相应 destroy queue
2. **扫所有 Constraint** 反作用力 → 物理路径断裂入 `constraint_destroy_queue`
3. **扫所有接触点** 冲量 → 入 `damage_events`（下一帧处理；本帧不立即处理，避免拓扑震荡）
4. **帧末批处理**：
   - 清 `constraint_destroy_queue` → 销毁 weld joint
   - 清 `block_destroy_queue` → 销毁 body（自动断开剩余 weld）+ 发 `block_destroyed` 信号
   - 清 `debris_spawn_queue` → 生成视觉碎片

### 4.5 视觉碎片（DebrisSpawner）

- 输入：Block 销毁位置、线速度、角速度
- 输出：N=4 个短命 sprite，生命周期 1.0 s，alpha 渐隐
- 初速 = Block 速度 + 各向随机扰动
- 仅受重力（手动 integration），不参与 Box2D
- Collision mask = 0

### 4.6 关卡构造（LevelBuilder）

程序化构造，MVP 3 个场景：

**场景 1：砖墙**
- 10 × 10 Block，原点 (0, 0)，size = `block_size`
- 所有相邻对建 Constraint
- 底层下方放一个 static body 地面

**场景 2：拱门**
- 两根柱：5 高 × 1 宽，柱中心距 6 个 block_size
- 一根横梁：1 高 × 7 宽，搁在两柱顶
- 所有相邻对（含两柱顶与梁底）建 Constraint
- 地面在下

**场景 3：三层小屋**
- 两侧墙各 6 高 × 1 宽
- 三层楼板各 1 高 × 8 宽，与两墙的对应行建 Constraint
- 屋顶 1 高 × 8 宽
- 地面在下

**邻居建 Constraint 算法**：

- **判定基准**：两 Block 中心点欧氏距离 ≤ `block_size × 1.05` 视为邻居
- **几何后果（重要）**：该阈值**排除对角邻居**（对角距离 ≈ `block_size × √2 ≈ 1.414 × block_size`）。每个 Block 最多 4 个邻居（上下左右），不是 8 个。砖墙因此是"横平竖直的网格刚性"而非"任意方向都焊死的实体"——这是有意的设计选择，使断裂面倾向于沿轴向，符合砖墙直觉
- **算法**：MVP 用 O(N²) 枚举所有 Block 对；100 块场景下约 1 万次距离比较，构造期一次性开销可忽略。规模升级后换 spatial hash
- **注册**：LevelBuilder 创建 Constraint 后立即注册到 `ConstraintBreaker.active_constraints`，以便每帧反作用力扫描覆盖

**Constraint 的生命周期不变量**：

- **构造期建立不走 DestructionPipeline**：LevelBuilder 在 `_physics_process` 之外执行，直接创建 weld joint + 注册，不需要批处理（pipeline 的约束只针对 physics step 中途的拓扑变更）
- **运行期只销毁、绝不新建**：DestructionPipeline 没有 `constraint_create_queue`。两块散落 Block 重新接触**不会自动焊上**；一旦 Constraint 断开，那对 Block 永远物理独立。这是有意的简化——破坏不可逆，符合 demo 场景需求（"塌方"而非"重建"）
- **Block 销毁时连接的 Constraint 由 Box2D 自动 invalidate**：销毁 body 时挂在其上的 weld joint 自动失效。`ConstraintBreaker` 每帧扫描时需要容忍并清理 invalid joint（或在 `block_destroy_queue` 处理中显式从 `active_constraints` 摘掉对应 Constraint，二选一，实现期定）

### 4.7 Debug 输入

- 鼠标左键：点伤（debug 单点）
- 鼠标右键：范围伤害（debug 简版）
- `F1` 切换 debug 面板
- 数字键 `1` / `2` / `3` 切换场景（重新构造）

### 4.8 Debug 面板（runtime 调参）

可调：
- `block_initial_health`、`damage_to_constraint_ratio`
- `constraint_initial_health`、`max_reaction_force`、`max_reaction_torque`
- `point_damage`、`radial_damage_base`、`radial_damage_radius`、`radial_impulse_base`（debug 输入参数）
- `impact_threshold`、`impact_coefficient`
- `block_size`（切换后重载当前场景）

屏显：
- FPS、活跃 Block 数、活跃 Constraint 数
- 本帧：派发伤害事件数、销毁 Block 数、销毁 Constraint 数（区分物理路径 vs 伤害路径）
- 三机制独立开关（debug）：关闭"伤害转发"、关闭"物理路径断裂"、关闭"冲击伤害" —— 便于隔离调试

### 4.9 调参初值

| 参数 | 初值 | 调参方向 |
|---|---|---|
| `block_size` | 0.25 m | 越小越细腻、越吃性能 |
| `block_initial_health` | 100 | 高 = 耐打 |
| `constraint_initial_health` | 50 | 高 = 难通过伤害断 |
| `damage_to_constraint_ratio` | 0.3 | 高 = Block 受伤更易带塌邻居 |
| `point_damage` | 50 | 两下打穿一块 |
| `radial_damage_base` / `radius` | 200 / 1.5 m | base 决定中心威力，radius 决定波及（debug） |
| `radial_impulse_base` | 5 N·s | Block mass ≈ 0.0625 kg，中心块瞬时速度 ≈ 80 m/s；越大越"炸飞"（debug） |
| `impact_threshold` / `coefficient` | 2 N·s / 10 | threshold 越低越脆，coef 越高越脆 |
| `max_reaction_force` / `torque` | 200 N / 30 N·m | 越大越坚固，越小越易塌 |
| `debris_count` / `lifetime` | 4 / 1.0 s | 视觉调味 |

所有初值在 demo 期实测调整。

### 4.10 文件 / 模块划分

| 路径 | 职责 |
|---|---|
| `destruction/block.gd` | 单个 Block 的状态机（血量、take_damage、伤害转发、销毁信号） |
| `destruction/constraint.gd` | 一条 Constraint 的封装（封 weld joint + 血量 + take_damage + 阈值） |
| `destruction/constraint_breaker.gd` | 系统：每帧扫描所有 Constraint 反作用力（物理路径） |
| `destruction/damage_dispatcher.gd` | 系统：把 damage_events 队列派发到 take_damage |
| `destruction/impact_watcher.gd` | 系统：监听 Box2D 接触冲量并转伤害事件 |
| `destruction/debris_spawner.gd` | 系统：生成视觉碎片 |
| `destruction/destruction_pipeline.gd` | 单例：拓扑变更批处理 |
| `destruction/block_factory.gd` | 工厂：创建 Block（未来接对象池仅改内部） |
| `destruction/level_builder.gd` | 工厂：测试场景构造 |
| `destruction/debug_input.gd` | Debug 鼠标输入（左键点伤 / 右键范围）—— v2+ 删除，由武器 spec 替代 |
| `destruction/debug_panel.gd` | runtime 调参 UI |
| `destruction/destruction_demo.tscn` | 主场景 |

每个模块单职责、可独立替换。

---

## 5. 测试与验证

### 5.1 功能验证（手动 demo）

| # | 操作 | 期望 |
|---|---|---|
| T1 | 场景 1，左键点同一位置 2 次 | 该 Block 消失，留视觉碎片 |
| T2 | 场景 1，左键打穿一条竖线 | 上方 Block 部分下落（边缘的因 Constraint 仍能挂住） |
| T3 | 场景 1，右键中心范围伤害 | 中心块伤害最高，周围按距离衰减；可能整组塌（伤害转发让多个 Constraint 同时断） |
| T4 | 场景 2，右键炸柱底 | 该柱塌；房顶按物理拉扯演化（中段断或一侧塌） |
| T5 | 场景 3，多次范围伤害 | 整体倾斜塌陷 |
| T6 | 任意场景，高空掉一个 Block 到下方 | 接触瞬间 normal impulse 高 → 下方块通过 take_damage + 伤害转发可能直接打散一片 |
| T7 | 关闭"伤害转发"开关，重复 T3 | 中心块销毁，但周围结构基本保留（验证 Path X 是否在起作用） |

### 5.2 性能验证

- 场景 3 启动后稳定 60fps（基线机型：i5 / 集显）
- 大规模范围伤害瞬间无明显卡顿（帧时间 < 16.6 ms）
- Debug 面板的活跃 Block 数 / 帧销毁数实时显示，便于发现性能拐点

### 5.3 架构验证

- 所有 body/joint 拓扑变更都通过 DestructionPipeline 走，不出现 Box2D assert
- Block 通过 BlockFactory 创建，未来接对象池仅改工厂内部，不动消费者
- 三机制（Block 销毁、Constraint 双路径断裂、冲击）的开关能在 debug 面板独立关闭，便于隔离调试
- **跨 spec 契约验证**：Block.take_damage / Constraint.take_damage 的签名与 [ADR-0007](adr/0007-effect-dual-channel.md) 一致；模块内 grep 无 `weapon` / `projectile` / `effect` import（单向依赖）

---

## 6. 后续步骤

v1 通过后：

1. **性能优化**：Constraint 邻居建立从 O(N²) 改 spatial hash（规模升中型时）；接对象池
2. **联动 D（武器）**：删除本 spec 的 debug 伤害源；让 [weapon spec](weapon-prototype-design.md) 的 RadialDamage / RadialBlast 直接作用 → 原型 3A
3. **联动 A（3C）**：接 3C 角色 —— 角色能站在 Block 上、被砸到、推动 → 联调到"塌陷追逐" setpiece 雏形
4. **材质扩展**：引入 Brick / Wood / Stone 等参数包，不同 Block 血量、Constraint 血量、转发比例与反作用力阈值 → 复杂破坏行为
