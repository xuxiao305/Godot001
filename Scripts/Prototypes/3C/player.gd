# Scripts/Prototypes/3C/player.gd
# 3C 原型角色控制器 —— 内在发动机派（ADR-0001）。
# 每帧只 apply_force / apply_impulse，绝不写入 linear_velocity。
class_name Player3C
extends RigidBody2D

# --------- EXPORT (Debug 面板会读写这些) ---------- #
@export_category("Engine — Ground (§4.2)")
@export var v_max: float = 8.0 * 100.0          # m/s → 100 px/m
@export var f_max_ground: float = 80.0 * 100.0
@export var saturation_full: float = 2.0 * 100.0
@export var f_active_brake: float = 0.0

@export_category("Engine — Air (§4.3)")
@export var f_max_air: float = 40.0 * 100.0

@export_category("Jump (§4.4)")
@export var j_jump_initial: float = 11.2 * 100.0
@export var f_jump_hold: float = 8.0 * 100.0
@export var hold_window_max: float = 0.30
@export var gravity_y: float = 25.0 * 100.0      # 单位 px/s²

@export_category("Perceptual Compensation (§4.5)")
@export var coyote_time: float = 0.10
@export var jump_buffer_time: float = 0.10

@export_category("Ground Detection (§4.6)")
@export var cos_theta_max: float = 0.7
@export_range(0, 5) var ground_state_buffer_frames: int = 0

# --------- RUNTIME STATE (Debug 面板会读) ---------- #
var is_grounded: bool = false
var ground_normal_y: float = 0.0
var current_state: String = "Idle"
var net_force_this_frame: Vector2 = Vector2.ZERO

var _ground_debounce := GroundCheck.Debouncer.new()

# --------- LIFECYCLE ---------- #
func _ready() -> void:
	lock_rotation = true
	linear_damping = 0.0
	contact_monitor = true
	max_contacts_reported = 8
	# 单位策略：1 m = 100 px。所有 spec 中的 m, m/s, N 在 export 默认值里已乘 100。
	# 项目重力关掉（用 ADR-0003 的恒定 gravity_y）：
	gravity_scale = 0.0  # 我们自己施加重力，便于 Debug 面板调

# 用 _integrate_forces 而非 _physics_process —— Box2D 提供完整 state，且这是 Godot 推荐的物理操作时机。
func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# 1. 接地检测
	_ground_debounce.buffer_frames = ground_state_buffer_frames
	var gc := GroundCheck.check(state, cos_theta_max)
	is_grounded = _ground_debounce.feed(gc.grounded)
	ground_normal_y = gc.min_normal_y

	# 2. 恒定重力（ADR-0003）
	var force := Vector2(0, gravity_y * mass)

	# 3. 其他子系统的力会在后续 Task 累加进 force
	# TODO(Task 4): + 地面/空中发动机力（统一处理，is_grounded 分支）
	# TODO(Task 5): + 跳跃持续推力

	net_force_this_frame = force
	state.apply_central_force(force)
