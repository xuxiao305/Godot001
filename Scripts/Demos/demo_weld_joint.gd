# Weld Demo —— 用 PinJoint2D + angular_limit_enabled 锁住相对旋转，等效于焊接
# (godot-box2d 未注册 WeldJoint2D 类，只能用此方案近似)
extends DemoLevel


func _ready() -> void:
	super._ready()
