extends DampedSpringJoint2D

var line : Line2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	line = $Line2D as Line2D
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if line == null:
		return

	var line_pos_a := get_node(node_a).global_position as Vector2
	var line_pos_b := get_node(node_b).global_position as Vector2

	line.clear_points()
	line.add_point(line.to_local(line_pos_a))
	line.add_point(line.to_local(line_pos_b))

	pass
