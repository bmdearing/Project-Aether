extends VBoxContainer
class_name SettingsPanel
## Options shared by the title screen and the pause menu, in two tabs:
## General (sliders and toggles) and Controls (click a binding, then press a
## key or mouse button; Esc cancels). Changes apply and save immediately;
## Back emits back_pressed.

signal back_pressed

const WIDTH := 460.0
const CONTROLS_HEIGHT := 440.0

var _general: VBoxContainer
var _bind_buttons: Dictionary = {}  # action -> Button
## The action waiting for a new key, or "".
var _capturing: String = ""

func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_constant_override("separation", 10)
	alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	add_child(title)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(WIDTH, 0)
	add_child(tabs)
	_general = VBoxContainer.new()
	_general.name = "General"
	_general.add_theme_constant_override("separation", 10)
	tabs.add_child(_general)
	tabs.add_child(_build_controls_tab())

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
	back.pressed.connect(func():
		_capturing = ""
		back_pressed.emit())
	add_child(back)

func _build_controls_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "Controls"
	tab.add_theme_constant_override("separation", 8)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH, CONTROLS_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for entry in GameSettings.REMAPPABLE:
		var action: String = entry[0]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = entry[1]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(170, 0)
		button.pressed.connect(_start_capture.bind(action))
		row.add_child(button)
		list.add_child(row)
		_bind_buttons[action] = button
	var reset := Button.new()
	reset.text = "Reset to Defaults"
	reset.pressed.connect(func():
		_capturing = ""
		GameSettings.reset_controls()
		_refresh_bindings()
		_commit())
	tab.add_child(reset)
	_refresh_bindings()
	return tab

func _start_capture(action: String) -> void:
	_capturing = action
	_refresh_bindings()
	_bind_buttons[action].text = "Press a key..."

func _refresh_bindings() -> void:
	for action in _bind_buttons:
		_bind_buttons[action].text = GameSettings.key_name(action)

## Takes the next key or mouse press as the new binding. The click that
## started capturing is a release by the time it arrives here, so it's skipped.
func _input(event: InputEvent) -> void:
	if _capturing == "" or not is_visible_in_tree():
		return
	var chosen: InputEvent = null
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_capturing = ""
			_refresh_bindings()
			get_viewport().set_input_as_handled()
			return
		var key := InputEventKey.new()
		key.physical_keycode = (event as InputEventKey).physical_keycode
		chosen = key
	elif event is InputEventMouseButton and event.pressed:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = (event as InputEventMouseButton).button_index
		chosen = mouse
	if chosen == null:
		return
	get_viewport().set_input_as_handled()
	GameSettings.bind(_capturing, chosen)
	_capturing = ""
	_refresh_bindings()
	_commit()

func _add_slider(label_text: String, min_v: float, max_v: float, step: float, value: float, setter: Callable, fmt: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var readout := Label.new()
	readout.text = fmt.call(value)
	row.add_child(readout)
	_general.add_child(row)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.value_changed.connect(func(v: float):
		setter.call(v)
		readout.text = fmt.call(v)
		_commit())
	_general.add_child(slider)

func _add_toggle(label_text: String, value: bool, setter: Callable) -> void:
	var box := CheckBox.new()
	box.text = label_text
	box.button_pressed = value
	box.toggled.connect(func(on: bool):
		setter.call(on)
		_commit())
	_general.add_child(box)

func _commit() -> void:
	GameSettings.apply()
	GameSettings.save()
