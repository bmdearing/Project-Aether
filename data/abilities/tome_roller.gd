extends RefCounted
class_name TomeRoller
## Rolls a SkillTome for a random ability the player doesn't already own
## (see GameState.owned_ability_ids) - dropped by Enemy.gd on death,
## same LootPickup.gd flow as regular gear. No pre-authored Tome .tres
## files exist; a Tome is fully synthesized here from whichever real
## Ability the roll picks (display_name/flavor_text mirror the ability's
## own), since its only job is to reference that ability, not carry any
## independent stats of its own.

const ABILITY_DIR := "res://data/abilities/instances/"

## [ability_id, path] for every ability, read once (scanning and loading
## the folder on every roll cost ~8 ms per kill).
static var _all: Array = []

static func _abilities() -> Array:
	if _all.is_empty():
		for f in DirAccess.get_files_at(ABILITY_DIR):
			f = f.trim_suffix(".remap")
			if f.ends_with(".tres"):
				var ability := load(ABILITY_DIR + f) as Ability
				if ability:
					_all.append([ability.ability_id, ABILITY_DIR + f])
	return _all

static func roll_for_unowned(owned_ability_ids: Array) -> SkillTome:
	var candidates: Array[String] = []
	for pair: Array in _abilities():
		if not owned_ability_ids.has(pair[0]):
			candidates.append(pair[1])
	if candidates.is_empty():
		return null

	var path: String = candidates[randi() % candidates.size()]
	var ability: Ability = load(path)
	var tome := SkillTome.new()
	tome.item_id = "tome_%s_%d" % [ability.ability_id, randi()]
	tome.display_name = "Tome of %s" % ability.display_name
	tome.rarity = Constants.ItemRarity.RARE
	tome.flavor_text = ability.description
	tome.ability_id = ability.ability_id
	tome.ability_path = path
	return tome
