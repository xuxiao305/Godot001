extends DampedSpringJoint2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var body_b := get_node(node_b) as RigidBody2D	
	if body_b != null:
		print("pos=%s velocity=%s" % [body_b.position, body_b.linear_velocity])

	pass
