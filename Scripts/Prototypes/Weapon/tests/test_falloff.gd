# Scripts/Prototypes/Weapon/tests/test_falloff.gd
# 纯函数测试 —— 线性衰减 f(d, R) = max(0, 1 - d/R)。
# RadialDamage / RadialBlast 共用同一公式（spec §4.4 / §4.5 都写 linear）。
extends Node

const RadialDamage := preload("res://Scripts/Prototypes/Weapon/damage_fields/radial_damage.gd")

func _ready() -> void:
	# 1) 中心 = 1.0（满）
	assert(_approx(RadialDamage.compute_falloff(0.0, 3.0), 1.0), "d=0 should be 1.0")
	# 2) 半距 = 0.5
	assert(_approx(RadialDamage.compute_falloff(1.5, 3.0), 0.5), "d=R/2 should be 0.5")
	# 3) 边界 = 0
	assert(_approx(RadialDamage.compute_falloff(3.0, 3.0), 0.0), "d=R should be 0")
	# 4) 超出 = 0（clamp）
	assert(_approx(RadialDamage.compute_falloff(5.0, 3.0), 0.0), "d>R should be 0")
	# 5) R<=0 守卫
	assert(_approx(RadialDamage.compute_falloff(1.0, 0.0), 0.0), "R=0 should be 0")
	assert(_approx(RadialDamage.compute_falloff(1.0, -1.0), 0.0), "R<0 should be 0")

	print("[TEST falloff] ALL PASS")
	get_tree().quit()

static func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.001
