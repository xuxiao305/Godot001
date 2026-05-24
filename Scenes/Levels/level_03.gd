extends Node2D

@export var ball_scene : PackedScene

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func _on_timer_timeout():
	for i  in range(5):
		var random_position = Vector2(randi_range(0, 100.0), randi_range(0,10))
		var ball_instance = ball_scene.instantiate()
		
		ball_instance.position = random_position
		
		add_child(ball_instance)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
