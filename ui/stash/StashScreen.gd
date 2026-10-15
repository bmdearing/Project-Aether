extends CanvasLayer
class_name StashScreen
## Hub stash: carried inventory on the left, stash tabs on the right. Drag
## between them, or right-click an entry to send it to the other side. An
## item sent to the stash goes to the tab its category has an affinity for
## (right-click a tab to set them), else the open tab, else the first tab
## that takes it. The Currency tab is a fixed slot per currency
## (CurrencyTabView); the last tab is the Unique tab (UniqueTabView).
## Crafting works as in Path of Exile: right-click a currency on the Currency
## tab to hold it on the cursor, then click any item in the inventory or the
## stash to use it (Shift keeps it in hand for the next click). Brands and
## Edicts are right-clicked on for the next craft.
## Doesn't pause the game.

const CELL := 44

var _is_open := false
var _active_tab := 0
var _carried_view: InventoryGridView
var _stash_view: InventoryGridView
var _stash_scroll: ScrollContainer
var _currency_view: CurrencyTabView
var _unique_view: UniqueTabView
var _tab_bar: HFlowContainer
var _search: LineEdit
## Search text per content (instance id -> lowercased card text), cleared on open.
var _text_cache: Dictionary = {}
const PAGE_SIZE := Vector2(744, 560)
var _status: Label
var _affinity_menu: PopupMenu
var _affinity_tab := 0
## A stash currency held on the cursor, used on the next item clicked.
var _held: StringName = &""
var _cursor_icon: ItemIcon
const CURSOR_ICON_SIZE := 46.0

func _ready() -> void:
	layer = AetherStyle.SCREEN_LAYER  # above the HUD
	AetherStyle.style_screen(self)
	visible = false
	add_to_group("stash_screen")
	add_to_group("blocking_menu")
	_build()
	_cursor_icon = ItemIcon.new()
	_cursor_icon.size = Vector2.ONE * CURSOR_ICON_SIZE
	_cursor_icon.visible = false
	add_child(_cursor_icon)

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status.text = ""
	_text_cache.clear()
	_refresh()

func close() -> void:
	_is_open = false
	_held = &""
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel") and _held != &"":
		_drop_held()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.84)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	center.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)
	var title := _label("Stash", 22)
	AetherStyle.title_label(title, 22)
	header.add_child(title)
	_search = LineEdit.new()
	_search.placeholder_text = "Search names and modifiers (e.g. Ring, Fire, Life)"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(420, 0)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t): _apply_search())
	header.add_child(_search)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	root.add_child(columns)

	var left := VBoxContainer.new()
	columns.add_child(left)
	var carried_head := HBoxContainer.new()
	left.add_child(carried_head)
	var carried_title := AetherStyle.section_header("Inventory")
	carried_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	carried_head.add_child(carried_title)
	var dump := Button.new()
	dump.text = "Dump to Stash"
	dump.tooltip_text = "Sends everything carried to the tab its category has an affinity for (right-click a tab to set them). Favored items and things with no affinity stay."
	dump.pressed.connect(_on_dump_pressed)
	carried_head.add_child(dump)
	_carried_view = _make_view()
	left.add_child(_carried_view)

	# The stash: tabs over one fixed-size page, whatever the tab shows.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	columns.add_child(right)
	_tab_bar = HFlowContainer.new()
	_tab_bar.custom_minimum_size.x = PAGE_SIZE.x
	_tab_bar.add_theme_constant_override("h_separation", 4)
	_tab_bar.add_theme_constant_override("v_separation", 4)
	right.add_child(_tab_bar)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = PAGE_SIZE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_stash_scroll = scroll
	var page := VBoxContainer.new()
	scroll.add_child(page)
	_stash_view = _make_view()
	page.add_child(_stash_view)
	_currency_view = CurrencyTabView.new()
	_currency_view.visible = false
	_currency_view.slot_clicked.connect(_withdraw_currency)
	_currency_view.currency_dropped.connect(_on_currency_dropped)
	_currency_view.slot_used.connect(_on_currency_right_clicked)
	_currency_view.held = func(id: StringName) -> bool: return id == _held
	_currency_view.bench_clicked.connect(_take_from_bench)
	_currency_view.bench_dropped.connect(_on_bench_dropped)
	_currency_view.preview_for = _bench_preview
	_currency_view.brand_active = func(id: StringName) -> bool: return _bench_brands != null and _bench_brands.is_active(id)
	page.add_child(_currency_view)
	_unique_view = UniqueTabView.new()
	_unique_view.visible = false
	_unique_view.slot_clicked.connect(_withdraw_unique)
	page.add_child(_unique_view)
	# Each half framed in a glass plate.
	AetherStyle.wrap_in_plate(left, 14)
	AetherStyle.wrap_in_plate(right, 14)

	_status = _label("", 14)
	root.add_child(_status)
	var hint := _label("Drag to move items. Right-click sends an item to the other side, into the tab set for its kind. Right-click a tab to set what it collects. On the Currency tab, right-click a currency to pick it up, then click any item to use it (hold Shift to keep using it); right-click Brands and Edicts to switch them on for the next craft. E or Esc closes.", 12)
	hint.modulate = Color(1, 1, 1, 0.6)
	root.add_child(hint)

	_affinity_menu = PopupMenu.new()
	_affinity_menu.hide_on_checkable_item_selection = false
	_affinity_menu.id_pressed.connect(_on_affinity_chosen)
	add_child(_affinity_menu)

func _make_view() -> InventoryGridView:
	var view := InventoryGridView.new()
	view.cell_size = CELL
	view.drop_failed.connect(func(): _status.text = "That doesn't fit there.")
	view.changed.connect(func(): _status.text = "")
	view.entry_right_clicked.connect(_on_entry_right_clicked)
	view.entry_clicked.connect(_on_entry_clicked)
	view.craft_preview = _held_preview
	return view

func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l

func _refresh() -> void:
	_carried_view.set_inventory(GameState.inventory)
	var stash := GameState.stash
	var tabs := stash.tabs
	_active_tab = clampi(_active_tab, 0, tabs.size())
	for child in _tab_bar.get_children():
		child.queue_free()
	for i in tabs.size() + 1:
		var b := TabButton.new()
		b.index = i
		b.text = _tab_name(i)
		b.disabled = i == _active_tab
		b.tooltip_text = _affinity_tooltip(i)
		b.pressed.connect(_select_tab.bind(i))
		b.right_clicked.connect(_open_affinity_menu)
		_tab_bar.add_child(b)
	var uniques_open := is_unique_tab_open()
	var currency_open := not uniques_open and tabs[_active_tab].accepts == GridInventory.Accepts.CURRENCY
	_stash_view.visible = not uniques_open and not currency_open
	_unique_view.visible = uniques_open
	_currency_view.visible = currency_open
	if uniques_open:
		_unique_view.stash = stash
		_unique_view.refresh()
	elif currency_open:
		_currency_view.bench_item = stash.bench
		_currency_view.set_inventory(tabs[_active_tab])
	else:
		_stash_view.set_inventory(tabs[_active_tab])
	_apply_search()

## ---- Search -------------------------------------------------------------

func _query() -> String:
	return _search.text.strip_edges().to_lower() if _search else ""

## Whether content's card text (name, type, modifiers) contains the query.
func matches(content, query: String) -> bool:
	if query == "":
		return true
	var key = content if content is StringName else content.get_instance_id()
	if not _text_cache.has(key):
		_text_cache[key] = ItemText.of(content).to_lower()
	return String(_text_cache[key]).contains(query)

## Fades everything that doesn't match, in both grids and every tab view,
## and counts the hits on each tab.
func _apply_search() -> void:
	var query := _query()
	var miss := func(entry: GridInventory.Entry) -> bool: return not matches(entry.content, query)
	for view in [_carried_view, _stash_view]:
		view.dimmed = miss if query != "" else Callable()
		view.refresh()
	_currency_view.dimmed = (func(id: StringName) -> bool: return not matches(id, query)) if query != "" else Callable()
	_currency_view.refresh()
	_unique_view.dimmed = (func(def: Dictionary, item: Item) -> bool: return not (String(def["name"]).to_lower().contains(query) or (item != null and matches(item, query)))) if query != "" else Callable()
	if _unique_view.visible:
		_unique_view.refresh()
	var stash := GameState.stash
	for button in _tab_bar.get_children():
		var b := button as TabButton
		if b == null:
			continue
		b.text = _tab_name(b.index)
		if query == "":
			continue
		var hits := 0
		if b.index < stash.tabs.size():
			for e in stash.tabs[b.index].get_entries():
				if matches(e.content, query):
					hits += 1
		else:
			for id in stash.uniques:
				if matches(stash.uniques[id], query):
					hits += 1
		if hits > 0:
			b.text += "  [%d]" % hits

func is_unique_tab_open() -> bool:
	return _active_tab == GameState.stash.tabs.size()

## Index of a tab in the Stash, mapping the last button to Stash.UNIQUE_TAB.
func _stash_index(button_index: int) -> int:
	return Stash.UNIQUE_TAB if button_index == GameState.stash.tabs.size() else button_index

func _tab_name(index: int) -> String:
	var stash := GameState.stash
	var base := "Uniques"
	if index < stash.tabs.size():
		match stash.tabs[index].accepts:
			GridInventory.Accepts.CURRENCY:
				base = "Currency"
			GridInventory.Accepts.SLATE:
				base = "Slates"
			GridInventory.Accepts.FIGMENT:
				base = "Figments"
			_:
				base = "Tab %d" % (index + 1)
	# A diamond marks a tab collecting something other than its own kind.
	var own := {"Currency": "currency", "Slates": "slates", "Figments": "figments", "Uniques": "uniques"}
	for category in stash.categories_for_tab(_stash_index(index)):
		if own.get(base, "") != category:
			return base + " ◆"
	return base

func _affinity_tooltip(index: int) -> String:
	var categories := GameState.stash.categories_for_tab(_stash_index(index))
	var names := categories.map(func(c: String): return Stash.CATEGORY_NAMES[c])
	var collects := "Collects: %s" % ", ".join(PackedStringArray(names)) if not names.is_empty() else "Collects nothing automatically"
	return collects + "\nRight-click to change."

func _select_tab(index: int) -> void:
	_active_tab = index
	_refresh()

## ---- Affinities ------------------------------------------------------------

func _open_affinity_menu(index: int) -> void:
	_affinity_tab = index
	var stash := GameState.stash
	var tab_index := _stash_index(index)
	_affinity_menu.clear()
	_affinity_menu.add_separator("%s collects" % _tab_name(index).trim_suffix(" ◆"))
	for i in Stash.CATEGORIES.size():
		var category: String = Stash.CATEGORIES[i]
		_affinity_menu.add_check_item(Stash.CATEGORY_NAMES[category], i)
		var item := _affinity_menu.get_item_index(i)
		_affinity_menu.set_item_checked(item, stash.affinities.has(category) and stash.affinities[category] == tab_index)
		_affinity_menu.set_item_disabled(item, not stash.tab_can_take(tab_index, category))
	_affinity_menu.reset_size()
	_affinity_menu.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()), Vector2i.ZERO))

func _on_affinity_chosen(id: int) -> void:
	var category: String = Stash.CATEGORIES[id]
	GameState.stash.toggle_affinity(category, _stash_index(_affinity_tab))
	var item := _affinity_menu.get_item_index(id)
	var stash := GameState.stash
	_affinity_menu.set_item_checked(item, stash.affinities.has(category) and stash.affinities[category] == _stash_index(_affinity_tab))
	_refresh()

## ---- Moving things ---------------------------------------------------------

func _on_entry_right_clicked(view: InventoryGridView, entry: GridInventory.Entry) -> void:
	if _held != &"":
		_drop_held()
		return
	if view == _carried_view:
		if not deposit(entry):
			_status.text = "No room for that."
	elif not send(view.inventory, entry, GameState.inventory):
		_status.text = "No room for that."
	_refresh()

func _on_dump_pressed() -> void:
	var moved := dump_by_affinity()
	_status.text = "Stashed %d item%s." % [moved, "" if moved == 1 else "s"] if moved > 0 else "Nothing carried has a tab to go to."
	_refresh()

## Dump: every carried entry whose category has an affinity goes to that
## tab. Favored items stay. Returns how many entries moved (or partly moved).
func dump_by_affinity() -> int:
	var stash := GameState.stash
	var moved := 0
	for entry in GameState.inventory.get_entries().duplicate():
		var content = entry.content
		if content is Item and (content as Item).mark == Item.Mark.FAVORED:
			continue
		for category in Stash.categories_of(content):
			if not stash.affinities.has(category):
				continue
			var index: int = stash.affinities[category]
			if index == Stash.UNIQUE_TAB:
				if stash.store_unique(content):
					GameState.inventory.remove(entry)
					moved += 1
					break
			elif stash.tab_can_take(index, category) and send(GameState.inventory, entry, stash.tabs[index]):
				moved += 1
				break
	return moved

## Sends a carried entry into the stash: its category's tab first, then the
## open tab, then the first tab that takes it. Returns false if none had room.
func deposit(entry: GridInventory.Entry) -> bool:
	var stash := GameState.stash
	var content = entry.content
	for category in Stash.categories_of(content):
		if not stash.affinities.has(category):
			continue
		var index: int = stash.affinities[category]
		if index == Stash.UNIQUE_TAB:
			if stash.store_unique(content):
				GameState.inventory.remove(entry)
				return true
		elif stash.tab_can_take(index, category) and send(GameState.inventory, entry, stash.tabs[index]):
			return true
	if is_unique_tab_open() and content is Item and stash.store_unique(content):
		GameState.inventory.remove(entry)
		return true
	if not is_unique_tab_open() and stash.tabs[_active_tab].accepts_content(content) and send(GameState.inventory, entry, stash.tabs[_active_tab]):
		return true
	for tab in stash.tabs:
		if tab.accepts_content(content) and send(GameState.inventory, entry, tab):
			return true
	return false

## Moves an entry into the first free space of another grid. Currency
## stacks move as much as fits.
static func send(from: GridInventory, entry: GridInventory.Entry, to: GridInventory) -> bool:
	var leftover := to.add(entry.content, entry.count)
	if leftover == entry.count:
		return false
	entry.count = leftover
	if entry.count == 0:
		from.remove(entry)
	return true

## A currency stack dragged onto the Currency tab.
func _on_currency_dropped(data: Dictionary) -> void:
	var entry: GridInventory.Entry = data["grid_entry"]
	var source: InventoryGridView = data["view"]
	var tab := GameState.stash.get_tab(GridInventory.Accepts.CURRENCY)
	if tab == null or not send(source.inventory, entry, tab):
		_status.text = "No room for that."
	_refresh()

## Takes a stack (or everything that fits) of one currency into the inventory.
func _withdraw_currency(id: StringName, take_all: bool) -> void:
	if _held != &"":
		_drop_held()
		return
	var tab := GameState.stash.get_tab(GridInventory.Accepts.CURRENCY)
	var held := tab.count_of(id)
	if held <= 0:
		return
	var want := held if take_all else mini(held, Constants.MAX_STACK)
	var moved := want - GameState.inventory.add(id, want)
	if moved > 0:
		tab.remove_currency(id, moved)
		_status.text = ""
	else:
		_status.text = "No room for that."
	_refresh()

## ---- Crafting Bench ----------------------------------------------------
## One item on the Currency tab, crafted on with the stash's own currency.

var _resolver: CraftingResolver
var _bench_brands: ActiveBrands

## The resolver and Brands both draw on the stash's currency tab.
func _bench_resolver() -> CraftingResolver:
	var tab := GameState.stash.get_tab(GridInventory.Accepts.CURRENCY)
	if _resolver == null:
		_resolver = CraftingResolver.create_default()
	_resolver.currency = tab
	if _bench_brands == null or _bench_brands.carried != tab:
		_bench_brands = ActiveBrands.new(tab)
	return _resolver

func _bench_preview(id: StringName) -> CraftPreview:
	var bench := GameState.stash.bench
	if bench == null or bench is FigmentItem:
		return null
	var resolver := _bench_resolver()
	return resolver.preview(bench, id, _bench_brands)

func _on_bench_dropped(data: Dictionary) -> void:
	var entry: GridInventory.Entry = data["grid_entry"]
	var source: InventoryGridView = data["view"]
	if GameState.stash.bench != null:
		_status.text = "Take the item on the Crafting Bench back first."
		return
	if source.inventory != GameState.inventory:
		_status.text = "Put items on the bench from your inventory."
		return
	GameState.stash.bench = entry.content
	source.inventory.remove(entry)
	_status.text = ""
	_refresh()

func _take_from_bench() -> void:
	var bench := GameState.stash.bench
	if bench == null:
		return
	if _held != &"":
		_use_held_on(bench)
		return
	if GameState.add_to_inventory(bench):
		GameState.stash.bench = null
		_status.text = ""
	else:
		_status.text = "No room for that."
	_refresh()

## ---- Currency on the cursor ------------------------------------------------

## Right-click on a Currency tab slot: a Brand or Edict switches on or off
## for the next craft; anything usable goes onto the cursor (again: back).
func _on_currency_right_clicked(id: StringName) -> void:
	var resolver := _bench_resolver()
	if resolver.brand_defs.has(id) or resolver.edict_defs.has(id):
		if _bench_brands.is_active(id):
			_bench_brands.deactivate(id)
			_status.text = "%s switched off." % CurrencyText.name_of(id)
		elif _bench_brands.activate(id):
			_status.text = "%s switched on for your next craft from the stash." % CurrencyText.name_of(id)
		_currency_view.refresh()
		return
	if not (Constants.ORB_IDS.has(id) or Constants.CRAFTING_CONSUMABLE_IDS.has(String(id))):
		_status.text = CurrencyText.description_of(id)
		return
	if _held == id:
		_drop_held()
		return
	if _currency_tab().count_of(id) <= 0:
		return
	_held = id
	_status.text = "Click an item to use %s on it. Hold Shift to keep it in hand. Right-click or Esc puts it back." % CurrencyText.name_of(id)
	_refresh_views()

func _drop_held() -> void:
	_held = &""
	_status.text = ""
	_refresh_views()

func _on_entry_clicked(_view: InventoryGridView, entry: GridInventory.Entry) -> void:
	if _held != &"" and not entry.is_currency():
		_use_held_on(entry.content)

func _currency_tab() -> GridInventory:
	return GameState.stash.get_tab(GridInventory.Accepts.CURRENCY)

## Uses the held currency on target, paid from the Currency tab. It stays
## held while Shift is down and some is left.
func _use_held_on(target: Resource) -> void:
	var id := _held
	var tab := _currency_tab()
	if tab.count_of(id) <= 0:
		_drop_held()
		return
	var resolver := _bench_resolver()
	if target is FigmentItem:
		if not Constants.ORB_IDS.has(id):
			_status.text = "%s can't be used on a Figment." % CurrencyText.name_of(id)
			return
		var outcome := CraftingSystem.craft_figment(target, id)
		if outcome["success"]:
			tab.remove_currency(id)
		_status.text = outcome["message"]
	elif not (target is Item or target is Slate):
		_status.text = "%s can't be used on that." % CurrencyText.name_of(id)
		return
	elif Constants.ORB_IDS.has(id):
		var result := resolver.apply(target, id, _bench_brands)
		_status.text = InventoryScreen._describe_craft(id, result) if result.success else result.get_message()
	else:
		var outcome := InventoryScreen.use_stone(id, target)
		if outcome["success"]:
			tab.remove_currency(id)
		_status.text = outcome["message"]
	if not Input.is_key_pressed(KEY_SHIFT) or tab.count_of(id) <= 0:
		_held = &""
	_text_cache.erase(target.get_instance_id())
	_refresh()

## The held Orb's preview on target, for its card while hovering.
func _held_preview(target: Resource) -> CraftPreview:
	if _held == &"" or not Constants.ORB_IDS.has(_held):
		return null
	if not (target is Item or target is Slate) or target is FigmentItem or target.resource_path != "":
		return null
	return _bench_resolver().preview(target, _held, _bench_brands)

func _refresh_views() -> void:
	_carried_view.refresh()
	_stash_view.refresh()
	_currency_view.refresh()

func _process(_delta: float) -> void:
	_cursor_icon.visible = _is_open and _held != &""
	if not _cursor_icon.visible:
		return
	if not is_same(_cursor_icon.content, _held):
		_cursor_icon.content = _held
	_cursor_icon.count = _currency_tab().count_of(_held)
	# Just above-left of the pointer, so its tip stays on the target.
	_cursor_icon.position = get_viewport().get_mouse_position() - Vector2(CURSOR_ICON_SIZE * 0.75, CURSOR_ICON_SIZE * 0.75)
	_cursor_icon.move_to_front()

## A Unique tab slot's item back into the inventory.
func _withdraw_unique(id: String) -> void:
	var item: Item = GameState.stash.uniques.get(id)
	if item == null:
		return
	if GameState.add_to_inventory(item):
		GameState.stash.take_unique(id)
		_status.text = ""
	else:
		_status.text = "No room for that."
	_refresh()

class TabButton extends Button:
	signal right_clicked(index: int)
	var index := 0

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			right_clicked.emit(index)
			accept_event()
