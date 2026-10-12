extends VBoxContainer
class_name BaseTypeWiki
## Wiki page: every droppable base type, by group and item type, with the
## item level it starts dropping at, its requirements, base numbers and
## implicits - so a build can be planned before the base drops.

const WIDTH := 980.0
const LIST_HEIGHT := 500.0
const GROUP_COLOR := Color(0.95, 0.8, 0.5)

var current_group: String = ""
var current_type: String = ""
## Base display names in the order shown, for tests.
var shown: Array[String] = []

var _group_bar: HBoxContainer
var _type_bar: HFlowContainer
var _list: VBoxContainer

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(WIDTH, 0)
	var intro := ModifierWiki._text("Each base starts dropping at its item level; a drop always uses the best base of its line the area allows. Base numbers are before modifiers and quality.", 13, ModifierWiki.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(WIDTH, 0)
	add_child(intro)
	_group_bar = HBoxContainer.new()
	add_child(_group_bar)
	for group in WikiCatalog.BASE_GROUPS:
		var b := Button.new()
		b.text = group
		b.toggle_mode = true
		b.pressed.connect(show_group.bind(group))
		_group_bar.add_child(b)
	_type_bar = HFlowContainer.new()
	_type_bar.custom_minimum_size = Vector2(WIDTH, 0)
	add_child(_type_bar)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	show_group(WikiCatalog.BASE_GROUPS[0])

func show_group(group: String) -> void:
	current_group = group
	for b in _group_bar.get_children():
		b.button_pressed = b.text == group
	for child in _type_bar.get_children():
		_type_bar.remove_child(child)
		child.queue_free()
	var types: Array = WikiCatalog.bases_in(group).keys()
	types.sort()
	for type in types:
		var b := Button.new()
		b.text = type
		b.toggle_mode = true
		b.pressed.connect(show_type.bind(type))
		_type_bar.add_child(b)
	show_type(types[0] if not types.is_empty() else "")

func show_type(type: String) -> void:
	current_type = type
	for b in _type_bar.get_children():
		b.button_pressed = b.text == type
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	shown.clear()
	var bases: Array = WikiCatalog.bases_in(current_group).get(type, [])
	_list.add_child(ModifierWiki._text("%s  ·  %d bases" % [type, bases.size()], 18, GROUP_COLOR))
	for base in bases:
		shown.append(base.display_name)
		_list.add_child(_row(base))

func _row(base: Item) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", AetherStyle.glass_box(Color(GROUP_COLOR, 0.25), Color(0.05, 0.05, 0.08, 0.85), 1, 6.0))
	var box := VBoxContainer.new()
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var name_label := ModifierWiki._text(base.display_name, 15, AetherStyle.TEXT)
	name_label.custom_minimum_size = Vector2(260, 0)
	head.add_child(name_label)
	var level_label := ModifierWiki._text("Item Level %d" % base.item_level, 13, AetherStyle.GOLD)
	level_label.custom_minimum_size = Vector2(120, 0)
	head.add_child(level_label)
	var req := WikiCatalog.base_requirement_text(base)
	var req_label := ModifierWiki._text("Requires %s" % req if req != "" else "No requirements", 13, ModifierWiki.MUTED)
	req_label.custom_minimum_size = Vector2(230, 0)
	head.add_child(req_label)
	if base.max_sockets > 0:
		head.add_child(ModifierWiki._text("%d sockets" % base.max_sockets, 13, ModifierWiki.MUTED))
	var details: Array[String] = WikiCatalog.base_stat_parts(base)
	var implicit := WikiCatalog.base_implicit_text(base)
	if implicit != "":
		details.append(implicit)
	if base.flavor_text != "":
		details.append(base.flavor_text)
	if not details.is_empty():
		var text := ModifierWiki._text("   ·   ".join(details), 13, Color(0.75, 0.85, 1.0))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(WIDTH - 40.0, 0)
		box.add_child(text)
	return panel
