# Scripts/Prototypes/3C/debug_panel.gd
# 实时滑条 + 数值显示 + JSON save/load。F1 切换可见。
# 来源：spec §4.9
class_name DebugPanel
extends CanvasLayer

const MovementState := preload("res://Scripts/Prototypes/3C/movement_state.gd")

@export var player_path: NodePath
@export var default_save_path: String = "user://3c_params.json"

var _player: Player3C
var _root: PanelContainer
var _value_labels: Dictionary = {}  # 实时数值显示
var _slider_bindings: Array = []    # [(prop_name, slider, label, min, max)]

const SLIDER_SPECS := [
	# (property, label, min, max)
	["v_max", "v_max (px/s)", 100.0, 1500.0],
	["f_max_ground", "F_max ground", 1000.0, 20000.0],
	["saturation_full", "saturation_full", 50.0, 1000.0],
	["f_active_brake", "F_active_brake", 0.0, 5000.0],
	["f_max_air", "F_max air", 500.0, 10000.0],
	["j_jump_initial", "Jump impulse", 200.0, 3000.0],
	["f_jump_hold", "Jump hold force", 0.0, 3000.0],
	["hold_window_max", "Hold window (s)", 0.0, 0.6],
	["gravity_y", "Gravity (px/s²)", 500.0, 6000.0],
	["coyote_time", "Coyote (s)", 0.0, 0.3],
	["jump_buffer_time", "Buffer (s)", 0.0, 0.3],
	["cos_theta_max", "cos_theta_max", 0.0, 1.0],
	["ground_state_buffer_frames", "Anti-debounce frames", 0.0, 5.0],
]

const READOUT_KEYS := [
	"position", "linear_velocity", "is_grounded", "current_state",
	"ground_normal_y", "net_force_this_frame",
]

func _ready() -> void:
	_player = get_node(player_path) as Player3C
	_build_ui()
	visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		visible = not visible

func _process(_dt: float) -> void:
	if not visible or _player == null:
		return
	for key in READOUT_KEYS:
		if not _value_labels.has(key):
			continue
		var label := _value_labels[key] as Label
		if key == "current_state":
			label.text = "%s: %s" % [key, MovementState.to_display(_player.current_state)]
		else:
			label.text = "%s: %s" % [key, _player.get(key)]

func _build_ui() -> void:
	_root = PanelContainer.new()
	_root.position = Vector2(900, 10)
	_root.custom_minimum_size = Vector2(360, 700)
	add_child(_root)

	var vbox := VBoxContainer.new()
	_root.add_child(vbox)

	# 标题
	var title := Label.new()
	title.text = "[F1] 3C Debug Panel"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	# 实时数值
	for key in READOUT_KEYS:
		var l := Label.new()
		l.text = "%s: ..." % key
		vbox.add_child(l)
		_value_labels[key] = l

	vbox.add_child(HSeparator.new())

	# 滑条
	for spec in SLIDER_SPECS:
		var prop: String = spec[0]
		var label_text: String = spec[1]
		var smin: float = spec[2]
		var smax: float = spec[3]

		var hb := HBoxContainer.new()
		vbox.add_child(hb)
		var lab := Label.new()
		lab.custom_minimum_size.x = 140
		hb.add_child(lab)
		var slider := HSlider.new()
		slider.min_value = smin
		slider.max_value = smax
		slider.step = (smax - smin) / 200.0
		slider.value = _player.get(prop)
		slider.custom_minimum_size.x = 180
		hb.add_child(slider)
		lab.text = "%s = %.2f" % [label_text, slider.value]
		slider.value_changed.connect(func(v: float) -> void:
			_player.set(prop, v)
			lab.text = "%s = %.2f" % [label_text, v]
		)
		_slider_bindings.append([prop, slider, lab, label_text])

	vbox.add_child(HSeparator.new())

	# 按钮：reset / save / load
	var btn_reset := Button.new()
	btn_reset.text = "Reset to defaults"
	btn_reset.pressed.connect(_on_reset)
	vbox.add_child(btn_reset)

	var btn_save := Button.new()
	btn_save.text = "Save to JSON"
	btn_save.pressed.connect(_on_save)
	vbox.add_child(btn_save)

	var btn_load := Button.new()
	btn_load.text = "Load from JSON"
	btn_load.pressed.connect(_on_load)
	vbox.add_child(btn_load)

func _on_reset() -> void:
	# 重新加载 player.gd 的默认值（用一个新实例读取）
	var fresh := preload("res://Scripts/Prototypes/3C/player.gd").new()
	for binding in _slider_bindings:
		var prop: String = binding[0]
		var slider: HSlider = binding[1]
		var lab: Label = binding[2]
		var label_text: String = binding[3]
		var v = fresh.get(prop)
		_player.set(prop, v)
		slider.value = v
		lab.text = "%s = %.2f" % [label_text, v]
	fresh.free()

func _on_save() -> void:
	var data := {}
	for binding in _slider_bindings:
		var prop: String = binding[0]
		data[prop] = _player.get(prop)
	var f := FileAccess.open(default_save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	print("[DebugPanel] saved to %s" % default_save_path)

func _on_load() -> void:
	if not FileAccess.file_exists(default_save_path):
		push_warning("No saved params at %s" % default_save_path)
		return
	var f := FileAccess.open(default_save_path, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	for binding in _slider_bindings:
		var prop: String = binding[0]
		var slider: HSlider = binding[1]
		var lab: Label = binding[2]
		var label_text: String = binding[3]
		if data.has(prop):
			var v: float = data[prop]
			_player.set(prop, v)
			slider.value = v
			lab.text = "%s = %.2f" % [label_text, v]
