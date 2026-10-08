extends SceneTree
## Generates the Greataxe base line (data/weapons/instances/gen_greataxe_*.tres)
## from the Claymore line's tiers: same item levels, requirements and
## sockets, ~10% more damage per hit for the slower swing.
## Run: godot --headless --path . --script res://tools/generate_greataxe_line.gd

const DIR := "res://data/weapons/instances/"
const DAMAGE_SCALE := 1.1
const NAMES := {
	"crude_claymore": "Crude Greataxe", "heavy_claymore": "Heavy Greataxe", "battle_claymore": "Battle Axe",
	"war_claymore": "War Axe", "breaker_claymore": "Breaker Axe", "crushing_claymore": "Splitting Axe",
	"sunder_claymore": "Sundering Axe", "ruin_claymore": "Ruin Axe", "colossus_claymore": "Colossus Axe",
	"titans_claymore": "Titan's Axe", "warlords_claymore": "Warlord's Axe", "devastators_claymore": "Devastator's Axe",
	"annihilator": "Headsman's Axe", "obliterator": "Worldcleaver", "cataclysm": "Cataclysm Axe",
}

func _init() -> void:
	var made := 0
	for file in DirAccess.get_files_at(DIR):
		if not file.begins_with("gen_claymore_") or not file.ends_with(".tres"):
			continue
		var key := file.trim_prefix("gen_claymore_").trim_suffix(".tres")
		var source := load(DIR + file) as Weapon
		var axe := source.duplicate(true) as Weapon
		axe.weapon_type = "Greataxe"
		axe.display_name = NAMES.get(key, source.display_name.replace("Claymore", "Greataxe"))
		var id := axe.display_name.to_snake_case().replace("'", "")
		axe.item_id = "gen_greataxe_" + id
		axe.base_line_id = source.base_line_id.replace("claymore", "greataxe")
		axe.base_damage_min = roundf(source.base_damage_min * DAMAGE_SCALE)
		axe.base_damage_max = roundf(source.base_damage_max * DAMAGE_SCALE)
		axe.flavor_text = "Heavy Cleave"
		ResourceSaver.save(axe, DIR + axe.item_id + ".tres")
		made += 1
	print("generated %d greataxe bases" % made)
	quit()
