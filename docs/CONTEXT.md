# PlatformerPhysics — 项目语言

为 PlatformerPhysics 项目建立的精确术语表，避免在讨论物理 / 控制 / 角色行为时使用模糊或冲突的概念。本文档是 glossary，不是 spec，不放实现细节。

## Language

### 物理派别

**内在发动机派 (Inner Engine)**:
角色作为 Box2D dynamic body，玩家的所有操作（移动、跳跃、空中转向）都转化为施加在角色上的力或冲量，由 Box2D 物理解算演化速度。角色自发的力与场景施加的力（爆炸、推、碰撞）处于同一本体论层级，物理反馈自然涌现。**本项目采用此派别**。
_Avoid_: 力派 (force school)、动力学派 (dynamics school)、纯物理派

**速度覆盖派 (Velocity Override)**:
每帧手动写入 `linear_velocity` 压制 Box2D 自由演化，输入即响应。Celeste / Hollow Knight 等典型作品采用。**本项目已弃用此派别**，仅作对比术语保留。
_Avoid_: 直接控制派、kinematic-emulated dynamic

### 角色行为概念

**启动 (Spin-up)**:
角色从静止到达到最大速度的过程，由**发动机转速曲线**输出的水平力 + 摩擦力共同决定。本项目用高启动力保持响应感（目标 ≈ 0.1 s 内大部分加速完成）。
_Avoid_: 加速时间常数（这是速度覆盖派术语）

**发动机转速曲线 (Engine Torque Curve)**:
角色"内在发动机"的力输出函数。形如 `F = F_max · softsign(v_target − v_current) · saturation(|v_target − v_current|)`，关键性质：
- 玩家按方向键 → `v_target = ±v_max`；否则 `v_target = 0`（发动机不出力，靠摩擦衰减）
- 当前速度接近目标转速 → 力平滑衰减到 0（不是硬 clamp）
- 当前速度反向远离目标 → 全力反向出力（玩家被推飞后按反向键仍能刹车）
- 当前速度超过目标方向 → 力 = 0（被推飞超过 v_max 时发动机不强行回拉）

**最大速度 v_max (Engine Max RPM)**:
发动机的"额定转速上限"。**不是**对角色速度的硬 clamp。玩家自己跑会收敛到 v_max；但外力（爆炸、推、动平台）可以推得超过 v_max，之后靠摩擦自然衰减。这是 setpiece 戏剧感的来源。

**惯性 (Inertia)**:
玩家松开方向键后，角色因仍有水平速度而继续滑行的现象。**主要由地面摩擦决定衰减速率**；不同地面材质（冰、油、泥、木）天然给出不同手感，是"内在发动机派"区别于速度覆盖派的核心可感知特征。
_Avoid_: 滑步、漂移

**地面摩擦 (Ground Friction)**:
角色与地面接触时由 Box2D 物理材质（角色 fixture + 地面 fixture）共同决定的减速力。本项目的**第一调参对象** —— 走 / 滑 / 急停的手感主要靠它调，不靠速度覆盖。

**主动刹车 (Active Braking)**:
无方向输入时，角色发动机可选地额外施加与当前速度相反的小力。是地面摩擦的**微调补充**，**不是**主要减速机制。默认 0；当某些地面（如冰）摩擦太低导致控制失态时，可临时调高补救。

**知觉一致性补偿 (Perceptual Compensation)**:
为补偿玩家视觉延迟、输入采样延迟、人类反应误差而对**输入判定**做的容忍机制。Coyote time（离开平台 0.10s 内仍可起跳）、Jump Buffer（落地前 0.10s 按跳仍生效）属于此类。
**关键性质**：不改变物理结果，只改变"何时算作有效输入"。一旦判定为有效输入，物理过程完全按发动机模型走。
**不是魔法**（[项目总览 §2.5](项目总览.md) 意义上的）—— 是修正物理引擎对人类不公平之处，不是绕开物理。所以即便走"纯物理优先"路线，仍然在 v1 包含。
_Avoid_: 输入魔法、jump magic（这两个词容易跟"物理魔法"混淆）

**喷气推力 (Air Jet Impulse)**:
玩家在空中按方向键时施加的水平推力，量级约为地面发动机的一半。角色当前速度仍生效，需要时间"刹车 + 反向"才能改变方向，类似在空中点火喷气。空中无水平阻力，所以松手时空中水平速度永久保持。
_Avoid_: 空中加速度、空中控制（这两个是速度覆盖派术语）

**助跑跳 (Running Jump)**:
本项目核心动作语法 —— **跳跃的横向距离由地面助跑速度决定**，不由空中操控决定。原地起跳横向位移很短；想跨大缺口必须先助跑到顶速再起跳。是 [ADR-0004](docs/adr/0004-air-control-model.md) 的直接后果，决定了关卡设计的基本节奏：跑道 → 缺口 → 跑道。

**跳跃冲量 (Jump Impulse)**:
按下跳跃键瞬间施加的垂直冲量，决定基础起跳高度。按住期间持续施加小垂直推力延长上升时间；松开立刻停止推力，由重力自然演化弹道。
_Avoid_: 跳跃初速度、跳跃速度（这些是速度覆盖派术语）

**物理可干预性 (Physical Reactivity)**:
角色作为 dynamic body 能被场景中的物理事件（爆炸、推、碰撞、动平台）影响的能力。是项目愿景的硬约束 —— 任何架构方案都必须保留这项。
_Avoid_: 物理感、可被推动性

**手感 (Feel)**:
在本项目特指"物理反馈的可预测性与一致性"，**不是**"输入直接响应度"。重新定义自 Celeste/Hollow Knight 派的常用义。
_Avoid_: 流畅、响应（指 input response 时另说）

### 武器 / 弹道 / 效果

**三元组分解 (Weapon × Projectile × Effect)**:
本项目所有"开火 → 击中 → 后果"链路统一分解为三个正交对象：
- **Weapon（武器）** —— 瞄准 + 触发 + 飞行道具生成器（cooldown、muzzle、initial_speed）
- **Projectile（飞行道具）** —— 飞行过程载体（Box2D body、寿命、命中检测）
- **Effect（效果）** —— 命中后果（伤害 + 物理力）
组合即玩法：手枪 = 直射 Projectile + 单点伤害 Effect；火箭炮 = 抛物线 Projectile + 范围 Effect。详见 [ADR-0010](docs/adr/0010-weapon-projectile-effect-decomposition.md)。
_Avoid_: 子弹 = 单一类（混合飞行 + 伤害）

**Effect（效果）**:
命中位置触发的瞬时事件，本质是一个**双通道**容器：同时挂载若干 DamageField + ForceField。Effect 不知道接受者内部是什么（Block / Constraint / Player / Enemy），只调用其 `take_damage` / `apply_impulse` 接口。详见 [ADR-0007](docs/adr/0007-effect-dual-channel.md)。
_Avoid_: 爆炸（太具体）、伤害事件（漏掉物理力通道）

**DamageField（伤害场）**:
Effect 的伤害通道。对范围内每个实现 `take_damage` 的物理体调用其 take_damage 方法。统一伤害语言：DamageField 不区分对方是 Block、Constraint、还是 Player —— duck-typing。
_Avoid_: 伤害事件、伤害区

**ForceField（力场）**:
Effect 的物理力通道。对范围内每个 dynamic body 施加冲量或持续力（径向、定向、扭矩）。与 DamageField 解耦：可以只有伤害无推力（毒气）、可以只有推力无伤害（气浪）、两者皆有（爆炸）。
_Avoid_: 冲击波、爆炸力

**径向冲击 (Radial Impulse)**:
ForceField 最常见形式 —— 以爆点为中心，对范围内 dynamic body 按 `(1 − d/R)` 衰减施加径向方向冲量。是爆炸的"推飞"部分。
_Avoid_: 爆炸力（太含糊）

**统一伤害语言 (Unified Damage Language)**:
项目级约定：所有可受损物理体（Block、Constraint、未来的 Enemy、Player）都实现 `take_damage(amount, point, source)` 方法。DamageField 通过 duck typing 调用，不依赖任何接口/基类。是 [ADR-0007](docs/adr/0007-effect-dual-channel.md) 的核心 invariant。
_Avoid_: IDamageable 接口、伤害事件总线（v1 不引入抽象层）

**伤害转发 (Damage Forwarding)**:
Block.take_damage 内部除了扣自己的血，还会按比例 `damage_to_constraint_ratio`（默认 0.3）调用其所有相连 Constraint 的 take_damage。结果：DamageField 命中 Block 即可自然削弱周围约束 → 体块可能塌而非碎。Effect 完全不知道有 Constraint —— 单向依赖原则（[ADR-0007](docs/adr/0007-effect-dual-channel.md)）。
_Avoid_: 约束伤害、连带伤害

**自爆跳 (Self-Splash Jump)**:
玩家朝脚下开枪 → Projectile 在脚下爆炸 → Effect 的 ForceField 把玩家自己推飞。**不是**后坐力造成的反向跳跃 —— 后坐力（2 N·s）量级远小于自爆冲量（12 N·s 峰值）。是 [ADR-0007](docs/adr/0007-effect-dual-channel.md) `affect_player=true` 的涌现产物，详见 [ADR-0008](docs/adr/0008-self-splash-jump.md)。
_Avoid_: 火箭跳（多义 —— Quake 火箭跳实际也是 self-splash，但用语避免混淆）、后坐力跳

**后坐力 (Recoil)**:
开火瞬间施加在玩家身上的反向小冲量（量级 ~2 N·s）。**与自爆跳无关** —— 量级上只够让玩家退一小步（≈ 1.5 m/s）。作用：质感反馈 + 空中横向调位。可关闭对比。
_Avoid_: 火箭跳来源（错）、反作用力（与"自爆跳"易混）

**冲击伤害 (Impact Damage)**:
Box2D contact 中 normal impulse 超阈值时由 ImpactWatcher 自动转换为 take_damage 调用。是 DamageField 之外**另一条**自然进入伤害系统的路径 —— 高处掉下的体块砸到下层体块，触发链式破坏，不需要任何武器参与。详见 [destruction spec §4.3](2026-05-24-destruction-prototype-design.md)。
_Avoid_: 碰撞伤害（多义）

**Constraint（约束）**:
体块（Block）之间的物理连接，运行期 = 一条 Box2D weld joint 包装。有两个独立断裂路径：
- 物理路径：每帧扫描 reaction_force / reaction_torque，超阈值即断
- 伤害路径：自身血量归零即断（由 Block 的伤害转发驱动）
详见 [destruction spec §4.2](2026-05-24-destruction-prototype-design.md)。**取代早期文档中的"Bond"一词** —— 全项目统一称 Constraint。
_Avoid_: Bond（旧词，已废弃）、关节（太底层）、焊接

**直射弹 (Direct Projectile)**:
高速、`gravity_scale = 0` 的 Box2D 物理体；视觉上是直线但仍然走完整碰撞解算，CCD 防穿透。**不是 hitscan**（hitscan = 立即 raycast 命中），因为后者破坏物理一致性、无法被子弹时间慢放、无法被风/力场偏转。详见 [ADR-0009](docs/adr/0009-direct-shot-is-physics-projectile.md)。
_Avoid_: 激光、hitscan、瞬发弹（这三个都暗示无飞行过程）

**抛物线弹 (Ballistic Projectile)**:
普通 dynamic body，`gravity_scale = 1`，受世界重力。火箭、手雷、抛投物的通用基础。

**单向依赖原则 (Single-Direction Dependency)**:
武器系统知道破坏系统的存在（调用其 take_damage 接口），反之不成立。破坏系统对武器系统**零感知** —— 删除武器系统不影响破坏系统编译/运行。这是 [ADR-0007](docs/adr/0007-effect-dual-channel.md) 推导的架构 invariant，保证两系统能独立开发与测试。

### Flagged ambiguities

**"丝滑"**:
3C 文档早期使用此词表示"Celeste 般输入直接响应"。当前项目方向（内在发动机派）不再追求此目标，**该词在本项目废弃**。后续讨论手感时统一用"**物理反馈一致 (Physical Feedback Coherence)**"或单独说"**高启动加速度 (High Spin-up Acceleration)**"，避免再用"丝滑"。

**"重量感"**:
多义。3C 文档 §2.2 原图中指"输入响应慢"。内在发动机派下应理解为"**惯性强**（松手滑得远）+ **物理可干预性高**（被外力推得动）"，跟"响应慢"无关。

**"物理感"**:
多义。文档早期同时指"被外物影响"和"主观重量感"。**该词废弃**，按需替换为"物理可干预性"或"惯性"。

## 例对话

> Dev：玩家撞到小凸起会被顶飞吗？  
> 设计：会，**内在发动机派**下角色的 dynamic body 自然受碰撞反作用力，不需要特例代码。  
> Dev：那启动会不会很粘？  
> 设计：不会，**启动加速度**调得极高（≈ 80 m/s²），玩家几乎感觉不到延迟。但松手会**滑行**，那是**惯性**，不是 bug。  
> Dev：空中按反方向能立刻反向吗？  
> 设计：不能。空中给的是**喷气推力**，当前速度还在，需要"刹车 + 反向"。这是和速度覆盖派最明显的差异。
