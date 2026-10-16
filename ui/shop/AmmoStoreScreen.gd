extends CanvasLayer
class_name AmmoStoreScreen
## The Hub Ammo Store (E at the AmmoStore): a full resupply for Gold, and a
## carry-capacity upgrade per ammo type (AmmoInventory: +25% of the base cap
## per tier, five tiers, each costing double the last).

const ROW_TYPES := [
	Constants.AmmoType.PISTOL, Constants.AmmoType.REVOLVER, Constants.AmmoType.AUTOMATIC,
	Constants.AmmoType.SHOTGUN, Constants.AmmoType.RIFLE, Constants.AmmoType.CROSSBOW_BOLT,
]
const AMMO_NAMES := {
	Constants.AmmoType.PISTOL: "Pistol rounds", Constants.AmmoType.REVOLVER: "Revolver rounds",
	Constants.AmmoType.AUTOMATIC: "Automatic rounds", Constants.AmmoType.SHOTGUN: "Shotgun shells",
	Constants.AmmoType.RIFLE: "Rifle rounds", Constants.AmmoType.CROSSBOW_BOLT: "Crossbow bolts",
}

var store: AmmoStore
var _is_open := false
var _gold: Label
var _resupply: Button
var _rows: VBoxContainer
var _status: Label

## The scene's screen, created on first use.
static func open_for(tree: SceneTree, p_store: AmmoStore) -> AmmoStoreScreen:
	var screen := tree.get_first_node_in_group("ammo_store_screen") as AmmoStoreScreen
	if screen == null:
		screen = AmmoStoreScreen.new()
		tree.current_scene.add_child(screen)
	screen.store = p_store
	screen.open()
	return screen

func _ready() -> void:
	layer = AetherStyle.SCREEN_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("ammo_store_screen")
	add_to_group("blocking_menu")
	_build()

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	visible = true
	_status.text = ""
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()

func close() -> void:
	_is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if _is_open and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
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
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(620, 0)
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)
	var title := Label.new()
	title.text = "Ammo Store"
	AetherStyle.title_label(title, 22)
	column.add_child(title)
	_gold = Label.new()
	_gold.add_theme_color_override("font_color", AetherStyle.GOLD)
	column.add_child(_gold)
	_resupply = Button.new()
	_resupply.pressed.connect(_on_resupply)
	column.add_child(_resupply)
	column.add_child(AetherStyle.section_header("Carry capacity"))
	var hint := Label.new()
	hint.text = "Each ammo type has its own capacity. Pickups top you up to it, resupply fills to it, and each upgrade raises it by a quarter of the base."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", AetherStyle.TEXT_DIM)
	column.add_child(hint)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	column.add_child(_rows)
	_status = Label.new()
	_status.add_theme_color_override("font_color", AetherStyle.TEXT_DIM)
	column.add_child(_status)
	var close_button := Button.new()
	close_button.text = "Close (Esc)"
	close_button.pressed.connect(close)
	column.add_child(close_button)
	AetherStyle.wrap_in_plate(column, 22)

func refresh() -> void:
	_gold.text = "Gold: %d" % GameState.gold
	var player := get_tree().get_first_node_in_group("player") as Player
	var cost := store.get_resupply_cost(player) if store and player else 0
	_resupply.text = "Resupply everything - %d Gold" % cost if cost > 0 else "Fully stocked"
	_resupply.disabled = cost == 0
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for ammo_type in ROW_TYPES:
		_rows.add_child(_row(ammo_type))

func _row(ammo_type: Constants.AmmoType) -> Control:
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", AetherStyle.row_box(_rows.get_child_count() % 2 == 1))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	plate.add_child(line)
	var name_label := Label.new()
	name_label.text = AMMO_NAMES[ammo_type]
	name_label.custom_minimum_size.x = 170
	line.add_child(name_label)
	var carried := Label.new()
	carried.text = "%d / %d" % [AmmoInventory.get_reserve(ammo_type), AmmoInventory.get_capacity(ammo_type)]
	carried.add_theme_font_override("font", AetherStyle.numbers())
	carried.custom_minimum_size.x = 100
	line.add_child(carried)
	var tier := Label.new()
	tier.text = "Tier %d / %d" % [AmmoInventory.get_capacity_tier(ammo_type), AmmoInventory.MAX_CAPACITY_TIER]
	tier.add_theme_color_override("font_color", AetherStyle.TEXT_DIM)
	tier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(tier)
	var upgrade := Button.new()
	var cost := AmmoInventory.get_upgrade_cost(ammo_type)
	if cost < 0:
		upgrade.text = "Maxed"
		upgrade.disabled = true
	else:
		var step := roundi(AmmoInventory.STARTING_AMMO[ammo_type] * AmmoInventory.BASE_CAPACITY_SHARE * AmmoInventory.CAPACITY_STEP)
		upgrade.text = "+%d capacity - %d Gold" % [step, cost]
		upgrade.disabled = GameState.gold < cost
	upgrade.pressed.connect(_on_upgrade.bind(ammo_type))
	line.add_child(upgrade)
	return plate

func _on_upgrade(ammo_type: Constants.AmmoType) -> void:
	if AmmoInventory.buy_capacity_tier(ammo_type):
		_status.text = "%s capacity raised to %d." % [AMMO_NAMES[ammo_type], AmmoInventory.get_capacity(ammo_type)]
	else:
		_status.text = "Not enough Gold."
	refresh()

func _on_resupply() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if store and player:
		_status.text = store.resupply(player)
	refresh()
