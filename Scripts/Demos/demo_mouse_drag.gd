# MouseDrag Demo —— 用 DragVisualizer 展示拖拽弹性线 + 拖尾
# (addon 未提供 MouseJoint2D 类，用 DemoLevel 已有的 velocity-drag + 可视化代替)
extends DemoLevel


func _ready() -> void:
	super._ready()
