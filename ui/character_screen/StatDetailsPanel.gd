extends Control
class_name StatDetailsPanel
## "More Info" on the character sheet: every stat your gear, jewels, Slates
## and Lenses change (StatSources), grouped by kind. Hovering a stat's name
## explains it (StatGlossary); hovering its value lists where it comes from.
## Esc or a click outside closes it.

const PANEL_SIZE := Vector2(720, 640)

var _list: VBoxContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			close())
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", AetherStyle.glass_box(AetherStyle.GOLD_DIM, AetherStyle.GLASS_SOLID, 1, 16.0))
	frame.custom_minimum_size = PANEL_SIZE
	center.add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	frame.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var title := Label.new()
	title.text = "Character Details"
	AetherStyle.title_label(title)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	top.add_child(close_button)
	var hint := Label.new()
	hint.text = "Everything your gear, jewels, Slates and Lenses change. Hover a value for its sources, or a name for what it does."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", AetherStyle.TEXT_DIM)
	column.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)

func open(player: Player) -> void:
	_rebuild(player)
	visible = true

func close() -> void:
	visible = false

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _rebuild(player: Player) -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var rows := StatSources.collect(player)
	if rows.is_empty():
		var none := Label.new()
		none.text = "Nothing changes your stats yet."
		none.add_theme_color_override("font_color", AetherStyle.TEXT_DIM)
		_list.add_child(none)
		return
	var category := ""
	var index := 0
	for row in rows:
		if row["category"] != category:
			category = row["category"]
			index = 0
			_list.add_child(AetherStyle.section_header(category))
		_list.add_child(_row(row, index))
		index += 1

func _row(row: Dictionary, index: int) -> Control:
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", AetherStyle.row_box(index % 2 == 1))
	plate.mouse_filter = Control.MOUSE_FILTER_PASS
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(line)
	var name_label := Label.new()
	name_label.text = row["name"]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", AetherStyle.TEXT_DIM)
	name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	name_label.tooltip_text = StatGlossary.explain(row["key"])
	line.add_child(name_label)
	var value := Label.new()
	value.text = StatGlossary.format(row["key"], row["total"])
	value.add_theme_font_override("font", AetherStyle.numbers())
	value.add_theme_font_size_override("font_size", 16)
	value.add_theme_color_override("font_color", AetherStyle.MOD_BLUE)
	value.mouse_filter = Control.MOUSE_FILTER_STOP
	value.mouse_default_cursor_shape = Control.CURSOR_HELP
	value.tooltip_text = StatSources.breakdown_text(row)
	line.add_child(value)
	return plate
