extends RefCounted
class_name LootWarmup
## Drops build their model from a .glb the first time that weapon, armour or
## item kind falls, and reading one from disk took up to ~30 ms on the kill
## frame. Once per session every manifest model is loaded on background
## threads and kept, so a drop only instances what's already in memory.

const MANIFESTS := [
	"res://assets/models/weapons/weapons_manifest.json",
	"res://assets/models/equipment/equipment_manifest.json",
	"res://assets/models/items/items_manifest.json",
]

static var _started := false
static var _kept: Array[Resource] = []
static var _drops_warmed := false
const WARM_SPOT := Vector3(0, -620, 0)
const LOOT_SCENE := "res://entities/pickups/loot_pickup/LootPickup.tscn"
const GOLD_SCENE := "res://entities/pickups/gold_pickup/GoldPickup.tscn"

## The first drop of each kind built its roller's caches and its pickup's
## model and materials on the kill frame (the first gear roll alone took
## ~90 ms). Once per session, behind the loading screen, one of each is
## rolled and its pickup spawned far below the level for a couple of frames.
static func warm_drops(tree: SceneTree) -> void:
	if _drops_warmed or tree.current_scene == null:
		return
	_drops_warmed = true
	var level := maxi(GameState.player_level, 1)
	var items: Array[Item] = []
	for item: Item in [ItemRoller.roll(level, 1.0), JewelRoller.roll(level, 1.0), LensRoller.roll(level, 1.0),
			FigmentRoller.roll_for_drop(), TomeRoller.roll_for_unowned([]),
			UniqueRoller.roll(Constants.ItemRarity.UNIQUE, level), UniqueRoller.roll(Constants.ItemRarity.MYTHIC, level)]:
		if item:
			items.append(item)
	Constants.roll_currency_drop(level)
	var slate := SlateRoller.roll(level, 1.0)
	var nodes: Array[Node3D] = []
	var scene := tree.current_scene
	for item in items:
		var pickup: LootPickup = (load(LOOT_SCENE) as PackedScene).instantiate()
		pickup.item = item
		nodes.append(pickup)
	if slate:
		var sp: LootPickup = (load(LOOT_SCENE) as PackedScene).instantiate()
		sp.slate = slate
		nodes.append(sp)
	var cp: LootPickup = (load(LOOT_SCENE) as PackedScene).instantiate()
	cp.currency_id = Ability.AETHER_CURRENCY
	nodes.append(cp)
	for amount in [5, 30, 120, 600]:
		var gold: GoldPickup = (load(GOLD_SCENE) as PackedScene).instantiate()
		gold.amount = amount
		nodes.append(gold)
	for i in nodes.size():
		nodes[i].process_mode = Node.PROCESS_MODE_DISABLED
		scene.add_child(nodes[i])
		nodes[i].global_position = WARM_SPOT + Vector3(i * 1.5, 0, 0)
	# A rarer kill's burst, flash and light (Enemy._kill_burst).
	SpellFx.burst(scene, WARM_SPOT, Color(3, 2, 1), 40, Vector2(3.0, 6.0), 0.7, Vector2(0.1, 0.22), 180.0, -6.0)
	SpellFx.flash(scene, WARM_SPOT, Color(2, 2, 1, 0.6), 1.4, 0.2)
	SpellFx.light_pop(scene, WARM_SPOT, Color.WHITE, 2.5, 5.0, 0.3)
	for f in 3:
		await tree.process_frame
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()

static func start(tree: SceneTree) -> void:
	if _started:
		return
	_started = true
	var pending: Array[String] = []
	for manifest: String in MANIFESTS:
		if not ResourceLoader.exists(manifest):
			continue
		var data: Variant = (load(manifest) as JSON).data
		if not data is Dictionary:
			continue
		for entry: Variant in (data as Dictionary).values():
			if entry is Dictionary and entry.has("file") and ResourceLoader.exists(entry["file"]) \
					and not ResourceLoader.has_cached(entry["file"]) and not pending.has(entry["file"]):
				if ResourceLoader.load_threaded_request(entry["file"], "", true) == OK:
					pending.append(entry["file"])
	# Collect as they finish, a few per frame, so nothing waits on a thread.
	while not pending.is_empty():
		await tree.process_frame
		for path in pending.duplicate():
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				_kept.append(ResourceLoader.load_threaded_get(path))
				pending.erase(path)
			elif status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				pending.erase(path)
