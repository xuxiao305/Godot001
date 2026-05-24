# Scripts/Prototypes/Weapon/weapon_demo.gd
# 主场景控制器：reset、Q 键 spawn Effect、活跃数统计。
class_name WeaponDemo
extends Node2D

@export var player_path: NodePath
@export var player_spawn: Vector2 = Vector2(400, 400)
@export var standalone_effect_scene: PackedScene  # 键 Q 在鼠标位置 spawn

var _player: RigidBody2D

func _ready() -> void:
	_player = get_node(player_path) as RigidBody2D
	if _player and not _player.is_in_group("player"):
		_player.add_to_group("player")  # affect_player=false 用 group 识别

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("Reset"):
			_reset_player()
		elif event.is_action_pressed("SpawnEffect"):
			_spawn_standalone_effect()

func _reset_player() -> void:
	if _player == null:
		return
	_player.linear_velocity = Vector2.ZERO
	_player.angular_velocity = 0.0
	_player.global_position = player_spawn

func _spawn_standalone_effect() -> void:
	if standalone_effect_scene == null:
		return
	var fx := standalone_effect_scene.instantiate() as Effect
	if fx == null:
		return
	add_child(fx)
	fx.trigger(get_global_mouse_position(), {"source": self, "direction": Vector2.RIGHT})

# Debug 面板读 —— 全场 Projectile 与 Effect 节点数（含子树）。
func count_active_projectiles() -> int:
	return get_tree().get_nodes_in_group("projectile").size()

func count_active_effects() -> int:
	return get_tree().get_nodes_in_group("effect").size()
