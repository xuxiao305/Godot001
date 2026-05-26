# Scripts/Prototypes/Destruction/constraint_visualizer.gd
# 可视化：_draw() 根据约束血量画彩色连线。
class_name ConstraintVisualizer
extends Node2D

@export var enabled: bool = true
@export var healthy_color: Color = Color.GREEN
@export var warning_color: Color = Color.ORANGE
@export var critical_color: Color = Color.RED
@export var line_width: float = 2.0

var _blocks: Array = []
var _constraints: Array = []

func set_data(blocks: Array, constraints: Array) -> void:
	_blocks = blocks
	_constraints = constraints

func _process(_dt: float) -> void:
	if enabled:
		queue_redraw()

func _draw() -> void:
	if not enabled:
		return
	for c in _constraints:
		if not is_instance_valid(c) or not is_instance_valid(c.pin):
			continue
		var block_a = c.block_a  # Block
		var block_b = c.block_b  # Block
		if not is_instance_valid(block_a) or not is_instance_valid(block_b):
			continue
		var health_ratio: float = c.health / c.initial_health if c.initial_health > 0.0 else 0.0
		var col: Color
		if health_ratio > 0.5:
			col = healthy_color
		elif health_ratio > 0.3:
			col = warning_color
		else:
			col = critical_color
		draw_line(block_a.global_position - global_position,
			block_b.global_position - global_position,
			col, line_width)
