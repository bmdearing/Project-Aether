extends VBoxContainer
class_name StatDetailsPanel
## The character sheet's Advanced view: every stat your gear, jewels, Slates
## and Lenses change (StatSources), grouped by kind. Hovering a stat's name
## explains it (StatGlossary); hovering its value lists where it comes from.
## Sits in the sheet in place of the Basic stat columns.

var _list: VBoxContainer

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var hint := Label.new()
	hint.text = "Everything your gear, jewels, Slates and Lenses change. Hover a value for its sources, or a name for what it does."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", AetherStyle.TEXT_DIM)
	add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)

func refresh(player: Player) -> void:
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
