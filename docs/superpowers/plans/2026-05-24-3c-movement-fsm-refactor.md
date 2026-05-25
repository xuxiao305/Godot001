# 3C 角色 — MovementState FSM 重构实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 [3C-prototype-design.md](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/3C-prototype-design.md) §4.7 已经画出来的 4 态 FSM 草图（`Idle / Running / Rising / Falling`）从"player.gd 末尾的显示字符串"提升为一个**派生型 helper + 等价重构**，使 `_integrate_forces` 从 65 行的线性堆叠变为 5 段清晰流程。物理行为**逐帧等价**，不引入任何新行为或新调参。

**Architecture:** 新增静态纯函数 helper `MovementState`（仿 `EngineTorque` 风格），暴露 `derive() / is_grounded_state() / to_display()`。`player.gd` 把 `current_state: String` 改为 `current_state: MovementState.State`，重排 `_integrate_forces` 为"观察 → 计时器 → 输入 → 力 → 应用"，抽出私有 `_compute_engine_force_x()`。`debug_panel.gd` 一处调用改为 `MovementState.to_display(...)`。**状态是观察口径，不接管力的分发**（不变量见 spec §3.1）。

**Tech Stack:** Godot 4.6, GDScript, godot-box2d v0.9.11。Godot 二进制位于 `D:/Godot/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe`（注意 `.exe` 是文件夹名）。单元测试以场景 + `assert()` + `print()` 形式存在，可通过 headless smoke run 验证；物理手感最终签字由用户 F6 完成（按 memory `feedback_verify_each_edit`：物理代码路径必须人工 F6）。

**Spec 引用：** [2026-05-24-3c-movement-fsm-refactor-design.md](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/2026-05-24-3c-movement-fsm-refactor-design.md)（已通过用户审阅，2026-05-24）

---

## 验证约定（按 memory `feedback_verify_each_edit`）

每个 task 的 implementer subagent 在 commit 前**必须**按改动性质跑 Godot 验证，并把 stderr/grep 结果粘进 report。SDD controller 会把下面这段注入 implementer prompt：

```text
Before reporting DONE, you MUST run Godot verification per
~/.claude/projects/d--GoDot-Projects-2DPlatformerSample/memory/feedback_verify_each_edit.md.

Godot binary (absolute path):
  D:/Godot/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe
(yes, the `.exe` segment is a folder name)

Layer 1 (parse) — for every .gd you touched:
  & "<godot>" --headless --check-only --script "<path>"
  Expect EXIT=0 and no SCRIPT ERROR.

Layer 2 (import) — once after all .tscn/.gd edits:
  & "<godot>" --headless --quit
  Expect EXIT=0 and no new error lines (the debug_panel uid warning is pre-existing).

Layer 3 (smoke run) — when a runnable scene was changed/added or _ready/物理 step touched:
  & "<godot>" --headless "res://<scene.tscn>" 2>&1
  Grep for "SCRIPT ERROR|Invalid call|Invalid set|Invalid get|Null instance|Node not found|ERROR:" — must be empty.
  For test scenes, also expect the explicit "[TEST <name>] ALL PASS" line.

Paste full stderr / grep result into your report. If any layer fails,
fix and re-run before reporting. Do not report DONE without evidence.

If this change affects physics / input / camera / visual / audio,
report DONE_WITH_CONCERNS and explicitly request human F6 of <scene>
observing <specific behavior>. Do not claim the physics/feel is correct.
```

Spec-reviewer 也加一条 acceptance criterion：**implementer 的 report 必须包含 Godot 验证 evidence，否则 reject**。

---

## 文件结构

```
Scripts/Prototypes/3C/
├── movement_state.gd                 ← 新增（纯静态类）
├── player.gd                          ← 修改（字段类型 + _integrate_forces 重排 + 抽方法）
├── debug_panel.gd                     ← 修改（一处显示调用）
└── tests/
    └── test_movement_state.gd         ← 新增

Scenes/Prototypes/3C/tests/
└── test_movement_state.tscn           ← 新增（仿 test_input_buffer.tscn 风格）

D:/ObsidianNote/.../docs/
└── 3C-prototype-design.md             ← §4.7 末尾追加一行实现备注
```

**职责划分：**
- `movement_state.gd` — 纯静态函数，无内部状态，可在测试场景独立断言。
- `player.gd` — 状态推导从函数尾部移到顶部；力分发用 `MovementState.is_grounded_state()` 表达"地面/空中"二分。
- `debug_panel.gd` — 只改 `current_state` 显示一处，其它逻辑不动。

**不改：** `engine_torque.gd` / `input_buffer.gd` / `jump_controller.gd` / `ground_check.gd` / `camera_follow.gd`。

---

## Task 1: 新增 `MovementState` helper 及其测试场景

**目的：** 创建纯函数 helper，提供"从物理观测派生状态"+"查询助手"+"显示翻译"三个能力。测试覆盖所有边界 case，确保后续 player.gd 重构有可信的基础。

**Files:**
- Create: `Scripts/Prototypes/3C/movement_state.gd`
- Create: `Scripts/Prototypes/3C/tests/test_movement_state.gd`
- Create: `Scenes/Prototypes/3C/tests/test_movement_state.tscn`

- [ ] **Step 1: 写测试脚本（先写测试 — TDD 红）**

`Scripts/Prototypes/3C/tests/test_movement_state.gd`:

```gdscript
# Scripts/Prototypes/3C/tests/test_movement_state.gd
# 纯函数测试 —— 在 _ready 时跑断言，全部通过则打印 PASS。
extends Node

const MovementState := preload("res://Scripts/Prototypes/3C/movement_state.gd")

func _ready() -> void:
    # 1) 接地：|vx| < 5.0 → Idle；>= 5.0 → Running
    assert(MovementState.derive(true, 0.0, 0.0) == MovementState.State.IDLE,
        "静止接地应为 Idle")
    assert(MovementState.derive(true, 4.99, 0.0) == MovementState.State.IDLE,
        "vx=4.99 接地（阈值下边界，<）应为 Idle")
    assert(MovementState.derive(true, 5.0, 0.0) == MovementState.State.RUNNING,
        "vx=5.0 接地（阈值上边界，5.0 不满足 <5.0）应为 Running")
    assert(MovementState.derive(true, -5.0, 0.0) == MovementState.State.RUNNING,
        "vx=-5.0 接地应按绝对值判为 Running")
    assert(MovementState.derive(true, 100.0, 999.0) == MovementState.State.RUNNING,
        "接地态忽略 vy")

    # 2) 离地：vy < 0 → Rising；vy >= 0 → Falling（保持 player.gd 改前的 vy<0 语义）
    assert(MovementState.derive(false, 0.0, -0.01) == MovementState.State.RISING,
        "离地 vy=-0.01 应为 Rising")
    assert(MovementState.derive(false, 0.0, 0.0) == MovementState.State.FALLING,
        "离地 vy=0.0 应为 Falling（vy<0 不含等号）")
    assert(MovementState.derive(false, 0.0, 0.01) == MovementState.State.FALLING,
        "离地 vy=0.01 应为 Falling")
    assert(MovementState.derive(false, 999.0, -100.0) == MovementState.State.RISING,
        "离地态忽略 vx 大小")

    # 3) is_grounded_state 查询助手
    assert(MovementState.is_grounded_state(MovementState.State.IDLE),
        "IDLE 应为接地态")
    assert(MovementState.is_grounded_state(MovementState.State.RUNNING),
        "RUNNING 应为接地态")
    assert(not MovementState.is_grounded_state(MovementState.State.RISING),
        "RISING 应为非接地态")
    assert(not MovementState.is_grounded_state(MovementState.State.FALLING),
        "FALLING 应为非接地态")

    # 4) to_display 显示翻译
    assert(MovementState.to_display(MovementState.State.IDLE) == "Idle",
        "IDLE 显示为 'Idle'")
    assert(MovementState.to_display(MovementState.State.RUNNING) == "Running",
        "RUNNING 显示为 'Running'")
    assert(MovementState.to_display(MovementState.State.RISING) == "Rising",
        "RISING 显示为 'Rising'")
    assert(MovementState.to_display(MovementState.State.FALLING) == "Falling",
        "FALLING 显示为 'Falling'")

    print("[TEST movement_state] ALL PASS")
    get_tree().quit()
```

- [ ] **Step 2: 写测试场景（仿 `test_input_buffer.tscn` 格式）**

`Scenes/Prototypes/3C/tests/test_movement_state.tscn`:

```
[gd_scene load_steps=2 format=3 uid="uid://dtmvst001"]

[ext_resource type="Script" uid="uid://stmvst001" path="res://Scripts/Prototypes/3C/tests/test_movement_state.gd" id="1_mvst"]

[node name="TestMovementState" type="Node"]
script = ExtResource("1_mvst")
```

> **注意：** ext_resource 的 `uid` 是占位值，与 Godot 自动生成的 `.gd.uid` 不一定匹配。这与现有 `test_input_buffer.tscn` 的做法一致（其占位 uid `stipbuf001` 也与实际 `.gd.uid` 不匹配，Godot 通过 path 兜底解析）。无需手动同步 — 用户首次在编辑器里打开项目时，Godot 会按 path 兜底解析并在再保存时静默更新。`uid` 属性本身必须存在（memory `tscn_needs_uid_for_packedscene_refs`：缺失 `uid` 才会让 ext_resource 解析失败）。

- [ ] **Step 3: 写 helper 实现（TDD 绿）**

`Scripts/Prototypes/3C/movement_state.gd`:

```gdscript
# Scripts/Prototypes/3C/movement_state.gd
# 角色运动状态枚举 + 从物理观测派生当前状态。
# 状态是"观察口径"，不接管力的分发（详见 3C-prototype-design.md §4.7）。
class_name MovementState
extends RefCounted

enum State { IDLE, RUNNING, RISING, FALLING }

const SPEED_IDLE_THRESHOLD: float = 5.0  # 与 player.gd 改前同值

# 从物理观测派生当前状态。纯函数，无副作用。
static func derive(is_grounded: bool, vx: float, vy: float) -> State:
    if is_grounded:
        return State.IDLE if absf(vx) < SPEED_IDLE_THRESHOLD else State.RUNNING
    return State.RISING if vy < 0.0 else State.FALLING

# 查询助手：状态属于"接地态"么？力分发按此分支选 ground vs air。
static func is_grounded_state(s: State) -> bool:
    return s == State.IDLE or s == State.RUNNING

# 显示翻译：给 Debug 面板用。
static func to_display(s: State) -> String:
    match s:
        State.IDLE: return "Idle"
        State.RUNNING: return "Running"
        State.RISING: return "Rising"
        State.FALLING: return "Falling"
    return "?"
```

- [ ] **Step 4: 静态等价性自检（subagent 必做）**

逐条核对：
- `derive()` 内 `is_grounded` 分支用 `absf(vx) < 5.0` —— 与改前 `player.gd:112` 的 `absf(vx) < 5.0` 一致 ✓
- 离地分支用 `vy < 0.0` —— 与改前 `player.gd:117` 的 `vy < 0.0` 一致 ✓
- 测试断言覆盖所有 12 条 case；每条断言的左值由 `derive()` 真实计算路径产出（不存在硬编码"应该是 X"但实际算法返回 Y 的情况）✓

如发现任何不一致，**回到 Step 3 修正实现**，不要修测试。

- [ ] **Step 5: Commit**

```bash
git add Scripts/Prototypes/3C/movement_state.gd \
        Scripts/Prototypes/3C/tests/test_movement_state.gd \
        Scenes/Prototypes/3C/tests/test_movement_state.tscn
git commit -m "feat(3c): add MovementState observation helper + tests

Pure static functions to derive Idle/Running/Rising/Falling from
(is_grounded, vx, vy). Used to lift the 4-state diagram from
player.gd's display-only string into a proper observation口径.

Force dispatch still follows Ground/Air binary; the 4 states carry
no per-state force config in v1 (see design doc §3.1 invariant 2).

Tests cover threshold boundaries (vx=4.99 vs 5.0, vy=0 as Falling)
and all helper queries.

Refs: docs/superpowers/plans/2026-05-24-3c-movement-fsm-refactor.md Task 1"
```

---

## Task 2: 重构 `player.gd` + 同步 `debug_panel.gd`

**目的：** 把 `current_state` 从 String 升级为 `MovementState.State`，并把 `_integrate_forces` 重排为 5 段清晰流程。**两文件必须同一提交**，否则中间状态会因字段类型冲突而无法运行。

**Files:**
- Modify: `Scripts/Prototypes/3C/player.gd:9-11`（追加 `MovementState` preload）
- Modify: `Scripts/Prototypes/3C/player.gd:40`（字段类型变更）
- Modify: `Scripts/Prototypes/3C/player.gd:60-124`（`_integrate_forces` 重排 + 新增 `_compute_engine_force_x`）
- Modify: `Scripts/Prototypes/3C/debug_panel.gd:46-51`（`_process` 的显示翻译）

- [ ] **Step 1: 在 player.gd 顶部追加 MovementState preload**

`player.gd:9-11` 改前：

```gdscript
const EngineTorque := preload("res://Scripts/Prototypes/3C/engine_torque.gd")
const JumpController := preload("res://Scripts/Prototypes/3C/jump_controller.gd")
const InputBuffer := preload("res://Scripts/Prototypes/3C/input_buffer.gd")
```

改后（追加一行）：

```gdscript
const EngineTorque := preload("res://Scripts/Prototypes/3C/engine_torque.gd")
const JumpController := preload("res://Scripts/Prototypes/3C/jump_controller.gd")
const InputBuffer := preload("res://Scripts/Prototypes/3C/input_buffer.gd")
const MovementState := preload("res://Scripts/Prototypes/3C/movement_state.gd")
```

- [ ] **Step 2: 变更 `current_state` 字段类型**

`player.gd:40` 改前：

```gdscript
var current_state: String = "Idle"
```

改后：

```gdscript
var current_state: MovementState.State = MovementState.State.IDLE
```

字段名保持 `current_state`，减少 debug_panel 改动面。

- [ ] **Step 3: 替换 `_integrate_forces` 整个函数**

把 `player.gd:60-124` 现有的 `_integrate_forces` 函数（不含函数注释行 :59，但替换函数本身）整体替换为：

```gdscript
# 用 _integrate_forces 而非 _physics_process —— Box2D 提供完整 state，且这是 Godot 推荐的物理操作时机。
func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
    # === 1. 观察物理 ===
    _ground_debounce.buffer_frames = ground_state_buffer_frames
    var gc := GroundCheck.check(state, cos_theta_max)
    is_grounded = _ground_debounce.feed(gc.grounded)
    # 未接地时不暴露哨兵值 1.0（"完美朝下"的假象），归零方便 Debug 面板读
    ground_normal_y = gc.min_normal_y if gc.grounded else 0.0
    current_state = MovementState.derive(
        is_grounded, state.linear_velocity.x, state.linear_velocity.y
    )

    # === 2. 更新计时器 ===
    var now := Time.get_ticks_msec() / 1000.0
    # 同步 export 滑条值（Debug 面板会实时改这两个）
    _input_buf.coyote_time = coyote_time
    _input_buf.jump_buffer_time = jump_buffer_time
    _input_buf.update_grounded(is_grounded, now)

    # === 3. 处理跳跃输入（Coyote / Buffer） ===
    if Input.is_action_just_pressed("Jump"):
        _input_buf.on_jump_pressed(now)
    # 满足条件即起跳：
    #   - 接地 + 当前 buffer 有效（落地瞬间按下生效）
    #   - 不接地 + coyote 窗口内 + 当前 buffer 有效
    var can_jump_now := _input_buf.can_buffer(now) and (is_grounded or _input_buf.can_coyote(now))
    if can_jump_now and not _jump.hold_active:
        var impulse := _jump.trigger_jump(j_jump_initial, f_jump_hold, hold_window_max)
        state.apply_central_impulse(impulse)
        _input_buf.consume_buffer()
        if not is_grounded:
            _input_buf.consume_coyote()

    # === 4. 累加力（重力 + 发动机 + 跳跃持续推力） ===
    var force := Vector2(0, gravity_y * mass)  # 恒定重力（ADR-0003）
    force.x += _compute_engine_force_x(state.linear_velocity.x)
    # 跳跃持续推力（§4.4），由 JumpController 自维护 hold_active 窗口
    force += _jump.tick(state.step, Input.is_action_pressed("Jump"), state.linear_velocity.y)

    # === 5. 应用 ===
    net_force_this_frame = force
    state.apply_central_force(force)


# 按当前状态选 ground/air 发动机配方，返回本帧水平力分量。
# 在内在发动机派下，"力的选择"是 state 唯一参与控制流的位置（详见 design §3.1）。
func _compute_engine_force_x(vx: float) -> float:
    var input_dir := Input.get_axis("Left", "Right")  # -1, 0, +1
    var v_target := input_dir * v_max
    var on_ground := MovementState.is_grounded_state(current_state)
    var f_max := f_max_ground if on_ground else f_max_air
    var f := EngineTorque.compute(vx, v_target, f_max, saturation_full)
    # 主动刹车（§4.2，默认 f_active_brake = 0）—— 仅地面态生效
    if on_ground and input_dir == 0.0 and absf(vx) > 0.01:
        f -= signf(vx) * f_active_brake
    return f
```

**关键删除：** 旧函数末尾 `# 5. 状态转换（仅用于显示，不影响物理）` 那一整段（约 13 行 if/elif 写 `current_state = "..."`）整段消失 —— 它的语义被 Step 1 顶部的 `MovementState.derive(...)` 一行替代。

- [ ] **Step 4: 修改 debug_panel.gd 的 `_process` 显示翻译**

`debug_panel.gd:1-5` 改前（顶部）：

```gdscript
# Scripts/Prototypes/3C/debug_panel.gd
# 实时滑条 + 数值显示 + JSON save/load。F1 切换可见。
# 来源：spec §4.9
class_name DebugPanel
extends CanvasLayer
```

在 `class_name DebugPanel` 行**之前**追加一行 preload（保持与其他 helper preload 约定一致），变为：

```gdscript
# Scripts/Prototypes/3C/debug_panel.gd
# 实时滑条 + 数值显示 + JSON save/load。F1 切换可见。
# 来源：spec §4.9
const MovementState := preload("res://Scripts/Prototypes/3C/movement_state.gd")

class_name DebugPanel
extends CanvasLayer
```

然后修改 `_process()` 中的显示循环。`debug_panel.gd:46-51` 改前：

```gdscript
func _process(_dt: float) -> void:
    if not visible or _player == null:
        return
    for key in READOUT_KEYS:
        if _value_labels.has(key):
            (_value_labels[key] as Label).text = "%s: %s" % [key, _player.get(key)]
```

改后：

```gdscript
func _process(_dt: float) -> void:
    if not visible or _player == null:
        return
    for key in READOUT_KEYS:
        if not _value_labels.has(key):
            continue
        var label := _value_labels[key] as Label
        if key == "current_state":
            label.text = "%s: %s" % [key, MovementState.to_display(_player.current_state)]
        else:
            label.text = "%s: %s" % [key, _player.get(key)]
```

理由：`current_state` 现在是 enum (int)，`%s` 格式化会显示 `0`/`1`/`2`/`3` 而不是 `Idle`/`Running`/...；其它字段（如 `position`、`linear_velocity`）仍按原 `_player.get(key)` 通用路径走。

- [ ] **Step 5: 静态等价性自检（subagent 必做）**

逐条核对**改前后行为是否逐帧等价**：

| 行为 | 改前 | 改后 | 等价？ |
|---|---|---|---|
| 接地检测顺序 | 函数顶部 | 函数顶部 | ✓ |
| `is_grounded` 计算 | `_ground_debounce.feed(gc.grounded)` | 同 | ✓ |
| `ground_normal_y` 三元式 | 同 | 同 | ✓ |
| `coyote_time` / `jump_buffer_time` 注入 | 接地检测后 | 接地检测后 | ✓ |
| `update_grounded` 时机 | 同 | 同 | ✓ |
| `Input.is_action_just_pressed("Jump")` → buffer | 同 | 同 | ✓ |
| `can_jump_now` 表达式 | `_input_buf.can_buffer(now) and (is_grounded or _input_buf.can_coyote(now))` | 同 | ✓ |
| 跳跃冲量 `state.apply_central_impulse(...)` 在 `_jump.trigger_jump(...)` 后立即施加 | 同 | 同 | ✓ |
| 跳跃后 `consume_buffer` / `consume_coyote` 顺序与条件 | 同 | 同 | ✓ |
| 重力 `Vector2(0, gravity_y * mass)` | 同 | 同 | ✓ |
| 发动机力：`input_dir = Input.get_axis("Left", "Right")` | 同 | 同（仅位置移到 `_compute_engine_force_x` 内） | ✓ |
| 发动机力：地面用 `f_max_ground`、空中用 `f_max_air` | 用 `if is_grounded` 二分 | 用 `MovementState.is_grounded_state(current_state)` 二分 | **关键：需验证 `MovementState.is_grounded_state(current_state)` 与 `is_grounded` 同帧同值** |
| 发动机力：`EngineTorque.compute(vx, v_target, f_max, saturation_full)` | 同 | 同 | ✓ |
| 主动刹车条件 `input_dir == 0.0 and absf(vx) > 0.01` 且仅地面态 | 同 | 同 | ✓ |
| 跳跃 hold 推力 `_jump.tick(state.step, Input.is_action_pressed("Jump"), state.linear_velocity.y)` | 同 | 同 | ✓ |
| `force` 累加顺序 | 重力 → engine.x → hold | 重力 → engine.x → hold | ✓ |
| `net_force_this_frame = force` 在 apply 前 | 同 | 同 | ✓ |
| `state.apply_central_force(force)` 在函数末尾 | 同 | 同 | ✓ |

**关键等价性证明（最后一行那条）：**

改前：`if is_grounded: f_engine = EngineTorque.compute(..., f_max_ground, ...) else: ..., f_max_air, ...`
改后：`var on_ground := MovementState.is_grounded_state(current_state)`；`current_state = MovementState.derive(is_grounded, vx, vy)`

`MovementState.is_grounded_state(MovementState.derive(is_grounded, vx, vy))`：
- 若 `is_grounded == true`：`derive` 返回 IDLE 或 RUNNING；`is_grounded_state` 对两者均返回 `true` → `on_ground == true` ✓
- 若 `is_grounded == false`：`derive` 返回 RISING 或 FALLING；`is_grounded_state` 对两者均返回 `false` → `on_ground == false` ✓

恒等成立。**无回归风险**。

如有任何一行核对不通过，回到 Step 3 修正。**不要**修测试或自检表格来掩盖差异。

- [ ] **Step 6: 静态 parse 检查（subagent 可做）**

确认改后的两个文件没有引入 GDScript 语法错误：
- `player.gd` 所有 `var x := ...` 类型推导仍成立（特别是 `var on_ground := MovementState.is_grounded_state(...)` 返回 bool）
- `debug_panel.gd` 顶部 preload 在 `class_name` 之前（GDScript 允许 const 在 class_name 之前；现有 `player.gd` 就是这种写法）
- 没有遗留对旧 `current_state` 字符串赋值（grep `current_state = "` 应无命中）

执行检查命令：

```bash
grep -n 'current_state = "' "d:/GoDot/Projects/2DPlatformerSample/Scripts/Prototypes/3C/player.gd"
```

期望：无输出（旧字符串赋值已全部清除）。

- [ ] **Step 7: Commit**

```bash
git add Scripts/Prototypes/3C/player.gd \
        Scripts/Prototypes/3C/debug_panel.gd
git commit -m "refactor(3c): use MovementState helper, restructure _integrate_forces

- player.gd: change current_state from String to MovementState.State;
  restructure _integrate_forces into 5 labeled sections
  (observe → timers → input → forces → apply); extract
  _compute_engine_force_x() with state-driven ground/air dispatch.
- debug_panel.gd: translate enum to display string via
  MovementState.to_display() for current_state readout.

Force dispatch now reads MovementState.is_grounded_state(current_state)
instead of raw is_grounded — value-equivalent by construction
(derive() partitions exactly on is_grounded), making the FSM diagram
in spec §4.7 visible at the dispatch site without changing physics.

Function length: ~65 → ~25 lines for _integrate_forces, +~10 line
helper. Zero physics behavior change (proven by static equivalence
table in plan Task 2 Step 5).

Refs: docs/superpowers/plans/2026-05-24-3c-movement-fsm-refactor.md Task 2"
```

---

## Task 3: 给 spec §4.7 追加实现备注

**目的：** 防止后来人误读"4 个状态意味着 4 套力配方"。一行 inline 注释，不动 §4.7 现有内容。

**Files:**
- Modify: `D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/3C-prototype-design.md` §4.7 末尾（在以 `v1 不需要 'Apex Hang' 状态` 开头的那行**之后**追加）

> **路径说明：** 该文件在 ObsidianNote 目录（不是 git 仓库），保存即生效但不会被 commit。这与项目 spec 文档现有约定一致（见 [project 总览](D:/ObsidianNote/MyNote/白日做梦/PlatformerPhysics/docs/项目总览.md)）。

- [ ] **Step 1: 编辑 spec 文件**

在 `3C-prototype-design.md` §4.7 末尾（当前最后一行 `v1 不需要 Apex Hang 状态...` 之后）追加一行：

```markdown
**实现备注**：4 态是观察口径（每帧从 `is_grounded` / `vx` / `vy` 派生）；力的分发仍按 Ground/Air 二分。详见 `Scripts/Prototypes/3C/movement_state.gd`（位于 godot 项目树），实现计划见 `docs/superpowers/plans/2026-05-24-3c-movement-fsm-refactor.md`。
```

- [ ] **Step 2: 不 commit**

ObsidianNote 不是 git 仓库，无需 commit。直接进入 Task 4。

---

## Task 4: 用户 F6 物理签字（HUMAN GATE — 非 subagent 任务）

**目的：** 按 memory `feedback_verify_each_edit`：物理代码路径改动**必须**人工 F6 验证手感无回归。这是 plan 的终态 gate，由用户执行，subagent 不参与。

> **Subagent driver 注意：** 当 Task 1-3 全部完成后，**不要**自己尝试运行 Godot 或宣称 plan 完成。停在这一步，明确请用户做下面的验证后再判定。

**用户操作清单：**

- [ ] **A. 在 Godot 编辑器里打开本项目**

让 Godot 重新导入新增的 `.gd` 文件，自动生成 `.gd.uid`。

预期：
- `Scripts/Prototypes/3C/movement_state.gd.uid` 生成
- `Scripts/Prototypes/3C/tests/test_movement_state.gd.uid` 生成
- 控制台无 parse error 红字

- [ ] **B. F6 跑 `Scenes/Prototypes/3C/tests/test_movement_state.tscn`**

预期输出（在 Godot Output 面板）：

```
[TEST movement_state] ALL PASS
```

如失败：报错信息会显示具体哪个 assertion 失败 → 反馈给 subagent 修正。

- [ ] **C. F6 跑 `Scenes/Prototypes/3C/test_level.tscn`，做手感复盘**

逐条试：
- [ ] 左右移动启动 / 滑行 — 与改前一致（不应有任何手感变化）
- [ ] 跳跃高度、长按 vs 短按差异 — 与改前一致
- [ ] 走到悬崖边离地后 0.1s 内按跳 — coyote 起跳仍可触发
- [ ] 落地前 0.1s 按跳 — buffer 起跳仍可触发
- [ ] 按 F1 打开 Debug 面板，观察 `current_state` 字段：站定显示 `Idle`、走动显示 `Running`、跳起显示 `Rising`、下落显示 `Falling`；切换平滑，**无 `0`/`1`/`2`/`3` 数字、无 `?`、无空字符串**

如任一条与改前不同 → 报告差异，subagent 回到 Task 2 排查。

- [ ] **D. 用户签字**

口头/书面确认手感无回归 → plan 完成。

---

## 验证完成判定

全部满足才算 plan 完成：

- [ ] Task 1 commit 落在 git history（feat(3c): add MovementState...）
- [ ] Task 2 commit 落在 git history（refactor(3c): use MovementState...）
- [ ] Task 3 spec 文件已编辑（不需 commit）
- [ ] Task 4 用户 F6 全清单通过 + 口头签字

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| `current_state` 类型 String → enum，可能漏改其它读取点（除 debug_panel 之外） | Task 2 Step 6 grep 检查；project-wide 搜 `\.current_state` 在编辑器里再扫一次 |
| `test_movement_state.tscn` 占位 uid 与 Godot 自动生成的 `.gd.uid` 不匹配 | 与现有 `test_input_buffer.tscn` 同样做法，Godot 按 path 兜底解析；用户首次打开会自动调和 |
| 等价性表格漏掉某条静默差异 | 用户 F6 手感复盘兜底；如发现手感回归，回 Task 2 重排 |
| Subagent 试图自动运行 Godot（PATH 没有 godot CLI） | Task 4 明确标注 HUMAN GATE，subagent 不应尝试 `godot --headless` 类命令 |
