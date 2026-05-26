# Weld Demo —— 用 PinJoint2D + angular_limit_enabled 锁住相对旋转，等效于焊接
# (Rapier2D 同样通过 PinJoint + 角度限制近似焊接)
extends DemoLevel


func _ready() -> void:
	super._ready()
