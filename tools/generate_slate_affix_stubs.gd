extends Node
## One-shot data generator (Patch v3.6 Section 1) - writes 3 placeholder
## SlateAffix.tres stubs per tag into data/slates/affix_pool/, per the
## brief's "stubs only, full pool design is a separate pass" scope. Run
## headlessly via tools/generate_slate_affix_stubs.tscn, not part of the
## game itself.

const OUT_DIR := "res://data/slates/affix_pool/"

const TAGS := [
	"kinetic", "piercing", "explosive", "fire", "cold", "lightning",
	"aetheric", "entropic", "pale", "spell", "attack", "generic",
]

## Three flavor archetypes per tag, matching the brief's own
## "cold_increased_damage" / "Glacial Intensity" example shape. Display
## names are hand-picked per tag below; stat_key/value ranges are
## deliberately simple placeholders, not real design.
const ARCHETYPES := [
	{"suffix": "increased_damage", "stat_key_suffix": "increased_damage", "min": 12.0, "max": 28.0, "is_prefix": true},
	{"suffix": "conditional_surge", "stat_key_suffix": "conditional_surge", "min": 8.0, "max": 20.0, "is_prefix": false},
	{"suffix": "behavior_shift", "stat_key_suffix": "behavior_shift", "min": 1.0, "max": 1.0, "is_prefix": false},
]

const TAG_DISPLAY := {
	"kinetic": "Kinetic", "piercing": "Piercing", "explosive": "Explosive",
	"fire": "Fire", "cold": "Cold", "lightning": "Lightning",
	"aetheric": "Aetheric", "entropic": "Entropic", "pale": "Pale",
	"spell": "Spell", "attack": "Attack", "generic": "Generic",
}

var _count := 0

func _ready() -> void:
	var dir := DirAccess.open("res://data/slates/")
	if dir and not dir.dir_exists("affix_pool"):
		dir.make_dir("affix_pool")

	for tag in TAGS:
		for i in range(ARCHETYPES.size()):
			_write_stub(tag, ARCHETYPES[i])

	print("Wrote %d SlateAffix stubs across %d tags." % [_count, TAGS.size()])
	get_tree().quit()

func _write_stub(tag: String, archetype: Dictionary) -> void:
	var affix := SlateAffix.new()
	affix.tag = tag
	affix.affix_id = "%s_%s" % [tag, archetype["suffix"]]
	affix.stat_key = "%s_%s" % [tag, archetype["stat_key_suffix"]]
	affix.display_name = "%s %s" % [TAG_DISPLAY.get(tag, tag.capitalize()), _flavor_word(archetype["suffix"])]
	affix.description = "%s (stub)" % affix.display_name
	affix.value_min = archetype["min"]
	affix.value_max = archetype["max"]
	affix.value = archetype["min"]
	affix.tier = 1
	affix.is_prefix = archetype["is_prefix"]
	affix.min_item_level = 1
	affix.is_generic = tag in ["spell", "attack", "generic"]
	affix.damage_type = Constants.DAMAGE_TYPE_TAGS.get(tag, -1)
	affix.is_conditional = archetype["suffix"] == "conditional_surge"
	affix.condition_description = "Placeholder condition - not yet designed." if affix.is_conditional else ""
	affix.is_behavior_modifier = archetype["suffix"] == "behavior_shift"

	var path := "%s%s.tres" % [OUT_DIR, affix.affix_id]
	if ResourceSaver.save(affix, path) == OK:
		_count += 1
	else:
		push_error("Failed to save %s" % path)

func _flavor_word(suffix: String) -> String:
	match suffix:
		"increased_damage": return "Intensity"
		"conditional_surge": return "Surge"
		"behavior_shift": return "Shift"
	return suffix.capitalize()
