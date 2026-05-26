# Scripts/Prototypes/Destruction/block_factory.gd
# 工厂：创建 Block + 配 Body 参数 + 加 CollisionShape2D。
# 未来接对象池仅改本类内部，消费者（GridStructure）签名不变。
class_name BlockFactory
extends RefCounted

const BlockKlass := preload("res://Scripts/Prototypes/Destruction/block.gd")

# block_size 像素
# impact 参数未类型标注 —— ImpactWatcher 在 Task 5 才创建，避免 parse error
static func create(
	pipeline,  # DestructionPipeline,
	pos: Vector2,
	block_size: float,
	impact,  # ImpactWatcher (nullable until Task 5)
	initial_health: float = 100.0
) -> RigidBody2D:
	var b := BlockKlass.new()
	b.global_position = pos
	b.initial_health = initial_health
	b.pipeline = pipeline
	# Body 参数（spec §4.1）
	b.freeze = false
	b.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC  # freeze_mode 仅在 freeze=true 时生效
	b.mass = 0.1 
	var mat := PhysicsMaterial.new()
	mat.friction = 0.6
	mat.bounce = 0.05
	b.physics_material_override = mat
	b.linear_damp = 0.05
	b.angular_damp = 0.1
	b.contact_monitor = true
	b.max_contacts_reported = 8  # ImpactWatcher 需要
	# Collision shape（正方形）
	var shape := RectangleShape2D.new()
	shape.size = Vector2(block_size, block_size)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	b.add_child(cs)
	# Visual: spec §3.1 "v1 每个 Block 独立显示色块". 半透明 (alpha 0.75) 让
	# ConstraintVisualizer 的连线能透过来显示血量颜色。名为 "Visual" 便于外部覆盖
	# 颜色（如 destruction_demo._spawn_falling_block 把它涂红区分调试块）。
	var s := block_size * 0.5
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = PackedVector2Array([Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)])
	visual.color = Color(0.75, 0.72, 0.65, 0.75)  # 米灰，砖石质感
	b.add_child(visual)
	# collision layers 由 GridStructure 在 add_child 后统一设（或在此设默认值）
	b.collision_layer = 4   # layer 4 = block
	b.collision_mask = 4 | 1  # block + world（layer 1 = world）
	b.impact_watcher = impact
	return b
