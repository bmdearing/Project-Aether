extends RefCounted
class_name EnemyRoster
## Builds roster units (MeleeUnit/RangedUnit + an EnemyDefinition) and rolls
## packs from the Constants.ENEMY_PACKS_* tables.

const DEFINITION_DIR := "res://data/enemies/definitions/"
const MELEE_UNIT_SCENE := preload("res://entities/enemies/units/MeleeUnit.tscn")
const RANGED_UNIT_SCENE := preload("res://entities/enemies/units/RangedUnit.tscn")

static func load_definition(unit_id: String) -> EnemyDefinition:
	return load(DEFINITION_DIR + unit_id + ".tres") as EnemyDefinition

## Not yet in the tree: definition is set here, before add_child(), because
## Enemy._apply_definition() runs in _ready().
static func create_unit(unit_id: String) -> Enemy:
	var definition := load_definition(unit_id)
	var scene: PackedScene = RANGED_UNIT_SCENE if definition.is_ranged else MELEE_UNIT_SCENE
	var enemy := scene.instantiate() as Enemy
	enemy.definition = definition
	enemy.name = unit_id.to_pascal_case()
	return enemy

## Weighted pick of one pack, expanded to unit ids. Each pack entry is
## [unit_id or Array of unit_ids, min, max]; an Array picks a random id per unit.
static func roll_pack(table: Array) -> Array[String]:
	var total := 0.0
	for pack in table:
		total += float(pack["weight"])
	var roll := randf() * total
	var chosen: Dictionary = table[-1]
	for pack in table:
		roll -= float(pack["weight"])
		if roll <= 0.0:
			chosen = pack
			break
	var ids: Array[String] = []
	for entry in chosen["units"]:
		var count := randi_range(int(entry[1]), int(entry[2]))
		for i in count:
			ids.append(String(entry[0].pick_random() if entry[0] is Array else entry[0]))
	return ids
