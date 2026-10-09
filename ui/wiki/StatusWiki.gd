extends VBoxContainer
class_name StatusWiki
## Wiki page: every status effect, what it does and, for ailments, the
## damage a hit must deal to cause it from "+% chance to cause X" gear.

const WIDTH := 980.0
const LIST_HEIGHT := 590.0
const AILMENT_COLOR := Color(0.95, 0.55, 0.35)
const EFFECT_COLOR := Color(0.6, 0.78, 0.95)

## Effect ids in the order shown, for tests.
var shown: Array[String] = []

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(WIDTH, 0)
	var intro := ModifierWiki._text("Ailments roll to land: a spell's own chance plus your \"chance to cause\" gear. Gear chance only works through hits of the matching damage. Other effects come from specific skills and always land.", 13, ModifierWiki.MUTED)
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
	var heading := ""
	for row in WikiCatalog.status_effects():
		var section := "Ailments" if row["ailment"] else "Other effects"
		if section != heading:
			heading = section
			list.add_child(ModifierWiki._text(section, 18, AILMENT_COLOR if row["ailment"] else EFFECT_COLOR))
		shown.append(row["id"])
		list.add_child(_row(row))

func _row(row: Dictionary) -> PanelContainer:
	var color: Color = AILMENT_COLOR if row["ailment"] else EFFECT_COLOR
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", AetherStyle.glass_box(Color(color, 0.35), Color(0.05, 0.05, 0.08, 0.85), 1, 8.0))
	var box := VBoxContainer.new()
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	head.add_child(ModifierWiki._text(row["name"], 16, color.lightened(0.3)))
	var types: Array = row["types"]
	if not types.is_empty():
		head.add_child(ModifierWiki._text("   from %s damage" % " / ".join(types), 13, AetherStyle.GOLD))
	var text := ModifierWiki._text(row["text"], 13, AetherStyle.TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(WIDTH - 40.0, 0)
	box.add_child(text)
	return panel
