extends VBoxContainer
class_name MonsterWiki
## Wiki page: monster rarity tiers (per-pack odds, Life and damage, what the
## tier means) and every affix each tier can roll.

const WIDTH := 980.0
const LIST_HEIGHT := 590.0

## Affix ids in the order shown, for tests.
var shown: Array[String] = []

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(WIDTH, 0)
	var intro := ModifierWiki._text("Rarity is rolled for each pack. Rare monsters drop more and better loot; their affixes show above their health bar.", 13, ModifierWiki.MUTED)
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
	for tier in WikiCatalog.monster_tiers():
		var color: Color = tier["color"]
		list.add_child(ModifierWiki._text("%s  ·  %s of packs  ·  ×%s Life, ×%s damage" % [tier["name"], ModifierWiki._percent(tier["chance"]), _num(tier["life"]), _num(tier["damage"])], 18, color))
		var text := ModifierWiki._text(tier["text"], 13, AetherStyle.TEXT)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(WIDTH - 20.0, 0)
		list.add_child(text)
		for affix in tier["affixes"]:
			shown.append(affix.affix_id)
			list.add_child(_affix_row(affix, color))

func _affix_row(affix: EnemyAffix, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", AetherStyle.glass_box(Color(color, 0.3), Color(0.05, 0.05, 0.08, 0.85), 1, 8.0))
	var box := VBoxContainer.new()
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	head.add_child(ModifierWiki._text(affix.display_name, 16, color.lightened(0.25)))
	if affix.has_aura:
		head.add_child(ModifierWiki._text("   Aura, %dm" % roundi(affix.aura_radius), 13, AetherStyle.GOLD))
	if affix.item_rarity_bonus > 0.0 or affix.item_quantity_bonus > 0.0:
		head.add_child(ModifierWiki._text("   +%d%% Item Rarity, +%d%% Item Quantity" % [roundi(affix.item_rarity_bonus), roundi(affix.item_quantity_bonus)], 12, ModifierWiki.MUTED))
	var text := ModifierWiki._text(affix.description, 13, AetherStyle.TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(WIDTH - 40.0, 0)
	box.add_child(text)
	return panel

static func _num(v: float) -> String:
	return str(v) if v != roundf(v) else str(int(v))
