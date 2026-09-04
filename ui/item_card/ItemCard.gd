extends PanelContainer
class_name ItemCard
## Rich stat card, built dynamically per call from whatever Item/Slate/
## Ability is passed in. Two display modes: the normal one (used by
## ItemSlotButton's native hover tooltip - auto-position/hide come from
## Godot) and `advanced` (Alt-hover, via AdvancedTooltip.gd) which adds a
## Close button, full tier ranges on rolled mods, and clickable stat
## keywords that print their Section 12 per-point value inline.
##
## The 3 card types are deliberately given a distinct silhouette so a
## player can tell which one they're looking at before reading a word of
## it (user-reported: rarity-colored borders alone made a Rare Item and a
## Rare Slate look identical). Each type layers 3 independent cues -
## a colored type badge, a corner-radius/border-width "shape," and a
## faint background tint - so recognition doesn't depend on any single
## one landing: **Item** stays sharp-cornered with the existing rarity-
## color border (the genre-standard cue players already expect) plus an
## "ITEM" badge in that same rarity color. **Slate** is rounded with a
## thicker border and a fixed violet "SLATE" badge, independent of the
## Slate's own rarity color (still shown on the border) - a Common and a
## Mythic Slate should still both read as "Slate" at a glance. **Ability**
## is the most rounded of the three (no gear has soft corners; only
## spells do) with a "SPELL" badge and border both colored by the
## ability's own damage type instead of one flat color for every spell
## regardless of element - a fix that also makes different spells
## distinguishable from EACH OTHER, not just from items/Slates.

signal closed

const AFFIX_COLOR := Color(0.45, 0.65, 0.95)
const MORE_MOD_COLOR := Color(0.85, 0.55, 0.95)
const STAT_COLOR := Color(0.85, 0.85, 0.85)
const SUBTITLE_COLOR := Color(0.65, 0.65, 0.65)
const FLAVOR_COLOR := Color(0.75, 0.65, 0.45)
const GLOSSARY_COLOR := Color(0.6, 0.85, 0.6)
const CARD_WIDTH := 260.0

const SLATE_BADGE_COLOR := Color(0.55, 0.35, 0.85)  # fixed - independent of the Slate's own rarity color, shown on the border instead

const ITEM_CORNER_RADIUS := 2
const SLATE_CORNER_RADIUS := 10
const ABILITY_CORNER_RADIUS := 16
const ITEM_BORDER_WIDTH := 2
const SLATE_BORDER_WIDTH := 4
const ABILITY_BORDER_WIDTH := 2

const ITEM_BG := Color(0.08, 0.08, 0.10, 0.97)
const SLATE_BG := Color(0.10, 0.08, 0.13, 0.97)
const ABILITY_BG := Color(0.07, 0.09, 0.12, 0.97)

## Not @onready - ItemSlotButton builds a card via instantiate() and
## calls display_item()/etc. on it immediately, before it's ever added
## to a SceneTree, so @onready (NOTIFICATION_READY) would still be null.
func _content() -> VBoxContainer:
	return $Margin/Content

func display_item(item: Item, advanced: bool = false) -> void:
	_clear()
	var rarity_color: Color = Constants.ITEM_RARITY_COLOR.get(item.rarity, Color.WHITE)
	_set_card_style(rarity_color, ITEM_BG, ITEM_CORNER_RADIUS, ITEM_BORDER_WIDTH)
	if advanced:
		_add_close_button()
	_add_type_badge("ITEM", rarity_color)
	if item.icon_path != "":
		_add_title_with_icon(item.display_name, rarity_color, item.icon_path)
	else:
		_add_title(item.display_name, rarity_color)
	_add_subtitle(_item_type_line(item))
	_add_separator()
	for line in _item_stat_lines(item):
		_add_stat_line(line)
	# Patch v3.7 Section 7: implicits shown separately, above the rolled
	# affix list - same distinction Section 18 draws between the two.
	var implicits := item.affixes.filter(func(a: ItemAffix): return a.is_implicit)
	var explicits := item.affixes.filter(func(a: ItemAffix): return not a.is_implicit)
	if implicits.size() > 0:
		_add_separator()
		for affix in implicits:
			_add_mod_line(affix.description, AFFIX_COLOR)
	if explicits.size() > 0:
		_add_separator()
		for affix in explicits:
			if advanced and affix.tier > 0:
				_add_mod_line_advanced(affix)
			else:
				_add_mod_line(affix.description, AFFIX_COLOR)
	if item.flavor_text != "":
		_add_separator()
		_add_flavor(item.flavor_text)

func display_slate(slate: Slate, advanced: bool = false) -> void:
	_clear()
	var rarity_color: Color = Constants.SLATE_RARITY_COLOR.get(slate.rarity, Color.WHITE)
	_set_card_style(rarity_color, SLATE_BG, SLATE_CORNER_RADIUS, SLATE_BORDER_WIDTH)
	if advanced:
		_add_close_button()
	_add_type_badge("SLATE", SLATE_BADGE_COLOR)
	_add_title(slate.display_name, rarity_color)
	var tag_name: String = slate.category_tag_override if slate.category_tag_override != "" else Constants.DAMAGE_TYPE_NAME.get(slate.tag, "?")
	_add_subtitle("Slate - %s" % tag_name)
	_add_separator()
	_add_stat_line("Size: %d tiles" % slate.get_size())
	_add_stat_line("Aether Cost: %d" % slate.aether_cost)
	if slate.is_hybrid:
		var secondary_name: String = Constants.DAMAGE_TYPE_NAME.get(slate.secondary_tag, "?")
		_add_stat_line("Hybrid: bridges %s / %s chains" % [tag_name, secondary_name])
	if slate.modifiers.size() > 0:
		_add_separator()
		for mod in slate.modifiers:
			_add_mod_line(mod.description, MORE_MOD_COLOR if mod.is_more_multiplier else AFFIX_COLOR)
	if slate.implicit_flavor_text != "":
		_add_separator()
		_add_flavor(slate.implicit_flavor_text)

## stat_sheet optional so callers without a live Player can still show
## the card, just without the "Predicted Damage" line.
func display_ability(ability: Ability, stat_sheet: StatSheet = null, advanced: bool = false) -> void:
	_clear()
	var element_color: Color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, AFFIX_COLOR)
	_set_card_style(element_color, ABILITY_BG, ABILITY_CORNER_RADIUS, ABILITY_BORDER_WIDTH)
	if advanced:
		_add_close_button()
	_add_type_badge("SPELL", element_color)
	_add_title(ability.display_name, element_color)
	_add_subtitle("Ability - %s (Rank %d/%d)" % [Constants.DAMAGE_TYPE_NAME.get(ability.damage_type, "?"), ability.rank, Ability.MAX_RANK])
	_add_separator()
	_add_stat_line("Cooldown: %.1fs" % ability.get_effective_cooldown())
	_add_stat_line("Mana Cost: %.0f" % ability.resource_cost)
	_add_stat_line("Range: %.0fm" % ability.radius)
	_add_stat_line("Motion Value: %.2f" % ability.get_effective_motion_value())
	_add_stat_line("Scaling Grade: %s" % Constants.ScalingGrade.keys()[ability.scaling_grade])
	_add_stat_line("Crit Chance: %.0f%%" % (ability.base_crit_chance * 100.0))
	if stat_sheet:
		_add_stat_line("Predicted Damage: %.1f" % ability.predict_damage(stat_sheet))
	if ability.applies_status_effects.size() > 0:
		_add_stat_line("Applies: %s" % ", ".join(ability.applies_status_effects))
	if ability.description != "":
		_add_separator()
		_add_flavor(ability.description)

func _item_type_line(item: Item) -> String:
	if item is Weapon:
		var w := item as Weapon
		var tags: Array[String] = []
		if w.is_two_handed:
			tags.append("Two-Handed")
		if w.is_ranged:
			tags.append("Ranged")
		return "%s%s" % [w.weapon_type, " (%s)" % ", ".join(tags) if tags.size() > 0 else ""]
	if item is Armor:
		return "Armour - %s" % Constants.EquipmentSlot.keys()[item.equip_slot].capitalize()
	if item is Shield:
		return "Shield"
	if item is FigmentItem:
		return "Figment - Tier %d" % (item as FigmentItem).tier
	return Constants.EquipmentSlot.keys()[item.equip_slot].capitalize()

func _item_stat_lines(item: Item) -> Array[String]:
	var lines: Array[String] = []
	if item is Weapon:
		var w := item as Weapon
		var dtype_name: String = Constants.DAMAGE_TYPE_NAME.get(w.native_damage_type, "?")
		# Patch v3.7 Section 7: read the live rolled value (a real drop),
		# falling back to the base's own range display for anything not
		# yet rolled (a base .tres, or a hand-authored single that never
		# gets rolled at all) - never the flat base_damage field, which no
		# longer exists.
		if w.rolled_base_damage > 0.0:
			lines.append("%s Damage: %.0f" % [dtype_name, w.rolled_base_damage])
		else:
			lines.append("%s Damage: %.0f - %.0f" % [dtype_name, w.base_damage_min, w.base_damage_max])
		if w.is_conduit:
			if w.rolled_spell_power > 0.0:
				lines.append("Spell Power: %.0f" % w.rolled_spell_power)
			else:
				lines.append("Spell Power: %.0f - %.0f" % [w.spell_power_min, w.spell_power_max])
		if w.infused_damage_type != -1:
			lines.append("Infused: %s" % Constants.DAMAGE_TYPE_NAME.get(w.infused_damage_type, "?"))
		var grade_letter: String = Constants.ScalingGrade.keys()[w.scaling_grade]
		if w.primary_scaling_stat != "":
			lines.append("Scaling Grade: %s %s" % [grade_letter, w.primary_scaling_stat.capitalize()])
		else:
			lines.append("Scaling Grade: %s" % grade_letter)
		lines.append("Base Crit Chance: %.0f%%" % (w.get_base_crit_chance() * 100.0))
	elif item is Armor:
		var a := item as Armor
		if a.armor_value > 0.0:
			lines.append("Armour: %.0f" % a.armor_value)
		if a.evasion_value > 0.0:
			lines.append("Evasion: %.0f" % a.evasion_value)
		if a.ward_value > 0.0:
			lines.append("Ward: %.0f" % a.ward_value)
	elif item is Shield:
		var s := item as Shield
		if s.armor_value > 0.0:
			lines.append("Armour: %.0f" % s.armor_value)
		lines.append("Block Chance: %.0f%%" % s.block_chance)
		lines.append("Block Threshold: %.0f" % s.block_threshold)
	elif item is FigmentItem:
		var m := item as FigmentItem
		lines.append("Monster Damage: %.0f%%" % (m.enemy_damage_multiplier * 100.0))
		lines.append("Monster Life: %.0f%%" % (m.enemy_health_multiplier * 100.0))
		lines.append("Item Quantity: %.0f%% (no loot system yet - inert)" % (m.loot_quantity_multiplier * 100.0))
		lines.append("Item Rarity: %.0f%% (no loot system yet - inert)" % (m.loot_rarity_multiplier * 100.0))
	if item.max_sockets > 0:
		lines.append("Sockets: %d" % item.max_sockets)
	if item.item_level > 1:
		lines.append("Requires Level %d" % item.item_level)
	if item.stat_requirement != -1:
		lines.append("Requires %.0f %s" % [item.stat_requirement_value, Constants.STAT_NAME.get(item.stat_requirement, "?")])
	return lines

func _clear() -> void:
	for child in _content().get_children():
		child.queue_free()

func _set_card_style(border_color: Color, bg_color: Color, corner_radius: int, border_width: int) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = bg_color
	box.border_color = border_color
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(corner_radius)
	add_theme_stylebox_override("panel", box)

## The first thing drawn in the card - a small colored pill naming the
## card's TYPE (not its rarity/element), so recognition doesn't depend on
## reading the subtitle line underneath it.
func _add_type_badge(text: String, color: Color) -> void:
	var badge := Label.new()
	badge.text = text
	badge.add_theme_font_size_override("font_size", 11)
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(3)
	box.content_margin_left = 6.0
	box.content_margin_right = 6.0
	box.content_margin_top = 1.0
	box.content_margin_bottom = 1.0
	badge.add_theme_stylebox_override("normal", box)
	badge.add_theme_color_override("font_color", Constants.get_contrasting_text_color(color))
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_content().add_child(badge)

func _add_close_button() -> void:
	var row := HBoxContainer.new()
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var button := Button.new()
	button.text = "x"
	button.custom_minimum_size = Vector2(22, 22)
	button.pressed.connect(func(): closed.emit())
	row.add_child(button)
	_content().add_child(row)

func _add_title(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 18)
	_content().add_child(label)

func _add_title_with_icon(text: String, color: Color, icon_path: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var icon := TextureRect.new()
	icon.texture = load(icon_path)
	icon.custom_minimum_size = Vector2(32, 32)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(CARD_WIDTH - 40, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 18)
	row.add_child(label)
	_content().add_child(row)

func _add_subtitle(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", SUBTITLE_COLOR)
	_content().add_child(label)

func _add_separator() -> void:
	_content().add_child(HSeparator.new())

func _add_stat_line(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", STAT_COLOR)
	_content().add_child(label)

func _add_mod_line(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	label.add_theme_color_override("font_color", color)
	_content().add_child(label)

## Advanced-only: shows the affix's full tier range and, for a
## flat_<stat> affix, a clickable keyword that prints the stat's
## Section 12 per-point value inline when clicked.
func _add_mod_line_advanced(affix: ItemAffix) -> void:
	var stat: int = EquipmentComponent.AFFIX_STAT_KEYS.get(affix.stat_key, -1)
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	var color_hex := AFFIX_COLOR.to_html(false)
	var range_text := " (Tier %d, range %d-%d)" % [affix.tier, round(affix.value_min), round(affix.value_max)]
	if stat != -1:
		var stat_name: String = Constants.Stat.keys()[stat]
		var linked_text: String = affix.description.replace(stat_name.capitalize(), "[url=stat:%d]%s[/url]" % [stat, stat_name.capitalize()])
		rtl.text = "[color=#%s]%s%s[/color]" % [color_hex, linked_text, range_text]
		rtl.meta_clicked.connect(_on_glossary_link_clicked)
	else:
		rtl.text = "[color=#%s]%s%s[/color]" % [color_hex, affix.description, range_text]
	_content().add_child(rtl)

func _on_glossary_link_clicked(meta: Variant) -> void:
	var meta_str: String = str(meta)
	if not meta_str.begins_with("stat:"):
		return
	var stat: int = int(meta_str.substr(5))
	var definition: String = Constants.STAT_GLOSSARY.get(stat, "")
	if definition == "":
		return
	var label := Label.new()
	label.text = "%s: %s" % [Constants.Stat.keys()[stat].capitalize(), definition]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	label.add_theme_color_override("font_color", GLOSSARY_COLOR)
	_content().add_child(label)

func _add_flavor(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	label.add_theme_color_override("font_color", FLAVOR_COLOR)
	_content().add_child(label)
