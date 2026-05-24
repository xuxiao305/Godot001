# Scripts/Prototypes/3C/tests/spike_box2d.gd
# Box2D 能力 spike —— 验证后续依赖的 4 项 API 全部可用。
extends Node2D

func _ready() -> void:
	# 1) 能创建 RigidBody2D 并设置 Capsule shape
	var body := RigidBody2D.new()
	body.lock_rotation = true
	body.linear_damping = 0.0
	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 20.0
	capsule.height = 90.0
	shape.shape = capsule
	body.add_child(shape)
	body.position = Vector2(400, 100)
	body.contact_monitor = true
	body.max_contacts_reported = 8
	add_child(body)

	# 2) 能 apply_central_force / apply_central_impulse
	body.apply_central_impulse(Vector2(0, -200))
	print("[SPIKE] impulse applied, expect upward kick")

	# 3) 地面用 StaticBody2D + 自带 physics material
	var ground := StaticBody2D.new()
	var ground_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(800, 32)
	ground_shape.shape = rect
	ground.add_child(ground_shape)
	ground.position = Vector2(400, 500)
	var mat := PhysicsMaterial.new()
	mat.friction = 0.5
	ground.physics_material_override = mat
	add_child(ground)

	# 4) 等 0.5s 后探针 contact 列表（保证已落地）
	await get_tree().create_timer(0.5).timeout
	body.apply_central_force(Vector2(150, 0))
	await get_tree().create_timer(0.2).timeout

	# 通过 _integrate_forces 桥读 contact 数据 —— 见下方 PlayerProbe
	var probe := PlayerProbe.new()
	probe.target = body
	add_child(probe)

class PlayerProbe extends Node:
	var target: RigidBody2D
	func _physics_process(_dt: float) -> void:
		if target == null: return
		var state := PhysicsServer2D.body_get_direct_state(target.get_rid())
		var count := state.get_contact_count()
		print("[SPIKE] contacts=%d, vel=%s" % [count, state.linear_velocity])
		for i in count:
			var n := state.get_contact_local_normal(i)
			print("  contact %d normal=%s n.y=%.3f" % [i, n, n.y])
