extends VBoxContainer
class_name UniqueWiki
## Main menu Wiki: every Unique and Mythic in UniqueCatalog, where it comes
## from and how likely it is to drop (UniqueOdds). The odds follow a Magic
## Find slider that starts at the character's own Magic Find; their gear's
## flat Item Quantity / Item Rarity are added on top.

const WIDTH := 980.0
const LIST_HEIGHT := 560.0
const MAGIC_FIND_MAX := 500.0
const MOD_COLOR := Color(0.95, 0.68, 0.38)
const ODDS_LABEL_COLOR := Color(0.66, 0.62, 0.55)
const COLLECTED_COLOR := Color(0.55, 0.85, 0.55)

enum Filter { ALL, UNIQUE, MYTHIC }

var magic_find: float = 0.0
var filter: int = Filter.ALL

var _gear: Dictionary = {}
var _slider: HSlider
var _mf_label: Label
var _summary: Label
var _list: VBoxContainer
## UniqueCatalog id -> {"gear": Label, "kill": Label, "boss": Label, "pinnacle": Label}
var _odds_labels: Dictionary = {}
var _entries: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	custom_minimum_size = Vector2(WIDTH, 0)
	_build()
	refresh_character()

## Re-reads the character's gear (the save, on the main menu) and resets the
## slider to their Magic Find.
func refresh_character() -> void:
	_gear = UniqueOdds.character_bonuses()
	set_magic_find(_gear.get(Loot.MAGIC_FIND_KEY, 0.0))
	_rebuild_list()

func set_magic_find(value: float) -> void:
	magic_find = clampf(value, 0.0, MAGIC_FIND_MAX)
	if _slider and not is_equal_approx(_slider.value, magic_find):
		_slider.set_value_no_signal(magic_find)
	_update_odds()

## Item Quantity / Item Rarity multipliers the odds use: the gear's flat
## bonuses plus the slider's Magic Find.
func multipliers() -> Dictionary:
	var bonuses := _gear.duplicate()
	bonuses[Loot.MAGIC_FIND_KEY] = magic_find
	return {
		"quantity": maxf(1.0 + Loot.quantity_percent(bonuses) / 100.0, 0.0),
		"rarity": maxf(1.0 + Loot.rarity_percent(bonuses) / 100.0, 0.0),
	}

func _build() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	row.add_child(_text("Magic Find", 16, AetherStyle.TEXT))
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = MAGIC_FIND_MAX
	_slider.step = 5.0
	_slider.custom_minimum_size = Vector2(320, 24)
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.value_changed.connect(set_magic_find)
	row.add_child(_slider)
	_mf_label = _text("0", 16, AetherStyle.GOLD)
	_mf_label.custom_minimum_size = Vector2(48, 0)
	row.add_child(_mf_label)
	var mine := Button.new()
	mine.text = "Use my character's"
	mine.pressed.connect(refresh_character)
	row.add_child(mine)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var filter_box := OptionButton.new()
	for f in ["All", "Uniques", "Mythics"]:
		filter_box.add_item(f)
	filter_box.item_selected.connect(func(i: int):
		filter = i
		_rebuild_list())
	row.add_child(filter_box)

	_summary = _text("", 13, ODDS_LABEL_COLOR)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

func _rebuild_list() -> void:
	for child in _list.get_children():
		child.queue_free()
	_odds_labels.clear()
	_entries.clear()
	var defs := UniqueCatalog.DEFS.duplicate()
	# Mythics first, then Uniques; catalog order within each.
	defs.sort_custom(func(a, b): return a["rarity"] > b["rarity"])
	for def in defs:
		if filter == Filter.UNIQUE and def["rarity"] != Constants.ItemRarity.UNIQUE:
			continue
		if filter == Filter.MYTHIC and def["rarity"] != Constants.ItemRarity.MYTHIC:
			continue
		var entry := _entry(def)
		_entries[def["id"]] = entry
		_list.add_child(entry)
	_update_odds()

## Ids currently listed, in order.
func listed_ids() -> Array:
	return _entries.keys()

func _entry(def: Dictionary) -> PanelContainer:
	var color: Color = Constants.ITEM_RARITY_COLOR.get(def["rarity"], Color.WHITE)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", AetherStyle.glass_box(Color(color, 0.45), Color(0.05, 0.05, 0.07, 0.85), 1, 12.0))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	panel.add_child(columns)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 3)
	columns.add_child(left)
	var name_row := HBoxContainer.new()
	left.add_child(name_row)
	var name_label := _text(def["name"], 20, color)
	name_label.add_theme_font_override("font", AetherStyle.title())
	name_row.add_child(name_label)
	if GameState.stash.uniques.has(def["id"]):
		name_row.add_child(_text("   ✓ In your Unique tab", 13, COLLECTED_COLOR))
	var rarity_name := "Mythic" if def["rarity"] == Constants.ItemRarity.MYTHIC else "Unique"
	var base := "Any gear" if def["base_type"] == "any" else String(def["base_type"]).capitalize()
	left.add_child(_text("%s  ·  %s" % [rarity_name, base], 13, ODDS_LABEL_COLOR))
	for mod in def["mods"]:
		var line := _text(UniqueRoller.range_text(mod), 14, MOD_COLOR)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left.add_child(line)
	if def.get("flavor", "") != "":
		var flavor := _text(def["flavor"], 13, Color(0.75, 0.65, 0.45))
		flavor.add_theme_font_override("font", AetherStyle.serif_italic())
		flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left.add_child(flavor)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(340, 0)
	right.add_theme_constant_override("separation", 3)
	columns.add_child(right)
	var source := _text(UniqueOdds.source_text(def), 15, AetherStyle.GOLD)
	source.add_theme_stylebox_override("normal", AetherStyle.glass_box(Color(AetherStyle.GOLD, 0.5), Color(AetherStyle.GOLD, 0.08), 1, 4.0))
	source.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	right.add_child(source)
	var labels := {}
	for key in ["gear", "kill", "boss", "pinnacle"]:
		labels[key] = _text("", 13, AetherStyle.TEXT)
		right.add_child(labels[key])
	_odds_labels[def["id"]] = labels
	return panel

func _update_odds() -> void:
	if _mf_label == null:
		return
	var mults := multipliers()
	_mf_label.text = "%d" % roundi(magic_find)
	_summary.text = "Item Rarity +%.0f%%  ·  Item Quantity +%.0f%%   (%d Magic Find, plus Item Rarity +%.0f%% / Item Quantity +%.0f%% from your gear). Figment and monster bonuses add on top of these." % [
		(mults["rarity"] - 1.0) * 100.0, (mults["quantity"] - 1.0) * 100.0, roundi(magic_find),
		_gear.get(Loot.RARITY_KEY, 0.0), _gear.get(Loot.QUANTITY_KEY, 0.0)]
	for id in _odds_labels:
		var def := UniqueCatalog.get_def(id)
		var labels: Dictionary = _odds_labels[id]
		if def.get("corrupted_only", false):
			labels["gear"].text = "Never drops. A Shard of Tharsis can turn an item into it."
			for key in ["kill", "boss", "pinnacle"]:
				labels[key].visible = false
			continue
		var world := UniqueOdds.is_world_drop(def)
		labels["gear"].visible = world
		labels["kill"].visible = world
		labels["boss"].visible = world
		if world:
			labels["gear"].text = "Per gear drop:  %s" % UniqueOdds.format_chance(UniqueOdds.per_gear_drop(def, mults["rarity"]))
			labels["kill"].text = "Per monster kill:  %s" % UniqueOdds.format_chance(UniqueOdds.per_kill(def, Constants.EnemyRank.NORMAL, mults["quantity"], mults["rarity"]))
			labels["boss"].text = "Per boss kill:  %s" % UniqueOdds.format_chance(UniqueOdds.per_kill(def, Constants.EnemyRank.BOSS, mults["quantity"], mults["rarity"]))
		var boss_id: String = def.get("boss", Pinnacle.BOSSES.keys()[0])
		labels["pinnacle"].text = "%s reward:  %s" % ["Pinnacle boss" if world else "Guaranteed", UniqueOdds.format_chance(UniqueOdds.per_pinnacle_reward(def, boss_id))]

func _text(text: String, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label
