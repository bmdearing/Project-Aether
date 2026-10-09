extends VBoxContainer
class_name LensWiki
## Wiki page: Lenses. Their sizes, every radius modifier (one per Lens) and
## the jewel modifiers they can roll, with each tier's range. Read from
## LensRoller and JewelModifierPool, so it can't drift from the drops.

const WIDTH := 980.0
const LIST_HEIGHT := 590.0
const RADIUS_COLOR := Color(0.55, 0.9, 0.85)

## Radius modifier ids in the order shown, for tests.
var shown: Array[String] = []

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(WIDTH, 0)
	var intro := ModifierWiki._text("Lenses go into Slate sockets (in the inventory, or straight onto a placed Slate on the Fate Board). Each has one radius modifier that changes the Slates around its host, and jewel modifiers that count as yours while the host is placed. Orbs craft them like Jewels.", 13, ModifierWiki.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	list.add_child(ModifierWiki._text("Sizes", 18, AetherStyle.GOLD))
	var total := 0
	for r in LensRoller.RADIUS_WEIGHTS:
		total += LensRoller.RADIUS_WEIGHTS[r]
	for r in LensRoller.RADIUS_WEIGHTS:
		list.add_child(ModifierWiki._text("%s Lens: radius %d tiles (%d%% of drops)" % [Lens.SIZE_NAMES.get(r, "?"), r, roundi(100.0 * LensRoller.RADIUS_WEIGHTS[r] / total)], 14, AetherStyle.TEXT))

	list.add_child(ModifierWiki._text("Radius modifiers (one per Lens)", 18, RADIUS_COLOR))
	for id in LensRoller.RADIUS_MODS:
		var def: Dictionary = LensRoller.RADIUS_MODS[id]
		var text := String(def["text"]).replace("{tag}", "<Damage type>")
		if def["min"] != def["max"]:
			text = text.replace("{v}", "(%d-%d)" % [def["min"], def["max"]])
		else:
			text = text.replace("{v}", str(int(def["min"])))
		shown.append(id)
		list.add_child(ModifierWiki._text("  " + text, 14, RADIUS_COLOR.lightened(0.2)))

	var counts := PackedStringArray()
	for rarity in LensRoller.JEWEL_MODS_BY_RARITY:
		counts.append("%s %d" % [Constants.ItemRarity.keys()[rarity].capitalize(), LensRoller.JEWEL_MODS_BY_RARITY[rarity]])
	list.add_child(ModifierWiki._text("Jewel modifiers (%s)" % ", ".join(counts), 18, AetherStyle.GOLD))
	var tier_note := ModifierWiki._text("Tier 3 from item level 1, Tier 2 from 41, Tier 1 from 80.", 13, ModifierWiki.MUTED)
	list.add_child(tier_note)
	var probe := Lens.new()
	probe.item_level = 100
	for def in JewelModifierPool.defs_for(probe):
		var ranges := PackedStringArray()
		for tier in def.tiers:
			ranges.append("T%d %s-%s" % [tier.tier, _num(tier.value_min), _num(tier.value_max)])
		var row := HBoxContainer.new()
		var name_label := ModifierWiki._text("  " + def.text.replace("%d", "#").replace("%%", "%"), 14, AetherStyle.MOD_BLUE)
		name_label.custom_minimum_size = Vector2(520, 0)
		row.add_child(name_label)
		row.add_child(ModifierWiki._text("   ".join(ranges), 13, AetherStyle.TEXT_DIM))
		list.add_child(row)

static func _num(v: float) -> String:
	return str(int(round(v))) if is_equal_approx(v, round(v)) else "%.1f" % v
