extends CanvasLayer
class_name AbilitiesScreen
## Spells screen (open_abilities, K). Every owned spell is an icon in a grid:
## - left click opens that spell's page: level up, its card and the space
##   for its skill web (SkillWebView, not designed yet);
## - right click pops up a small diagram of the Spell Page (keys 1-4) and the
##   Stance Page (cast while holding RMB with a Spell Library conduit); the
##   next click on one of its slots puts the spell there.
## The loadout rows under the grid show both pages; clicking a slot empties it.
##
## Owned spells are scanned from data/abilities/instances/, filtered to
## GameState.owned_ability_ids. Leveling costs Gold + Crystallized Aether.

const ABILITY_INSTANCE_DIR := "res://data/abilities/instances/"
const ICON_SIZE := 76.0
const GRID_COLUMNS := 8
const SLOT_SIZE := 64.0
const MINI_SLOT_SIZE := 46.0

var _is_open: bool = false
var _ability_loadout: AbilityLoadoutComponent
var _owned_abilities: Array[Ability] = []

var _library: VBoxContainer
var _grid: GridContainer
var _empty_label: Label
var _page_slots: Array[ItemSlotButton] = []
var _currency_label: Label
var _status: Label

var _web_page: VBoxContainer
var _web_ability: Ability
var _web_title: Label
var _web_level: Label
var _web_upgrade: Button
var _web_card_holder: Control
var _web_view: SkillWebView

## Right-click assign popup: covers the screen so a click anywhere else closes it.
var _assign_layer: Control
var _assign_panel: PanelContainer
var _assign_slots: Array[ItemSlotButton] = []
var _assigning: Ability

func _ready() -> void:
	layer = AetherStyle.SCREEN_LAYER  # above the HUD
	AetherStyle.style_screen(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("abilities_screen")
	add_to_group("blocking_menu")
	_build()

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player := get_tree().get_first_node_in_group("player") as Player
	_ability_loadout = player.ability_loadout if player else null
	if _ability_loadout and not _ability_loadout.loadout_changed.is_connected(_refresh_loadout):
		_ability_loadout.loadout_changed.connect(_refresh_loadout)
	_status.text = ""
	_close_assign()
	_show_library()
	_build_grid()
	_refresh_loadout()

func close() -> void:
	_is_open = false
	visible = false
	_close_assign()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		if _assign_layer.visible:
			_close_assign()
		elif _web_page.visible:
			_show_library()
		else:
			close()
		get_viewport().set_input_as_handled()

## ---- Layout ----------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(GRID_COLUMNS * (ICON_SIZE + 8.0) + 40.0, 640)
	root.add_theme_constant_override("separation", 10)
	center.add_child(root)
	AetherStyle.wrap_in_plate(root, 24)

	var title := Label.new()
	title.text = "Spells"
	AetherStyle.title_label(title, 26)
	root.add_child(title)

	_library = VBoxContainer.new()
	_library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_library.add_theme_constant_override("separation", 10)
	root.add_child(_library)
	_library.add_child(_dim_label("Left-click a spell to open its page. Right-click it to choose where it goes on your Spell or Stance Page."))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = ICON_SIZE * 3 + 40.0
	_library.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)
	_empty_label = _dim_label("You don't know any spells yet. Skill Tomes drop in Figments.")
	_library.add_child(_empty_label)

	_build_web_page(root)

	root.add_child(_section_label("Spell Page - keys 1-4"))
	root.add_child(_slot_row(0))
	root.add_child(_section_label("Stance Page - cast while holding RMB with a Spell Library conduit"))
	root.add_child(_slot_row(AbilityLoadoutComponent.SLOT_COUNT))
	root.add_child(_dim_label("Click a slot to empty it."))

	_currency_label = Label.new()
	root.add_child(_currency_label)
	_status = Label.new()
	_status.add_theme_color_override("font_color", AetherStyle.GOLD)
	root.add_child(_status)
	var close_button := Button.new()
	close_button.text = "Close (Esc)"
	close_button.pressed.connect(close)
	root.add_child(close_button)

	_build_assign_popup()

func _dim_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", AetherStyle.TEXT_DIM)
	return label

func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", AetherStyle.GOLD)
	return label

func _slot_row(first: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for i in AbilityLoadoutComponent.SLOT_COUNT:
		var button := _make_slot_button(SLOT_SIZE, str(i + 1) if first == 0 else "RMB %d" % (i + 1))
		button.pressed.connect(_on_loadout_slot_pressed.bind(first + i))
		row.add_child(button)
		_page_slots.append(button)
	return row

## A spell slot with a small key caption in its corner.
func _make_slot_button(side: float, caption: String) -> ItemSlotButton:
	var button := ItemSlotButton.new()
	button.custom_minimum_size = Vector2(side, side)
	var key := Label.new()
	key.text = caption
	key.add_theme_font_size_override("font_size", 11)
	key.add_theme_color_override("font_color", AetherStyle.TEXT_DIM)
	key.position = Vector2(4, 1)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(key)
	return button

## ---- Spell grid ------------------------------------------------------------

func _scan_owned_abilities() -> void:
	_owned_abilities = []
	var dir := DirAccess.open(ABILITY_INSTANCE_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next().trim_suffix(".remap")
	while file_name != "":
		if file_name.ends_with(".tres"):
			var ability: Ability = load(ABILITY_INSTANCE_DIR + file_name) as Ability
			if ability and GameState.owned_ability_ids.has(ability.ability_id):
				_owned_abilities.append(ability)
		file_name = dir.get_next().trim_suffix(".remap")
	dir.list_dir_end()
	_owned_abilities.sort_custom(func(a: Ability, b: Ability): return a.display_name < b.display_name)

func _build_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_scan_owned_abilities()
	_empty_label.visible = _owned_abilities.is_empty()
	for ability in _owned_abilities:
		var icon := SpellIcon.new()
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.ability = ability
		icon.tooltip_text = ability.display_name
		AetherStyle.style_slot_button(icon, SpellArt.colour_of(ability))
		icon.left_clicked.connect(_open_web.bind(ability))
		icon.right_clicked.connect(_open_assign.bind(ability))
		_grid.add_child(icon)
	_refresh_currency()

func _refresh_loadout() -> void:
	if _ability_loadout == null:
		return
	for i in _page_slots.size():
		_style_slot(_page_slots[i], _ability_loadout.slots[i])
	for i in _assign_slots.size():
		_style_slot(_assign_slots[i], _ability_loadout.slots[i])
	for icon in _grid.get_children():
		if icon is SpellIcon:
			icon.refresh_marks()

func _style_slot(button: ItemSlotButton, ability: Ability) -> void:
	button.ability = ability
	button.text = ""
	button.tooltip_text = ability.display_name if ability else ""
	AetherStyle.style_slot_button(button, SpellArt.colour_of(ability) if ability else AetherStyle.GOLD_FAINT)

func _on_loadout_slot_pressed(slot_index: int) -> void:
	if _ability_loadout:
		_ability_loadout.unequip(slot_index)
		GameState.sync_ability_loadout(_ability_loadout)

func _refresh_currency() -> void:
	_currency_label.text = "Gold: %d    %s: %d" % [GameState.gold, CurrencyText.name_of(Ability.AETHER_CURRENCY), GameState.inventory.count_of(Ability.AETHER_CURRENCY)]

## ---- Spell page (skill web) -----------------------------------------------

func _build_web_page(root: VBoxContainer) -> void:
	_web_page = VBoxContainer.new()
	_web_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_web_page.add_theme_constant_override("separation", 10)
	_web_page.visible = false
	root.add_child(_web_page)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_web_page.add_child(header)
	var back := Button.new()
	back.text = "< All Spells"
	back.pressed.connect(_show_library)
	header.add_child(back)
	_web_title = Label.new()
	AetherStyle.title_label(_web_title, 22)
	header.add_child(_web_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_web_level = Label.new()
	header.add_child(_web_level)
	_web_upgrade = Button.new()
	_web_upgrade.pressed.connect(func():
		if _web_ability:
			_on_upgrade_pressed(_web_ability))
	header.add_child(_web_upgrade)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	_web_page.add_child(body)
	_web_card_holder = VBoxContainer.new()
	_web_card_holder.custom_minimum_size.x = 300
	body.add_child(_web_card_holder)
	_web_view = SkillWebView.new()
	_web_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_web_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_web_view.custom_minimum_size = Vector2(760, 520)
	_web_view.changed.connect(_refresh_web)
	body.add_child(_web_view)

func _show_library() -> void:
	_web_ability = null
	_web_page.visible = false
	_library.visible = true

func _open_web(ability: Ability) -> void:
	_close_assign()
	_web_ability = ability
	_library.visible = false
	_web_page.visible = true
	_web_view.ability = ability
	_refresh_web()

func _refresh_web() -> void:
	if _web_ability == null:
		return
	_web_view.queue_redraw()
	_web_title.text = _web_ability.display_name
	_web_level.text = "Level %d/%d" % [_web_ability.level, Ability.MAX_LEVEL]
	if _web_ability.can_upgrade():
		_web_upgrade.text = "Level Up (%d Gold, %d %s)" % [_web_ability.get_upgrade_gold_cost(), _web_ability.get_upgrade_aether_cost(), CurrencyText.name_of(Ability.AETHER_CURRENCY)]
		_web_upgrade.disabled = not _can_afford(_web_ability)
	else:
		_web_upgrade.text = "Max Level"
		_web_upgrade.disabled = true
	for child in _web_card_holder.get_children():
		child.queue_free()
	var card: ItemCard = ItemSlotButton.ITEM_CARD_SCENE.instantiate()
	var player := get_tree().get_first_node_in_group("player") as Player
	# Shown as its web makes it (Molten Core's Comet is Fire).
	card.display_ability(PlayerAbilityCast.web_variant(_web_ability), player.stat_sheet if player else null)
	_web_card_holder.add_child(card)

func _can_afford(ability: Ability) -> bool:
	return GameState.gold >= ability.get_upgrade_gold_cost() and GameState.inventory.count_of(Ability.AETHER_CURRENCY) >= ability.get_upgrade_aether_cost()

func _on_upgrade_pressed(ability: Ability) -> void:
	if ability.can_upgrade() and _can_afford(ability):
		GameState.gold -= ability.get_upgrade_gold_cost()
		GameState.inventory.remove_currency(Ability.AETHER_CURRENCY, ability.get_upgrade_aether_cost())
		ability.level += 1
		GameState.ability_levels[ability.ability_id] = ability.level
	_refresh_currency()
	_refresh_web()
	_refresh_loadout()

## ---- Right-click assign popup ---------------------------------------------

func _build_assign_popup() -> void:
	_assign_layer = Control.new()
	_assign_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_assign_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_assign_layer.visible = false
	_assign_layer.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_close_assign())
	add_child(_assign_layer)
	_assign_panel = PanelContainer.new()
	_assign_panel.add_theme_stylebox_override("panel", AetherStyle.glass_box(AetherStyle.GOLD, AetherStyle.GLASS_SOLID, 1, 10.0))
	_assign_layer.add_child(_assign_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_assign_panel.add_child(box)
	box.add_child(_section_label("Spell Page"))
	box.add_child(_assign_row(0))
	box.add_child(_section_label("Stance Page"))
	box.add_child(_assign_row(AbilityLoadoutComponent.SLOT_COUNT))

func _assign_row(first: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for i in AbilityLoadoutComponent.SLOT_COUNT:
		var button := _make_slot_button(MINI_SLOT_SIZE, str(i + 1))
		button.pressed.connect(_assign_to.bind(first + i))
		row.add_child(button)
		_assign_slots.append(button)
	return row

func _open_assign(ability: Ability) -> void:
	if _ability_loadout == null:
		_status.text = "No character to equip spells on here."
		return
	_assigning = ability
	_refresh_loadout()
	_assign_layer.visible = true
	_assign_panel.reset_size()
	var view := _assign_layer.get_viewport_rect().size
	var at := _assign_layer.get_local_mouse_position() + Vector2(12, 12)
	at.x = minf(at.x, view.x - _assign_panel.size.x - 8.0)
	at.y = minf(at.y, view.y - _assign_panel.size.y - 8.0)
	_assign_panel.position = at

func _close_assign() -> void:
	_assigning = null
	if _assign_layer:
		_assign_layer.visible = false

## Puts the spell in a slot. It leaves any other slot on that page, so a
## page never holds the same spell twice.
func _assign_to(slot_index: int) -> void:
	if _assigning and _ability_loadout:
		var first := 0 if slot_index < AbilityLoadoutComponent.SLOT_COUNT else AbilityLoadoutComponent.SLOT_COUNT
		for i in range(first, first + AbilityLoadoutComponent.SLOT_COUNT):
			if i != slot_index and _ability_loadout.slots[i] == _assigning:
				_ability_loadout.unequip(i)
		_ability_loadout.equip(_assigning, slot_index)
		GameState.sync_ability_loadout(_ability_loadout)
		_status.text = "%s set to %s slot %d." % [_assigning.display_name, "Spell Page" if first == 0 else "Stance Page", slot_index - first + 1]
	_close_assign()

## A spell in the grid: left and right clicks are separate signals, and a
## small mark shows which pages it's on.
class SpellIcon extends ItemSlotButton:
	signal left_clicked
	signal right_clicked

	var _marks: Control

	func _ready() -> void:
		super._ready()
		pressed.connect(func(): left_clicked.emit())
		_marks = Control.new()
		_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_marks.draw.connect(_draw_marks)
		add_child(_marks)

	func refresh_marks() -> void:
		if _marks:
			_marks.queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			right_clicked.emit()
			accept_event()

	func _draw_marks() -> void:
		var player: Player = get_tree().get_first_node_in_group("player") as Player
		if player == null or player.ability_loadout == null or ability == null:
			return
		var slots := player.ability_loadout.slots
		var on_bar := slots.slice(0, AbilityLoadoutComponent.SLOT_COUNT).has(ability)
		var on_stance := slots.slice(AbilityLoadoutComponent.SLOT_COUNT).has(ability)
		if on_bar:
			_marks.draw_circle(Vector2(size.x - 9, 9), 4.5, AetherStyle.GOLD_BRIGHT)
		if on_stance:
			_marks.draw_circle(Vector2(size.x - 9, 21), 4.5, AetherStyle.AETHER)
