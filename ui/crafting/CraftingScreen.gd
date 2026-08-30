extends CanvasLayer
class_name CraftingScreen
## Section 20 - Crafting System UI. Opens via the `open_crafting` hotkey
## (K), same pattern as Inventory/Abilities/Character/Map (see
## PauseMenu.gd). Built entirely in code (PlayerHUD's style) rather than
## a hand-laid-out .tscn, given how much of this is dynamic (owned Brand
## counts, an item's own affix list, up to 8 Cube slots).
##
## Three columns: owned target items (GameState.owned_loot only - NEVER
## the hand-authored "one of each base" list InventoryScreen shows, since
## those are shared load()-cached Resources and crafting one in place
## would permanently corrupt that base .tres for the rest of the session,
## including future ItemRoller.roll() picks from it), the Cube itself
## (selected item + its affix list + up to 8 placed Brands + Craft), and
## owned Brands/crafting consumables (Infusion/Shrivening Stone, Shard of
## Tharsis - these three act directly on the selected item, bypassing the
## Cube entirely, per the doc's "Three distinct crafting methods").
##
## Clicking an affix row selects it as the target for Cleave (lock) or
## Excise (remove) - the only two Brand functions that need the player to
## choose which modifier. Selecting one is harmless for every other
## Brand combination; CraftingSystem.gd ignores it unless it's actually
## needed.
##
## Clicking a Brand (still adds it to the Cube, unchanged) also shows a
## preview of what it can actually do to the selected item - for a
## Damage/Defensive/Umbrella Brand, the real list of modifiers
## ItemRoller._pool_for_brand_tag() would draw from (the exact same pool
## _add_weighted_affix() rolls against, so the preview can't drift from
## what a craft actually produces); for a Utility/Special Brand, its
## function description instead (no "pool" to preview - it does a fixed
## action, not a weighted roll).

const CUBE_CAPACITY := CraftingSystem.CUBE_CAPACITY
const PANEL_BG := Color(0.1, 0.1, 0.12, 0.97)
const COLUMN_BG := Color(0.15, 0.15, 0.18, 0.9)
const SLOT_EMPTY_COLOR := Color(0.22, 0.22, 0.25)
const SLOT_FILLED_COLOR := Color(0.35, 0.3, 0.15)
const AFFIX_SELECTED_COLOR := Color(0.45, 0.35, 0.1)

var _is_open: bool = false
var _target_item: Item = null
var _cube_brands: Array[Brand] = []
var _selected_affix_index: int = -1

var _root: Control
var _items_list: VBoxContainer
var _target_label: Label
var _affix_list: VBoxContainer
var _brand_preview_label: Label
var _cube_row: HBoxContainer
var _craft_button: Button
var _empower_button: Button
var _status_label: Label
var _brands_list: VBoxContainer
var _consumables_list: VBoxContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("crafting_screen")
	add_to_group("blocking_menu")
	_build_ui()
	visible = false

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_target_item = null
	_cube_brands = []
	_selected_affix_index = -1
	_status_label.text = ""
	_brand_preview_label.text = ""
	_refresh()

func close() -> void:
	_is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

## ---- UI construction ---------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -520
	panel.offset_right = 520
	panel.offset_top = -320
	panel.offset_bottom = 320
	var panel_box := StyleBoxFlat.new()
	panel_box.bg_color = PANEL_BG
	panel_box.set_corner_radius_all(6)
	panel_box.content_margin_left = 16
	panel_box.content_margin_right = 16
	panel_box.content_margin_top = 16
	panel_box.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", panel_box)
	_root.add_child(panel)

	var outer := VBoxContainer.new()
	panel.add_child(outer)

	var title := Label.new()
	title.text = "The Cube"
	title.add_theme_font_size_override("font_size", 20)
	outer.add_child(title)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.custom_minimum_size = Vector2(0, 520)
	outer.add_child(hbox)

	hbox.add_child(_build_column("Owned Items", func(col): _items_list = _build_scroll_list(col)))
	hbox.add_child(_build_cube_column())
	hbox.add_child(_build_column("Brands & Consumables", func(col):
		_brands_list = _build_scroll_list(col)
		var sep := HSeparator.new()
		col.add_child(sep)
		var consumables_label := Label.new()
		consumables_label.text = "Consumables"
		col.add_child(consumables_label)
		_consumables_list = _build_scroll_list(col)
	))

	var close_button := Button.new()
	close_button.text = "Close (Esc)"
	close_button.pressed.connect(close)
	outer.add_child(close_button)

func _build_column(header: String, populate: Callable) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := StyleBoxFlat.new()
	box.bg_color = COLUMN_BG
	box.set_corner_radius_all(4)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", box)

	var col := VBoxContainer.new()
	panel.add_child(col)
	var label := Label.new()
	label.text = header
	label.add_theme_font_size_override("font_size", 15)
	col.add_child(label)
	populate.call(col)
	return panel

func _build_scroll_list(parent: VBoxContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list

func _build_cube_column() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := StyleBoxFlat.new()
	box.bg_color = COLUMN_BG
	box.set_corner_radius_all(4)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", box)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	_target_label = Label.new()
	_target_label.text = "Select an item"
	_target_label.add_theme_font_size_override("font_size", 15)
	col.add_child(_target_label)

	var affix_header := Label.new()
	affix_header.text = "Modifiers (click to target Cleave/Excise)"
	col.add_child(affix_header)
	_affix_list = VBoxContainer.new()
	col.add_child(_affix_list)

	var preview_header := Label.new()
	preview_header.text = "Brand preview (click a Brand below)"
	col.add_child(preview_header)
	_brand_preview_label = Label.new()
	_brand_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_brand_preview_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.75))
	col.add_child(_brand_preview_label)

	var cube_header := Label.new()
	cube_header.text = "Cube slots (click a Brand to place, a slot to remove)"
	col.add_child(cube_header)
	_cube_row = HBoxContainer.new()
	_cube_row.add_theme_constant_override("separation", 4)
	col.add_child(_cube_row)

	_craft_button = Button.new()
	_craft_button.text = "Craft"
	_craft_button.pressed.connect(_on_craft_pressed)
	col.add_child(_craft_button)

	## Figments don't take Brands - see CraftingSystem.empower_figment()'s
	## own comment for why the generic Cube path doesn't apply to them.
	_empower_button = Button.new()
	_empower_button.text = "Empower Figment (%d Gold)" % CraftingSystem.EMPOWER_FIGMENT_GOLD_COST
	_empower_button.visible = false
	_empower_button.pressed.connect(_on_empower_pressed)
	col.add_child(_empower_button)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(_status_label)

	return panel

## ---- Refresh --------------------------------------------------------

func _refresh() -> void:
	_refresh_items_list()
	_refresh_target_panel()
	_refresh_brands_list()

func _refresh_items_list() -> void:
	for child in _items_list.get_children():
		child.queue_free()
	for item in GameState.owned_loot:
		if item is Brand or _is_crafting_consumable(item):
			continue
		var button := _make_row_button(item.display_name, _item_color(item))
		button.pressed.connect(_on_item_selected.bind(item))
		_items_list.add_child(button)

func _refresh_target_panel() -> void:
	for child in _affix_list.get_children():
		child.queue_free()
	for child in _cube_row.get_children():
		child.queue_free()

	if _target_item == null:
		_target_label.text = "Select an item"
		_craft_button.disabled = true
		_empower_button.visible = false
		return

	_target_label.text = "%s%s" % [_target_item.display_name, " (uncraftable)" if not _target_item.is_craftable else ""]

	if _target_item is FigmentItem:
		_craft_button.disabled = true
		_empower_button.visible = true
		var figment := _target_item as FigmentItem
		var info := Label.new()
		info.text = "Tier %d Figment - Empowering raises its tier and strengthens its rolls." % figment.tier
		info.autowrap_mode = TextServer.AUTOWRAP_WORD
		_affix_list.add_child(info)
		for affix in figment.affixes:
			_affix_list.add_child(_make_row_button(affix.description, SLOT_EMPTY_COLOR))
		return
	_empower_button.visible = false
	_craft_button.disabled = not _target_item.is_craftable or _cube_brands.is_empty()

	for i in range(_target_item.affixes.size()):
		var affix: ItemAffix = _target_item.affixes[i]
		var button := _make_row_button(affix.description, AFFIX_SELECTED_COLOR if i == _selected_affix_index else SLOT_EMPTY_COLOR)
		button.pressed.connect(_on_affix_clicked.bind(i))
		_affix_list.add_child(button)
	if _target_item.sealed_tags.size() > 0:
		var sealed_label := Label.new()
		sealed_label.text = "Sealed tags: %s" % ", ".join(_target_item.sealed_tags)
		_affix_list.add_child(sealed_label)

	for i in range(CUBE_CAPACITY):
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(36, 36)
		slot.clip_text = true
		if i < _cube_brands.size():
			var brand := _cube_brands[i]
			slot.text = brand.display_name.left(3)
			slot.tooltip_text = brand.display_name
			_apply_button_color(slot, SLOT_FILLED_COLOR)
			slot.pressed.connect(_on_cube_slot_clicked.bind(i))
		else:
			slot.text = ""
			_apply_button_color(slot, SLOT_EMPTY_COLOR)
			slot.disabled = true
		_cube_row.add_child(slot)

func _refresh_brands_list() -> void:
	for child in _brands_list.get_children():
		child.queue_free()
	for child in _consumables_list.get_children():
		child.queue_free()

	var brand_counts: Dictionary = {}  # item_id -> {brand, count}
	for item in GameState.owned_loot:
		if item is Brand:
			var entry: Dictionary = brand_counts.get(item.item_id, {"brand": item, "count": 0})
			entry["count"] += 1
			brand_counts[item.item_id] = entry
	for item_id in brand_counts:
		var entry: Dictionary = brand_counts[item_id]
		var brand: Brand = entry["brand"]
		var button := _make_row_button("%s x%d" % [brand.display_name, entry["count"]], SLOT_EMPTY_COLOR)
		button.tooltip_text = brand.flavor_text
		button.pressed.connect(_on_brand_clicked.bind(brand))
		_brands_list.add_child(button)

	var consumable_counts: Dictionary = {}  # item_id -> {item, count}
	for item in GameState.owned_loot:
		if _is_crafting_consumable(item):
			var entry: Dictionary = consumable_counts.get(item.item_id, {"item": item, "count": 0})
			entry["count"] += 1
			consumable_counts[item.item_id] = entry
	for item_id in consumable_counts:
		var entry: Dictionary = consumable_counts[item_id]
		var item: Item = entry["item"]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s x%d" % [item.display_name, entry["count"]]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var action := Button.new()
		action.text = _consumable_action_label(item.item_id)
		action.pressed.connect(_on_consumable_pressed.bind(item))
		row.add_child(action)
		_consumables_list.add_child(row)

func _consumable_action_label(item_id: String) -> String:
	match item_id:
		"infusion_stone": return "Infuse"
		"shrivening_stone": return "Shrive"
		"shard_of_tharsis": return "Corrupt"
	return "Use"

func _is_crafting_consumable(item: Item) -> bool:
	return Constants.CRAFTING_CONSUMABLE_IDS.has(item.item_id)

## ---- Actions --------------------------------------------------------

func _on_item_selected(item: Item) -> void:
	_target_item = item
	_cube_brands = []
	_selected_affix_index = -1
	_status_label.text = ""
	_brand_preview_label.text = ""
	_refresh_target_panel()

func _on_affix_clicked(index: int) -> void:
	_selected_affix_index = -1 if _selected_affix_index == index else index
	_refresh_target_panel()

func _on_brand_clicked(brand: Brand) -> void:
	_show_brand_preview(brand)
	if _target_item == null:
		_status_label.text = "Select an item first."
		return
	if _cube_brands.size() >= CUBE_CAPACITY:
		_status_label.text = "The Cube is full."
		return
	var same_count := 0
	for b in _cube_brands:
		if b.item_id == brand.item_id:
			same_count += 1
	if same_count >= CraftingSystem.MAX_SAME_BRAND:
		_status_label.text = "Maximum %d of the same Brand per craft." % CraftingSystem.MAX_SAME_BRAND
		return
	_cube_brands.append(brand)
	_refresh_target_panel()

## Category Brands (Damage/Defensive/Umbrella) roll from a real, fixed
## pool - show exactly what's in it for the currently selected item, so
## the preview can never promise something a craft wouldn't actually
## produce. Utility/Special Brands (Render, Cleave, Binder, ...) don't
## roll from a pool at all - show what they DO instead.
func _show_brand_preview(brand: Brand) -> void:
	if _target_item == null:
		_brand_preview_label.text = "%s - select an item to preview its rolls." % brand.display_name
		return
	if brand.brand_function in [Brand.BrandFunction.DAMAGE_TYPE, Brand.BrandFunction.DEFENSIVE_TYPE, Brand.BrandFunction.UMBRELLA]:
		var pool := ItemRoller._pool_for_brand_tag(_target_item, brand.category_tag)
		if pool.is_empty():
			_brand_preview_label.text = "%s: no modifier exists for this category on this item type." % brand.display_name
			return
		var lines := PackedStringArray(["%s can roll one of:" % brand.display_name])
		for entry in pool:
			lines.append("- %s" % _format_pool_entry_preview(entry))
		_brand_preview_label.text = "\n".join(lines)
	else:
		_brand_preview_label.text = "%s: %s" % [brand.display_name, brand.flavor_text]

## Pool entries carry a "%d"/"%d%%" printf-style template (e.g. "+%d
## Vitality") meant for a real rolled value - substitute a placeholder
## since this is a preview of what's POSSIBLE, not an actual roll.
func _format_pool_entry_preview(entry: Dictionary) -> String:
	return (entry["desc"] as String).replace("%d", "X").replace("%%", "%")

func _on_cube_slot_clicked(index: int) -> void:
	if index < 0 or index >= _cube_brands.size():
		return
	_cube_brands.remove_at(index)
	_refresh_target_panel()

func _on_craft_pressed() -> void:
	if _target_item == null or _cube_brands.is_empty():
		return
	var power_level: int = GameState.active_map.tier if GameState.active_map else GameState.player_level
	var result := CraftingSystem.craft_cube(_target_item, _cube_brands, power_level, _selected_affix_index)
	_status_label.text = result["message"]
	if result["success"]:
		for brand in result["consumed"]:
			GameState.owned_loot.erase(brand)
		if result["destroyed"]:
			GameState.owned_loot.erase(_target_item)
			_target_item = null
		_cube_brands = []
		_selected_affix_index = -1
	_refresh()

func _on_empower_pressed() -> void:
	if not (_target_item is FigmentItem):
		return
	if GameState.gold < CraftingSystem.EMPOWER_FIGMENT_GOLD_COST:
		_status_label.text = "Need %d Gold." % CraftingSystem.EMPOWER_FIGMENT_GOLD_COST
		return
	var result := CraftingSystem.empower_figment(_target_item)
	if result["success"]:
		GameState.gold -= CraftingSystem.EMPOWER_FIGMENT_GOLD_COST
	_status_label.text = result["message"]
	_refresh()

func _on_consumable_pressed(consumable: Item) -> void:
	if _target_item == null:
		_status_label.text = "Select an item first."
		return
	var result: Dictionary
	match consumable.item_id:
		"infusion_stone":
			if not (_target_item is Weapon):
				_status_label.text = "Infusion Stone only works on weapons."
				return
			result = CraftingSystem.infuse(_target_item)
		"shrivening_stone":
			if not (_target_item is Weapon):
				_status_label.text = "Shrivening Stone only works on weapons."
				return
			result = CraftingSystem.shrive(_target_item)
		"shard_of_tharsis":
			var power_level: int = GameState.active_map.tier if GameState.active_map else GameState.player_level
			result = CraftingSystem.corrupt(_target_item, power_level)
		_:
			return
	_status_label.text = result["message"]
	if result["success"]:
		GameState.owned_loot.erase(consumable)
	_refresh()

## ---- Shared row/button styling --------------------------------------

func _make_row_button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.clip_text = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_apply_button_color(button, color)
	return button

func _apply_button_color(button: Button, color: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(4)
	button.add_theme_stylebox_override("normal", box)
	button.add_theme_stylebox_override("hover", box)
	button.add_theme_stylebox_override("pressed", box)
	button.add_theme_stylebox_override("disabled", box)
	var text_color := Constants.get_contrasting_text_color(color)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_pressed_color", text_color)
	button.add_theme_color_override("font_disabled_color", text_color)

func _item_color(item: Item) -> Color:
	if item is Weapon:
		var weapon := item as Weapon
		var dtype: int = weapon.infused_damage_type if weapon.infused_damage_type != -1 else weapon.native_damage_type
		return Constants.DAMAGE_TYPE_COLOR.get(dtype, Color.WHITE)
	return Constants.ITEM_RARITY_COLOR.get(item.rarity, Color.WHITE)
