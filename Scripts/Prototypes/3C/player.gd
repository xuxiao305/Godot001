# Scripts/Prototypes/3C/player.gd
# 3C 原型角色控制器 —— 内在发动机派（ADR-0001）。
# 每帧只 apply_force / apply_impulse，绝不写入 linear_velocity。
class_name Player3C
extends RigidBody2D

# 单位约定：1 m = 100 px。spec 中所有 m, m/s, N 的数值在 export 默认值里都乘以此常量。
const PX_PER_M: float = 100.0
const EngineTorque := preload("res://Scripts/Prototypes/3C/engine_torque.gd")
const JumpController := preload("res://Scripts/Prototypes/3C/jump_controller.gd")
const InputBuffer := preload("res://Scripts/Prototypes/3C/input_buffer.gd")
const MovementState := preload("res://Scripts/Prototypes/3C/movement_state.gd")

# --------- EXPORT (Debug 面板会读写这些) ---------- #
@export_category("Engine — Ground (§4.2)")
@export var v_max: float = 8.0 * PX_PER_M          # 8 m/s
@export var f_max_ground: float = 80.0 * PX_PER_M  # 80 N
@export var saturation_full: float = 2.0 * PX_PER_M
@export var f_active_brake: float = 0.0

@export_category("Engine — Air (§4.3)")
@export var f_max_air: float = 40.0 * PX_PER_M     # 40 N

@export_category("Jump (§4.4)")
@export var j_jump_initial: float = 11.2 * PX_PER_M
@export var f_jump_hold: float = 8.0 * PX_PER_M
@export var hold_window_max: float = 0.30
@export var gravity_y: float = 25.0 * PX_PER_M     # 25 m/s² → 2500 px/s²

@export_category("Perceptual Compensation (§4.5)")
@export var coyote_time: float = 0.10
@export var jump_buffer_time: float = 0.10

@export_category("Ground Detection (§4.6)")
@export var cos_theta_max: float = 0.7
@export_range(0, 5) var ground_state_buffer_frames: int = 0

# --------- RUNTIME STATE (Debug 面板会读) ---------- #
var is_grounded: bool = false
var ground_normal_y: float = 0.0
var current_state: MovementState.State = MovementState.State.IDLE
var net_force_this_frame: Vector2 = Vector2.ZERO

var _ground_debounce := GroundCheck.Debouncer.new()
var _jump := JumpController.new()
var _input_buf := InputBuffer.new()

# --------- LIFECYCLE ---------- #
func _ready() -> void:
	lock_rotation = true
	linear_damp = 0.0
	contact_monitor = true
	max_contacts_reported = 8
	# 单位策略：1 m = 100 px。所有 spec 中的 m, m/s, N 在 export 默认值里已乘 100。
	# 项目重力关掉（用 ADR-0003 的恒定 gravity_y）：
	gravity_scale = 0.0  # 我们自己施加重力，便于 Debug 面板调
	_input_buf.coyote_time = coyote_time
	_input_buf.jump_buffer_time = jump_buffer_time

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
