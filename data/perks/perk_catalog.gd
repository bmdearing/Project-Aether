extends RefCounted
class_name PerkCatalog
## Monster Infrequent perks: behaviour an item can only get by dropping from
## one of the perk's source enemies (EnemyDefinition file names). Each perk
## rolls one number in [min, max] ("%d" in its text). PerkEffects runs them.
## Names and numbers are placeholders.

const S := Constants.EquipmentSlot

## kinds: optional weapon kinds ("melee", "ranged", "throwing", "conduit").
const PERKS := {
	&"reload_on_kill": {"name": "Brigand's Haste", "text": "Kills have a %d%% chance to fully reload your weapon", "min": 15.0, "max": 25.0,
		"slots": [S.PRIMARY_WEAPON], "kinds": ["ranged"], "sources": ["unchartered_brigand"]},
	&"opening_strike": {"name": "Cutthroat's Patience", "text": "Your first hit after 2 seconds without attacking deals %d%% more damage", "min": 40.0, "max": 60.0,
		"slots": [S.GLOVES], "sources": ["unchartered_cutthroat"]},
	&"ricochet": {"name": "Javelineer's Ricochet", "text": "Thrown weapon hits ricochet to a nearby enemy for %d%% of the damage", "min": 40.0, "max": 60.0,
		"slots": [S.PRIMARY_WEAPON], "kinds": ["throwing"], "sources": ["unchartered_javelineer"]},
	&"heavy_knockback": {"name": "Enforcer's Weight", "text": "Heavy and charged melee hits knock enemies back and deal %d%% more damage", "min": 10.0, "max": 20.0,
		"slots": [S.PRIMARY_WEAPON], "kinds": ["melee"], "sources": ["unchartered_enforcer"]},
	&"elite_battle_cry": {"name": "Chieftain's Roar", "text": "Killing an Elite or stronger enemy grants %d%% more damage for 6 seconds", "min": 15.0, "max": 25.0,
		"slots": [S.AMULET], "sources": ["unchartered_chieftain"]},
	&"last_round": {"name": "Soldier's Last Round", "text": "The last round in your magazine deals %d%% more damage", "min": 60.0, "max": 100.0,
		"slots": [S.PRIMARY_WEAPON], "kinds": ["ranged"], "sources": ["directorate_soldier"]},
	&"adjudicator_mark": {"name": "Adjudicator's Mark", "text": "Weapon hits Mark enemies; your spells deal %d%% more damage to Marked enemies, consuming the Mark", "min": 20.0, "max": 35.0,
		"slots": [S.GLOVES], "sources": ["directorate_adjudicator"]},
	&"block_shockwave": {"name": "Dreadknight's Rebuke", "text": "Blocking releases a shockwave that knocks back nearby enemies and deals %d%% of your Armour as Kinetic damage", "min": 4.0, "max": 8.0,
		"slots": [S.OFFHAND], "kinds": ["shield"], "sources": ["legion_dreadknight"]},
	&"landing_strike": {"name": "Threshold Landing", "text": "Landing from a jump or a fall deals %d%% of your maximum Life as Kinetic damage around you", "min": 15.0, "max": 25.0,
		"slots": [S.BOOTS], "sources": ["legion_threshold_knight"]},
	&"ember_trail": {"name": "Ember Stride", "text": "While sprinting, you Ignite enemies near you as if hit for %d%% of your maximum Life", "min": 10.0, "max": 20.0,
		"slots": [S.BOOTS], "sources": ["synod_ember_golem"]},
	&"free_spell": {"name": "Aether Golem's Core", "text": "Every %dth spell you cast costs no Mana", "min": 6.0, "max": 4.0,
		"slots": [S.AMULET], "sources": ["synod_aether_golem"]},
	&"big_hit_ward": {"name": "Warden's Bulwark", "text": "When a hit takes more than 20%% of your Life, gain Ward equal to %d%% of it", "min": 30.0, "max": 50.0,
		"slots": [S.BODY_ARMOUR], "sources": ["synod_warden_golem"]},
	&"airborne_mana": {"name": "Exarch's Ascent", "text": "Kills while airborne restore %d Mana", "min": 8.0, "max": 15.0,
		"slots": [S.AMULET], "sources": ["synod_exarch"]},
	&"ignite_spread": {"name": "Vindicator's Pyre", "text": "Melee hits on Ignited enemies spread Ignite to a nearby enemy for %d%% of the hit", "min": 60.0, "max": 100.0,
		"slots": [S.PRIMARY_WEAPON], "kinds": ["melee"], "sources": ["synod_vindicator"]},
	&"curse_spread": {"name": "Cantor's Refrain", "text": "When a Cursed enemy dies, its Curses spread to a nearby enemy at %d%% strength", "min": 70.0, "max": 100.0,
		"slots": [S.GLOVES], "sources": ["veilborne_cantor"]},
	&"control_burst": {"name": "Mindbender's Collapse", "text": "Enemies killed while Chilled, Shocked, Electrocuted, Unraveling or Pallid explode for %d%% of their maximum Life as Aetheric damage", "min": 5.0, "max": 10.0,
		"slots": [S.HELMET], "sources": ["veilborne_mindbender"]},
	&"hollow_life": {"name": "Shambler's Hunger", "text": "Kills restore %d%% of your maximum Life", "min": 2.0, "max": 4.0,
		"slots": [S.HELMET], "sources": ["hollowed_shambler"]},
	&"element_shift": {"name": "Orb's Rotation", "text": "An elemental hit of a different element than your last deals %d%% more damage", "min": 15.0, "max": 25.0,
		"slots": [S.RING], "sources": ["element_orb"]},
	&"sand_burst": {"name": "Sand Globe's Burst", "text": "Kills release a sand burst that Chills enemies within %d metres", "min": 3.0, "max": 5.0,
		"slots": [S.BELT], "sources": ["sand_globe"]},
	&"ignite_erupt": {"name": "Golem's Eruption", "text": "Fire hits on Ignited enemies erupt for %d%% of the hit to enemies around them", "min": 30.0, "max": 50.0,
		"slots": [S.GLOVES], "sources": ["aurelia_fire_golem"]},
}

static func has(id: StringName) -> bool:
	return PERKS.has(id)

static func name_of(id: StringName) -> String:
	return PERKS.get(id, {}).get("name", String(id))

## The perk's card line with `value` filled in.
static func text_of(id: StringName, value: float) -> String:
	var text: String = PERKS.get(id, {}).get("text", String(id))
	return text % roundi(value) if "%d" in text else text

## Perks the enemy with this definition file name can drop.
static func perks_from(source: String) -> Array[StringName]:
	var result: Array[StringName] = []
	for id in PERKS:
		if (PERKS[id]["sources"] as Array).has(source):
			result.append(id)
	return result

## Display names of a perk's source enemies (from their definitions).
static func source_names(id: StringName) -> Array[String]:
	var names: Array[String] = []
	for source in PERKS.get(id, {}).get("sources", []):
		names.append(MonsterInfrequent.source_display_name(source))
	return names

static func roll_value(id: StringName, rng: RandomNumberGenerator = null) -> float:
	var def: Dictionary = PERKS[id]
	var lo: float = minf(def["min"], def["max"])
	var hi: float = maxf(def["min"], def["max"])
	return float(rng.randi_range(int(lo), int(hi)) if rng else randi_range(int(lo), int(hi)))

## Whether `item` is a base this perk can roll on.
static func fits(id: StringName, item: Item) -> bool:
	var def: Dictionary = PERKS[id]
	if item == null or not item.is_equipment() or item.unique_id != "":
		return false
	if not (def["slots"] as Array).has(int(item.equip_slot)):
		return false
	var kinds: Array = def.get("kinds", [])
	if kinds.is_empty():
		return not item is Weapon or item.equip_slot != S.OFFHAND
	if kinds.has("shield"):
		return item is Shield
	if not item is Weapon:
		return false
	var weapon := item as Weapon
	if kinds.has("throwing") and weapon.is_throwing():
		return true
	return not weapon.is_throwing() and kinds.has(ItemRoller.weapon_kind(weapon))
