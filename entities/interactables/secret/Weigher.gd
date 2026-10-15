extends Node3D
class_name Weigher
## The Weigher (placeholder name): a Libra-style bargainer that waits in some
## secret rooms (MapEncounters.WEIGHER). Press E for its offer:
##   - three deals, each a boon paid for with a price for the rest of this
##     Figment (written onto the active FigmentItem, so a portal trip keeps it),
##   - or a challenge: its champion, an Ascendant pack, appears in the room,
##     and beating it leaves a hoard.
## One choice per Figment; walking away leaves the offer standing.

enum Stage { OFFERING, BARGAINED, CHALLENGED, DEFEATED }

## Placeholder numbers. quantity/rarity add to the Figment's Item
## Quantity/Rarity (0.4 = +40%); damage/life scale monsters (0.25 = 25% more).
const DEALS := {
	"avarice": {"boon": "+40% Item Quantity", "price": "Monsters deal 25% more damage", "quantity": 0.4, "damage": 0.25},
	"fortune": {"boon": "+60% Item Rarity", "price": "Monsters have 35% more Life", "rarity": 0.6, "life": 0.35},
	"tithe": {"boon": "4 Currency, now", "price": "-25% Item Quantity", "currency": 4, "quantity": -0.25},
	"hoard": {"boon": "A hoard, now", "price": "Monsters deal 30% more damage and have 20% more Life", "hoard": true, "damage": 0.3, "life": 0.2},
	"mercy": {"boon": "Monsters deal 20% less damage", "price": "-30% Item Quantity and Item Rarity", "damage": -0.2, "quantity": -0.3, "rarity": -0.3},
}
const OFFER_COUNT := 3
const NAME := "The Weigher"
const ROBE := Color(0.12, 0.08, 0.16)
const MASK := Color(0.86, 0.82, 0.74)
const EYE := Color(1.0, 0.7, 0.3)
const BRASS := Color(0.85, 0.66, 0.3)
const BOB_HEIGHT := 0.08
const SWAY_DEGREES := 9.0

var map: GeneratedMap
var stage: Stage = Stage.OFFERING
var offers: Array[String] = []
var _figure: Node3D
var _beam: Node3D
var _prompt: Label3D
var _player_in_range := false
var _time := 0.0
var _champions: Dictionary = {}
var _hoard: SecretHoard
var _hoard_opened_on_restore := false

func _ready() -> void:
	var ids: Array = DEALS.keys()
	ids.sort()
	for i in OFFER_COUNT:
		offers.append(ids.pop_at(randi() % ids.size()))
	_build_figure()
	EventBus.enemy_died.connect(_on_enemy_died)

## ---- Look -------------------------------------------------------------------

func _build_figure() -> void:
	_figure = Node3D.new()
	add_child(_figure)
	var robe := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.22
	cone.bottom_radius = 0.62
	cone.height = 1.9
	robe.mesh = cone
	robe.material_override = _mat(ROBE, 0.0)
	robe.position.y = 0.95
	_figure.add_child(robe)
	var mask := MeshInstance3D.new()
	var face := SphereMesh.new()
	face.radius = 0.2
	face.height = 0.46
	mask.mesh = face
	mask.material_override = _mat(MASK, 0.0)
	mask.position = Vector3(0, 2.08, 0.04)
	_figure.add_child(mask)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var dot := SphereMesh.new()
		dot.radius = 0.035
		dot.height = 0.07
		eye.mesh = dot
		eye.material_override = _mat(EYE, 2.5)
		eye.position = Vector3(side * 0.07, 2.12, 0.22)
		_figure.add_child(eye)
	# The scales, held up in front of it: a post, a tilting beam, two pans.
	var post := _part(Vector3(0.04, 0.7, 0.04), Vector3(0, 1.95, 0.5))
	_figure.add_child(post)
	_beam = Node3D.new()
	_beam.position = Vector3(0, 2.3, 0.5)
	_figure.add_child(_beam)
	_beam.add_child(_part(Vector3(0.9, 0.04, 0.04), Vector3.ZERO))
	for side in [-1.0, 1.0]:
		_beam.add_child(_part(Vector3(0.015, 0.3, 0.015), Vector3(side * 0.43, -0.15, 0)))
		var pan := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.14
		disc.bottom_radius = 0.1
		disc.height = 0.04
		pan.mesh = disc
		pan.material_override = _mat(BRASS, 0.3)
		pan.position = Vector3(side * 0.43, -0.31, 0)
		_beam.add_child(pan)
	var glow := OmniLight3D.new()
	glow.light_color = EYE
	glow.light_energy = 1.0
	glow.omni_range = 4.0
	glow.position = Vector3(0, 2.2, 0.6)
	_figure.add_child(glow)
	var title := Label3D.new()
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.text = NAME
	title.font_size = 34
	title.outline_size = 8
	title.modulate = AetherStyle.GOLD
	title.position.y = 2.75
	_figure.add_child(title)
	_prompt = Label3D.new()
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.font_size = 40
	_prompt.outline_size = 8
	_prompt.text = "Press E to bargain"
	_prompt.position.y = 3.1
	_prompt.visible = false
	_figure.add_child(_prompt)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 2.2
	shape.shape = capsule
	shape.position.y = 1.1
	body.add_child(shape)
	_figure.add_child(body)
	var area := Area3D.new()
	area.monitorable = false
	var reach := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.8
	reach.shape = sphere
	reach.position.y = 1.0
	area.add_child(reach)
	_figure.add_child(area)
	area.body_entered.connect(func(b: Node3D):
		if b is Player:
			_player_in_range = true
			GameSettings.refresh_interact_prompt(_prompt)
			_prompt.visible = stage == Stage.OFFERING)
	area.body_exited.connect(func(b: Node3D):
		if b is Player:
			_player_in_range = false
			_prompt.visible = false)

func _part(size: Vector3, at: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _mat(BRASS, 0.3)
	mesh.position = at
	return mesh

func _mat(color: Color, glow: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	return mat

func _process(delta: float) -> void:
	if not is_instance_valid(_figure):
		return
	_time += delta
	_figure.position.y = sin(_time * 1.6) * BOB_HEIGHT + BOB_HEIGHT
	_beam.rotation.z = deg_to_rad(sin(_time * 0.9) * SWAY_DEGREES)

## ---- The bargain --------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range and stage == Stage.OFFERING and event.is_action_pressed("interact") and not AetherStyle.menu_open(get_tree()):
		get_viewport().set_input_as_handled()
		var screen := BargainScreen.new()
		get_tree().current_scene.add_child(screen)
		screen.open(self)

## Text rows for the screen: [{id, boon, price}].
func offer_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id in offers:
		rows.append({"id": id, "boon": DEALS[id]["boon"], "price": DEALS[id]["price"]})
	return rows

func accept(deal_id: String) -> void:
	if stage != Stage.OFFERING or not DEALS.has(deal_id):
		return
	var deal: Dictionary = DEALS[deal_id]
	var figment := GameState.active_map
	if figment:
		figment.loot_quantity_multiplier = maxf(figment.loot_quantity_multiplier + deal.get("quantity", 0.0), 0.0)
		figment.loot_rarity_multiplier = maxf(figment.loot_rarity_multiplier + deal.get("rarity", 0.0), 0.0)
		figment.enemy_damage_multiplier *= 1.0 + deal.get("damage", 0.0)
		var life: float = deal.get("life", 0.0)
		if life != 0.0:
			figment.enemy_health_multiplier *= 1.0 + life
			_scale_living_enemies(1.0 + life)
	for i in int(deal.get("currency", 0)):
		_drop_currency()
	if deal.get("hoard", false):
		_leave_hoard()
	stage = Stage.BARGAINED
	_vanish()

## Monsters already in the map gain the new Life share too.
func _scale_living_enemies(scale: float) -> void:
	if map == null:
		return
	for child in map.get_children():
		if child is Enemy and child.health.is_alive():
			var e := child as Enemy
			var current := e.health.current_health * scale
			e.health.set_max_health(e.health.max_health * scale)
			e.health.current_health = current
			e.health.health_changed.emit(e.health.current_health, e.health.max_health)

func challenge() -> void:
	if stage != Stage.OFFERING:
		return
	stage = Stage.CHALLENGED
	_spawn_champion()
	_vanish()

func _spawn_champion() -> void:
	if map == null:
		return
	var first := map._next_spawn_index
	map._spawn_pack(EnemyRoster.roll_pack(map._pack_table()), global_position + Vector3(0, 0.1, 0), Constants.EnemyRarity.ASCENDANT)
	for child in map.get_children():
		if child is Enemy and int(child.get_meta(&"spawn_index", -1)) >= first:
			_champions[child.get_instance_id()] = child
	map._emit_enemy_count()

func _on_enemy_died(enemy: Node) -> void:
	if stage != Stage.CHALLENGED or not _champions.erase(enemy.get_instance_id()):
		return
	_check_champions()

## Champions killed before a portal trip are removed again on the way back.
func _check_champions() -> void:
	for id in _champions.keys():
		if not is_instance_valid(_champions[id]) or (_champions[id] as Node).is_queued_for_deletion() or not (_champions[id] as Node).is_inside_tree():
			_champions.erase(id)
	if stage == Stage.CHALLENGED and _champions.is_empty():
		stage = Stage.DEFEATED
		_leave_hoard()

func _leave_hoard() -> void:
	_hoard = SecretHoard.new()
	_hoard._opened_on_restore = _hoard_opened_on_restore
	get_parent().add_child(_hoard)
	_hoard.global_position = global_position
	_hoard.rotation = rotation

func _drop_currency() -> void:
	var pickup: LootPickup = TreasureChest.LOOT_PICKUP_SCENE.instantiate()
	pickup.currency_id = Constants.roll_currency_drop()
	get_parent().add_child(pickup)
	var angle := randf() * TAU
	pickup.global_position = global_position + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(0.9, 1.6) + Vector3.UP * 0.4

func _vanish() -> void:
	_prompt.visible = false
	set_process_unhandled_input(false)
	var figure := _figure
	_figure = null
	var tween := create_tween()
	tween.tween_property(figure, "scale", Vector3(0.05, 1.6, 0.05), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(figure.queue_free)

## ---- Portal trips -------------------------------------------------------------

func capture_state() -> Dictionary:
	var state := {"stage": int(stage)}
	if is_instance_valid(_hoard):
		state["hoard"] = _hoard.capture_state()
	return state

## A deal's effects are already on the saved Figment; a challenge left unbeaten
## brings its champion back.
func restore_state(state: Dictionary) -> void:
	stage = int(state.get("stage", Stage.OFFERING)) as Stage
	_hoard_opened_on_restore = bool(state.get("hoard", {}).get("opened", false))
	if stage == Stage.OFFERING:
		return
	_prompt.visible = false
	set_process_unhandled_input(false)
	_figure.queue_free()
	_figure = null
	if stage == Stage.CHALLENGED:
		_spawn_champion()
		_check_champions.call_deferred()
	elif stage == Stage.DEFEATED or state.has("hoard"):
		_leave_hoard()
