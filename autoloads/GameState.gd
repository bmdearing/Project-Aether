extends Node
## Holds current run/session state, and doubles as the live loadout
## source of truth SaveManager.gd serializes to disk. "Session" fields
## below (equipment_paths/ability_loadout_paths/ability_ranks) matter for
## TWO separate reasons: they let equip/ability changes survive a
## Hub<->Map scene reload WITHIN one run (Player is a fresh instance every
## scene load - without this, gear/abilities silently reset to
## DEFAULT_EQUIPMENT_PATHS/DEFAULT_ABILITY_LOADOUT_PATHS on every
## transition, which was true and unnoticed until SaveManager was added),
## and they're exactly what gets written to/read from the save file for
## persistence ACROSS app restarts. Vertical slice scope only - Fate
## Board layout and current Health/Ward/Mana are still not part of this
## (see SaveManager.gd's header for the full deferred list).

const HUB_SCENE := "res://levels/hub/Hub.tscn"
const MAP_SCENE := "res://levels/test_arena/TestArena.tscn"  # the one map that exists so far - see README
const MAIN_MENU_SCENE := "res://ui/main_menu/MainMenu.tscn"

## worn_pistol.tres (Sidearm) is deliberately NOT included here, even
## though earlier README notes described it as equipped by default -
## found while wiring save/load: Player.tscn used to set primary_weapon/
## sidearm_weapon as raw static .tscn properties, which silently bypassed
## EquipmentComponent.equip()'s two-handed rule (a two-handed primary is
## supposed to clear the sidearm/offhand). Now that the default loadout
## is applied via the real equip() call (needed so save/load and
## Hub<->Map persistence go through one consistent path), that rule is
## correctly enforced, and crude_greatsword (two-handed) genuinely
## conflicts with also having a Sidearm equipped - equip() rejects it.
## This matches the precedent already set for guardians_kite_shield.tres,
## which was excluded from the original defaults for the identical
## reason ("would be a no-op with a 2H weapon"). worn_pistol.tres is
## still equippable via Inventory (after unequipping the 2H primary).
const DEFAULT_EQUIPMENT_PATHS: Array[String] = [
	"res://data/weapons/instances/crude_greatsword.tres",
	"res://data/armor/instances/padded_coat.tres",
]
const DEFAULT_ABILITY_LOADOUT_PATHS: Array[String] = [
	"res://data/abilities/instances/ice_pulse.tres",
	"res://data/abilities/instances/comet.tres",
	"res://data/abilities/instances/winters_eye.tres",
	"res://data/abilities/instances/frost_armor.tres",
]

var player_stat_sheet: Resource # StatSheet, assigned at runtime by Player.gd
var fate_board: Resource        # FateBoard, assigned at runtime
var player_equipment: Node      # EquipmentComponent, assigned at runtime by Player.gd

var debug_overlay_enabled: bool = true

## True once "New Game"/"Continue Game" has been used. Gates MainMenu's
## "Continue Game" button (alongside SaveManager.has_save()) and whether
## SaveManager.save_game() is a no-op.
var game_started: bool = false

## Settings - engine-level effects (AudioServer bus volume, window mode)
## apply immediately and don't need storing to take effect this session,
## but SettingsPanel needs a value to show when reopened, and Player needs
## somewhere to read mouse_sensitivity from since it's spawned fresh in
## every scene (Hub, Map) rather than persisting across scene changes.
var mouse_sensitivity: float = 0.0035
var master_volume: float = 1.0
var fullscreen: bool = false

## Resource paths for whatever is currently equipped - order-independent
## (each Item self-routes to its slot via item.equip_slot, see
## EquipmentComponent.equip()), written by InventoryScreen after every
## equip/unequip via sync_equipment(), read by Player.gd at _ready() to
## actually apply the loadout.
var equipment_paths: Array[String] = DEFAULT_EQUIPMENT_PATHS.duplicate()

## Resource paths for the 4 ability-bar slots - order DOES matter here
## (slot index = ability_N hotkey), "" marks an empty slot. Written by
## AbilitiesScreen after every equip/unequip via sync_ability_loadout().
var ability_loadout_paths: Array[String] = DEFAULT_ABILITY_LOADOUT_PATHS.duplicate()

## ability_id -> rank, for every ability that's ever been upgraded
## (not just currently-equipped ones). Written by AbilitiesScreen's
## Upgrade button; applied by Player.gd at _ready() by re-scanning
## data/abilities/instances/ and matching on ability_id (same directory-
## scan pattern AbilitiesScreen itself uses), not by assuming filename
## matches ability_id.
var ability_ranks: Dictionary = {}

func sync_equipment(equipment: EquipmentComponent) -> void:
	equipment_paths = equipment.get_all_equipped_paths()

func sync_ability_loadout(loadout: AbilityLoadoutComponent) -> void:
	ability_loadout_paths = loadout.get_all_paths()

## Used by MainMenu's "New Game" - explicitly resets the live loadout
## (and every known Ability resource's rank) back to the starting state,
## distinguishing a fresh start from Continue (which just leaves whatever
## SaveManager.load_game() already populated at boot untouched).
func reset_to_defaults() -> void:
	equipment_paths = DEFAULT_EQUIPMENT_PATHS.duplicate()
	ability_loadout_paths = DEFAULT_ABILITY_LOADOUT_PATHS.duplicate()
	ability_ranks = {}
	for path in DEFAULT_ABILITY_LOADOUT_PATHS:
		var ability: Ability = load(path)
		if ability:
			ability.rank = 0

## Set by MapDevice.gd (MapRoller.roll()) right before loading MAP_SCENE -
## Enemy.gd reads this to scale itself. Null means "no map modifiers,"
## which TestArena should still handle gracefully (e.g. opened directly
## from the editor rather than via the Hub's Map Device).
var active_map: MapItem = null
