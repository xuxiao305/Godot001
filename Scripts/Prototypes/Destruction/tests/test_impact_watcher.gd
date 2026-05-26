# Scripts/Prototypes/Destruction/tests/test_impact_watcher.gd
extends Node
const ImpactWatcher := preload("res://Scripts/Prototypes/Destruction/impact_watcher.gd")

func _ready() -> void:
	# impact_to_damage(normal_impulse, threshold, coefficient)
	# J=2 threshold=2 -> (2-2)*10 = 0 (critical)
	assert(absf(ImpactWatcher.impact_to_damage(2.0, 2.0, 10.0) - 0.0) < 0.001,
		"Critical impulse should yield 0 damage")
	# J=1 -> below threshold no damage
	assert(ImpactWatcher.impact_to_damage(1.0, 2.0, 10.0) == 0.0,
		"Below threshold should yield 0")
	# J=5 -> (5-2)*10 = 30
	assert(absf(ImpactWatcher.impact_to_damage(5.0, 2.0, 10.0) - 30.0) < 0.001,
		"J=5, threshold 2, coef 10 -> 30, got %f" % ImpactWatcher.impact_to_damage(5.0, 2.0, 10.0))
	# Negative J defense
	assert(ImpactWatcher.impact_to_damage(-3.0, 2.0, 10.0) == 0.0, "Negative impulse should yield 0")
	# Large J magnitude check: J=100 -> (100-2)*10 = 980
	assert(absf(ImpactWatcher.impact_to_damage(100.0, 2.0, 10.0) - 980.0) < 0.001,
		"J=100 -> damage 980, got %f" % ImpactWatcher.impact_to_damage(100.0, 2.0, 10.0))

	print("[TEST impact_watcher] ALL PASS")
	get_tree().quit()
