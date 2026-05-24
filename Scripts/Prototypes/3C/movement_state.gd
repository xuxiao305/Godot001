# Scripts/Prototypes/3C/movement_state.gd
# 角色运动状态枚举 + 从物理观测派生当前状态。
# 状态是"观察口径"，不接管力的分发（详见 3C-prototype-design.md §4.7）。
class_name MovementState
extends RefCounted

enum State { IDLE, RUNNING, RISING, FALLING }

const SPEED_IDLE_THRESHOLD: float = 5.0  # 与 player.gd 改前同值

# 从物理观测派生当前状态。纯函数，无副作用。
static func derive(is_grounded: bool, vx: float, vy: float) -> State:
	if is_grounded:
		return State.IDLE if absf(vx) < SPEED_IDLE_THRESHOLD else State.RUNNING
	return State.RISING if vy < 0.0 else State.FALLING

# 查询助手：状态属于"接地态"么？力分发按此分支选 ground vs air。
static func is_grounded_state(s: State) -> bool:
	return s == State.IDLE or s == State.RUNNING

# 显示翻译：给 Debug 面板用。
static func to_display(s: State) -> String:
	match s:
		State.IDLE: return "Idle"
		State.RUNNING: return "Running"
		State.RISING: return "Rising"
		State.FALLING: return "Falling"
	return "?"
