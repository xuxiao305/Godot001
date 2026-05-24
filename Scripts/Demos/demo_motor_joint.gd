# MotorJoint Demo —— 用 GrooveJoint2D + 周期性推力模拟线性马达
extends DemoLevel


@export var platform_path: NodePath
@export var force_magnitude: float = 1500.0   ## 推力幅度（牛）
@export var period: float = 4.0               ## 往返周期（秒）

var _platform: RigidBody2D = null
var _elapsed: float = 0.0


func _ready() -> void:
	super._ready()
	if platform_path != NodePath(""):
		_platform = get_node_or_null(platform_path) as RigidBody2D


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _platform == null:
		return
	# 拖拽中由基类的 velocity 覆盖逻辑接管，不要叠加马达推力
	if _drag_body == _platform:
		_elapsed = 0.0
		return
	_elapsed += delta
	var phase := TAU * _elapsed / period
	var fx := sin(phase) * force_magnitude
	_platform.apply_central_force(Vector2(fx, 0.0))
