# 3C 角色 — 自管地面摩擦（Path Y）

| 字段 | 值 |
|---|---|
| 日期 | 2026-05-25 |
| 状态 | Draft（待审） |
| 类型 | 物理模型迁移（行为变化、需人工 F6 签字） |
| 影响范围 | `Scenes/Prototypes/3C/player.tscn`、`Scripts/Prototypes/3C/player.gd`、新增 `ground_friction.gd` 及其测试、`Scenes/Prototypes/3C/test_level.tscn`（Mud 校准） |
| 物理输出 | **会变化**（落地保留 vx / 不再卡墙 / 极速略降 / 松手能停下） |
| ADR | 新增 [ADR-0011 角色摩擦自管派](adr/0011-custom-friction-over-box2d.md) |

**相关文档：**
- [3C-prototype-design.md](3C-prototype-design.md) §4.2 — 地面参数（本设计后追加摩擦实现指针）
- [ADR-0001 内在发动机派](adr/0001-inner-engine-school.md) — 哲学源头
- [ADR-0011 角色摩擦自管派](adr/0011-custom-friction-over-box2d.md) — 本次决策
- [2026-05-24-3c-movement-fsm-refactor-design.md](2026-05-24-3c-movement-fsm-refactor-design.md) — 正交的 FSM 重构，**先于本设计实施**

---

## 1. 背景

3C 原型 v1 跑通后的 F6 实测发现 Box2D Coulomb 摩擦带来的三类系统性问题：

1. **落地丢横向速度**：从平台带 vx 落地，vx 一帧内被抹光
2. **空中贴墙卡住**：按方向键贴 Wall / Stair 侧面，重力被摩擦平衡，玩家挂在墙上
3. **未来的扩展难**：每加一个新场景（坡面、堆叠、移动平台）都可能撞同一个耦合

根因分析与方案比选见 [ADR-0011](adr/0011-custom-friction-over-box2d.md)。本设计是其落地实施方案。

## 2. 范围

### 2.1 ✅ 包含

- `Player.tscn` 的 `PhysicsMaterial.friction` 改为 0.0
- 新增 helper `Scripts/Prototypes/3C/ground_friction.gd`（纯静态 RefCounted）
- `Scripts/Prototypes/3C/player.gd` 在地面分支调用 GroundFriction
- 新增 `Scripts/Prototypes/3C/tests/test_ground_friction.gd`
- `test_level.tscn` 的 `MatMud.friction` 从 10.0 调到 2.0（不再"禁区"）
- 3C-prototype-design.md §4.2 末尾加一行指针
- 新增 ADR-0011（已完成）

### 2.2 ❌ 不包含

- 不删 `f_active_brake`（保留作为可选叠加刹车，默认 0）
- 不动 `EngineTorque` / `JumpController` / `InputBuffer` / `GroundCheck`
- 不实现坡面投影摩擦（v1 测试关无真斜坡）
- 不实现多接触面 μ 混合（接受"取 n.y 最负"的简单策略）
- 不区分静/动摩擦（统一用同一个 μ）
- 不调 `v_max` 补偿极速下降（v1 接受 ~738 px/s）

## 3. 设计

### 3.1 不变量

1. **ADR-0001 保持**：只 `apply_force` / `apply_impulse`，不写 `linear_velocity`
2. **ADR-0004 保持**：空中既不摩擦也不刹车，水平速度永久保持
3. **空中行为零变化**：`EngineTorque` 空中分支不动
4. **既有 helper 行为零变化**：FSM 重构后的 5 段结构里只插入摩擦一行

### 3.2 `Player.tscn` 改动

```diff
 [sub_resource type="PhysicsMaterial" id="PlayerMat"]
+friction = 0.0
```

Box2D 合成 μ = √(0 × μ_surface) = 0，所有内置摩擦失效。落地丢 vx / 卡墙 / 卡侧面全部消失。

### 3.3 新文件 `Scripts/Prototypes/3C/ground_friction.gd`

```gdscript
# Scripts/Prototypes/3C/ground_friction.gd
# 自定义地面摩擦 —— Coulomb 模型 F = -sign(vx) · μ · m · g。
# 仅在地面分支调用。空中不应使用本模块（违反 ADR-0004）。
# 设计：ADR-0011 角色摩擦自管派
class_name GroundFriction
extends RefCounted

const DEADBAND: float = 1.0  # px/s，低于此 |vx| 不施加摩擦

# 找出最"地面"的 contact 并读其 PhysicsMaterial.friction。
# 找不到合适接触 → 返回 0（呼叫方应保证已经 is_grounded）。
static func read_ground_mu(state: PhysicsDirectBodyState2D, cos_theta_max: float) -> float:
    var mu := 0.0
    var min_ny := -cos_theta_max
    for i in state.get_contact_count():
        var n := state.get_contact_local_normal(i)
        if n.y < min_ny:
            min_ny = n.y
            var obj := state.get_contact_collider_object(i)
            if obj is PhysicsBody2D:
                var mat: PhysicsMaterial = obj.physics_material_override
                mu = mat.friction if mat != null else 1.0
    return mu

# 返回应施加的水平摩擦力（已带方向）。
static func compute_force(vx: float, mass: float, g: float, mu: float) -> float:
    if absf(vx) < DEADBAND or mu <= 0.0:
        return 0.0
    return -signf(vx) * mu * mass * g
```

约 30 行，纯静态、无状态、可单测（compute_force 部分）。风格仿 `EngineTorque` / `GroundCheck`。

### 3.4 `player.gd` 改动

**新增 preload：**

```gdscript
const GroundFriction := preload("res://Scripts/Prototypes/3C/ground_friction.gd")
```

**FSM 重构后的"4. 累加力"段内**（地面分支），原有：

```gdscript
if is_grounded:
    f_engine = EngineTorque.compute(v_cur_x, v_target, f_max_ground, saturation_full)
    if input_dir == 0.0 and absf(v_cur_x) > 0.01:
        f_engine -= signf(v_cur_x) * f_active_brake
else:
    f_engine = EngineTorque.compute(v_cur_x, v_target, f_max_air, saturation_full)
```

改为：

```gdscript
if is_grounded:
    f_engine = EngineTorque.compute(v_cur_x, v_target, f_max_ground, saturation_full)
    # 自定义 Coulomb 摩擦（ADR-0011）
    var mu := GroundFriction.read_ground_mu(state, cos_theta_max)
    f_engine += GroundFriction.compute_force(v_cur_x, mass, gravity_y, mu)
    # f_active_brake 保留（叠加在摩擦之上，默认 0）
    if input_dir == 0.0 and absf(v_cur_x) > 0.01:
        f_engine -= signf(v_cur_x) * f_active_brake
else:
    f_engine = EngineTorque.compute(v_cur_x, v_target, f_max_air, saturation_full)
```

合计有效新增 +3 行。如果 FSM 重构已经把这段抽到 `_compute_engine_force_x()` 私有方法里，则在该方法内修改。

### 3.5 `test_level.tscn` 改动（Mud 重新校准）

```diff
 [sub_resource type="PhysicsMaterial" id="MatMud"]
-friction = 10.0
+friction = 2.0
```

理由：`μ × g = 2 × 2500 = 5000 px/s²` 的减速，配合 `f_max_ground = 8000` 的发动机，给出 ~675 px/s 的 Mud 极速（vs Walkway ~738）——"明显慢但能走"。

如果实施后觉得不够沼泽感，可在 inspector 实时调到 2.5–3.0。**不要回到 10.0**（会变"禁区"）。

### 3.6 行为变化预览

| 场景 | 改前 | 改后 |
|---|---|---|
| Walkway 跑达极速 | 800 px/s | ~738 px/s |
| Walkway 松手停下 | 永不停（f_active_brake=0） | ~0.3s |
| Ice 松手停下 | 永不停 | ~0.6s |
| Mud 顶速（μ=2.0） | 走不动（Box2D 摩擦把 vx 抹掉） | ~675 px/s |
| 跳上 Stair3 vx 保留 | 大部分丢失 | ✅ 完全保留 |
| 空中贴 Wall 下落 | 卡住 | ✅ 正常下落 |
| 空中贴 Stair2 侧面下落 | 卡住 | ✅ 正常下落 |
| 落地撞到 DynamicBox | 不变 | 不变（DynamicBox 不在此设计范围） |

## 4. 新测试 `Scripts/Prototypes/3C/tests/test_ground_friction.gd`

`compute_force` 全覆盖；`read_ground_mu` 因 `PhysicsDirectBodyState2D` 无法 mock 跳过单测（靠 F6 覆盖）。

| 用例 | 期望 |
|---|---|
| `compute_force(800.0, 1.0, 2500.0, 1.0)` | -2500.0（Walkway 朝右跑） |
| `compute_force(-800.0, 1.0, 2500.0, 1.0)` | +2500.0（朝左跑对称） |
| `compute_force(800.0, 1.0, 2500.0, 0.5)` | -1250.0（Ice） |
| `compute_force(800.0, 1.0, 2500.0, 2.0)` | -5000.0（推荐 Mud） |
| `compute_force(0.5, 1.0, 2500.0, 1.0)` | 0.0（DEADBAND） |
| `compute_force(-0.5, 1.0, 2500.0, 1.0)` | 0.0（DEADBAND 负向） |
| `compute_force(800.0, 1.0, 2500.0, 0.0)` | 0.0（μ=0） |
| `compute_force(800.0, 1.0, 2500.0, -1.0)` | 0.0（μ ≤ 0 守卫） |
| `compute_force(800.0, 2.0, 2500.0, 1.0)` | -5000.0（mass=2 验证线性） |

## 5. 验证标准

按 memory `feedback_verify_each_edit` 定级到 **第 5 层（人工 F6）**——本次改动改变物理输出。

- [ ] `test_ground_friction.gd` 全部用例通过
- [ ] 现有 `test_engine_torque.gd` / `test_input_buffer.gd` / `test_movement_state.gd`（FSM 重构产出）不退化
- [ ] `player.tscn` / `test_level.tscn` 在编辑器里 parse + import 通过
- [ ] F6 启动 `test_level.tscn`，复测项：
  - **Wall 不再卡**：朝右贴 Wall 起跳，应自然下落到底
  - **Stair 侧面不再卡**：起跳撞 Stair3 侧面，应自然下落
  - **落地保留 vx**：从 PlatformA(y=420) 助跑跳到 Walkway(y=564)，水平速度明显保留
  - **Walkway 减速感**：松手能在 ~0.3s 内停下
  - **Ice 比 Walkway 明显滑**：松手要 ~0.6s 才停
  - **Mud（μ=2.0）能走但慢**：顶速观感 ~675 px/s
  - **Walkway 极速**：跑顶速 ~738 px/s（vs 改前 800）
  - **f_active_brake 仍生效**：Debug 面板拖到 5000，松手停止时间应显著缩短
  - **DynamicBox 互动不退化**：推箱子手感无回归
- [ ] **用户**手动 F6 复测并签字（物理变化必须人工确认）

## 6. 风险与缓解

| 风险 | 缓解 |
|---|---|
| FSM 重构尚未完成时直接做本设计 → 代码骨架不齐，"插入摩擦一行"的位置不明确 | 严格按顺序：FSM 重构先 merge → 再做本设计 |
| 极速从 800 降到 738 玩家不接受 | 在 inspector 调高 `v_max` 至 870 即可补偿；本设计不强制 |
| Mud μ=2.0 仍觉得太黏/太松 | inspector 实时调 1.5–3.0 区间找手感 |
| 玩家踩在两块不同 μ 的边界（如 Ice/Walkway 拼接处） | v1 接受闪烁；后续如成为问题再加平均策略 |
| 读 collider 的 `physics_material_override` 返回 null（设计意外） | `read_ground_mu` 兜底为 1.0（视作 Walkway 默认） |

## 7. 下一步

1. ✅ 用户审阅本设计 ← **当前节点**
2. ⬜ 进入实现计划阶段（writing-plans skill）：拆解为可执行步骤
3. ⬜ **先**完成 [FSM 重构](2026-05-24-3c-movement-fsm-refactor-design.md) 的实施 + F6 签字
4. ⬜ **后**完成本设计的实施 + F6 签字
