extends Node2D

@export var rigidbody_to_spawn : PackedScene

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Timer.timeout.connect(_on_timer_timeout)


func _on_timer_timeout():
	# _drop_rigidbody()
	pass
		

func _drop_rigidbody():
	var random_position = Vector2(randi_range($Marker1.position.x, $Marker2.position.x), $Marker1.position.y)
	var rigidbody_instance = rigidbody_to_spawn.instantiate()
	
	rigidbody_instance.position = random_position
	
	add_child(rigidbody_instance)
		
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
