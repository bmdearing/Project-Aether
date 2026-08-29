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

static func roll_for_unowned(owned_ability_ids: Array) -> SkillTome:
	var candidates: Array[String] = []
	var dir := DirAccess.open(ABILITY_DIR)
	if dir == null:
		return null
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var ability: Ability = load(ABILITY_DIR + file_name) as Ability
			if ability and not owned_ability_ids.has(ability.ability_id):
				candidates.append(ABILITY_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
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
