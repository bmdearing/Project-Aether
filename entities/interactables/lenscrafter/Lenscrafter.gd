extends Node3D
class_name Lenscrafter
## Hub NPC who deals in Lenses. Press E for the VendorScreen: a stock of
## rolled Lenses to buy, and carried Lenses to sell. "Lens Services" lists
## the carried Lenses with three crafts (each re-seeds the Lens's Star sites,
## see FateStars.lens_seed()):
##   Recut   - rerolls the radius modifier (and its tag and value)
##   Regrind - rerolls the jewel modifiers, same rarity
##   Polish  - raises rarity by one (up to Rare), adding a jewel modifier
## All prices are placeholders.

const STOCK_SIZE := 6
const STOCK_GRID := Vector2i(12, 8)
const BUY_PRICE := {Constants.ItemRarity.COMMON: 40, Constants.ItemRarity.UNCOMMON: 90, Constants.ItemRarity.RARE: 200}
const SELL_PRICE := {Constants.ItemRarity.COMMON: 8, Constants.ItemRarity.UNCOMMON: 20, Constants.ItemRarity.RARE: 50}
const RECUT_COST := 60
const REGRIND_COST := 80
const POLISH_COST := {Constants.ItemRarity.COMMON: 120, Constants.ItemRarity.UNCOMMON: 300}
## Loot rarity multiplier for the stock: better odds of Uncommon/Rare than drops.
const STOCK_RARITY := 2.0

const ROBE := Color(0.1, 0.16, 0.2)
const SKIN := Color(0.78, 0.66, 0.55)
const BRASS := Color(0.85, 0.66, 0.3)
const GLASS := Color(0.55, 0.85, 1.0)

## Kept for the session; rerolled on level-up.
static var _stock: GridInventory
static var _stock_level := -1

var _prompt: Label3D
var _player_in_range := false
var _lens: MeshInstance3D
var _time := 0.0

func _ready() -> void:
	_build()

## ---- Look ---------------------------------------------------------------

func _build() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 1.0, 0.9)
	shape.shape = box
	shape.position = Vector3(0, 0.5, 0.6)
	body.add_child(shape)
	# The bench, with a few Lenses laid out on it.
	_add_mesh(_box(Vector3(1.8, 0.9, 0.8)), Vector3(0, 0.45, 0.6), _mat(Color(0.3, 0.2, 0.12), 0.0))
	for i in 3:
		var disc := CylinderMesh.new()
		disc.top_radius = 0.07 + 0.02 * i
		disc.bottom_radius = disc.top_radius
		disc.height = 0.02
		_add_mesh(disc, Vector3(-0.5 + 0.45 * i, 0.91, 0.55), _mat(GLASS.lerp(BRASS, 0.2 * i), 0.8))
	# The crafter: robe, head, and a glowing loupe over one eye.
	var robe := CylinderMesh.new()
	robe.top_radius = 0.24
	robe.bottom_radius = 0.5
	robe.height = 1.6
	_add_mesh(robe, Vector3(0, 0.8, -0.2), _mat(ROBE, 0.0))
	var head := SphereMesh.new()
	head.radius = 0.19
	head.height = 0.4
	_add_mesh(head, Vector3(0, 1.8, -0.2), _mat(SKIN, 0.0))
	var hood := SphereMesh.new()
	hood.radius = 0.24
	hood.height = 0.42
	_add_mesh(hood, Vector3(0, 1.86, -0.26), _mat(ROBE, 0.0))
	var loupe := CylinderMesh.new()
	loupe.top_radius = 0.06
	loupe.bottom_radius = 0.07
	loupe.height = 0.08
	var loupe_mi := _add_mesh(loupe, Vector3(0.07, 1.83, -0.02), _mat(BRASS, 0.0))
	loupe_mi.rotation_degrees.x = 90.0
	_lens = _add_mesh(_disc(0.05), Vector3(0.07, 1.83, 0.025), _mat(GLASS, 3.0))
	_lens.rotation_degrees.x = 90.0
	var area := Area3D.new()
	area.monitorable = false
	var sphere := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 3.0
	sphere.shape = s
	sphere.position.y = 1.0
	area.add_child(sphere)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	_prompt = Label3D.new()
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.font_size = 42
	_prompt.outline_size = 8
	_prompt.text = "Press E to see the Lenscrafter"
	_prompt.position.y = 2.6
	_prompt.visible = false
	add_child(_prompt)

func _process(delta: float) -> void:
	_time += delta
	if _lens:
		(_lens.material_override as StandardMaterial3D).emission_energy_multiplier = 2.4 + 0.8 * sin(_time * 2.2)

func _add_mesh(mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	if (mat as BaseMaterial3D).emission_enabled:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

func _disc(radius: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = 0.01
	return c

func _mat(color: Color, glow: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	return mat

## ---- Shop ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range and event.is_action_pressed("interact") and not get_tree().paused:
		get_viewport().set_input_as_handled()
		_open_shop()

func _refresh_stock() -> void:
	if _stock == null or _stock_level != GameState.player_level:
		_roll_stock()

func _roll_stock() -> void:
	_stock = GridInventory.new(STOCK_GRID.x, STOCK_GRID.y)
	_stock_level = GameState.player_level
	for i in STOCK_SIZE:
		_stock.add(LensRoller.roll(maxi(GameState.player_level, 1), STOCK_RARITY))

func _open_shop() -> void:
	_refresh_stock()
	VendorScreen.open_for(get_tree(), {
		"title": "Lenscrafter",
		"stock": _stock,
		"buy_price": func(content) -> int: return BUY_PRICE.get((content as Lens).rarity, 40) if content is Lens else 0,
		"sell_price": func(content) -> int: return SELL_PRICE.get((content as Lens).rarity, 8) if content is Lens else 0,
		"action": {"label": "Lens Services", "cost": 0, "on_action": _open_services},
		"notice": "Buys Lenses only.",
	})

func _open_services() -> void:
	var vendor := get_tree().get_first_node_in_group("vendor_screen") as VendorScreen
	if vendor and vendor.is_open():
		vendor.close()
	_open_services_list.call_deferred()

func _open_services_list() -> void:
	var screen := get_tree().get_first_node_in_group("shop_screen") as ShopScreen
	if screen == null:
		return
	var entries: Array = []
	for content in GameState.get_inventory_items():
		var lens := content as Lens
		# Corrupted Lenses (the Lodestar) can't be changed.
		if lens == null or lens.is_corrupted:
			continue
		var color: Color = Constants.ITEM_RARITY_COLOR.get(lens.rarity, Color.WHITE)
		entries.append(_service_row("Recut: %s" % _lens_label(lens), lens, RECUT_COST, "Recut", color, recut.bind(lens)))
		if LensRoller.JEWEL_MODS_BY_RARITY.get(lens.rarity, 0) > 0:
			entries.append(_service_row("Regrind: %s" % _lens_label(lens), lens, REGRIND_COST, "Regrind", color, regrind.bind(lens)))
		if POLISH_COST.has(lens.rarity):
			entries.append(_service_row("Polish: %s" % _lens_label(lens), lens, POLISH_COST[lens.rarity], "Polish", color, polish.bind(lens)))
	screen.open_with("Lens Services", entries)
	screen.set_notice("Recut rerolls the radius modifier, Regrind the jewel modifiers, Polish raises rarity. Any change moves the Lens's Star bonuses." if not entries.is_empty() else "Carry a Lens to have it worked.")

func _service_row(label: String, lens: Lens, cost: int, button: String, color: Color, on_buy: Callable) -> Dictionary:
	return {"label": label, "item": lens, "cost": cost, "button_label": button, "color": color,
		"on_buy": func() -> bool:
			on_buy.call()
			_reopen_services.call_deferred()
			return true}

func _lens_label(lens: Lens) -> String:
	return "%s - %s" % [lens.display_name, lens.radius_text()]

func _reopen_services() -> void:
	var screen := get_tree().get_first_node_in_group("shop_screen") as ShopScreen
	if screen and screen.is_open():
		screen.close()
		_open_services_list()

static func recut(lens: Lens, rng: RandomNumberGenerator = null) -> void:
	rng = _rng(rng)
	var fresh := LensRoller.roll(lens.item_level, 1.0, rng)
	lens.radius_mod = fresh.radius_mod
	lens.radius_value = fresh.radius_value
	lens.radius_tag = fresh.radius_tag
	EventBus.item_stats_changed.emit(lens)

static func regrind(lens: Lens, rng: RandomNumberGenerator = null) -> void:
	rng = _rng(rng)
	lens.affixes.clear()
	JewelRoller.add_random_modifiers(lens, LensRoller.JEWEL_MODS_BY_RARITY.get(lens.rarity, 0), rng)
	EventBus.item_stats_changed.emit(lens)

static func polish(lens: Lens, rng: RandomNumberGenerator = null) -> void:
	if lens.rarity >= Constants.ItemRarity.RARE:
		return
	rng = _rng(rng)
	lens.rarity = (lens.rarity + 1) as Constants.ItemRarity
	var want: int = LensRoller.JEWEL_MODS_BY_RARITY.get(lens.rarity, 0)
	JewelRoller.add_random_modifiers(lens, maxi(want - lens.affixes.size(), 0), rng)
	EventBus.item_stats_changed.emit(lens)

static func _rng(rng: RandomNumberGenerator) -> RandomNumberGenerator:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return rng

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_player_in_range = true
		GameSettings.refresh_interact_prompt(_prompt)
		_prompt.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_player_in_range = false
		_prompt.visible = false
