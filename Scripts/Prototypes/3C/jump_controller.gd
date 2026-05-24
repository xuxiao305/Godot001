# Scripts/Prototypes/3C/jump_controller.gd
# 跳跃状态机 —— 管理"按住期间持续推力"窗口。
class_name JumpController
extends RefCounted

var hold_active: bool = false
var _hold_elapsed: float = 0.0
var _hold_window: float = 0.30
var _f_hold: float = 0.0

# 接到合法的起跳信号 → 返回初始冲量（外部 apply）；并启动 hold 窗口。
func trigger_jump(j_initial: float, f_hold: float, hold_window: float) -> Vector2:
	hold_active = true
	_hold_elapsed = 0.0
	_hold_window = hold_window
	_f_hold = f_hold
	return Vector2(0, -j_initial)  # 向上（Y 轴朝下世界里 -y 是上）

# 每 physics tick 调用 —— 返回本帧的持续推力（vector，可能为 0）。
# input_held: 当前 Jump 键是否还按着
# vy:        角色当前 vy（vy >= 0 = 已开始下落，立刻停推）
func tick(delta: float, input_held: bool, vy: float) -> Vector2:
	if not hold_active:
		return Vector2.ZERO
	# 终止条件：松键 / 开始下落 / 窗口超时
	if not input_held or vy >= 0.0 or _hold_elapsed >= _hold_window:
		hold_active = false
		return Vector2.ZERO
	_hold_elapsed += delta
	return Vector2(0, -_f_hold)

func reset() -> void:
	hold_active = false
	_hold_elapsed = 0.0
