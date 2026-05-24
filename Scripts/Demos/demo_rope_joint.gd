# Chain Demo —— 用 PinJoint2D 串联演示刚性摆锤 + 多段链条
# (godot-box2d 未注册 RopeJoint2D 类；"绳索"的"可松弛"语义无法用内置 Joint 表达，
#  这里用刚性链条作为最接近的替代演示)
extends DemoLevel


func _ready() -> void:
	super._ready()
