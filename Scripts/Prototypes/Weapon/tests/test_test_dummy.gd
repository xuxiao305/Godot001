# Scripts/Prototypes/Weapon/tests/test_test_dummy.gd
# 受体纯函数测试 —— 验证 take_damage 累计与初始 hp。
# 不验证物理（冲量受体走 apply_central_impulse，无需测）。
extends Node

const TestDummy := preload("res://Scripts/Prototypes/Weapon/test_dummy.gd")

func _ready() -> void:
	var d := TestDummy.new()
	d.max_hp = 100.0
	d._ready()  # 手工触发 hp 初始化

	# 1) 初始 hp = max_hp
	assert(d.hp == 100.0, "init hp should equal max_hp")

	# 2) take_damage 累计扣血
	d.take_damage(30.0, Vector2.ZERO, null)
	assert(_approx(d.hp, 70.0), "after 30 damage hp should be 70, got %f" % d.hp)

	# 3) 多次扣
	d.take_damage(50.0, Vector2.ZERO, null)
	assert(_approx(d.hp, 20.0), "after 80 total hp should be 20, got %f" % d.hp)

	# 4) 过量扣 → hp clamp >= 0
	d.take_damage(999.0, Vector2.ZERO, null)
	assert(d.hp == 0.0, "hp should clamp to 0, got %f" % d.hp)

	# 5) hp 归零后再扣不再变
	d.take_damage(10.0, Vector2.ZERO, null)
	assert(d.hp == 0.0, "hp should stay at 0 after death")

	d.free()
	print("[TEST test_dummy] ALL PASS")
	get_tree().quit()

static func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.001
