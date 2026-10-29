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
const IMPLICIT_COLOR := Color(0.62, 0.8, 0.95)

enum Filter { ALL, UNIQUE, MYTHIC, SLATE, LENS }

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
## Unique Slate id -> its odds Label.
var _slate_odds: Dictionary = {}

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
	for f in ["All", "Uniques", "Mythics", "Unique Slates", "Unique Lenses"]:
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
	_slate_odds.clear()
	var defs := UniqueCatalog.DEFS.duplicate()
	# Mythics first, then Uniques; catalog order within each.
	defs.sort_custom(func(a, b): return a["rarity"] > b["rarity"])
	for def in defs:
		if filter == Filter.SLATE or filter == Filter.LENS:
			break
		if filter == Filter.UNIQUE and def["rarity"] != Constants.ItemRarity.UNIQUE:
			continue
		if filter == Filter.MYTHIC and def["rarity"] != Constants.ItemRarity.MYTHIC:
			continue
		var entry := _entry(def)
		_entries[def["id"]] = entry
		_list.add_child(entry)
	if filter == Filter.ALL or filter == Filter.SLATE:
		for def in UniqueCatalog.SLATE_DEFS:
			var entry := _slate_entry(def)
			_entries[def["id"]] = entry
			_list.add_child(entry)
	if filter == Filter.ALL or filter == Filter.LENS:
		for lens in unique_lenses():
			var entry := _lens_entry(lens)
			_entries[lens.unique_id] = entry
			_list.add_child(entry)
	_update_odds()

## Every unique Lens, built from where it drops (they aren't in UniqueCatalog).
static func unique_lenses() -> Array[Lens]:
	var lenses: Array[Lens] = [Pinnacle.make_maw_lens(1) as Lens]
	return lenses

## Where you already hold this unique: the Unique tab, worn (either weapon
## set), the inventory or another stash tab. "" if nowhere.
static func owned_where(id: String) -> String:
	if GameState.stash.uniques.has(id):
		return "In your Unique tab"
	var tree := Engine.get_main_loop() as SceneTree
	var player: Player = tree.get_first_node_in_group("player") as Player if tree else null
	if player and player.equipment:
		var worn: Array = player.equipment.get_all_equipped_items()
		worn.append_array(player.equipment.primary_weapons)
		worn.append_array(player.equipment.offhands)
		for item in worn:
			if item and item.unique_id == id:
				return "Equipped"
	if _grid_has_unique(GameState.inventory, id):
		return "In your inventory"
	for tab in GameState.stash.tabs:
		if _grid_has_unique(tab, id):
			return "In your stash"
	if GameState.fate_board:
		for lens in GameState.fate_board.star_lenses.values():
			if lens.unique_id == id:
				return "On your Fate Board"
	return ""

static func _grid_has_unique(grid: GridInventory, id: String) -> bool:
	for entry in grid.get_entries():
		if entry.content is Item and (entry.content as Item).unique_id == id:
			return true
	return false

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
	var owned := owned_where(def["id"])
	if owned != "":
		name_row.add_child(_text("   ✓ " + owned, 13, COLLECTED_COLOR))
	var rarity_name := "Mythic" if def["rarity"] == Constants.ItemRarity.MYTHIC else "Unique"
	var base := "Any gear" if def["base_type"] == "any" else String(def["base_type"]).capitalize()
	var base_item: Item = load(def["base_item"]) as Item if def.has("base_item") else null
	if base_item:
		base = base_item.display_name
	left.add_child(_text("%s  ·  %s" % [rarity_name, base], 13, ODDS_LABEL_COLOR))
	# The base's implicit comes with the unique.
	if base_item and not def.get("no_implicits", false):
		var implicit := WikiCatalog.base_implicit_text(base_item)
		if implicit != "":
			left.add_child(_text(implicit, 14, IMPLICIT_COLOR))
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
	for id in _slate_odds:
		_slate_odds[id].text = "Per Slate drop:  %s" % UniqueOdds.format_chance(slate_chance(id, mults["rarity"]))
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
		labels["pinnacle"].visible = not world
		if not world:
			labels["pinnacle"].text = "Per kill:  %s" % UniqueOdds.format_chance(UniqueOdds.per_pinnacle_reward(def, def["boss"]))

func _text(text: String, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label

## Chance a Slate drop is this Unique Slate: the Unique Slate chance (times
## Item Rarity, capped), split by weight.
static func slate_chance(id: String, rarity_mult: float) -> float:
	var total := 0.0
	var weight := 0.0
	for def in UniqueCatalog.SLATE_DEFS:
		total += float(def["weight"])
		if def["id"] == id:
			weight = float(def["weight"])
	if total <= 0.0:
		return 0.0
	return minf(UniqueCatalog.UNIQUE_SLATE_CHANCE * rarity_mult, UniqueCatalog.UNIQUE_SLATE_CHANCE_CAP) * weight / total

func _slate_entry(def: Dictionary) -> PanelContainer:
	var color: Color = Constants.ITEM_RARITY_COLOR.get(Constants.ItemRarity.UNIQUE, Color.WHITE)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", AetherStyle.glass_box(Color(color, 0.45), Color(0.05, 0.05, 0.07, 0.85), 1, 12.0))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	panel.add_child(columns)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 3)
	columns.add_child(left)
	var name_label := _text(def["name"], 20, color)
	name_label.add_theme_font_override("font", AetherStyle.title())
	left.add_child(name_label)
	var shape: Array = def["shape"]
	var tag_name: String = Constants.DAMAGE_TYPE_NAME.get(def["tag"], "Any")
	left.add_child(_text("Unique Slate  ·  %s  ·  %d cells, %d Aether" % [tag_name, shape.size(), shape.size() + SlateRoller.RARITY_AETHER_BONUS[Constants.SlateRarity.UNIQUE]], 13, ODDS_LABEL_COLOR))
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
	right.add_theme_constant_override("separation", 6)
	columns.add_child(right)
	var source := _text("Any Slate drop", 15, AetherStyle.GOLD)
	source.add_theme_stylebox_override("normal", AetherStyle.glass_box(Color(AetherStyle.GOLD, 0.5), Color(AetherStyle.GOLD, 0.08), 1, 4.0))
	source.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	right.add_child(source)
	_slate_odds[def["id"]] = _text("", 13, AetherStyle.TEXT)
	right.add_child(_slate_odds[def["id"]])
	right.add_child(_shape_grid(shape, color))
	return panel

func _lens_entry(lens: Lens) -> PanelContainer:
	var color: Color = Constants.ITEM_RARITY_COLOR.get(lens.rarity, Color.WHITE)
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
	var name_label := _text(lens.display_name, 20, color)
	name_label.add_theme_font_override("font", AetherStyle.title())
	name_row.add_child(name_label)
	var owned := owned_where(lens.unique_id)
	if owned != "":
		name_row.add_child(_text("   ✓ " + owned, 13, COLLECTED_COLOR))
	left.add_child(_text("Unique Lens  ·  Radius %d  ·  Corrupted" % lens.radius, 13, ODDS_LABEL_COLOR))
	# The rolled gift varies, so the wiki lists every one it can roll.
	for text in [String(lens.radius_def()["text"]), FateStars.lens_star_text(lens)]:
		var line := _text(text, 14, MOD_COLOR)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left.add_child(line)
	if lens.flavor_text != "":
		var flavor := _text(lens.flavor_text, 13, Color(0.75, 0.65, 0.45))
		flavor.add_theme_font_override("font", AetherStyle.serif_italic())
		flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left.add_child(flavor)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(340, 0)
	right.add_theme_constant_override("separation", 3)
	columns.add_child(right)
	var source := _text("Pinnacle: %s" % Pinnacle.BOSSES["herald_of_the_maw"]["name"], 15, AetherStyle.GOLD)
	source.add_theme_stylebox_override("normal", AetherStyle.glass_box(Color(AetherStyle.GOLD, 0.5), Color(AetherStyle.GOLD, 0.08), 1, 4.0))
	source.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	right.add_child(source)
	var pylons := MawArena.PYLONS.size()
	var odds := _text("Per kill:  %s, up to %s with all %d pylons standing" % [
		UniqueOdds.format_chance(Pinnacle.maw_lens_chance(0)), UniqueOdds.format_chance(Pinnacle.maw_lens_chance(pylons)), pylons], 13, AetherStyle.TEXT)
	odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(odds)
	right.add_child(_text("Item Rarity doesn't change these odds.", 12, ODDS_LABEL_COLOR))
	return panel

## The Slate's footprint as a small grid of cells.
func _shape_grid(shape: Array, color: Color) -> GridContainer:
	var max_x := 0
	var max_y := 0
	for cell in shape:
		max_x = maxi(max_x, cell.x)
		max_y = maxi(max_y, cell.y)
	var grid := GridContainer.new()
	grid.columns = max_x + 1
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	for y in max_y + 1:
		for x in max_x + 1:
			var rect := ColorRect.new()
			rect.custom_minimum_size = Vector2(14, 14)
			rect.color = Color(color, 0.8) if shape.has(Vector2i(x, y)) else Color(0, 0, 0, 0)
			grid.add_child(rect)
	return grid
