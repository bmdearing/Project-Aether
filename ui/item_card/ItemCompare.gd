extends RefCounted
class_name ItemCompare
## Item comparison for hover cards: the equipped item(s) an item would
## replace, shown beside its card, and what equipping it gains or loses.

const GAIN_COLOR := Color(0.45, 0.9, 0.45)
const LOSS_COLOR := Color(0.95, 0.38, 0.32)

## What `item` would be compared against: the gear in its slot (both rings
## for a ring). Empty for non-gear, or an item that's already equipped.
static func equipped_for(item: Item) -> Array[Item]:
	var result: Array[Item] = []
	var equipment := GameState.player_equipment as EquipmentComponent
	if item == null or equipment == null or not item.is_equipment() or item is Jewel:
		return result
	if equipment.get_all_equipped_items().has(item):
		return result
	var count := 2 if item.equip_slot == Constants.EquipmentSlot.RING else 1
	for i in count:
		var worn := equipment.get_equipped(item.equip_slot, i)
		if worn and worn != item:
			result.append(worn)
	return result

## The hover card for `item`, with the gear it would replace beside it.
static func wrap(card: ItemCard, item: Item) -> Control:
	var worn := equipped_for(item)
	if worn.is_empty():
		return card
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_child(card)
	for other in worn:
		var column := VBoxContainer.new()
		var label := Label.new()
		label.text = "EQUIPPED"
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", AetherStyle.GOLD)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
		column.add_child(label)
		var other_card: ItemCard = ItemSlotButton.ITEM_CARD_SCENE.instantiate()
		other_card.display_item(other)
		column.add_child(other_card)
		row.add_child(column)
	return row

## [{text, gain}] for every stat that differs between `item` and `worn`,
## as seen from equipping `item`.
static func diff_lines(item: Item, worn: Item) -> Array[Dictionary]:
	var mine := totals(item)
	var theirs := totals(worn)
	var keys: Array = mine.keys()
	for k in theirs:
		if not keys.has(k):
			keys.append(k)
	var lines: Array[Dictionary] = []
	for k in keys:
		var a: float = mine.get(k, [null, 0.0])[1]
		var b: float = theirs.get(k, [null, 0.0])[1]
		var d := a - b
		if absf(d) < 0.05:
			continue
		var template: String = mine[k][0] if mine.has(k) else theirs[k][0]
		lines.append({"text": _format(template, d), "gain": d > 0.0})
	return lines

## key -> [template, value]: core stats first, then every modifier summed by key.
static func totals(item: Item) -> Dictionary:
	var t := {}
	if item is Weapon:
		var w := item as Weapon
		var hit := average_hit(w)
		var aps := WeaponSpeed.attacks_per_second(w)
		if hit > 0.0:
			t["_hit"] = ["%s Average Hit", hit]
			t["_dps"] = ["%s Damage per Second", hit * aps]
		t["_aps"] = ["%s Attacks per Second", aps]
		t["_crit"] = ["%s%% Crit Chance", w.get_local_crit_chance() * 100.0]
	elif item is Armor:
		var a := item as Armor
		_add_defences(t, a.armor_value, a.evasion_value, a.ward_value)
	elif item is Shield:
		var s := item as Shield
		_add_defences(t, s.armor_value, s.evasion_value, s.ward_value)
		t["_block"] = ["%s%% Block Chance", s.block_chance * 100.0]
	for affix in item.get_effective_affixes():
		var template := CraftingResolver._template_for(affix)
		if not template.contains("%"):
			continue
		var key := affix.key()
		var have: Array = t.get(key, [template, 0.0])
		t[key] = [have[0], float(have[1]) + affix.value]
	return t

static func _add_defences(t: Dictionary, armour: float, evasion: float, ward: float) -> void:
	t["_armour"] = ["%s Armour", armour]
	t["_evasion"] = ["%s Evasion", evasion]
	t["_ward"] = ["%s Ward", ward]

## Mean damage of one attack, all damage lines and pellets together.
static func average_hit(w: Weapon) -> float:
	var range := w.get_base_range()
	var added := w.get_flat_added_damage()
	var total := (range.x + range.y + added.x + added.y) * 0.5
	for affix in w.affixes:
		if affix.stat_key == "gain_as_damage" and affix.damage_type != -1:
			total += (range.x + range.y) * 0.5 * affix.value / 100.0
	return total * w.get_local_multiplier("local_increased_weapon_damage")

## Fills a template with the size of the change, signed: "+12 to Strength",
## "-4% increased Attack Speed".
static func _format(template: String, d: float) -> String:
	var magnitude := absf(d)
	var number := str(int(round(magnitude))) if magnitude >= 10.0 or is_equal_approx(magnitude, round(magnitude)) else "%.1f" % magnitude
	var text := template.replace("%d", number).replace("%s", number).replace("%%", "%")
	if text.begins_with("+") or text.begins_with("-"):
		text = text.substr(1)
	# A negative "reduced" line reads as the "increased" it really is.
	if d < 0.0 and text.contains("reduced"):
		return "+" + text.replace("reduced", "increased")
	return ("+" if d > 0.0 else "-") + text
