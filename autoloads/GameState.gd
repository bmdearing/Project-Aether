extends Node
## Current run/session state, and the live loadout source of truth
## SaveManager.gd serializes to disk - lets equip/ability changes survive
## a Hub<->Map scene reload (Player is a fresh instance every load) as
## well as an app restart.

const HUB_SCENE := "res://levels/hub/Hub.tscn"
const MAP_SCENE := "res://levels/generated_map/GeneratedMap.tscn"
const MAIN_MENU_SCENE := "res://ui/main_menu/MainMenu.tscn"

## worn_pistol.tres isn't a default - it and crude_greatsword both target
## PRIMARY_WEAPON now (see worn_pistol.tres), so listing both would just
## have the second silently replace the first at boot.
const DEFAULT_EQUIPMENT_PATHS: Array[String] = [
	"res://data/weapons/instances/crude_greatsword.tres",
	"res://data/armor/instances/padded_coat.tres",
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
var equipment_refs: Array = DEFAULT_EQUIPMENT_PATHS.duplicate()

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

## Invented currency, no doc-sourced economy exists. Granted on enemy
## death, spent at the Hub's GearShop.
var gold: int = 0

## Ability ids the player has unlocked via SkillTome or SpellTestShop -
## abilities aren't a free "owns one" stand-in anymore.
var owned_ability_ids: Array[String] = []

func sync_equipment(equipment: EquipmentComponent) -> void:
	equipment_refs = equipment.get_all_equipped_refs()

func sync_ability_loadout(loadout: AbilityLoadoutComponent) -> void:
	ability_loadout_paths = loadout.get_all_paths()

func reset_to_defaults() -> void:
	equipment_refs = DEFAULT_EQUIPMENT_PATHS.duplicate()
	ability_loadout_paths = DEFAULT_ABILITY_LOADOUT_PATHS.duplicate()
	ability_ranks = {}
	owned_ability_ids = []
	_reset_all_ability_ranks()
	player_level = 1
	player_xp = 0.0
	owned_loot = []
	owned_slates = []
	gold = 0

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

## Set by MapDevice.gd right before loading MAP_SCENE - Enemy.gd reads
## this to scale itself. Null means no modifiers (e.g. TestArena).
var active_map: MapItem = null
