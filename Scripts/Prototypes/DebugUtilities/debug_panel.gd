# Scripts/Prototypes/Destruction/debug_panel.gd
# Runtime debug HUD: stats + 2 isolation toggles. spec §4.8.
# Toggle state flows: DebugPanel → impact.propagation_enabled / impact.enabled
# → Block.take_damage / ImpactWatcher.on_contact
extends CanvasLayer

var demo = null  # DestructionDemo
var impact = null  # ImpactWatcher

@onready var _panel: Control = $Panel
@onready var _fps_label: Label = $Panel/VBox/Stats/FpsLabel
@onready var _block_label: Label = $Panel/VBox/Stats/BlockLabel
@onready var _constraint_label: Label = $Panel/VBox/Stats/ConstraintLabel
@onready var _destroy_label: Label = $Panel/VBox/Stats/DestroyLabel
@onready var _sw_propagation: CheckBox = $Panel/VBox/Toggles/PropagationToggle
@onready var _sw_impact: CheckBox = $Panel/VBox/Toggles/ImpactToggle
@onready var _sw_contact_debug: CheckBox = $Panel/VBox/Toggles/ContactDebugToggle

func _ready() -> void:
	_panel.visible = true
	_sw_propagation.toggled.connect(_on_propagation_toggled)
	_sw_impact.toggled.connect(_on_impact_toggled)
	_sw_contact_debug.toggled.connect(_on_contact_debug_toggled)

func _on_propagation_toggled(b: bool) -> void:
	if impact != null:
		impact.propagation_enabled = b

func _on_impact_toggled(b: bool) -> void:
	if impact != null:
		impact.enabled = b

func _on_contact_debug_toggled(b: bool) -> void:
	Block.debug_contact_impulse = b

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_panel.visible = not _panel.visible

func _process(_dt: float) -> void:
	if not _panel.visible:
		return
	_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	if demo == null or demo.current_structure == null:
		return
	var s = demo.current_structure
	_block_label.text = "Blocks: %d" % s._blocks.size()
	var c_alive := 0
	for c in s._constraints:
		if is_instance_valid(c) and is_instance_valid(c.pin):
			c_alive += 1
	_constraint_label.text = "Constraints: %d" % c_alive
