# Scripts/Prototypes/Destruction/spike/spike_pin_reaction.gd
# Spike 0 — Constraint 物理路径决策
# 目标：在 PinJoint2D 上检测三种应力读法是否可行：
#   (a) 私有/扩展 API 读 reaction force
#   (b) 相对加速度代理 sigma_proxy = |mA·(aA·n)| + |mB·(aB·n)|
#   (c) 没辙，v1 不做物理路径
#
# 跑法：headless 8 秒自动退出；或在编辑器里 F6 观察 print。
# 每 0.1 秒往 Body B 加一个递增的水平 impulse，并 print 关键观测值。
extends Node2D

const IMPULSE_STEP_INTERVAL: float = 0.1   # 秒
const IMPULSE_STEP_MAGNITUDE: float = 5.0  # 每步 +5 N·s
const RUN_SECONDS: float = 8.0
const STATIC_PHASE_END: float = 1.0        # 0–1s: 不加 impulse，观察静态值
const IMPULSE_PHASE_END: float = 5.0       # 1–5s: 加递增 impulse
const PIN_DELETE_AT: float = 5.5           # 5.5s: 删 pin，看 sigma_proxy 是否归零

@onready var body_a: RigidBody2D = $BodyA
@onready var body_b: RigidBody2D = $BodyB
@onready var pin: PinJoint2D = $Pin

var _applied_impulse: float = 0.0
var _frame: int = 0
var _accum: float = 0.0
var _t: float = 0.0
var _pin_deleted: bool = false

# 上一帧速度，用于差分求加速度（策略 b 的应力代理）。
var _prev_v_a: Vector2 = Vector2.ZERO
var _prev_v_b: Vector2 = Vector2.ZERO

func _ready() -> void:
	print("[spike] === Pin Reaction Probe Start ===")
	print("[spike] physics engine = %s" % ProjectSettings.get_setting("physics/2d/physics_engine"))
	print("[spike] pin class = %s" % pin.get_class())
	# 关掉重力 + 不让 body 进 sleep — 否则 impulse 步进结果会被地面/sleep 吸收，
	# 测的就不是"pin 在反应外力"，而是"地面承担了一切"。
	body_a.gravity_scale = 0.0
	body_b.gravity_scale = 0.0
	body_a.can_sleep = false
	body_b.can_sleep = false
	# (a) 私有/扩展 API 探测：把所有可能的命名都试一遍。
	for m in ["get_reaction_force", "get_constraint_force", "get_applied_impulse",
			  "get_reaction_impulse", "get_force", "get_impulse"]:
		print("[spike] pin.has_method(\"%s\") = %s" % [m, pin.has_method(m)])
	for p in ["reaction_force", "constraint_force", "applied_impulse",
			  "reaction_impulse", "force", "impulse"]:
		var v: Variant = pin.get(p)
		print("[spike] pin.get(\"%s\") = %s (null=%s)" % [p, v, v == null])
	# 同样探测 PhysicsServer2D 的 joint RID 接口。
	var jrid: RID = pin.get_rid()
	print("[spike] pin.get_rid() = %s, valid=%s" % [jrid, jrid.is_valid()])
	# 看 PhysicsServer2D 是否暴露相关方法
	for m in ["joint_get_reaction_force", "joint_get_applied_impulse",
			  "joint_get_constraint_force"]:
		print("[spike] PhysicsServer2D.has_method(\"%s\") = %s" % [m, PhysicsServer2D.has_method(m)])
	# 8 秒后自动退出（headless smoke run 模板）
	await get_tree().create_timer(RUN_SECONDS).timeout
	print("[spike] === End — quitting ===")
	get_tree().quit()


func _physics_process(delta: float) -> void:
	_frame += 1
	_accum += delta
	_t += delta

	# 在 5.5s 删掉 pin，看应力代理是否归零（策略 b 的鲁棒性检查）。
	if not _pin_deleted and _t >= PIN_DELETE_AT:
		_pin_deleted = true
		print("[spike] >>> deleting pin at t=%.2f <<<" % _t)
		pin.queue_free()

	# 加速度差分（注意 RigidBody2D.linear_velocity 在 _physics_process 里读是当前步起点速度）。
	var v_a: Vector2 = body_a.linear_velocity
	var v_b: Vector2 = body_b.linear_velocity
	var a_a: Vector2 = (v_a - _prev_v_a) / max(delta, 1e-6)
	var a_b: Vector2 = (v_b - _prev_v_b) / max(delta, 1e-6)

	# pin 轴向 n：用 A→B 单位向量（pin 在中点，两端方向一致）。
	var rel: Vector2 = body_b.global_position - body_a.global_position
	var n: Vector2 = rel.normalized() if rel.length() > 1e-6 else Vector2.RIGHT

	# (b) sigma_proxy：两端沿轴向上的"惯性力"幅值之和。
	var m_a: float = body_a.mass
	var m_b: float = body_b.mass
	var sigma_proxy: float = absf(m_a * a_a.dot(n)) + absf(m_b * a_b.dot(n))

	# 阶段判定 — 决定要不要施加 impulse。
	var phase: String
	if _t < STATIC_PHASE_END:
		phase = "STATIC"
	elif _t < IMPULSE_PHASE_END:
		phase = "IMPULSE"
	elif not _pin_deleted:
		phase = "SETTLE"  # 5.0–5.5s 让数值稳一下再删 pin
	else:
		phase = "PIN_DELETED"

	# 每 IMPULSE_STEP_INTERVAL 处理一次（IMPULSE 阶段才真加 impulse），并 print 一帧。
	if _accum >= IMPULSE_STEP_INTERVAL:
		_accum = 0.0
		if phase == "IMPULSE":
			_applied_impulse += IMPULSE_STEP_MAGNITUDE
			body_b.apply_central_impulse(Vector2(IMPULSE_STEP_MAGNITUDE, 0.0))

		# 再尝试拿 reaction（如果运行时确实暴露了，就在 spike 输出里看到）。
		var rf_dyn: Variant = pin.get("reaction_force") if is_instance_valid(pin) else null
		var cf_dyn: Variant = pin.get("constraint_force") if is_instance_valid(pin) else null

		print("[spike] frame=%d t=%.2f phase=%s impulse_total=%.1f" % [_frame, _t, phase, _applied_impulse])
		print("  body_a vel=(%.3f,%.3f) acc=(%.3f,%.3f)" % [v_a.x, v_a.y, a_a.x, a_a.y])
		print("  body_b vel=(%.3f,%.3f) acc=(%.3f,%.3f)" % [v_b.x, v_b.y, a_b.x, a_b.y])
		print("  pin_axis_n=(%.3f,%.3f) rel_len=%.2f" % [n.x, n.y, rel.length()])
		print("  sigma_proxy=%.3f  (mA*aA.n=%.3f, mB*aB.n=%.3f)" % [
			sigma_proxy, m_a * a_a.dot(n), m_b * a_b.dot(n)])
		print("  pin.get(reaction_force)=%s  pin.get(constraint_force)=%s" % [rf_dyn, cf_dyn])

	_prev_v_a = v_a
	_prev_v_b = v_b
