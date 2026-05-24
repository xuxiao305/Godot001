extends DampedSpringJoint2D

@onready var line = $Line2D

func _process(_delta: float) -> void:
	if not line:
		return

	var body_a := get_node(node_a) as Node2D
	var body_b := get_node(node_b) as Node2D
	var test := bias as float 


	if not body_a or not body_b:
		return

	# Convert body global positions into Line2D's local space
	var local_a := line.to_local(body_a.global_position) as Vector2
	var local_b := line.to_local(body_b.global_position) as Vector2

	line.clear_points()
	line.add_point(local_a)
	line.add_point(local_b)

	print (test)
