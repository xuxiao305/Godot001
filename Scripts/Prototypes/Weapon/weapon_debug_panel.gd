# Scripts/Prototypes/Weapon/weapon_debug_panel.gd
# F1 切换可见；runtime 调 Weapon / Projectile / Effect 子组件参数。
# 仿 Scripts/Prototypes/3C/debug_panel.gd 同款滑条 + readout 风格。
class_name WeaponDebugPanel
extends CanvasLayer

@export var pistol_path: NodePath
@export var rocket_path: NodePath
@export var pistol_effect_scene_path: String = "res://Scenes/Prototypes/Weapon/effects/pistol_hit_effect.tscn"
@export var rocket_effect_scene_path: String = "res://Scenes/Prototypes/Weapon/effects/rocket_explosion_effect.tscn"
@export var demo_path: NodePath  # WeaponDemo (for active counts)

var _pistol: Weapon
var _rocket: Weapon
var _demo: WeaponDemo
var _value_labels: Dictionary = {}

const PISTOL_SLIDERS := [
	["cooldown", "Pistol cooldown (s)", 0.05, 1.0],
	["recoil_impulse", "Pistol recoil (px·kg/s)", 0.0, 1000.0],
	["projectile_initial_speed", "Pistol speed (px/s)", 1000.0, 20000.0],
]
const ROCKET_SLIDERS := [
	["cooldown", "Rocket cooldown (s)", 0.1, 2.0],
	["recoil_impulse", "Rocket recoil (px·kg/s)", 0.0, 2000.0],
	["projectile_initial_speed", "Rocket speed (px/s)", 500.0, 8000.0],
]

func _ready() -> void:
	if pistol_path != NodePath():
		_pistol = get_node(pistol_path) as Weapon
	if rocket_path != NodePath():
		_rocket = get_node(rocket_path) as Weapon
	if demo_path != NodePath():
		_demo = get_node(demo_path) as WeaponDemo
	_build_ui()
	visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		visible = not visible

func _process(_dt: float) -> void:
	if not visible:
		return
	if _demo != null:
		if _value_labels.has("active_projectiles"):
			_value_labels["active_projectiles"].text = "active projectiles: %d" % _demo.count_active_projectiles()
		if _value_labels.has("active_effects"):
			_value_labels["active_effects"].text = "active effects: %d" % _demo.count_active_effects()
	# Pistol/Rocket recoil 开关与 affect_player 复选框由 toggle 自身回写

func _build_ui() -> void:
	var root := PanelContainer.new()
	root.position = Vector2(10, 10)
	root.custom_minimum_size = Vector2(360, 700)
	add_child(root)
	var vbox := VBoxContainer.new()
	root.add_child(vbox)

	var title := Label.new()
	title.text = "[F1] Weapon Debug Panel"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	# 实时数值
	for key in ["active_projectiles", "active_effects"]:
		var l := Label.new(); l.text = "%s: ..." % key; vbox.add_child(l); _value_labels[key] = l

	# Pistol
	_add_section(vbox, "Pistol")
	for spec in PISTOL_SLIDERS:
		_add_slider_for(vbox, _pistol, spec[0], spec[1], spec[2], spec[3])
	_add_toggle_for(vbox, _pistol, "recoil_enabled", "Pistol recoil enabled")

	# Rocket
	_add_section(vbox, "Rocket Launcher")
	for spec in ROCKET_SLIDERS:
		_add_slider_for(vbox, _rocket, spec[0], spec[1], spec[2], spec[3])
	_add_toggle_for(vbox, _rocket, "recoil_enabled", "Rocket recoil enabled")

	# Effect 默认 .tscn 是 PackedScene → 每次 instantiate 后才能改；
	# v1 简化：rocket_explosion_effect 的 affect_player 在场景里编辑保存。
	# 想运行时切，挂一个常驻 RocketExplosionEffect template 节点也可（未来 v1.5）。
	var hint := Label.new()
	hint.text = "(Effect params: edit .tscn directly; v1)"
	hint.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(hint)
func _add_section(parent: Control, name: String) -> void:
	var l := Label.new()
	l.text = "--- %s ---" % name
	l.add_theme_font_size_override("font_size", 14)
	parent.add_child(l)

func _add_slider_for(parent: Control, target: Object, prop: String, label_text: String, lo: float, hi: float) -> void:
	if target == null:
		return
	var row := HBoxContainer.new(); parent.add_child(row)
	var l := Label.new(); l.text = label_text; l.custom_minimum_size = Vector2(140, 0); row.add_child(l)
	var v := Label.new(); v.custom_minimum_size = Vector2(60, 0); row.add_child(v)
	var s := HSlider.new(); s.min_value = lo; s.max_value = hi; s.step = (hi - lo) / 1000.0
	s.value = target.get(prop)
	s.custom_minimum_size = Vector2(140, 0)
	v.text = "%.2f" % s.value
	s.value_changed.connect(func(val):
		target.set(prop, val); v.text = "%.2f" % val)
	row.add_child(s)

func _add_toggle_for(parent: Control, target: Object, prop: String, label_text: String) -> void:
	if target == null:
		return
	var cb := CheckBox.new()
	cb.text = label_text
	cb.button_pressed = target.get(prop)
	cb.toggled.connect(func(on): target.set(prop, on))
	parent.add_child(cb)
