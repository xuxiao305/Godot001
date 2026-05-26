# Scripts/Prototypes/Destruction/destruction_demo.gd
# 主场景控制器：装配 pipeline / impact / 场景加载 / 帧末批处理。
extends Node2D

const DestructionPipeline := preload("res://Scripts/Prototypes/Destruction/destruction_pipeline.gd")
const ImpactWatcher := preload("res://Scripts/Prototypes/Destruction/impact_watcher.gd")
const GridStructureKlass := preload("res://Scripts/Prototypes/Destruction/grid_structure.gd")

@onready var structure_holder: Node2D = $StructureHolder

var pipeline
var impact
var current_structure = null  # GridStructure

func _ready() -> void:
	pipeline = DestructionPipeline.new()
	impact = ImpactWatcher.new()
	impact.pipeline = pipeline
	_load_scene("brick_wall")

func _load_scene(name: String) -> void:
	if current_structure != null:
		current_structure.clear()
		current_structure.queue_free()
		current_structure = null
	var path := "res://Scenes/Prototypes/Destruction/scenes/%s.tscn" % name
	var s := load(path) as PackedScene
	if s == null:
		push_error("Failed to load scene: " + path)
		return
	var inst := s.instantiate()
	structure_holder.add_child(inst)
	if inst.has_method("build_constraints"):
		current_structure = inst
		current_structure.pipeline = pipeline
		current_structure.impact_watcher = impact

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Scene1"):
		_load_scene("brick_wall")
	elif event.is_action_pressed("Scene2"):
		_load_scene("arch")
	elif event.is_action_pressed("Scene3"):
		_load_scene("house")

func _physics_process(_dt: float) -> void:
	pipeline.dispatch_damage_events()
	for c in pipeline.drain_constraint_destroys():
		c.destroy()
	for blk in pipeline.drain_block_destroys():
		if is_instance_valid(blk):
			blk.queue_free()
