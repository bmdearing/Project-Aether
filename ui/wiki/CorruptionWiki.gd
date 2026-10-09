extends VBoxContainer
class_name CorruptionWiki
## Wiki page for the Shard of Tharsis: every outcome by severity tier, its
## chance, what it does, and a row of slot icons - lit where the outcome can
## change an item of that slot, dim where it lands with no effect.

const WIDTH := 980.0
const LIST_HEIGHT := 560.0
const CORRUPT_COLOR := Color(0.72, 0.38, 0.92)
const TIER_NAMES := {1: "Minor", 2: "Significant", 3: "Major", 4: "Extreme"}
const DIM_ALPHA := 0.18
const ICON_SIZE := 28.0

## Outcome name -> Array[bool] per WikiCatalog.SLOT_TYPES, as shown.
var shown: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(WIDTH, 0)
	var intro := ModifierWiki._text("A Shard of Tharsis rolls a severity, then one outcome of it. The item is Corrupted afterwards and can't be crafted further. Icons: the slots an outcome can change.", 13, ModifierWiki.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 6)
	add_child(legend)
	for type in WikiCatalog.SLOT_TYPES:
		legend.add_child(_slot_icon(type, true))
		legend.add_child(ModifierWiki._text(_slot_name(type) + "   ", 12, ModifierWiki.MUTED))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for tier in WikiCatalog.corruption_tiers():
		list.add_child(ModifierWiki._text("%s  ·  %s" % [TIER_NAMES.get(tier["tier"], "?"), ModifierWiki._percent(tier["chance"])], 18, CORRUPT_COLOR))
		for outcome in tier["outcomes"]:
			shown[outcome["name"]] = outcome["slots"]
			list.add_child(_outcome_row(outcome))

func _outcome_row(outcome: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", AetherStyle.glass_box(Color(CORRUPT_COLOR, 0.35), Color(0.06, 0.04, 0.08, 0.85), 1, 8.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var head := HBoxContainer.new()
	left.add_child(head)
	head.add_child(ModifierWiki._text(outcome["label"], 16, CORRUPT_COLOR.lightened(0.35)))
	head.add_child(ModifierWiki._text("   %s per Shard" % ModifierWiki._percent(outcome["chance"]), 13, AetherStyle.GOLD))
	var text := ModifierWiki._text(outcome["text"], 13, AetherStyle.TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(560, 0)
	left.add_child(text)
	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 4)
	row.add_child(icons)
	for i in WikiCatalog.SLOT_TYPES.size():
		icons.add_child(_slot_icon(WikiCatalog.SLOT_TYPES[i], outcome["slots"][i]))
	return panel

static func _slot_name(type: StringName) -> String:
	match type:
		&"greatsword":
			return "Weapon"
		&"kite_shield":
			return "Shield"
	return String(type).capitalize()

static func _slot_icon(type: StringName, lit: bool) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	holder.tooltip_text = _slot_name(type) + ("" if lit else " - no effect")
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	var icon := ItemIcon.fill(holder)
	icon.content = WikiCatalog.base_of(type)
	if not lit:
		holder.modulate.a = DIM_ALPHA
	return holder
