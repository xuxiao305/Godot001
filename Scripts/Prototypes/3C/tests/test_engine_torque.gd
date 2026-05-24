# Scripts/Prototypes/3C/tests/test_engine_torque.gd
# 纯函数测试 —— 在 _ready 时跑断言，全部通过则打印 PASS。
extends Node

const EngineTorque := preload("res://Scripts/Prototypes/3C/engine_torque.gd")

func _ready() -> void:
	# 1) 静止时无输入 → 力 = 0
	assert(_approx(EngineTorque.compute(0.0, 0.0, 80.0, 2.0), 0.0),
		"无输入静止应不出力")

	# 2) 满力区间：差值 > saturation_full → 满力且方向对
	assert(_approx(EngineTorque.compute(0.0, 8.0, 80.0, 2.0), 80.0),
		"启动应满力向右")
	assert(_approx(EngineTorque.compute(0.0, -8.0, 80.0, 2.0), -80.0),
		"启动应满力向左")

	# 3) 接近目标：差值在 (0, saturation_full) → 衰减
	# diff=1.0, saturation_full=2.0 → 80 * 1.0 * 0.5 = 40.0
	var f1 := EngineTorque.compute(7.0, 8.0, 80.0, 2.0)
	assert(_approx(f1, 40.0), "接近顶速应衰减出力到 40.0, got %f" % f1)

	# Test 3b: 反向接近目标 (从 -3 加速到 8)
	var f3b := EngineTorque.compute(-3.0, 8.0, 80.0, 2.0)
	assert(_approx(f3b, 80.0), "test 3b failed: expected 80.0, got %f" % f3b)

	# 4) 到达目标 → 力 = 0
	assert(_approx(EngineTorque.compute(8.0, 8.0, 80.0, 2.0), 0.0),
		"到顶速应不出力")

	# 5) 超速且无反向输入（v_target=0）→ 力 = 0（不强行回拉，ADR-0002）
	assert(_approx(EngineTorque.compute(12.0, 0.0, 80.0, 2.0), 0.0),
		"超速无输入应放任摩擦衰减")

	# 5b) 低速且无输入（v_target=0）→ 力 = 0（不主动刹车，那是 f_active_brake 的事）
	assert(_approx(EngineTorque.compute(1.5, 0.0, 80.0, 2.0), 0.0),
		"低速无输入不应主动刹车（靠摩擦 + f_active_brake）")

	# 6) 超速且玩家反向输入 → 全力反向（ADR-0002 "反方向远离目标 → 全力反向"）
	assert(_approx(EngineTorque.compute(12.0, -8.0, 80.0, 2.0), -80.0),
		"超速反输入应全力反向刹车")

	# 7) 超速且玩家继续按同向 → 力 = 0（"超过目标方向 → 力 = 0"）
	assert(_approx(EngineTorque.compute(12.0, 8.0, 80.0, 2.0), 0.0),
		"超速继续按同向不应再加力")

	print("[TEST engine_torque] ALL PASS")
	get_tree().quit()

static func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.001
