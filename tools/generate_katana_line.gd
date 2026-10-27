extends SceneTree
## Generates the Katana base line (data/weapons/instances/gen_katana_*.tres)
## from the Saber's Physical Damage line (saber_line1): same item levels,
## requirements and sockets, ~10% more damage per hit for the slower swing.
## Run: godot --headless --path . --script res://tools/generate_katana_line.gd

const DIR := "res://data/weapons/instances/"
const DAMAGE_SCALE := 1.1
const NAMES := {
	"worn_saber": "Worn Katana", "light_saber": "Uchigatana", "battle_saber": "Battle Katana",
	"war_saber": "War Katana", "cavalry_saber": "Tachi", "officers_saber": "Ronin's Katana",
	"commanders_saber": "Kensei's Katana", "warlords_saber": "Shogun's Katana", "conquerors_saber": "Moonlit Katana",
}

func _init() -> void:
	var made := 0
	for file in DirAccess.get_files_at(DIR):
		if not file.begins_with("gen_saber_") or not file.ends_with(".tres"):
			continue
		var source := load(DIR + file) as Weapon
		if source == null or source.base_line_id != "saber_line1":
			continue
		var key := file.trim_prefix("gen_saber_").trim_suffix(".tres")
		var katana := source.duplicate(true) as Weapon
		katana.weapon_type = "Katana"
		katana.display_name = NAMES.get(key, source.display_name.replace("Saber", "Katana"))
		katana.item_id = "gen_katana_" + katana.display_name.to_snake_case().replace("'", "")
		katana.base_line_id = "katana_line1"
		katana.base_damage_min = roundf(source.base_damage_min * DAMAGE_SCALE)
		katana.base_damage_max = roundf(source.base_damage_max * DAMAGE_SCALE)
		katana.flavor_text = "Hidden Strike"
		ResourceSaver.save(katana, DIR + katana.item_id + ".tres")
		made += 1
	print("generated %d katana bases" % made)
	quit()
