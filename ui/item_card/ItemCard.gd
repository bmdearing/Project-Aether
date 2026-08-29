extends PanelContainer
class_name ItemCard
## Rich stat card, built dynamically per call from whatever Item/Slate/
## Ability is passed in. Two display modes: the normal one (used by
## ItemSlotButton's native hover tooltip - auto-position/hide come from
## Godot) and `advanced` (Alt-hover, via AdvancedTooltip.gd) which adds a
## Close button, full tier ranges on rolled mods, and clickable stat
## keywords that print their Section 12 per-point value inline.

signal closed

const AFFIX_COLOR := Color(0.45, 0.65, 0.95)
const MORE_MOD_COLOR := Color(0.85, 0.55, 0.95)
const STAT_COLOR := Color(0.85, 0.85, 0.85)
const SUBTITLE_COLOR := Color(0.65, 0.65, 0.65)
const FLAVOR_COLOR := Color(0.75, 0.65, 0.45)
const GLOSSARY_COLOR := Color(0.6, 0.85, 0.6)
const CARD_WIDTH := 260.0

## Not @onready - ItemSlotButton builds a card via instantiate() and
## calls display_item()/etc. on it immediately, before it's ever added
## to a SceneTree, so @onready (NOTIFICATION_READY) would still be null.
func _content() -> VBoxContainer:
	return $Margin/Content

func display_item(item: Item, advanced: bool = false) -> void:
	_clear()
	var rarity_color: Color = Constants.ITEM_RARITY_COLOR.get(item.rarity, Color.WHITE)
	_set_border_color(rarity_color)
	if advanced:
		_add_close_button()
	_add_title(item.display_name, rarity_color)
	_add_subtitle(_item_type_line(item))
	_add_separator()
	for line in _item_stat_lines(item):
		_add_stat_line(line)
	if item.affixes.size() > 0:
		_add_separator()
		for affix in item.affixes:
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
	_set_border_color(rarity_color)
	if advanced:
		_add_close_button()
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
	_set_border_color(AFFIX_COLOR)
	if advanced:
		_add_close_button()
	_add_title(ability.display_name, AFFIX_COLOR)
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
	if item is MapItem:
		return "Map - Tier %d" % (item as MapItem).tier
	return Constants.EquipmentSlot.keys()[item.equip_slot].capitalize()

func _item_stat_lines(item: Item) -> Array[String]:
	var lines: Array[String] = []
	if item is Weapon:
		var w := item as Weapon
		var dtype_name: String = Constants.DAMAGE_TYPE_NAME.get(w.native_damage_type, "?")
		lines.append("%s Damage: %.0f" % [dtype_name, w.base_damage])
		if w.infused_damage_type != -1:
			lines.append("Infused: %s" % Constants.DAMAGE_TYPE_NAME.get(w.infused_damage_type, "?"))
		lines.append("Scaling Grade: %s" % Constants.ScalingGrade.keys()[w.scaling_grade])
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
	elif item is MapItem:
		var m := item as MapItem
		lines.append("Monster Damage: %.0f%%" % (m.enemy_damage_multiplier * 100.0))
		lines.append("Monster Life: %.0f%%" % (m.enemy_health_multiplier * 100.0))
		lines.append("Item Quantity: %.0f%% (no loot system yet - inert)" % (m.loot_quantity_multiplier * 100.0))
		lines.append("Item Rarity: %.0f%% (no loot system yet - inert)" % (m.loot_rarity_multiplier * 100.0))
	if item.max_sockets > 0:
		lines.append("Sockets: %d" % item.max_sockets)
	return lines

func _clear() -> void:
	for child in _content().get_children():
		child.queue_free()

func _set_border_color(color: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.08, 0.1, 0.97)
	box.border_color = color
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", box)

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
