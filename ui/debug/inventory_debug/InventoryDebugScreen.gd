extends CanvasLayer
## Debug-only view of the footprint grid inventory and Hub stash (F6).
## Drag to move between cells, tabs and the stash. Right-click an item to
## use the selected Orb or Edict on it, or a Brand to toggle it active.
## Doesn't pause the game.

var _is_open := false
var _active_tab := 0
var _carried_view: InventoryGridView
var _stash_view: InventoryGridView
var _stash_box: VBoxContainer
var _tab_bar: HBoxContainer
var _ammo_label: Label
var _status: Label
var _currency_picker: OptionButton
var _resolver: CraftingResolver
var _active_brands: ActiveBrands

func _ready() -> void:
	layer = 20
	visible = false
	add_to_group("blocking_menu")
	_build()

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_resolver = CraftingResolver.create_default()
	_resolver.currency = GameState.inventory
	if _active_brands == null or _active_brands.carried != GameState.inventory:
		_active_brands = ActiveBrands.new(GameState.inventory)
	_refresh()

func close() -> void:
	_is_open = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_inventory_debug"):
		close() if _is_open else open()
		get_viewport().set_input_as_handled()
	elif _is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _in_hub() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path == GameState.HUB_SCENE

func _build() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 24)
	panel.add_child(root)

	var left := VBoxContainer.new()
	root.add_child(left)
	left.add_child(_label("Inventory (debug, F6)"))
	_carried_view = _make_view()
	left.add_child(_carried_view)
	_ammo_label = _label("")
	left.add_child(_ammo_label)

	var tools := HBoxContainer.new()
	left.add_child(tools)
	tools.add_child(_button("Add gear", _add_gear))
	tools.add_child(_button("Add Slate", _add_slate))
	tools.add_child(_button("Add currency", _add_currency))
	tools.add_child(_button("Clear", _clear))
	var craft_row := HBoxContainer.new()
	left.add_child(craft_row)
	craft_row.add_child(_label("Right-click item uses:"))
	_currency_picker = OptionButton.new()
	for id in Constants.ORB_IDS:
		_currency_picker.add_item(CurrencyText.name_of(id))
		_currency_picker.set_item_metadata(_currency_picker.item_count - 1, id)
	for path in DirAccess.get_files_at(CraftingResolver.EDICTS_DIR):
		if path.ends_with(".tres"):
			var id := StringName(path.get_basename())
			_currency_picker.add_item(CurrencyText.name_of(id))
			_currency_picker.set_item_metadata(_currency_picker.item_count - 1, id)
	craft_row.add_child(_currency_picker)
	_status = _label("")
	_status.custom_minimum_size.x = 420
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_status)

	_stash_box = VBoxContainer.new()
	root.add_child(_stash_box)
	_stash_box.add_child(_label("Stash"))
	_tab_bar = HBoxContainer.new()
	_stash_box.add_child(_tab_bar)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(12 * 36 + 12, 12 * 36 + 4)
	_stash_box.add_child(scroll)
	_stash_view = _make_view()
	scroll.add_child(_stash_view)

func _make_view() -> InventoryGridView:
	var view := InventoryGridView.new()
	view.changed.connect(_refresh)
	view.drop_failed.connect(func(): _status.text = "Doesn't fit there.")
	view.entry_right_clicked.connect(_on_entry_right_clicked)
	return view

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

func _button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	return b

func _refresh() -> void:
	_carried_view.set_inventory(GameState.inventory)
	_stash_box.visible = _in_hub()
	var tabs := GameState.stash.tabs
	_active_tab = clampi(_active_tab, 0, tabs.size() - 1)
	for child in _tab_bar.get_children():
		child.queue_free()
	for i in tabs.size():
		var name := "Tab %d" % (i + 1)
		match tabs[i].accepts:
			GridInventory.Accepts.CURRENCY: name = "Currency"
			GridInventory.Accepts.SLATE: name = "Slates"
		var b := _button(name, _select_tab.bind(i))
		b.disabled = i == _active_tab
		_tab_bar.add_child(b)
	_stash_view.set_inventory(tabs[_active_tab])
	var ammo: Array[String] = []
	for type in Constants.AmmoType.values():
		if type != Constants.AmmoType.ARROW:
			ammo.append("%s %d" % [Constants.AmmoType.keys()[type].capitalize(), AmmoInventory.get_reserve(type)])
	var brands := _active_brands.get_ids().map(func(id): return CurrencyText.name_of(id)) if _active_brands else []
	_ammo_label.text = "Ammo: " + "  ".join(ammo) + ("\nActive Brands: " + ", ".join(brands) if not brands.is_empty() else "")

func _select_tab(index: int) -> void:
	_active_tab = index
	_refresh()

func _on_entry_right_clicked(_view: InventoryGridView, entry: GridInventory.Entry) -> void:
	if entry.is_currency():
		var id: StringName = entry.content
		if not _resolver.brand_defs.has(id):
			_status.text = "Pick it in the dropdown, then right-click an item."
			return
		if _active_brands.is_active(id):
			_active_brands.deactivate(id)
			_status.text = "%s deactivated." % CurrencyText.name_of(id)
		elif _active_brands.activate(id):
			_status.text = "%s activated." % CurrencyText.name_of(id)
		else:
			_status.text = "Brands must be carried to be activated."
		_refresh()
		return
	var used: StringName = _currency_picker.get_selected_metadata()
	var result: CraftResult
	if _resolver.edict_defs.has(used):
		result = _resolver.apply_edict(entry.content, used)
	else:
		result = _resolver.apply(entry.content, used, _active_brands)
	_status.text = ("%s: done.\n%s" % [CurrencyText.name_of(used), InventoryGridView.describe(entry)]) if result.success else result.get_message()
	_refresh()

func _add_gear() -> void:
	var item := ItemRoller.roll(maxi(1, GameState.player_level))
	if item and GameState.inventory.add(item) > 0:
		_status.text = "No room for %s." % item.display_name
	_refresh()

func _add_slate() -> void:
	var slate := SlateRoller.roll()
	if slate and GameState.inventory.add(slate) > 0:
		_status.text = "No room for the Slate."
	_refresh()

func _add_currency() -> void:
	for id in Constants.ORB_IDS:
		GameState.inventory.add(id, 20)
	for id in [&"brand_fire", &"brand_cold", &"brand_prefix", &"brand_suffix", &"brand_preservation", &"edict_prefix"]:
		GameState.inventory.add(id, 5)
	_refresh()

func _clear() -> void:
	GameState.inventory = GridInventory.new()
	_active_brands = ActiveBrands.new(GameState.inventory)
	_resolver.currency = GameState.inventory
	_refresh()
