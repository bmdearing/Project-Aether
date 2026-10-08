extends VBoxContainer
class_name SettingsPanel
## Options list shared by the title screen and the pause menu. Changes apply
## and save immediately; Back emits back_pressed.

signal back_pressed

const WIDTH := 380.0

func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_constant_override("separation", 10)
	alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	add_child(title)

	_add_slider("Mouse Sensitivity", 0.001, 0.01, 0.0005, GameState.mouse_sensitivity,
		func(v: float): GameState.mouse_sensitivity = v, func(v: float): return "%.1f" % (v * 1000.0))
	_add_slider("Field of View", 60.0, 110.0, 1.0, GameState.field_of_view,
		func(v: float): GameState.field_of_view = v, func(v: float): return "%d" % int(v))
	_add_slider("Master Volume", 0.0, 1.0, 0.01, GameState.master_volume,
		func(v: float): GameState.master_volume = v, func(v: float): return "%d%%" % int(round(v * 100.0)))
	_add_toggle("Fullscreen", GameState.fullscreen, func(on: bool): GameState.fullscreen = on)
	_add_toggle("V-Sync", GameState.vsync, func(on: bool): GameState.vsync = on)
	_add_toggle("Always Show Item Sockets", GameState.always_show_sockets, func(on: bool): GameState.always_show_sockets = on)

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func(): back_pressed.emit())
	add_child(back)

func _add_slider(label_text: String, min_v: float, max_v: float, step: float, value: float, setter: Callable, fmt: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var readout := Label.new()
	readout.text = fmt.call(value)
	row.add_child(readout)
	add_child(row)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.value_changed.connect(func(v: float):
		setter.call(v)
		readout.text = fmt.call(v)
		_commit())
	add_child(slider)

func _add_toggle(label_text: String, value: bool, setter: Callable) -> void:
	var box := CheckBox.new()
	box.text = label_text
	box.button_pressed = value
	box.toggled.connect(func(on: bool):
		setter.call(on)
		_commit())
	add_child(box)

func _commit() -> void:
	GameSettings.apply()
	GameSettings.save()
