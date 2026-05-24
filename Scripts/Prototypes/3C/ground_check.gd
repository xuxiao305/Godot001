# Scripts/Prototypes/3C/ground_check.gd
# 接地判定 —— 给定 contact 法线列表，判定是否接地。
# 法线方向约定：来自 PhysicsDirectBodyState2D.get_contact_local_normal()，
#   "从碰撞对象指向角色"，所以"地面"对应 normal.y 显著为负（向上推角色）。
#   Spike Task 1 已验证：地面 contact 的 n.y ≈ -1。
class_name GroundCheck
extends RefCounted

# 输入 contact 数和 PhysicsDirectBodyState2D，返回 (is_grounded, ground_normal_y_min)
static func check(state: PhysicsDirectBodyState2D, cos_theta_max: float) -> Dictionary:
	var grounded := false
	var min_ny := 1.0  # 最"地面"的法线 y（最负的）
	for i in state.get_contact_count():
		var n := state.get_contact_local_normal(i)
		# 地面法线指向角色 → n.y < -cos_theta_max
		# cos_theta_max = 0.7 → 接受 n.y <= -0.7（约 45° 内的坡）
		if n.y < -cos_theta_max:
			grounded = true
			if n.y < min_ny:
				min_ny = n.y
	return {"grounded": grounded, "min_normal_y": min_ny}

# 1 帧防抖封装 —— 接地态从 true→false 时延迟 buffer_frames 帧。
# 来源：spec §4.6 ground_state_buffer_frames（默认关 = 0）
class Debouncer extends RefCounted:
	var buffer_frames: int = 0
	var _last_true: bool = false
	var _frames_since_false: int = 0

	func feed(raw_grounded: bool) -> bool:
		if raw_grounded:
			_last_true = true
			_frames_since_false = 0
			return true
		# raw = false
		if not _last_true:
			return false
		_frames_since_false += 1
		if _frames_since_false > buffer_frames:
			_last_true = false
			return false
		return true  # 仍处于防抖窗口
