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
