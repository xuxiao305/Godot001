# Scripts/Prototypes/3C/engine_torque.gd
# 发动机转速曲线 —— 纯数学函数，不依赖 Node。
# 来源：ADR-0002 https://docs/adr/0002-engine-torque-curve.md
class_name EngineTorque
extends RefCounted

# 计算当前帧发动机输出力。
#   v_current:        当前水平速度
#   v_target:         目标水平速度（±v_max 或 0）
#   f_max:            发动机额定力上限
#   saturation_full:  |v_target - v_current| 大于此值时 saturation = 1
static func compute(v_current: float, v_target: float, f_max: float, saturation_full: float) -> float:
	var diff := v_target - v_current
	if absf(diff) < 0.0001:
		return 0.0
	# ADR-0002 "v_target=0 时发动机不出力，靠摩擦衰减"：无输入不主动刹车（那是 f_active_brake 的事）
	if v_target == 0.0:
		return 0.0
	# ADR-0002 "超过目标方向 → 力 = 0"：当前已超过 v_target 且方向相同
	if signf(v_current) == signf(v_target) and absf(v_current) > absf(v_target):
		return 0.0
	var dir := signf(diff)
	var saturation := minf(absf(diff) / saturation_full, 1.0)
	return f_max * dir * saturation
