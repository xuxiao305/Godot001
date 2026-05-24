# Scripts/Prototypes/3C/tests/test_input_buffer.gd
extends Node

const InputBuffer := preload("res://Scripts/Prototypes/3C/input_buffer.gd")

func _ready() -> void:
	# 1) Coyote: 接地的最后一帧是 t=0.10，离地后 coyote_time 窗内仍可起跳
	var b := InputBuffer.new()
	b.coyote_time = 0.10
	b.jump_buffer_time = 0.10
	# 模拟玩家在 t=0.10 时刻最后一次"被报告为接地"
	b.update_grounded(true, 0.10)
	# t=0.11 离地
	b.update_grounded(false, 0.11)
	# last_grounded_true_at = 0.10 → coyote 截止 = 0.20
	assert(b.can_coyote(0.15), "离地 0.05s 应有 coyote")
	assert(b.can_coyote(0.20), "离地 0.10s 边界仍有 coyote")
	assert(not b.can_coyote(0.21), "离地 0.11s 应过期")

	# 2) Buffer: 落地前 buffer 窗内按 Jump 算有效
	var b2 := InputBuffer.new()
	b2.coyote_time = 0.10
	b2.jump_buffer_time = 0.10
	b2.on_jump_pressed(0.0)
	assert(b2.can_buffer(0.05), "0.05s 时按过 jump 应 buffer 有效")
	assert(not b2.can_buffer(0.11), "0.11s 应过期")
	# Buffer 一旦消费应清零
	b2.consume_buffer()
	assert(not b2.can_buffer(0.05), "消费后 buffer 应失效")

	# 3) 落地（false→true）应自动复位 buffer
	var b3 := InputBuffer.new()
	b3.on_jump_pressed(0.0)
	b3.consume_buffer()
	b3.update_grounded(false, 0.01)
	b3.update_grounded(true, 0.02)  # 落地
	b3.on_jump_pressed(0.03)
	assert(b3.can_buffer(0.04), "落地后再按 Jump 应有 buffer")

	print("[TEST input_buffer] ALL PASS")
	get_tree().quit()
