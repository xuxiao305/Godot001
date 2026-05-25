# Scripts/Prototypes/Weapon/test_dummy.gd
# 武器原型 v1 受体 —— 普通 dynamic body 实现简单 take_damage。
# 完整破坏框架（Block + Constraint）由家族 B 独立 demo 验证（ADR-0007 单向依赖）。
# duck typing：实现 take_damage(amount, point, source) 即可被 DamageField 命中。
class_name WeaponTestDummy
extends RigidBody2D

@export var max_hp: float = 100.0
var hp: float = 0.0

func _ready() -> void:
	hp = max_hp

# DamageField 调用入口（ADR-0007 统一伤害语言）。
func take_damage(amount: float, point: Vector2, source: Node) -> void:
	var before := hp
	hp = maxf(0.0, hp - amount)
	var src_name: String = "<null>" if source == null else source.name
	print("[TestDummy %s] dmg=%.1f hp %.1f → %.1f @%s by %s" % [name, amount, before, hp, point, src_name])
