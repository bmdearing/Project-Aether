extends Item
class_name SkillTome
## A lootable item that unlocks an Ability. Picking one up adds the
## referenced ability to GameState.owned_ability_ids (see LootPickup.gd),
## making it selectable in AbilitiesScreen - just the acquisition half,
## not the doc's literal "socketed into weapon slots" mechanic (no socket
## system exists yet). equip_slot is meaningless here, same as MapItem.gd.

@export var ability_id: String
@export var ability_path: String
