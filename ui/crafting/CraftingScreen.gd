extends CanvasLayer
class_name CraftingScreen
## Orb crafting UI (hotkey K). Built in code. Three columns:
## - targets: carried items and Slates plus equipped gear (never the shared
##   load()-cached hand-authored bases - crafting one would change it for
##   the whole session)
## - the selected target: rarity, tolerance, quality, sockets, Edict and
##   modifiers, plus the selected Orb's preview (CraftingResolver.preview())
## - carried currency: Orbs (select to preview, Use to apply), Brands
##   (toggle active for the next Orb), Edicts (apply to the target), and the
##   Infusion/Shrivening Stone and Shard of Tharsis.

const PANEL_BG := Color(0.1, 0.1, 0.12, 0.97)
const COLUMN_BG := Color(0.15, 0.15, 0.18, 0.9)
const ROW_COLOR := Color(0.22, 0.22, 0.25)
const SELECTED_COLOR := Color(0.45, 0.35, 0.1)
const ACTIVE_BRAND_COLOR := Color(0.25, 0.45, 0.3)
const PREVIEW_LINES := 8

var _is_open: bool = false
var _target: Resource = null
var _selected_orb: StringName = &""
var _resolver: CraftingResolver
var _active_brands: ActiveBrands

var _root: Control
var _items_list: VBoxContainer
var _target_label: Label
var _target_info: Label
var _affix_list: VBoxContainer
var _preview_label: Label
var _empower_button: Button
var _status_label: Label
var _orbs_list: VBoxContainer
var _brands_list: VBoxContainer
var _edicts_list: VBoxContainer
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
	_resolver = CraftingResolver.create_default()
	_resolver.currency = GameState.inventory
	if _active_brands == null or _active_brands.carried != GameState.inventory:
		_active_brands = ActiveBrands.new(GameState.inventory)
	_target = null
	_selected_orb = &""
	_status_label.text = ""
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
	panel.offset_left = -560
	panel.offset_right = 560
	panel.offset_top = -340
	panel.offset_bottom = 340
	panel.add_theme_stylebox_override("panel", _box(PANEL_BG, 16))
	_root.add_child(panel)

	var outer := VBoxContainer.new()
	panel.add_child(outer)
	var title := Label.new()
	title.text = "Crafting"
	title.add_theme_font_size_override("font_size", 20)
	outer.add_child(title)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.custom_minimum_size = Vector2(0, 560)
	outer.add_child(hbox)

	var items_col := _column(hbox, "Items", 300)
	_items_list = _scroll_list(items_col)

	var target_col := _column(hbox, "", 380)
	_target_label = Label.new()
	_target_label.add_theme_font_size_override("font_size", 15)
	target_col.add_child(_target_label)
	_target_info = Label.new()
	_target_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	target_col.add_child(_target_info)
	_affix_list = VBoxContainer.new()
	target_col.add_child(_affix_list)
	target_col.add_child(HSeparator.new())
	_preview_label = Label.new()
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_preview_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.75))
	target_col.add_child(_preview_label)
	_empower_button = Button.new()
	_empower_button.text = "Empower Figment (%d Gold)" % CraftingSystem.EMPOWER_FIGMENT_GOLD_COST
	_empower_button.visible = false
	_empower_button.pressed.connect(_on_empower_pressed)
	target_col.add_child(_empower_button)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	target_col.add_child(_status_label)

	var currency_col := _column(hbox, "Currency", 340)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	currency_col.add_child(scroll)
	var lists := VBoxContainer.new()
	lists.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(lists)
	_orbs_list = _section(lists, "Orbs")
	_brands_list = _section(lists, "Brands (click to activate for the next Orb)")
	_edicts_list = _section(lists, "Edicts")
	_consumables_list = _section(lists, "Stones & Shard")

	var close_button := Button.new()
	close_button.text = "Close (Esc)"
	close_button.pressed.connect(close)
	outer.add_child(close_button)

func _box(color: Color, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(4)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	return box

func _column(parent: Control, header: String, width: int) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _box(COLUMN_BG, 8))
	parent.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	if header != "":
		var label := Label.new()
		label.text = header
		label.add_theme_font_size_override("font_size", 15)
		col.add_child(label)
	return col

func _scroll_list(parent: VBoxContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list

func _section(parent: VBoxContainer, header: String) -> VBoxContainer:
	var label := Label.new()
	label.text = header
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	parent.add_child(label)
	var list := VBoxContainer.new()
	parent.add_child(list)
	return list

## ---- Refresh --------------------------------------------------------

func _refresh() -> void:
	_refresh_items_list()
	_refresh_target_panel()
	_refresh_currency()

func _targets() -> Array:
	var targets := GameState.get_inventory_items().filter(func(c): return c is Slate or c is Item)
	if GameState.player_equipment:
		targets.append_array(GameState.player_equipment.get_all_equipped_items())
	return targets.filter(func(c): return c.resource_path == "")

func _refresh_items_list() -> void:
	for child in _items_list.get_children():
		child.queue_free()
	for target in _targets():
		var button := _row(target.display_name, SELECTED_COLOR if target == _target else _color_of(target), target)
		button.pressed.connect(_on_target_selected.bind(target))
		_items_list.add_child(button)

func _refresh_target_panel() -> void:
	for child in _affix_list.get_children():
		child.queue_free()
	_empower_button.visible = _target is FigmentItem
	_preview_label.text = ""
	if _target == null:
		_target_label.text = "Select an item"
		_target_info.text = ""
		return
	_target_label.text = _target.display_name
	if _target is FigmentItem:
		_target_info.text = "Tier %d Figment - Empowering raises its tier and strengthens its rolls." % _target.tier
		for affix in _target.affixes:
			_affix_list.add_child(_row(affix.description, ROW_COLOR))
		return

	var t := CraftTarget.wrap(_target)
	var lines: Array[String] = [
		"%s   Aether Tolerance %d/%d" % [Constants.ItemRarity.keys()[t.get_rarity()].capitalize(), t.get_tolerance(), _target.tolerance_max],
	]
	if not t.is_slate:
		lines.append("Quality %d/%d   Sockets %d%s" % [t.get_quality(), Constants.QUALITY_CAP, t.get_sockets(), " (opened)" if t.sockets_rolled() else ""])
	if t.get_active_edict() != null:
		lines.append("Edict: %s" % CurrencyText.name_of(t.get_active_edict().id))
	if t.is_corrupted():
		lines.append("Corrupted")
	_target_info.text = "\n".join(lines)
	for affix in t.get_explicits():
		var kind := "P" if affix.is_prefix else "S"
		_affix_list.add_child(_row("[%s]%s %s" % [kind, " [Anchored]" if affix.anchored else "", affix.description], ROW_COLOR))
	if _selected_orb != &"":
		_preview_label.text = _preview_text()

func _preview_text() -> String:
	var p := _resolver.preview(_target, _selected_orb, _active_brands)
	var orb_name := CurrencyText.name_of(_selected_orb)
	if not p.is_valid():
		return "%s: %s" % [orb_name, CurrencyText.error_message(CraftResult.error_name(p.error))]
	var lines: Array[String] = [orb_name + ": " + CurrencyText.description_of(_selected_orb)]
	if not p.applied_brands.is_empty():
		lines.append("Brands used: " + ", ".join(p.applied_brands.map(func(id): return CurrencyText.name_of(id))))
	for r in p.removals.slice(0, PREVIEW_LINES):
		lines.append("Removes %s (%.0f%%)" % [r["affix"].description, r["probability"] * 100.0])
	var outcomes := p.outcomes.duplicate()
	outcomes.sort_custom(func(a, b): return a["probability"] > b["probability"])
	for o in outcomes.slice(0, PREVIEW_LINES):
		var text: String = o["def"].text if o["def"].text != "" else String(o["def"].id)
		lines.append("%s T%d (%.1f%%)" % [text.replace("%d", "X").replace("%%", "%"), o["tier"].tier, o["probability"] * 100.0])
	if outcomes.size() > PREVIEW_LINES:
		lines.append("...and %d more" % (outcomes.size() - PREVIEW_LINES))
	return "\n".join(lines)

func _refresh_currency() -> void:
	for list in [_orbs_list, _brands_list, _edicts_list, _consumables_list]:
		for child in list.get_children():
			child.queue_free()
	for id in Constants.ORB_IDS:
		var count := GameState.inventory.count_of(id)
		if count == 0:
			continue
		var row := HBoxContainer.new()
		var name_button := _row("%s x%d" % [CurrencyText.name_of(id), count], SELECTED_COLOR if id == _selected_orb else ROW_COLOR)
		name_button.tooltip_text = CurrencyText.description_of(id)
		name_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_button.pressed.connect(_on_orb_selected.bind(id))
		row.add_child(name_button)
		var use := Button.new()
		use.text = "Use"
		use.pressed.connect(_on_orb_used.bind(id))
		row.add_child(use)
		_orbs_list.add_child(row)
	for id in _resolver.brand_defs:
		var count := GameState.inventory.count_of(id)
		if count == 0:
			continue
		var active := _active_brands.is_active(id)
		var button := _row("%s x%d%s" % [CurrencyText.name_of(id), count, "  (active)" if active else ""], ACTIVE_BRAND_COLOR if active else ROW_COLOR)
		button.tooltip_text = CurrencyText.description_of(id)
		button.pressed.connect(_on_brand_toggled.bind(id))
		_brands_list.add_child(button)
	for id in _resolver.edict_defs:
		var count := GameState.inventory.count_of(id)
		if count == 0:
			continue
		var row := HBoxContainer.new()
		var label := _row("%s x%d" % [CurrencyText.name_of(id), count], ROW_COLOR)
		label.tooltip_text = CurrencyText.description_of(id)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var apply := Button.new()
		apply.text = "Apply"
		apply.pressed.connect(_on_edict_applied.bind(id))
		row.add_child(apply)
		_edicts_list.add_child(row)

	for id_string in Constants.CRAFTING_CONSUMABLE_IDS:
		var id := StringName(id_string)
		var count := GameState.inventory.count_of(id)
		if count == 0:
			continue
		var row := HBoxContainer.new()
		var name_button := _row("%s x%d" % [CurrencyText.name_of(id), count], ROW_COLOR)
		name_button.tooltip_text = CurrencyText.description_of(id)
		name_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_button)
		var action := Button.new()
		action.text = _consumable_action_label(id)
		action.pressed.connect(_on_consumable_pressed.bind(id))
		row.add_child(action)
		_consumables_list.add_child(row)

func _consumable_action_label(id: StringName) -> String:
	match String(id):
		"infusion_stone": return "Infuse"
		"shrivening_stone": return "Shrive"
		"shard_of_tharsis": return "Corrupt"
	return "Use"

## ---- Actions --------------------------------------------------------

func _on_target_selected(target: Resource) -> void:
	_target = target
	_status_label.text = ""
	_refresh()

func _on_orb_selected(id: StringName) -> void:
	_selected_orb = &"" if _selected_orb == id else id
	_refresh()

func _on_orb_used(id: StringName) -> void:
	_selected_orb = id
	if _target == null or _target is FigmentItem:
		_status_label.text = "Select an item first."
		_refresh()
		return
	var result := _resolver.apply(_target, id, _active_brands)
	if result.success:
		var parts: Array[String] = ["%s used." % CurrencyText.name_of(id)]
		for a in result.removed:
			parts.append("Removed: " + a.description)
		for a in result.added:
			parts.append("Added: " + a.description)
		if result.anchored:
			parts.append("Anchored: " + result.anchored.description)
		if result.quality_gained > 0:
			parts.append("+%d quality" % result.quality_gained)
		if result.sockets_rolled_to >= 0:
			parts.append("Sockets: %d" % result.sockets_rolled_to)
		parts.append("Tolerance spent: %d" % result.tolerance_spent)
		_status_label.text = "\n".join(parts)
	else:
		_status_label.text = result.get_message()
	_refresh()

func _on_brand_toggled(id: StringName) -> void:
	if _active_brands.is_active(id):
		_active_brands.deactivate(id)
	elif not _active_brands.activate(id):
		_status_label.text = CurrencyText.error_message("MISSING_CURRENCY")
	_refresh()

func _on_edict_applied(id: StringName) -> void:
	if _target == null or _target is FigmentItem:
		_status_label.text = "Select an item first."
		return
	var result := _resolver.apply_edict(_target, id)
	_status_label.text = "%s applied." % CurrencyText.name_of(id) if result.success else result.get_message()
	_refresh()

func _on_empower_pressed() -> void:
	if not (_target is FigmentItem):
		return
	if GameState.gold < CraftingSystem.EMPOWER_FIGMENT_GOLD_COST:
		_status_label.text = "Need %d Gold." % CraftingSystem.EMPOWER_FIGMENT_GOLD_COST
		return
	var result := CraftingSystem.empower_figment(_target)
	if result["success"]:
		GameState.gold -= CraftingSystem.EMPOWER_FIGMENT_GOLD_COST
	_status_label.text = result["message"]
	_refresh()

func _on_consumable_pressed(id: StringName) -> void:
	if not (_target is Item) or _target is FigmentItem:
		_status_label.text = "Select an item first."
		return
	var result: Dictionary
	match String(id):
		"infusion_stone":
			if not (_target is Weapon):
				_status_label.text = "Infusion Stone only works on weapons."
				return
			result = CraftingSystem.infuse(_target)
		"shrivening_stone":
			if not (_target is Weapon):
				_status_label.text = "Shrivening Stone only works on weapons."
				return
			result = CraftingSystem.shrive(_target)
		"shard_of_tharsis":
			var power_level: int = GameState.active_map.tier if GameState.active_map else GameState.player_level
			result = CraftingSystem.corrupt(_target, power_level)
		_:
			return
	_status_label.text = result["message"]
	if result["success"]:
		GameState.inventory.remove_currency(id)
	_refresh()

## ---- Row styling ----------------------------------------------------

## An Item or Slate row is an ItemSlotButton, so hovering shows its ItemCard.
func _row(text: String, color: Color, content: Resource = null) -> Button:
	var button: Button = ItemSlotButton.new() if content != null else Button.new()
	if content is Item:
		(button as ItemSlotButton).item = content
	elif content is Slate:
		(button as ItemSlotButton).slate = content
	if content != null:
		button.tooltip_text = content.display_name
	button.text = text
	button.clip_text = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_apply_button_color(button, color)
	return button

func _apply_button_color(button: Button, color: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(4)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, box)
	var text_color := Constants.get_contrasting_text_color(color)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		button.add_theme_color_override(state, text_color)

func _color_of(target: Resource) -> Color:
	if target is Slate:
		return Constants.SLATE_RARITY_COLOR.get(target.rarity, Color.WHITE)
	return Constants.ITEM_RARITY_COLOR.get(target.rarity, Color.WHITE)
