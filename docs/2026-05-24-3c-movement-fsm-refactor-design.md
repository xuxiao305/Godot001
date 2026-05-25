# 3C 角色 — MovementState FSM 重构

| 字段 | 值 |
|---|---|
| 日期 | 2026-05-24 |
| 状态 | Draft（待审） |
| 类型 | 代码重构（无新行为、无新参数、无新架构决策） |
| 影响范围 | `Scripts/Prototypes/3C/player.gd`、新增 `movement_state.gd` 及其测试、`debug_panel.gd` 一处显示调用 |
| 物理输出 | **与改前逐帧等价**（regression guard） |

**相关文档：**
- [3C-prototype-design.md](3C-prototype-design.md) §4.7（状态机草图）— 本设计是 §4.7 的代码化实兑现
- [ADR-0001 内在发动机派](adr/0001-inner-engine-school.md) — 不变量来源
- [CONTEXT.md](CONTEXT.md) — 术语

---

## 1. 背景

当前 `Scripts/Prototypes/3C/player.gd` 的 `_integrate_forces` 约 65 行，单函数线性堆叠 5 件事（接地检测、计时器、跳跃触发、力的累加、状态字符串）。`current_state` 字符串字段位于函数末尾，仅供 Debug 面板显示，不参与控制流。

3C 原型设计 §4.7 已经画出 4 态 FSM 草图 `Idle ↔ Running → Rising → Falling`，但当前代码中只以"显示字符串"形式存在。

本次重构把这张图实兑现为一个**派生型 FSM**，目的是**提升可读性**，为后续维护减负。不为任何尚未存在的行为做铺垫。

## 2. 范围

### 2.1 ✅ 包含

- 新增 helper 文件 `Scripts/Prototypes/3C/movement_state.gd`（纯函数静态类，仿 `EngineTorque` 风格）
- 重排 `player.gd::_integrate_forces` 为"观察 → 计时器 → 输入 → 力 → 应用"五段
- 抽出私有方法 `_compute_engine_force_x()`
- 新增 `Scripts/Prototypes/3C/tests/test_movement_state.gd`（边界 case）
- `debug_panel.gd` 一处调用改为 `MovementState.to_display(player.current_state)`
- 在 3C-prototype-design.md §4.7 加一行小注，指明"4 态为观察口径"

### 2.2 ❌ 不包含

- 不引入 State 对象 / enter / exit / 转换表
- 不新增状态（Landed / JumpHolding / Coyote / Apex 都不做）
- 不接动画、不发状态变化信号
- 不改 `JumpController` / `InputBuffer` / `EngineTorque` / `GroundCheck` 行为
- 不新增 export 调参字段（5.0 阈值保持硬编码常量）
- 不改变任何物理输出
- 不修订 ADR

## 3. 设计

### 3.1 不变量 (invariants)

1. **状态是观察口径，不是力的分配权威**：`current_state` 由 `(is_grounded, vx, vy)` 每帧派生。不存在"按下某键就强行切到某状态"。
2. **力的分发仍按 Ground/Air 二分**（与现状一致）。v1 没有"每状态独立力配方"的需求；4 态信息量在力分发层面等价于 2 态，差异只在命名/可读性/可观察性。
3. **ADR-0001 不动**：仍只 `apply_force` / `apply_impulse`，绝不写 `linear_velocity`。
4. **现有 helper 行为零变化**。

### 3.2 新文件 `Scripts/Prototypes/3C/movement_state.gd`

```gdscript
# 角色运动状态枚举 + 从物理观测派生当前状态。
# 状态是"观察口径"，不接管力的分发（详见 3C-prototype-design §4.7）。
class_name MovementState
extends RefCounted

enum State { IDLE, RUNNING, RISING, FALLING }

const SPEED_IDLE_THRESHOLD: float = 5.0  # 与 player.gd 改前同值

static func derive(is_grounded: bool, vx: float, vy: float) -> State:
    if is_grounded:
        return State.IDLE if absf(vx) < SPEED_IDLE_THRESHOLD else State.RUNNING
    return State.RISING if vy < 0.0 else State.FALLING

static func is_grounded_state(s: State) -> bool:
    return s == State.IDLE or s == State.RUNNING

static func to_display(s: State) -> String:
    match s:
        State.IDLE: return "Idle"
        State.RUNNING: return "Running"
        State.RISING: return "Rising"
        State.FALLING: return "Falling"
    return "?"
```

纯静态调用，无内部状态、不持有引用、可单测。与现有 `EngineTorque` 文件风格对齐。

### 3.3 `player.gd` 改造

**字段变更：**

| 改前 | 改后 |
|---|---|
| `var current_state: String = "Idle"` | `var current_state: MovementState.State = MovementState.State.IDLE` |

字段名保持 `current_state` 不变，减少 debug_panel 改动面。

**`_integrate_forces` 重排（按"观察 → 输入 → 力 → 应用"顺序）：**

```gdscript
func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
    # === 1. 观察物理 ===
    _ground_debounce.buffer_frames = ground_state_buffer_frames
    var gc := GroundCheck.check(state, cos_theta_max)
    is_grounded = _ground_debounce.feed(gc.grounded)
    ground_normal_y = gc.min_normal_y if gc.grounded else 0.0
    current_state = MovementState.derive(
        is_grounded, state.linear_velocity.x, state.linear_velocity.y
    )

    # === 2. 更新计时器 ===
    var now := Time.get_ticks_msec() / 1000.0
    _input_buf.coyote_time = coyote_time
    _input_buf.jump_buffer_time = jump_buffer_time
    _input_buf.update_grounded(is_grounded, now)

    # === 3. 处理跳跃输入 ===
    if Input.is_action_just_pressed("Jump"):
        _input_buf.on_jump_pressed(now)
    var can_jump_now := _input_buf.can_buffer(now) and (is_grounded or _input_buf.can_coyote(now))
    if can_jump_now and not _jump.hold_active:
        state.apply_central_impulse(_jump.trigger_jump(j_jump_initial, f_jump_hold, hold_window_max))
        _input_buf.consume_buffer()
        if not is_grounded:
            _input_buf.consume_coyote()

    # === 4. 累加力 ===
    var force := Vector2(0, gravity_y * mass)
    force.x += _compute_engine_force_x(state.linear_velocity.x)
    force += _jump.tick(state.step, Input.is_action_pressed("Jump"), state.linear_velocity.y)

    # === 5. 应用 ===
    net_force_this_frame = force
    state.apply_central_force(force)


func _compute_engine_force_x(vx: float) -> float:
    var input_dir := Input.get_axis("Left", "Right")
    var v_target := input_dir * v_max
    var on_ground := MovementState.is_grounded_state(current_state)
    var f_max := f_max_ground if on_ground else f_max_air
    var f := EngineTorque.compute(vx, v_target, f_max, saturation_full)
    if on_ground and input_dir == 0.0 and absf(vx) > 0.01:
        f -= signf(vx) * f_active_brake
    return f
```

**结构差异：**

| 维度 | 改前 | 改后 |
|---|---|---|
| `_integrate_forces` 行数 | ~65 | ~25 |
| 段落注释 | 散布、序号断 | 5 段 `# === N. ===` 顺次 |
| 状态推导位置 | 函数末尾（仅显示） | 函数顶部（成为后续输入） |
| 力分发的"地面/空中" | 直接读 `is_grounded` | 通过 `MovementState.is_grounded_state(current_state)` |
| 新增私有方法 | — | `_compute_engine_force_x` |

最后一行的"通过 state 表达地面/空中"是关键：等价转换、不改逻辑，但让 state 不再是纯装饰、让 spec §4.7 的图在代码中可见。

### 3.4 `debug_panel.gd` 改造

当前直接读 `player.current_state`（String）。改后调用方负责显示翻译：

```gdscript
# 改前
state_label.text = player.current_state
# 改后
state_label.text = MovementState.to_display(player.current_state)
```

一处修改。player 不挂 getter（避免派生字段语义重复）。

### 3.5 新测试 `Scripts/Prototypes/3C/tests/test_movement_state.gd`

仿 `test_input_buffer.gd` / `test_engine_torque.gd` 风格。覆盖：

| 输入 | 期望 | 用途 |
|---|---|---|
| `derive(true, 0.0, 0.0)` | IDLE | 静止接地基线 |
| `derive(true, 4.99, 0.0)` | IDLE | Idle 阈值下边界（含） |
| `derive(true, 5.0, 0.0)` | RUNNING | Idle/Running 切换点（`<` 不含等号） |
| `derive(true, -5.0, 0.0)` | RUNNING | 负向 vx 同样按绝对值判 |
| `derive(false, 0.0, -0.01)` | RISING | 离地上升 |
| `derive(false, 0.0, 0.0)` | FALLING | vy=0 算 Falling（保持现有 `vy < 0.0` 语义） |
| `derive(false, 0.0, 0.01)` | FALLING | 离地下落 |
| `is_grounded_state(IDLE)` | true | 查询助手 |
| `is_grounded_state(RUNNING)` | true | |
| `is_grounded_state(RISING)` | false | |
| `is_grounded_state(FALLING)` | false | |
| `to_display(IDLE / RUNNING / RISING / FALLING)` | `"Idle"` / `"Running"` / `"Rising"` / `"Falling"` | 显示翻译 |

### 3.6 spec §4.7 注释新增

在 3C-prototype-design.md §4.7 末尾追加一行：

> **实现备注**：4 态是观察口径（每帧从 `is_grounded` / `vx` / `vy` 派生）；力的分发仍按 Ground/Air 二分。详见 `Scripts/Prototypes/3C/movement_state.gd`（位于 godot 项目树）。

防止后来人误读"4 个状态意味着 4 套力配方"。

## 4. 验证标准

按 memory `feedback_verify_each_edit` 的 5 层验证，本次改动定级到 **第 5 层（人工 F6）**，因为涉及物理代码路径（即便等价转换）。

完成判定：

- [ ] `test_movement_state.gd` 全部用例通过
- [ ] 现有 `test_engine_torque.gd` / `test_input_buffer.gd` 不退化
- [ ] `player.tscn` 在 Godot 编辑器里能正常加载（parse + import 通过）
- [ ] `test_level.tscn` F6 启动，进行如下手感复盘：
  - 左右移动启动 / 滑行手感与改前一致
  - 跳跃高度、长按短按差异与改前一致
  - 离地 coyote 起跳仍可触发
  - 落地前 buffer 起跳仍可触发
  - Debug 面板 state 字段显示 Idle/Running/Rising/Falling 正常切换，无 `?` 或空字符串
- [ ] **用户**手动 F6 复测一次并确认手感无回归（物理改动必须人工签字）

## 5. 风险与缓解

| 风险 | 缓解 |
|---|---|
| `current_state` 字段类型从 String 变 enum，可能漏改 debug_panel 或其它读取点 | 改造前用 grep 全工程搜 `current_state`；改造后跑 `test_movement_state.gd` + smoke run 验证 |
| 阈值 5.0 重复出现在 helper 与原代码 | 改造时一并迁移到 `MovementState.SPEED_IDLE_THRESHOLD` 常量，player.gd 不再硬编码 5.0 |
| 等价转换看似无害但仍可能引入细微回归（如条件求值顺序） | 强制人工 F6（不接受"测试过就行"） |

## 6. 下一步

1. ✅ 用户审阅本设计 ← **当前节点**
2. ⬜ 进入实现计划阶段（writing-plans skill）：拆解为可执行步骤
3. ⬜ 执行实现
4. ⬜ 用户 F6 手感复测签字
