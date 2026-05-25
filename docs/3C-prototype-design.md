# 2D 平台物理游戏 — 3C 原型设计

| 字段 | 值 |
|---|---|
| 日期 | 2026-05-24 |
| 状态 | Draft（待审） |
| 引擎 | Godot 4.x + Box2D（通过 GDExtension） |
| 所属项目 | PlatformerPhysics |
| 文档定位 | 系列第 1 个原型；后续所有原型（破坏、流体、武器、AI）都依赖它 |

**相关文档：**
- 架构决策见 `docs/adr/`：[0001 内在发动机派](docs/adr/0001-inner-engine-school.md)、[0002 发动机转速曲线](docs/adr/0002-engine-torque-curve.md)、[0003 跳跃辅助力](docs/adr/0003-jump-curve-via-assist-forces.md)、[0004 空中控制](docs/adr/0004-air-control-model.md)、[0005 Capsule 形状](docs/adr/0005-capsule-as-learning-choice.md)、[0006 二段跳喷气背包](docs/adr/0006-double-jump-as-jetpack.md)
- 术语精确定义见 [CONTEXT.md](CONTEXT.md)
- 项目级方法学（§2.5 物理统一优先 / §2.6 反物理玩法方法学）见 [项目总览.md](项目总览.md)

---

## 1. 背景

### 1.1 大项目背景

`PlatformerPhysics` 是个人技术 demo + 学习项目，**不发布完整游戏**。愿景见 [项目总览.md](项目总览.md) §1。

### 1.2 为什么先做 3C

- 3C 是所有动作游戏的灵魂；3C 不舒服，再炫酷的破坏 / 流体也救不回来
- 后续所有物理原型都依赖一个可信的"玩家代理"
- 内在发动机派的角色架构是后续所有 setpiece "物理反馈自然涌现"的前提

### 1.3 成功标准

| # | 标志 |
|---|---|
| 1 | 角色启动响应快（≈ 0.1 s 到顶速感），玩家盲打不觉迟钝 |
| 2 | 松手后角色有可感的滑行（**惯性**），不同地面材质给出不同滑行距离 |
| 3 | 物理反馈一致：跳起来撞到天花板自然下落、撞凸起会被推 / 顶飞、推动 dynamic box 跟现实直觉吻合 |
| 4 | 知觉一致性补偿（Coyote / Buffer）能在测试关卡里被验证产生作用 |
| 5 | 所有手感参数能在 runtime 用滑条实时调整 |
| 6 | 角色被外力（推动 / 爆炸预演）作用时表现一致，**无需特例代码** |

"飘感 + 砸感"按 [ADR-0003](docs/adr/0003-jump-curve-via-assist-forces.md) v1 走真抛物线，留接口将来加。

---

## 2. 设计哲学

### 2.1 核心矛盾

核心矛盾是 **"统一物理本体论 vs 即时输入响应"**：

- **统一物理本体论**：所有速度变化都是"力的求和" → 角色与场景物理体规则一致 → setpiece 自然涌现
- **即时输入响应**：玩家按下立即获得期望速度 → Celeste 风的微操精度

本项目选择**统一物理本体论**，靠**高启动力**而非"速度覆盖"来补偿响应感（[ADR-0001](docs/adr/0001-inner-engine-school.md)）。

### 2.2 项目定位

```
LIMBO/Inside    [本项目 ≈ Trine / HL2 + 高启动响应]    Hollow Knight ↔ Ori    Celeste/Meat Boy
   ←——————————————————————————————————————————————————————————————————————————————→
 纯物理体              偏物理体 + 玩家驱动                    混合派                  纯直接控制
```

特征：
- **物理可干预性强** —— 跟所有物理体规则一致，能被推、被爆炸推飞、能踩动 dynamic box
- **启动响应快** —— 高发动机推力，0.1 s 到顶速
- **横向位移由助跑决定** —— 原地起跳跳不远（[ADR-0004](docs/adr/0004-air-control-model.md)）
- **惯性显式** —— 松手有滑行，不同地面手感不同

### 2.3 架构选择

见 [ADR-0001](docs/adr/0001-inner-engine-school.md)。一句话：角色 = Box2D dynamic body，**所有控制 = 施加力 / 冲量**，每帧不覆盖 `linear_velocity`。

### 2.4 项目级方法学

见 [项目总览 §2.5 §2.6](项目总览.md)：

- **物理统一优先，魔法后加** —— 跑通纯物理再判断要不要加魔法，魔法要可关闭
- **反物理玩法的优先级方法学** —— 物理化包装 → 知觉补偿 → 兜底承认魔法

---

## 3. 范围

### 3.1 ✅ v1（MVP）必须包含

- 左右移动（发动机转速曲线 + 地面摩擦决定惯性）
- 单段跳跃（初始冲量 + 按住期间持续小推力 + 松开停推）
- 空中方向控制（喷气推力，弱于地面）
- **恒定重力**（v1 不做不对称重力或 apex hang —— 见 [ADR-0003](docs/adr/0003-jump-curve-via-assist-forces.md)）
- 接地检测（Capsule contact + 法线检查，1 帧防抖接口实现但默认关闭）
- Coyote Time + Jump Buffer
- 基础摄像机：平滑跟随 + 死区 + 垂直 lookahead
- **Debug 面板**：runtime 调节所有手感参数（生命线）
- **可视化辅助**：实时显示速度、状态、接地情况、接触法线
- 最简测试关卡（见 §4.10）

### 3.2 🟡 v1.5（小代价加分项）

- 二段跳（喷气背包模型，详见 [ADR-0006](docs/adr/0006-double-jump-as-jetpack.md)）
- 跳跃辅助力（飘感 / 砸感，若真机测试发现需要）
- 起跑 / 落地粒子
- 着陆挤压动画（伪物理 scale）

### 3.3 🔴 v2+（每个都是独立子原型，本文档不涉及）

- 墙壁滑落 / 蹬墙跳（蹬墙反作用力，物理化）
- 冲刺 / Dash（大喷气）
- 抓边 / 攀爬 / 翻越
- 蹲下 / 翻滚
- 瞄准 / 射击系统
- 推动物体交互（不需要特殊代码，已经免费可用）
- 移动平台精确跟随

### 3.4 ⚫ 明确不在本项目（属于船 demo）

- 移动参考系（在剧烈晃动的船上跑）

---

## 4. 详细规格

### 4.1 角色物理体

| 属性 | 值 | 备注 |
|---|---|---|
| Body Type | Dynamic | 全程不改 |
| Fixed Rotation | true | 角色不翻倒 |
| Shape | **Capsule**（高 1.8 m，半径 0.4 m） | [ADR-0005](docs/adr/0005-capsule-as-learning-choice.md)：学习先行，主动接受弹跳风险 |
| Density | 1.0 → 实际 mass ≈ 1.3 kg | Box2D 单位 |
| Friction | **可调（与地面材质共同决定）** | 不再设 0；摩擦是惯性主调 |
| Restitution | 0.0 | 不弹 |
| Linear Damping | 0.0 | 空中无阻力（[ADR-0004](docs/adr/0004-air-control-model.md)） |
| Angular Damping | n/a | fixed_rotation = true |
| Collision Layer | `player` | |
| Collision Mask | `world` + `enemy` + `interactable` | |

### 4.2 移动参数 — 地面（发动机转速曲线）

按 [ADR-0002](docs/adr/0002-engine-torque-curve.md)：

```
F_engine = F_max · sign(v_target − v_current) · saturation(|v_target − v_current|)
v_target = ±v_max if 玩家按方向键 else 0
```

| 参数 | 起始值 | 说明 |
|---|---|---|
| `v_max` | 8.0 m/s | 自跑稳态速度（受摩擦影响实际略低） |
| `F_max_ground` | 80 N | 发动机额定输出（≈ 80 m/s² 起步加速度，1.3 kg） |
| `saturation_full` | 2.0 m/s | `|v_target − v_current|` 大于此值时 saturation = 1（满力） |
| 默认地面 friction μ | 0.10 | 中等地面（木板、土）；其它材质单设 |
| `F_active_brake` | 0 N | [主动刹车](CONTEXT.md)，默认关闭，作为微调备用 |

**派生预期**：
- 0 → v_max 启动时间 ≈ 0.1-0.15 s（加速段大部分时间满力，接近顶速时衰减）
- 松手滑行距离 ≈ 1.6-2.0 m（μ=0.10, 8 m/s 起，约 0.4-0.5 s）
- 不同材质示例：μ_冰 ≈ 0.02（滑很远）/ μ_泥 ≈ 0.3（立刻停）

**摩擦实现备注**：地面摩擦不走 Box2D 内置 μ，由 `Scripts/Prototypes/3C/ground_friction.gd` 按 Coulomb 模型自己算（Player 的 `PhysicsMaterial.friction = 0`）。决策见 [ADR-0011 角色摩擦自管派](docs/adr/0011-custom-friction-over-box2d.md)；实施详情见 [2026-05-25-3c-custom-ground-friction-design.md](2026-05-25-3c-custom-ground-friction-design.md)。

### 4.3 移动参数 — 空中（[ADR-0004](docs/adr/0004-air-control-model.md)）

| 参数 | 起始值 | 说明 |
|---|---|---|
| `F_max_air` | 40 N | 半地面力 |
| 空中水平阻力 | **0** | 起跳后水平速度永久保持，除非玩家反向输入 |
| 空中 v_max | 同 `v_max` (8.0) | 发动机额定属性，跟介质无关 |

**派生预期**：原地起跳全空中按右 → 落地时水平速度只到 v_max 的 30-50%；助跑起跳空中无输入 → 落地保持顶速。

### 4.4 跳跃参数（持续推力 < 重力）

| 参数 | 起始值 | 说明 |
|---|---|---|
| `J_jump_initial` | 11.2 N·s | 初始冲量；对应 1.3 kg 起跳速度 ≈ 8.6 m/s |
| `F_jump_hold` | 8 N | 按住期间持续上推力（远小于重力 m·g ≈ 32 N） |
| `hold_window_max` | 0.30 s | 持续推力最大时长（防止 bug 状态下永久上推） |
| `重力 g` | 25 m/s² | **恒定**，全程不切换 |
| `apex_hang` | ❌ v1 不实现 | 留接口；按 [ADR-0003](docs/adr/0003-jump-curve-via-assist-forces.md) 后补 |
| `gravity_fall_multiplier` | ❌ v1 不实现 | 同上 |

**触发逻辑**：
1. 按下 Jump（且满足接地或 coyote 或 jetpack 条件）→ 施加 `J_jump_initial` 上冲
2. 按住期间 vy > 0 → 持续施加 `F_jump_hold`
3. 松开 OR vy ≤ 0 OR `hold_window_max` 到 → 停止持续推力
4. 之后纯物理（恒定重力）演化

**派生预期**：
- 长按高度 ≈ 2.5 m，短按高度 ≈ 1.9 m（差异 ~30%）
- 接受 small vs big jump 差异有限，关卡设计不依赖极端差异

### 4.5 知觉一致性补偿（[CONTEXT.md](CONTEXT.md)）

| 参数 | 起始值 | 作用 |
|---|---|---|
| `coyote_time` | 0.10 s | 离开平台后仍可起跳的窗口 |
| `jump_buffer_time` | 0.10 s | 落地前按 Jump 仍生效的窗口 |

**关键性质**：这是补偿玩家视觉 + 输入延迟，**不是魔法**，无需可开关。一旦判定为有效起跳，物理过程完全按 §4.4 走。

### 4.6 接地检测（capsule contact + 法线检查）

按 [ADR-0001](docs/adr/0001-inner-engine-school.md) 哲学统一：用 Box2D 接触信息，不用 raycast。

```
接地条件：
  capsule fixture 至少有 1 个 contact，
  且该 contact 的法线 y 分量 > cos_theta_max
```

| 参数 | 起始值 | 说明 |
|---|---|---|
| `cos_theta_max` | 0.7（≈ 45°） | Capsule 弧面碰台阶角时可能斜到 60°，阈值需现场调 |
| `ground_state_buffer_frames` | 0（默认关） | 1 帧防抖，debug 面板可开启，开关式 |

**预期学习产物**（per [ADR-0005](docs/adr/0005-capsule-as-learning-choice.md)）：
- Capsule 弧面碰台阶角 → 法线偏转 → 接地态可能闪烁 → debug 面板可见
- 启用 1 帧防抖后接地态稳定，但 coyote / buffer 实际值变成 ≈ 0.117 s（无感）
- 可能会出现"贴墙误判接地"边缘 case → 调 `cos_theta_max` 或加额外条件

### 4.7 状态机（简化版）

```
   [Idle]  ←→  [Running]
      ↓ jump      ↓ jump
   [Rising]  →  [Falling]
                  ↓ (接地)
              [Landed] → (Idle/Running)
```

v1 不需要 `Apex Hang` 状态（[ADR-0003](docs/adr/0003-jump-curve-via-assist-forces.md) 推迟）。`Rising → Falling` 在 `vy ≤ 0` 时切换。

**实现备注**：4 态是观察口径（每帧从 `is_grounded` / `vx` / `vy` 派生）；力的分发仍按 Ground/Air 二分。详见 `Scripts/Prototypes/3C/movement_state.gd`（位于 godot 项目树），实现计划见 `docs/superpowers/plans/2026-05-24-3c-movement-fsm-refactor.md`。

### 4.8 摄像机

| 行为 | 设置 |
|---|---|
| 跟随模式 | 平滑插值（critically-damped spring） |
| 跟随时间常数 | ~0.15 s |
| 水平死区 | ±32 px |
| 垂直死区 | ±24 px |
| 垂直 Lookahead | 角色 \|vy\| 持续 > 5 m/s 且方向稳定 0.3 s → 摄像机偏移 ±64 px |
| 防抖延迟 | 0.3 s（防止短暂动作触发 lookahead；内在发动机派下未来可能有外力推飞产生瞬时高 vy，预留余量） |

**预留接口（v1 实现但不调用）：**
- `camera.shake(intensity, duration)` — 给未来爆炸 / 受击用
- `camera.set_target(node)` — 切换跟随对象

### 4.9 Debug 面板

按 `F1` 切换显示。Godot 4 内置 Control 节点 / `imgui-godot` 插件（v1 选轻的）。

**滑条参数（实时生效）：**

- 4.2 地面：`v_max`、`F_max_ground`、`saturation_full`、`μ`（地面默认材质）、`F_active_brake`
- 4.3 空中：`F_max_air`
- 4.4 跳跃：`J_jump_initial`、`F_jump_hold`、`hold_window_max`、`g`
- 4.5 补偿：`coyote_time`、`jump_buffer_time`
- 4.6 接地：`cos_theta_max`、`ground_state_buffer_frames`（0/1 开关）
- 4.8 摄像机：跟随时间、死区、lookahead 阈值

**实时数值显示：**

- position、velocity（含 vx / vy）、v_target、is_grounded、state
- coyote_remaining、jump_buffer_remaining
- jetpack_charges（v1.5 显示，v1 隐藏）
- **最近一帧 contact 列表**：fixture 名 + 法线方向 + 法线 y 分量（关键！用来看 Capsule 弹跳症状）
- 当前帧 net force on 角色（vector，方便看发动机出力）

**操作按钮：**

- 重置参数为默认值
- 保存当前参数到 JSON 文件
- 加载 JSON 参数
- **切换 1 帧防抖开关**（直观对比）

### 4.10 测试关卡

最简关卡，专门压力测试 3C：

- **平地走廊**（默认 μ）— 测试启动 / 滑行 / 转身
- **冰区**（μ ≈ 0.02）— 测试低摩擦下的失控感
- **泥区**（μ ≈ 0.3）— 测试高摩擦下的停止感
- **台阶序列**（3-5 级，每级高 0.2-0.4 m）—**预期学习目标：观察 Capsule 弹跳**（[ADR-0005](docs/adr/0005-capsule-as-learning-choice.md)）
- **小凸起**（高 0.05-0.1 m 的小 box）— 测试物理可干预性（角色应被微微顶起 / 减速）
- **不同高度的平台跳** — 测试跳跃高度精度
- **长距离跳跃** — 测试**助跑跳**（[ADR-0004](docs/adr/0004-air-control-model.md)）
- **紧密的悬崖边** — 测试 coyote
- **下降式平台序列** — 测试 buffer
- **一面墙** — 测试撞墙不会卡
- **一个 dynamic box**（v1 末期）— 测试踩上去稳定 + 物理交互

---

## 5. 实现要点

### 5.1 力的求和执行顺序（每个 physics tick）

1. 读输入
2. 更新 coyote / buffer 计时器
3. 更新接地状态（contact list + 法线检查）
4. 处理跳跃请求（buffer 命中 / coyote 命中 / jetpack 命中[v1.5]）→ 累积冲量
5. 计算地面发动机力 F_engine_ground（按 [ADR-0002](docs/adr/0002-engine-torque-curve.md) 公式）
6. 计算空中喷气推力 F_engine_air（若不接地）
7. 计算 jump_hold 力（若在按住期间）
8. （v1 不实现）跳跃辅助力（apex / fall）—— [ADR-0003](docs/adr/0003-jump-curve-via-assist-forces.md) 留位
9. 累加所有力 → `apply_force` / `apply_impulse` 给 Box2D
10. Box2D 解算物理（重力、摩擦、碰撞、推力）
11. 更新摄像机
12. 更新 debug 显示

**没有"覆盖 linear_velocity"** —— 全程只施加力或冲量。

### 5.2 帧率独立

- 物理在固定步长（60Hz）下运行
- 持续力（如 `F_jump_hold`）按时长累计 → 等价于冲量
- 计时器（coyote / buffer / hold_window）以秒为单位，配合 `delta`

### 5.3 Box2D 特有注意

- 锁定旋转：`fixed_rotation = true`
- **Friction 必须可调** —— 摩擦是惯性主调，材质区分用 fixture friction 实现
- **Linear damping = 0** —— 空中无阻力，靠输入和摩擦控制
- 接地态由 contact list 维护，不要在 `_physics_process` 里复用 raycast 查询
- Apply 力 / 冲量时区分：持续力用 `apply_central_force`（每帧调一次自动消耗一帧）；瞬时冲量用 `apply_central_impulse`

---

## 6. 验证标准

v1 完成的判定（必须全部通过）：

- [ ] 所有 §4.9 参数都能在 runtime 滑条调
- [ ] 在测试关卡能制造"边缘 Coyote 起跳"和"提前 Buffer 起跳"的成功 case
- [ ] 调整地面 μ 能明显改变滑行距离（冰 vs 泥 vs 默认 显著不同）
- [ ] **走过台阶序列能直接看到 Capsule 弹跳症状**：接地态闪烁 + 水平减速 + 视觉颠簸 + debug 面板法线变化
- [ ] 开启 1 帧防抖后，弹跳现象的一部分症状（接地态闪烁）被掩盖，但水平减速仍在 —— 印证防抖只解决一部分
- [ ] 助跑跳能跨过比原地跳明显更宽的缺口（验证 ADR-0004 的"助跑决定距离"）
- [ ] 把一个 dynamic box 放进关卡 → 跳上去 → 角色能站稳，box 会被踩动少量
- [ ] 推一下 dynamic box → 角色受反作用力被微微减速（验证物理统一）
- [ ] 摄像机平移不眩晕、不卡顿
- [ ] 至少给一个朋友试玩，能给出"挺顺手"或更高评价

---

## 7. 风险与未决问题

| 风险 | 缓解 |
|---|---|
| Box2D capsule 在台阶上弹跳 | **接受为学习产物**（[ADR-0005](docs/adr/0005-capsule-as-learning-choice.md)）；§4.10 台阶序列就是为它准备的；切换 Box+脚趾的接口在 fixture 层面 |
| Godot 4 的 Box2D GDExtension 成熟度未知 | **实现前先做 30 分钟 spike**：能创建 RigidBody、能 apply_force / apply_impulse、能查 contact list + normal、能设 fixture friction |
| 发动机转速曲线 saturation 函数选哪个（linear / tanh / sigmoid）调出来差异大 | 起始用 linear-with-cap，跑通后真机调形状 |
| Debug 面板从零搭建可能费时 | 先用 `imgui-godot` 插件直接拿轮子；不行再退到原生 Control |
| Capsule 接地法线阈值 `cos_theta_max` 调不出来（贴墙误判 vs 上斜失败） | 先用 0.7，不行加额外条件（如"contact 在角色脚部 y 范围内"）；最坏退到 raycast 补丁 |
| 手感真机不行 → 是 force-based 派的根本问题还是参数没调好 | 验证流程：先把 §4.2-4.4 参数轮调一遍；若仍不行，启用 §4.4 的 `apex_hang` / `gravity_fall_multiplier` 接口（[ADR-0003](docs/adr/0003-jump-curve-via-assist-forces.md)）；仍不行再考虑反转 ADR-0001 |

**未决问题（实现时决定）：**

- 用 `RigidBody2D`（Godot 包装）还是直接调 Box2D GDExt API？
- Debug UI 用 `imgui-godot` 还是手搓 Control？
- 测试关卡用 TileMap 还是手摆 StaticBody？
- saturation 函数具体形状（linear-with-cap / tanh / sigmoid）—— 真机决定

---

## 8. 下一步

1. ✅ 用户审阅本文档 ← **当前节点**
2. ⬜ 进入实现计划阶段（writing-plans skill）：拆解为可执行的开发步骤序列
3. ⬜ 执行实现：
   - Box2D GDExt 接通 spike
   - 最小 Capsule 角色 + 重力 + 接地 contact 检测
   - 地面发动机（启动 / 转速曲线 / 摩擦）
   - 跳跃（初始冲量 + 持续推力）
   - 空中喷气
   - Coyote + Buffer
   - 摄像机
   - Debug 面板
4. ⬜ 在测试关卡上跑通验证标准
5. ⬜ 提炼经验，决定是否启用 [ADR-0003](docs/adr/0003-jump-curve-via-assist-forces.md) 的辅助力 / 切换到 Box+脚趾，更新本文档
6. ⬜ 规划下一个原型
