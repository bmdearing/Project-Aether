extends VBoxContainer
class_name MonsterInfrequentWiki
## Wiki page: every Monster Infrequent perk, its value range, the slots it
## rolls on and the enemies that drop it, so players can hunt for one.

const WIDTH := 980.0
const LIST_HEIGHT := 590.0
const SLOT_NAMES := {
	Constants.EquipmentSlot.HELMET: "Helmet", Constants.EquipmentSlot.BODY_ARMOUR: "Body Armour",
	Constants.EquipmentSlot.GLOVES: "Gloves", Constants.EquipmentSlot.BOOTS: "Boots",
	Constants.EquipmentSlot.PRIMARY_WEAPON: "Weapon", Constants.EquipmentSlot.OFFHAND: "Offhand",
	Constants.EquipmentSlot.AMULET: "Amulet", Constants.EquipmentSlot.BELT: "Belt", Constants.EquipmentSlot.RING: "Ring",
}

## Perk ids in the order shown, for tests.
var shown: Array[StringName] = []

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(WIDTH, 0)
	var intro := ModifierWiki._text("Monster Infrequents drop only from the enemies listed, as Uncommon or Rare items with one perk that crafting can't add, change or remove. The Recombinator's Gear tab can put a second perk on an item. Elite, Champion and Ascendant enemies drop them more often.", 13, ModifierWiki.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(WIDTH, 0)
	add_child(intro)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for id: StringName in PerkCatalog.PERKS:
		shown.append(id)
		list.add_child(_entry(id))

func _entry(id: StringName) -> Control:
	var def: Dictionary = PerkCatalog.PERKS[id]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(ModifierWiki._text(PerkCatalog.name_of(id), 16, Constants.MONSTER_INFREQUENT_COLOR))
	var lo := roundi(minf(def["min"], def["max"]))
	var hi := roundi(maxf(def["min"], def["max"]))
	var text: String = def["text"]
	var range_text := "(%d-%d)" % [lo, hi] if lo != hi else str(lo)
	var line := ModifierWiki._text(text.replace("%d", range_text).replace("%%", "%"), 14, Constants.MONSTER_INFREQUENT_COLOR.lightened(0.35))
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(WIDTH - 20, 0)
	box.add_child(line)
	var slots: Array = (def["slots"] as Array).map(func(s): return SLOT_NAMES.get(s, "?"))
	var kinds: Array = def.get("kinds", [])
	var where := ", ".join(slots) + (" (%s)" % ", ".join(kinds) if not kinds.is_empty() else "")
	if PerkCatalog.is_boss(id):
		box.add_child(ModifierWiki._text("Any non-unique gear    From: a Vestige of %s at the Siphon" % ", ".join(PerkCatalog.source_names(id)), 13, ModifierWiki.MUTED))
	else:
		box.add_child(ModifierWiki._text("Rolls on: %s    Dropped by: %s" % [where, ", ".join(PerkCatalog.source_names(id))], 13, ModifierWiki.MUTED))
	return box
