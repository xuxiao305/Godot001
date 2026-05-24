# Scripts/Prototypes/3C/input_buffer.gd
# Coyote + Jump Buffer 计时器。时间使用绝对秒（从 SceneTree 拿）。
# 来源：spec §4.5 + CONTEXT.md
#
# 用法：每帧调用 update_grounded() 喂入当前接地状态（不是仅边缘）；
# 输入侧调用 on_jump_pressed() 记录按键时刻；
# 决策侧用 can_coyote() / can_buffer() 查询当前是否允许起跳；
# 起跳后调用 consume_buffer() 防止重复触发。
class_name InputBuffer
extends RefCounted

var coyote_time: float = 0.10
var jump_buffer_time: float = 0.10

var _last_grounded_true_at: float = -INF   # 上次接地（true）的时间
var _is_grounded: bool = false
var _last_jump_pressed_at: float = -INF
var _buffer_consumed: bool = false
var _coyote_consumed: bool = false

# 每个 physics tick 调用 —— 不论 grounded 是否变化都要喂。
func update_grounded(grounded: bool, now: float) -> void:
	if grounded and not _is_grounded:
		# 落地 → buffer 和 coyote 都复位（可再用一次）
		_buffer_consumed = false
		_coyote_consumed = false
	if grounded:
		_last_grounded_true_at = now
	_is_grounded = grounded

# 离地后 _last_grounded_true_at 停在最后一次"接地 tick"的时间。
func can_coyote(now: float) -> bool:
	if _coyote_consumed:
		return false
	return (now - _last_grounded_true_at) <= coyote_time

func on_jump_pressed(now: float) -> void:
	_last_jump_pressed_at = now
	_buffer_consumed = false

func can_buffer(now: float) -> bool:
	if _buffer_consumed:
		return false
	return (now - _last_jump_pressed_at) <= jump_buffer_time

func consume_buffer() -> void:
	_buffer_consumed = true
	_last_jump_pressed_at = -INF

func consume_coyote() -> void:
	_coyote_consumed = true
