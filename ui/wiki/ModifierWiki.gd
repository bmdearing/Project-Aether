extends VBoxContainer
class_name ModifierWiki
## Wiki page for modifiers. "By item": pick a group, a base type and an item
## level; every prefix and suffix it can roll, each tier's range and the item
## level it needs, and the chance an Orb adds it (WikiCatalog). Tiers the
## level can't reach are dimmed. "By modifier": search a modifier and see
## every base type it rolls on.

const WIDTH := 980.0
const LIST_HEIGHT := 500.0
const PREFIX_COLOR := Color(0.55, 0.75, 1.0)
const SUFFIX_COLOR := Color(0.75, 0.6, 1.0)
const LOCKED_ALPHA := 0.32
const MUTED := Color(0.66, 0.62, 0.55)
const ICON_SIZE := 26.0

var level: int = 80
var by_modifier := false

var _modes: HBoxContainer
var _group_box: OptionButton
var _type_box: OptionButton
var _level_box: SpinBox
var _level_row: HBoxContainer
var _preview: ItemIcon
var _search: LineEdit
var _item_controls: HBoxContainer
var _list: VBoxContainer
var _summary: Label

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(WIDTH, 0)
	_build()
	_fill_types()
	refresh()

func _build() -> void:
	var modes := HBoxContainer.new()
	_modes = modes
	add_child(modes)
	for mode in ["By item", "By modifier"]:
		var b := Button.new()
		b.text = mode
		b.toggle_mode = true
		b.button_pressed = mode == "By item"
		b.pressed.connect(func():
			by_modifier = mode == "By modifier"
			refresh())
		modes.add_child(b)

	_item_controls = HBoxContainer.new()
	_item_controls.add_theme_constant_override("separation", 10)
	add_child(_item_controls)
	_preview = ItemIcon.new()
	_preview.custom_minimum_size = Vector2(40, 40)
	_item_controls.add_child(_preview)
	_group_box = OptionButton.new()
	for g in WikiCatalog.GROUPS:
		_group_box.add_item(g)
	_group_box.item_selected.connect(func(_i):
		_fill_types()
		refresh())
	_item_controls.add_child(_group_box)
	_type_box = OptionButton.new()
	_type_box.custom_minimum_size = Vector2(220, 0)
	_type_box.item_selected.connect(func(_i): refresh())
	_item_controls.add_child(_type_box)
	_level_row = HBoxContainer.new()
	_item_controls.add_child(_level_row)
	_level_row.add_child(_text("Item level", 15, AetherStyle.TEXT))
	_level_box = SpinBox.new()
	_level_box.min_value = 1
	_level_box.max_value = WikiCatalog.MAX_LEVEL
	_level_box.value = level
	_level_box.value_changed.connect(func(v: float):
		level = int(v)
		refresh())
	_level_row.add_child(_level_box)

	_search = LineEdit.new()
	_search.placeholder_text = "Search a modifier (e.g. Fire, Attack Speed, Life)"
	_search.custom_minimum_size = Vector2(420, 0)
	_search.text_changed.connect(func(_t): refresh())
	add_child(_search)

	_summary = _text("", 13, MUTED)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

func _fill_types() -> void:
	_type_box.clear()
	for t in WikiCatalog.types_in(current_group()):
		_type_box.add_item(t["name"])
	_type_box.select(0)

func current_group() -> String:
	return WikiCatalog.GROUPS[maxi(_group_box.selected, 0)]

## The selected base type's catalogue entry ({"name", "key", "base"}).
func current_type() -> Dictionary:
	var types := WikiCatalog.types_in(current_group())
	return types[clampi(_type_box.selected, 0, types.size() - 1)] if not types.is_empty() else {}

## Selects a group and type by name (tests, links).
func show_type(group: String, type_name: String, item_level: int) -> void:
	_group_box.select(WikiCatalog.GROUPS.find(group))
	_fill_types()
	for i in _type_box.item_count:
		if _type_box.get_item_text(i) == type_name:
			_type_box.select(i)
	level = item_level
	_level_box.set_value_no_signal(item_level)
	refresh()

## Rows currently listed (By item: WikiCatalog.modifier_rows; By modifier:
## modifier_index entries).
var rows: Array = []

func refresh() -> void:
	if _list == null:
		return
	for b in _modes.get_children():
		b.button_pressed = (b.text == "By modifier") == by_modifier
	_item_controls.visible = not by_modifier
	_search.visible = by_modifier
	for child in _list.get_children():
		child.queue_free()
	if by_modifier:
		_show_index()
	else:
		_show_item()

func _show_item() -> void:
	var t := current_type()
	if t.is_empty():
		rows = []
		return
	var base: Resource = t["base"]
	_preview.content = base
	_level_row.visible = not base is Slate
	rows = WikiCatalog.modifier_rows(base, level)
	var open := rows.filter(func(r): return r["chance"] > 0.0).size()
	_summary.text = "%d modifiers, %d can roll at item level %d. Chance = the chance an Orb adds that modifier (and tier) to a blank %s, with no Brands. Dim tiers need a higher item level." % [rows.size(), open, level, t["name"]] if not base is Slate else "%d modifiers. Chance = the chance an Orb adds that modifier (and tier) to a blank Slate of this tag, with no Brands. Slate tiers aren't gated by item level." % rows.size()
	var last_prefix := true
	for i in rows.size():
		var row: Dictionary = rows[i]
		if i == 0 or row["prefix"] != last_prefix:
			_list.add_child(_text("Prefixes" if row["prefix"] else "Suffixes", 17, PREFIX_COLOR if row["prefix"] else SUFFIX_COLOR))
			last_prefix = row["prefix"]
		_list.add_child(_modifier_row(row))
	if base is Item and not (base is Jewel):
		_add_implicit_pool(base)

func _modifier_row(row: Dictionary) -> PanelContainer:
	var locked: bool = row["chance"] <= 0.0
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", AetherStyle.glass_box(Color(AetherStyle.GOLD, 0.25), Color(0.05, 0.05, 0.07, 0.8), 1, 8.0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var name_label := _text(row["text"], 15, PREFIX_COLOR if row["prefix"] else SUFFIX_COLOR)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	if row["local"]:
		head.add_child(_text("Local  ", 12, MUTED))
	var chance_text := "from item level %d" % row["min_level"] if locked else "%s per Orb" % _percent(row["chance"])
	head.add_child(_text(chance_text, 14, MUTED if locked else AetherStyle.GOLD))
	var tiers := HFlowContainer.new()
	tiers.add_theme_constant_override("h_separation", 12)
	box.add_child(tiers)
	for t in row["tiers"]:
		var range_text := _number(t["min"]) if is_equal_approx(t["min"], t["max"]) else "%s-%s" % [_number(t["min"]), _number(t["max"])]
		var tier_text := "T%d  %s  (ilvl %d)" % [t["tier"], range_text, t["level"]]
		if t["chance"] > 0.0:
			tier_text += "  %s" % _percent(t["chance"])
		var chip := _text(tier_text, 13, AetherStyle.TEXT)
		if t["chance"] <= 0.0:
			chip.modulate.a = LOCKED_ALPHA
		tiers.add_child(chip)
	if locked:
		name_label.modulate.a = 0.55
	return panel

## Implicits this type can gain from a Shard of Tharsis (ImplicitPool).
func _add_implicit_pool(base: Item) -> void:
	var pool := ImplicitPool.pool_for_type(base.get_item_type())
	_list.add_child(_text("Corruption implicits", 17, CorruptionWiki.CORRUPT_COLOR))
	if pool.is_empty():
		_list.add_child(_text("None - no base of this type has an implicit to draw from.", 13, MUTED))
		return
	for affix in pool:
		_list.add_child(_text(StatKeys.implicit_text(affix), 14, CorruptionWiki.CORRUPT_COLOR.lightened(0.3)))

func _show_index() -> void:
	var query := _search.text.strip_edges().to_lower()
	rows = WikiCatalog.modifier_index().filter(func(r): return query == "" or String(r["text"]).to_lower().contains(query))
	_summary.text = "%d modifiers%s. Icons are the base types each one rolls on; hover for the name." % [rows.size(), " matching \"%s\"" % query if query != "" else ""]
	for row in rows.slice(0, 120):
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", AetherStyle.glass_box(Color(AetherStyle.GOLD, 0.25), Color(0.05, 0.05, 0.07, 0.8), 1, 8.0))
		var box := VBoxContainer.new()
		panel.add_child(box)
		var head := HBoxContainer.new()
		box.add_child(head)
		var name_label := _text(row["text"], 15, PREFIX_COLOR if row["prefix"] else SUFFIX_COLOR)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(name_label)
		head.add_child(_text("%s  ·  Tier 1 from item level %d" % ["Prefix" if row["prefix"] else "Suffix", row["t1_level"]], 13, MUTED))
		var icons := HFlowContainer.new()
		box.add_child(icons)
		for t in row["types"]:
			icons.add_child(_type_icon(t))
		_list.add_child(panel)

## A small icon of a base type, named on hover.
static func _type_icon(t: Dictionary) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	holder.tooltip_text = t["name"]
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	var icon := ItemIcon.fill(holder)
	icon.content = t["base"]
	return holder

static func _percent(p: float) -> String:
	var pct := p * 100.0
	return "%.1f%%" % pct if pct >= 1.0 else "%.2f%%" % pct

static func _number(v: float) -> String:
	return str(int(round(v))) if is_equal_approx(v, round(v)) else "%.1f" % v

static func _text(text: String, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label
