extends Node
## Current run/session state, and the live loadout source of truth
## SaveManager.gd serializes to disk - lets equip/ability changes survive
## a Hub<->Map scene reload (Player is a fresh instance every load) as
## well as an app restart.

const HUB_SCENE := "res://levels/hub/Hub.tscn"
const MAP_SCENE := "res://levels/generated_map/GeneratedMap.tscn"
const MAIN_MENU_SCENE := "res://ui/main_menu/MainMenu.tscn"

## Non-weapon defaults; weapons live in weapon sets.
const DEFAULT_EQUIPMENT_PATHS: Array[String] = [
	"res://data/armor/instances/padded_coat.tres",
]
## Set 1 starts empty.
const DEFAULT_WEAPON_SET_0_PATHS: Array[String] = [
	"res://data/weapons/instances/crude_greatsword.tres",
]
## Slot index = the ability_N hotkey; abilities start unequipped.
const DEFAULT_ABILITY_LOADOUT_PATHS: Array[String] = ["", "", "", ""]

var player_stat_sheet: Resource # StatSheet, assigned at runtime by Player.gd
var fate_board: Resource        # FateBoard, assigned at runtime
var player_equipment: Node      # EquipmentComponent, assigned at runtime by Player.gd

var debug_overlay_enabled: bool = true

## Gates MainMenu's "Continue Game" button and whether save_game() is a no-op.
var game_started: bool = false

var mouse_sensitivity: float = 0.0035
var master_volume: float = 1.0
var fullscreen: bool = false
var field_of_view: float = 80.0
var vsync: bool = true
## Draw item sockets on inventory art all the time, not just on hover.
var always_show_sockets: bool = false

## Each entry is a resource_path String or a Dictionary
## (ItemSerializer.to_dict(), for rolled items with no path). Written by
## InventoryScreen via sync_equipment(), applied by Player._ready().
## Weapon-set slots are NOT in here - see weapon_set_refs below.
var equipment_refs: Array = DEFAULT_EQUIPMENT_PATHS.duplicate()

## Per-set primary/offhand refs, same shape as equipment_refs. Stored by
## index because an item can't tell which set it belongs to. Any weapon
## equip change must call sync_weapon_sets(), not just sync_equipment().
var weapon_set_refs: Array = [DEFAULT_WEAPON_SET_0_PATHS.duplicate(), []]
var active_weapon_set: int = 0

## Slot index = the ability_N hotkey; "" marks an empty slot.
var ability_loadout_paths: Array[String] = DEFAULT_ABILITY_LOADOUT_PATHS.duplicate()

## ability_id -> rank, for every ability ever upgraded.
var ability_levels: Dictionary = {}

var player_level: int = 1
var player_xp: float = 0.0

## Each level above 1 grants this much of every stat (derived, not saved).
const STAT_GAIN_PER_LEVEL := 0.6

func get_level_stat_bonus() -> float:
	return (player_level - 1) * STAT_GAIN_PER_LEVEL

## Footprint-grid carried inventory and Hub stash (Rev2). Holds every
## unequipped item, unplaced Slate and crafting currency the player owns;
## equipped gear lives on EquipmentComponent and placed Slates on the Fate Board.
var inventory: GridInventory = GridInventory.new()
var stash: Stash = Stash.create_default()

## Fate Board layout, kept current by sync_fate_board() and restored by
## Player on every scene load. Each entry: {"slate_ref": String resource_path (hand-authored palette
## Slate) or Dictionary (SlateSerializer data for a rolled drop),
## "origin": [x,y], "rotation_steps": int, "flipped": bool,
## "designated_ability_id": String ("" if none)}.
var fate_board_placements: Array = []

## Dropped by enemies, spent at the Hub's GearShop.
var gold: int = 0

## Behaviors tab (inventory): RMB raises an equipped shield instead of
## entering the weapon stance; which stance page RMB uses.
var shield_on_rmb: bool = true
var stance_page: int = 0

## Ability ids unlocked via SkillTome or SpellTestShop.
var owned_ability_ids: Array[String] = []
## Booming Blade is a toggle that stays on across areas until cast again.
var booming_blade_on: bool = false

## Figment Tree points: one per tier of each completed Figment.
var figment_tree_points: int = 0
## Unlocked FigmentTreeNode.node_ids.
var figment_tree_unlocked_nodes: Array[String] = []

func _ready() -> void:
	EventBus.figment_completed.connect(_on_figment_completed)
	EventBus.player_died.connect(_on_player_died)

func _on_figment_completed(figment: FigmentItem) -> void:
	figment_tree_points += figment.tier if figment else 1

func sync_equipment(equipment: EquipmentComponent) -> void:
	equipment_refs = equipment.get_all_equipped_refs()

func sync_weapon_sets(equipment: EquipmentComponent) -> void:
	weapon_set_refs = [equipment.get_weapon_set_refs(0), equipment.get_weapon_set_refs(1)]
	active_weapon_set = equipment.active_weapon_set

func sync_ability_loadout(loadout: AbilityLoadoutComponent) -> void:
	ability_loadout_paths = loadout.get_all_paths()

## Called by FateBoard on every placement change. Palette Slates are saved
## by path; rolled drops in full, since they're no longer in the inventory.
func sync_fate_board(board: FateBoard) -> void:
	var data := []
	for placement_id in board.placements:
		var p: FateBoard.PlacedSlateData = board.placements[placement_id]
		var slate_ref
		if p.slate.resource_path != "":
			slate_ref = p.slate.resource_path
		else:
			slate_ref = SlateSerializer.to_dict(p.slate)
		data.append({
			"slate_ref": slate_ref,
			"origin": [p.origin.x, p.origin.y],
			"rotation_steps": p.rotation_steps,
			"flipped": p.flipped,
			"designated_ability_id": p.designated_ability_id,
			"aether_paid": p.aether_paid,
		})
	fate_board_placements = data

func reset_to_defaults() -> void:
	equipment_refs = DEFAULT_EQUIPMENT_PATHS.duplicate()
	weapon_set_refs = [DEFAULT_WEAPON_SET_0_PATHS.duplicate(), []]
	active_weapon_set = 0
	ability_loadout_paths = DEFAULT_ABILITY_LOADOUT_PATHS.duplicate()
	ability_levels = {}
	owned_ability_ids = []
	booming_blade_on = false
	_reset_all_ability_levels()
	player_level = 1
	player_xp = 0.0
	fate_board_placements = []
	inventory = GridInventory.new()
	stash = Stash.create_default()
	gold = 0
	figment_tree_points = 0
	figment_tree_unlocked_nodes = []
	shield_on_rmb = true
	stance_page = 0
	portal_map_state = {}
	portals_opened = 0
	returning_through_portal = false
	AmmoInventory.reset()

## Called when a map scene launches without going through the main menu.
## Sets enough state for the scene to function without a full new_game() call.
## active_map stays null - map scenes that need it set it themselves.
func initialize_standalone() -> void:
	if game_started:
		return
	player_level = 5
	gold = 0
	game_started = true

## Scans the whole instances directory (not a fixed list) since a Tome-
## found ability from a previous session still needs its level reset.
func _reset_all_ability_levels() -> void:
	var dir_path := "res://data/abilities/instances/"
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next().trim_suffix(".remap")
	while file_name != "":
		if file_name.ends_with(".tres"):
			var ability: Ability = load(dir_path + file_name) as Ability
			if ability:
				ability.level = 1
		file_name = dir.get_next().trim_suffix(".remap")
	dir.list_dir_end()

## Set by RealityEngine.gd right before loading MAP_SCENE - Enemy.gd reads
## this to scale itself. Null means no modifiers (e.g. TestArena).
var active_map: FigmentItem = null

## Adds to the carried inventory; false if it (or some of a currency
## stack) didn't fit.
func add_to_inventory(content, count: int = 1) -> bool:
	return inventory.add(content, count) == 0

func remove_from_inventory(content) -> bool:
	return inventory.remove_content(content)

## Every non-currency item and Slate in the carried inventory.
func get_inventory_items() -> Array:
	var items := []
	for entry in inventory.get_entries():
		if not entry.is_currency():
			items.append(entry.content)
	return items

## The map left through a portal (GeneratedMap.capture_state()), restored
## when the player takes the Hub's return portal. Empty when no run is
## open. Saved, so a run survives quitting from the Hub.
var portal_map_state: Dictionary = {}
var portals_opened: int = 0
## Set by the Hub return portal just before loading MAP_SCENE.
var returning_through_portal: bool = false
## Pinnacle boss id the arena should spawn (set by Pinnacle.enter()).
var pending_pinnacle: String = ""

func _on_player_died() -> void:
	portal_map_state = {}
