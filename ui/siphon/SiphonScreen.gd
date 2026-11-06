extends CanvasLayer
class_name SiphonScreen
## The Siphon's screen (Crafting Rev 3): one item box, the crafts, the family
## (or damage type, boss, or modifier) the craft targets, its cost and the
## item's cost multiplier, the odds on the item's card, a payment split for
## crafts any pool can pay, and your inventory on the right. Put an item in by
## dragging it onto the box or right-clicking it; click the box to take it
## back. Closing returns it. The rules are CraftingResolver's.

const SLOT_SIZE := 132
const CELL := 36

var _is_open := false
var _resolver := CraftingResolver.create_default()
var _craft: StringName = &"add"
var _session: CraftSession
var _box: SiphonSlot
var _card: ItemCard
var _meters: HBoxContainer
var _boss_bar: ResidueBar
var _crafts: VBoxContainer
var _picker: OptionButton
var _picker_label: Label
var _cost: Label
var _payment_box: HBoxContainer
var _spins: Dictionary = {}  # pool -> SpinBox
var _craft_button: Button
var _outcomes: VBoxContainer
var _hint: Label
var _inventory_view: InventoryGridView

static func open_for(tree: SceneTree) -> SiphonScreen:
	var screen := tree.get_first_node_in_group("siphon_screen") as SiphonScreen
	if screen == null:
		screen = SiphonScreen.new()
		tree.current_scene.add_child(screen)
	screen.open()
	return screen

func _ready() -> void:
	layer = AetherStyle.SCREEN_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("siphon_screen")
	add_to_group("blocking_menu")
	_build()

func is_open() -> bool:
	return _is_open

func open() -> void:
	_inventory_view.set_inventory(GameState.inventory)
	_set_hint("Drag an item onto the Siphon, or right-click it in your inventory.")
	_is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()

func close() -> void:
	_close_session()
	if item():
		_stow(item())
		_box.set_content(null)
	_is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

## ---- State ---------------------------------------------------------------

func item() -> Resource:
	return _box.content() if _box else null

func set_craft(craft_id: StringName) -> void:
	_close_session()
	_craft = craft_id
	_fill_picker()
	_refresh()

## The picker's value: family tag, damage type name, boss id, or "".
func family() -> StringName:
	if _craft == &"anchor" or _picker.item_count == 0 or _picker.selected < 0:
		return &""
	return StringName(str(_picker.get_item_metadata(_picker.selected)))

func choice() -> int:
	return -1

func outcome_count() -> int:
	return clampi(GameState.foresight_outcomes, 1, Constants.FORESIGHT_MAX_OUTCOMES)

func payment() -> Dictionary:
	var pools := CraftingResolver.payment_pools(_craft, family())
	if pools.size() <= 1 or item() == null:
		return _resolver.auto_payment(item(), _craft, family(), outcome_count()) if item() else {}
	var paid := {}
	for pool in pools:
		var spin: SpinBox = _spins.get(pool)
		if spin and spin.value > 0:
			paid[pool] = int(spin.value)
	return paid

func place(content: Resource) -> bool:
	if not (content is Item or content is Slate) or (content is Item and content.resource_path != ""):
		_set_hint("That can't go in the Siphon.")
		return false
	if not GameState.remove_from_inventory(content):
		return false
	_close_session()
	var old := item()
	_box.set_content(content)
	if old:
		_stow(old)
	_fill_picker()
	_set_hint("")
	_refresh()
	return true

func take() -> void:
	if item() == null:
		return
	_close_session()
	if not GameState.add_to_inventory(item()):
		_set_hint("No room in your inventory.")
		return
	_box.set_content(null)
	_set_hint("")
	_refresh()

func _stow(content: Resource) -> void:
	if GameState.add_to_inventory(content):
		return
	for tab in GameState.stash.tabs:
		if tab.add(content) == 0:
			return
	push_warning("SiphonScreen: nowhere to put %s" % content.get("display_name"))

## ---- Crafting ------------------------------------------------------------

func craft() -> bool:
	if item() == null:
		return false
	var session := _resolver.begin(item(), _craft, family(), payment(), outcome_count(), choice())
	if session.error != CraftResult.CraftError.NONE:
		_set_hint(CurrencyText.error_message(CraftResult.error_name(session.error)))
		_refresh()
		return false
	if session.outcomes.size() == 1:
		var result := session.choose(0)
		_set_hint(_describe(result))
	else:
		_session = session
		_set_hint("Foresight: pick one outcome, or keep the item as it is.")
	_after_craft()
	return true

func _choose(index: int) -> void:
	if _session == null:
		return
	var result := _session.choose(index)
	_session = null
	_set_hint(_describe(result))
	_after_craft()

func _close_session() -> void:
	if _session:
		_session.decline()
		_session = null

func _after_craft() -> void:
	_fill_picker()
	_refresh()

func _describe(result: CraftResult) -> String:
	if not result.success:
		return result.get_message()
	var parts: Array[String] = ["%s done." % CurrencyText.name_of(StringName("craft_" + String(result.craft_id)))]
	for a in result.removed:
		parts.append("Removed: " + a.description)
	for a in result.added:
		parts.append("Added: " + a.description)
	if result.anchored:
		parts.append("Anchored: " + result.anchored.description)
	if result.sockets_rolled_to >= 0:
		parts.append("Sockets: %d" % result.sockets_rolled_to)
	if result.perk_added != &"":
		parts.append("Perk: " + PerkCatalog.text_of(result.perk_added, result.perk_value))
	return "  ".join(parts)

## ---- Refresh -------------------------------------------------------------

func _refresh() -> void:
	_inventory_view.refresh()
	_boss_bar.visible = not GameState.killed_bosses.is_empty() or Residue.amount(Residue.BOSS) > 0
	for bar: ResidueBar in _meters.get_children():
		bar.refresh()
	for button: Button in _crafts.get_children():
		button.button_pressed = StringName(button.get_meta("craft")) == _craft
	_box.refresh_caption()
	var target := item()
	var cost: int = _resolver.cost_of(target, _craft, family(), outcome_count()) if target else 0
	var focus := CraftingResolver.focus_multiplier(_craft, family())
	_cost.text = ("Cost: %d residue   (this item's multiplier x%.2f%s)" % [cost, CraftingResolver.cost_multiplier(target), ", focused x%.0f" % focus if focus > 1.0 else ""]) if target else "Cost: -"
	_refresh_payment(cost)
	if target is Slate:
		_card.display_slate(target as Slate)
	elif target is Item:
		_card.display_item(target as Item)
	_card.visible = target != null
	var error := _craft_error()
	_craft_button.disabled = error != "" or _session != null
	_craft_button.tooltip_text = error
	_craft_button.text = "%s (%d)" % [CurrencyText.name_of(StringName("craft_" + String(_craft))), cost]
	_refresh_outcomes()

func _craft_error() -> String:
	var target := item()
	if target == null:
		return "Put an item in the Siphon."
	var preview := _resolver.preview(target, _craft, family(), choice())
	if not preview.is_valid():
		return CurrencyText.error_message(CraftResult.error_name(preview.error))
	if payment().is_empty():
		return CurrencyText.error_message("CANT_AFFORD")
	var cost := _resolver.cost_of(target, _craft, family(), outcome_count())
	var paid := 0
	var split := payment()
	for pool in split:
		paid += int(split[pool])
	if paid != cost:
		return "Split exactly %d residue across the pools (now %d)." % [cost, paid]
	return ""

func _refresh_payment(cost: int) -> void:
	var pools := CraftingResolver.payment_pools(_craft, family())
	_payment_box.visible = pools.size() > 1 and item() != null
	if not _payment_box.visible:
		return
	# Caps first: a SpinBox clamps on assignment and starts with a max of 100.
	for pool in _spins:
		(_spins[pool] as SpinBox).max_value = float(mini(Residue.amount(pool), cost))
	var auto := _resolver.auto_payment(item(), _craft, family(), outcome_count())
	var total := 0
	for pool in _spins:
		total += int((_spins[pool] as SpinBox).value)
	if total != cost:
		for pool in _spins:
			(_spins[pool] as SpinBox).set_value_no_signal(float(auto.get(pool, 0)))

func _refresh_outcomes() -> void:
	for child in _outcomes.get_children():
		child.queue_free()
	if _session == null:
		return
	for i in _session.outcomes.size():
		var o: Dictionary = _session.outcomes[i]
		var lines: Array[String] = []
		for a in o.get("added", []):
			lines.append("+ " + (a as ItemAffix).description)
		for a in o.get("removed", []):
			lines.append("- " + (a as ItemAffix).description)
		if o.has("perk"):
			lines.append("+ " + PerkCatalog.text_of(o["perk"][0], o["perk"][1]))
		var button := Button.new()
		button.text = "Outcome %d: %s" % [i + 1, ", ".join(lines) if not lines.is_empty() else "values rerolled"]
		button.pressed.connect(_choose.bind(i))
		_outcomes.add_child(button)
	var keep := Button.new()
	keep.text = "Keep the item as it is"
	keep.pressed.connect(func():
		_close_session()
		_set_hint("Kept as it was. The residue is spent.")
		_refresh())
	_outcomes.add_child(keep)

## The picker for the selected craft: families, damage types, bosses or modifiers.
func _fill_picker() -> void:
	_picker.clear()
	var target := item()
	match _craft:
		&"add", &"recast", &"bleed", &"settle":
			_picker_label.text = "Family"
			_picker.add_item("Unfocused (any pool)")
			_picker.set_item_metadata(0, "")
			for tag: StringName in Constants.CRAFT_FAMILIES:
				var pool: StringName = Constants.CRAFT_FAMILIES[tag]
				_picker.add_item("%s  (%s)" % [String(tag).capitalize(), CurrencyText.name_of(pool) if pool != &"" else "any pool"])
				_picker.set_item_metadata(_picker.item_count - 1, String(tag))
		&"retype":
			_picker_label.text = "Damage type"
			for type in Constants.DAMAGE_TYPE_NAME:
				_picker.add_item(String(Constants.DAMAGE_TYPE_NAME[type]))
				_picker.set_item_metadata(_picker.item_count - 1, String(Constants.DAMAGE_TYPE_NAME[type]).to_lower())
		&"vestige_add":
			_picker_label.text = "Boss (its perk)"
			for id in GameState.killed_bosses:
				_picker.add_item("%s  (%s)" % [MonsterInfrequent.source_display_name(id), PerkCatalog.name_of(PerkCatalog.boss_perk(id))])
				_picker.set_item_metadata(_picker.item_count - 1, id)
		_:
			_picker_label.text = ""
	_picker.visible = _picker.item_count > 0
	_picker_label.visible = _picker.visible

func _set_hint(text: String) -> void:
	_hint.text = text

## ---- UI ------------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	center.add_child(root)
	var title := _label("Siphon", 26, AetherStyle.GOLD_BRIGHT)
	title.add_theme_font_override("font", AetherStyle.title())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	_meters = HBoxContainer.new()
	_meters.alignment = BoxContainer.ALIGNMENT_CENTER
	_meters.add_theme_constant_override("separation", 22)
	root.add_child(_meters)
	for pool in Residue.ALL:
		var bar := ResidueBar.create(pool)
		_meters.add_child(bar)
		if pool == Residue.BOSS:
			_boss_bar = bar

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	root.add_child(columns)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)
	_box = SiphonSlot.new()
	_box.screen = self
	_box.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	AetherStyle.style_slot_button(_box, AetherStyle.GOLD)
	left.add_child(_box)
	_box.caption = _label("", 13, AetherStyle.TEXT_DIM)
	_box.caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.caption.custom_minimum_size = Vector2(240, 0)
	_box.caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_box.caption)
	_crafts = VBoxContainer.new()
	left.add_child(_crafts)
	for id in CraftingResolver.CRAFT_IDS:
		var button := Button.new()
		button.toggle_mode = true
		button.text = CurrencyText.name_of(StringName("craft_" + String(id)))
		button.tooltip_text = CurrencyText.description_of(StringName("craft_" + String(id)))
		button.set_meta("craft", String(id))
		button.custom_minimum_size = Vector2(240, 30)
		button.pressed.connect(set_craft.bind(id))
		_crafts.add_child(button)

	var middle := VBoxContainer.new()
	middle.add_theme_constant_override("separation", 8)
	middle.custom_minimum_size = Vector2(360, 0)
	columns.add_child(middle)
	_picker_label = _label("Family", 14, AetherStyle.TEXT)
	middle.add_child(_picker_label)
	_picker = OptionButton.new()
	_picker.item_selected.connect(func(_i): _refresh())
	middle.add_child(_picker)
	_cost = _label("", 15, AetherStyle.TEXT)
	middle.add_child(_cost)
	_payment_box = HBoxContainer.new()
	middle.add_child(_payment_box)
	for pool in Residue.REGULAR:
		_payment_box.add_child(_label(CurrencyText.name_of(pool).get_slice(" ", 0), 12, AetherStyle.TEXT_DIM))
		var spin := SpinBox.new()
		spin.step = 1
		spin.value_changed.connect(func(_v): _refresh_button_only())
		_payment_box.add_child(spin)
		_spins[pool] = spin
	_craft_button = Button.new()
	_craft_button.custom_minimum_size = Vector2(260, 44)
	_craft_button.add_theme_font_size_override("font_size", 18)
	_craft_button.pressed.connect(craft)
	middle.add_child(_craft_button)
	_outcomes = VBoxContainer.new()
	middle.add_child(_outcomes)
	_card = ItemSlotButton.new_item_card()
	_card.craft_preview_for = func(target: Resource) -> CraftPreview: return _resolver.preview(target, _craft, family(), choice())
	middle.add_child(_card)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	columns.add_child(right)
	right.add_child(_label("Your inventory - right-click to put it in the Siphon", 15, AetherStyle.TEXT))
	_inventory_view = InventoryGridView.new()
	_inventory_view.cell_size = CELL
	_inventory_view.allow_drop = true
	_inventory_view.entry_right_clicked.connect(func(_v, entry: GridInventory.Entry):
		if not entry.is_currency():
			place(entry.content))
	right.add_child(_inventory_view)

	_hint = _label("", 15, AetherStyle.TEXT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(900, 22)
	root.add_child(_hint)
	var close_button := Button.new()
	close_button.text = "Close (Esc)"
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(close)
	root.add_child(close_button)
	AetherStyle.wrap_in_plate(root, 24)
	_fill_picker()

func _refresh_button_only() -> void:
	var error := _craft_error()
	_craft_button.disabled = error != "" or _session != null
	_craft_button.tooltip_text = error
	if error.begins_with("Split") or _hint.text.begins_with("Split"):
		_set_hint(error if error.begins_with("Split") else "")

func _label(text: String, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label

## The item box: shows its item (card on hover), takes items dragged from the
## inventory, and gives the item back when clicked.
class SiphonSlot extends ItemSlotButton:
	var screen: SiphonScreen
	var caption: Label

	func _init() -> void:
		tooltip_text = " "
		focus_mode = Control.FOCUS_NONE
		pressed.connect(func(): screen.take())

	func content() -> Resource:
		return slate if slate else item

	func set_content(value: Resource) -> void:
		slate = value as Slate
		item = value as Item

	func refresh_caption() -> void:
		var c := content()
		if c:
			caption.text = str(c.get("display_name"))
			caption.add_theme_color_override("font_color", (c as Item).display_color() if c is Item else Constants.SLATE_RARITY_COLOR.get(c.rarity, Color.WHITE))
		else:
			caption.text = "Item"
			caption.add_theme_color_override("font_color", AetherStyle.TEXT_DIM)

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("grid_entry") and not (data["grid_entry"] as GridInventory.Entry).is_currency()

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		screen.place((data["grid_entry"] as GridInventory.Entry).content)
