extends Node
## Current run/session state, and the live loadout source of truth
## SaveManager.gd serializes to disk - lets equip/ability changes survive
## a Hub<->Map scene reload (Player is a fresh instance every load) as
## well as an app restart.

const HUB_SCENE := "res://levels/hub/Hub.tscn"
const MAP_SCENE := "res://levels/generated_map/GeneratedMap.tscn"
const MAIN_MENU_SCENE := "res://ui/main_menu/MainMenu.tscn"

## Non-weapon defaults only - weapon-set slots (PRIMARY_WEAPON/OFFHAND)
## moved to DEFAULT_WEAPON_SET_0_PATHS below as of the dual weapon-set
## system (2026-08-31, Implementation Brief v3.4 Section 4, user-expanded
## scope), since equipment_refs/get_all_equipped_refs() no longer cover
## weapon slots at all - see EquipmentComponent.WEAPON_SET_SLOTS.
const DEFAULT_EQUIPMENT_PATHS: Array[String] = [
	"res://data/armor/instances/padded_coat.tres",
]
## worn_pistol.tres isn't a default - it and crude_greatsword both target
## PRIMARY_WEAPON (see worn_pistol.tres), so listing both would just have
## the second silently replace the first at boot. Only weapon SET 0 gets
## a starting weapon; set 1 starts empty.
const DEFAULT_WEAPON_SET_0_PATHS: Array[String] = [
	"res://data/weapons/instances/crude_greatsword.tres",
]
## Abilities aren't free-equipped by default - found via SkillTome drops
## or the Hub's SpellTestShop. Fixed-length-4 (not `[]`) since slot index
## = the ability_N hotkey.
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

## Each entry is a resource_path String or a Dictionary
## (ItemSerializer.to_dict(), for rolled items with no path). Written by
## InventoryScreen via sync_equipment(), applied by Player._ready().
## Weapon-set slots are NOT in here - see weapon_set_refs below.
var equipment_refs: Array = DEFAULT_EQUIPMENT_PATHS.duplicate()

## Two weapon sets (Implementation Brief v3.4 Section 4, user-expanded
## scope) - weapon_set_refs[0]/[1], each the same ref-array shape
## equipment_refs uses, but scoped to just that set's own primary/
## offhand (EquipmentComponent.get_weapon_set_refs()). Restored
## explicitly by index in Player._apply_saved_loadout() rather than
## folded into the generic equipment_refs loop, since which SET an item
## belongs to isn't recoverable from the item itself the way which SLOT
## it belongs to is.
##
## Patch v3.8b bug fix: InventoryScreen's equip/unequip handlers used to
## call sync_equipment() only, never sync_weapon_sets() - get_all_
## equipped_refs() (which feeds sync_equipment()) deliberately EXCLUDES
## primary_weapon/offhand (see its own comment), so equipping a new
## weapon into the already-active set never touched this array. It stayed
## stale until the player explicitly toggled sets, so the next zone
## transition's _apply_saved_loadout() re-equipped the OLD weapon - the
## real cause of "weapon sets not persisting between zones." Both
## InventoryScreen handlers now call sync_weapon_sets() too.
var weapon_set_refs: Array = [DEFAULT_WEAPON_SET_0_PATHS.duplicate(), []]
var active_weapon_set: int = 0

## Slot index = the ability_N hotkey; "" marks an empty slot.
var ability_loadout_paths: Array[String] = DEFAULT_ABILITY_LOADOUT_PATHS.duplicate()

## ability_id -> rank, for every ability ever upgraded.
var ability_ranks: Dictionary = {}

var player_level: int = 1
var player_xp: float = 0.0

## Rolled loot picked up this session - persisted by SaveManager via
## ItemSerializer (full data, since rolled items have no resource_path).
var owned_loot: Array[Item] = []

## Rolled Slates picked up this session (SlateRoller drops) - persisted
## by SaveManager via SlateSerializer, same full-data rationale as
## owned_loot. The 2 hand-authored data/slates/instances/ samples are
## still always-available in FateBoardEditor's palette on top of these -
## this array is additive, not a replacement for that starter pool.
var owned_slates: Array[Slate] = []

## Fate Board LAYOUT - which Slate sits where, plus its designated ability
## for Spell Slates (see Slate.requires_spell_designation). User-reported
## bug fix (2026-08-30): "Slates do not persist between scenes, they need
## to stay on the character" - Player is a fresh instance every Hub<->Map
## reload (see header), and FateBoard used to be recreated empty every
## time (Player._ready() unconditionally did `fate_board = FateBoard.new()`
## with nothing to restore it from). This is now that restore source,
## rebuilt live by FateBoard.place_slate()/remove_slate() calling
## sync_fate_board() on every change, and persisted by SaveManager the
## same as everything else here - the older "only ownership persists, not
## layout" design note in SaveManager.gd is superseded by this.
## Each entry: {"slate_ref": String resource_path (hand-authored palette
## Slate) or int (index into owned_slates, a rolled single-use drop),
## "origin": [x,y], "rotation_steps": int, "flipped": bool,
## "designated_ability_id": String ("" if none)}.
var fate_board_placements: Array = []

## Invented currency, no doc-sourced economy exists. Granted on enemy
## death, spent at the Hub's GearShop.
var gold: int = 0

## Ability ids the player has unlocked via SkillTome or SpellTestShop -
## abilities aren't a free "owns one" stand-in anymore.
var owned_ability_ids: Array[String] = []

## Figment Tree (user request: "prepare legs for a Figment Tree to
## complete figments to get points, increasing the yield and type of
## content seen on Figments" - scaffolding only, see systems/figment_tree/
## FigmentTree.gd for what that means exactly. Earned by completing a
## Figment (its boss's death - EventBus.figment_completed), 1 point per
## Figment tier (invented, no design brief given for the exact rate).
var figment_tree_points: int = 0
## node_id's this session has unlocked (FigmentTreeNode.node_id) - the
## nodes themselves are hand-authored, not persisted; only which ones
## are unlocked needs saving.
var figment_tree_unlocked_nodes: Array[String] = []

func _ready() -> void:
	EventBus.figment_completed.connect(_on_figment_completed)

func _on_figment_completed(figment: FigmentItem) -> void:
	figment_tree_points += figment.tier if figment else 1

func sync_equipment(equipment: EquipmentComponent) -> void:
	equipment_refs = equipment.get_all_equipped_refs()

func sync_weapon_sets(equipment: EquipmentComponent) -> void:
	weapon_set_refs = [equipment.get_weapon_set_refs(0), equipment.get_weapon_set_refs(1)]
	active_weapon_set = equipment.active_weapon_set

func sync_ability_loadout(loadout: AbilityLoadoutComponent) -> void:
	ability_loadout_paths = loadout.get_all_paths()

## Called by FateBoard itself on every place_slate()/remove_slate() -
## snapshots its live placements into fate_board_placements so they
## survive the next scene reload/save. A palette Slate (loaded from
## data/slates/instances/) keeps its resource_path; a rolled owned_slates
## drop has none, so it's referenced by array index instead - preserves
## the same object identity FateBoardEditor's single-use-ownership check
## (_is_slate_available()) already relies on, rather than reconstructing
## a duplicate Slate that would silently double an owned copy.
func sync_fate_board(board: FateBoard) -> void:
	var data := []
	for placement_id in board.placements:
		var p: FateBoard.PlacedSlateData = board.placements[placement_id]
		var slate_ref
		if p.slate.resource_path != "":
			slate_ref = p.slate.resource_path
		else:
			var idx := owned_slates.find(p.slate)
			if idx == -1:
				continue  # a placed Slate is always either palette or owned - shouldn't happen
			slate_ref = idx
		data.append({
			"slate_ref": slate_ref,
			"origin": [p.origin.x, p.origin.y],
			"rotation_steps": p.rotation_steps,
			"flipped": p.flipped,
			"designated_ability_id": p.designated_ability_id,
		})
	fate_board_placements = data

func reset_to_defaults() -> void:
	equipment_refs = DEFAULT_EQUIPMENT_PATHS.duplicate()
	weapon_set_refs = [DEFAULT_WEAPON_SET_0_PATHS.duplicate(), []]
	active_weapon_set = 0
	ability_loadout_paths = DEFAULT_ABILITY_LOADOUT_PATHS.duplicate()
	ability_ranks = {}
	owned_ability_ids = []
	_reset_all_ability_ranks()
	player_level = 1
	player_xp = 0.0
	owned_loot = []
	owned_slates = []
	fate_board_placements = []
	gold = 1000000  # Patch v3.8c, user request - dev/testing convenience
	figment_tree_points = 0
	figment_tree_unlocked_nodes = []
	AmmoInventory.reset()

## Called when a map scene launches without going through the main menu.
## Sets enough state for the scene to function without a full new_game() call.
## active_map stays null - map scenes that need it set it themselves.
func initialize_standalone() -> void:
	if game_started:
		return
	player_level = 5
	gold = 1000000
	game_started = true

## Scans the whole instances directory (not a fixed list) since a Tome-
## found ability from a previous session still needs its rank reset.
func _reset_all_ability_ranks() -> void:
	var dir_path := "res://data/abilities/instances/"
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var ability: Ability = load(dir_path + file_name) as Ability
			if ability:
				ability.rank = 0
		file_name = dir.get_next()
	dir.list_dir_end()

## Set by RealityEngine.gd right before loading MAP_SCENE - Enemy.gd reads
## this to scale itself. Null means no modifiers (e.g. TestArena).
var active_map: FigmentItem = null
