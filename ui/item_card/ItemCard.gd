extends PanelContainer
class_name ItemCard
## Rich stat card, built dynamically per call from whatever Item/Slate/
## Ability is passed in. `ItemSlotButton._make_custom_tooltip()` shows
## this via Godot's native tooltip system (auto-position/hide/lifecycle
## all native) - the card itself listens for Alt directly (Patch v3.8
## Section 5) and swaps its OWN content between the normal card and Alt
## Info in place while still showing, rather than a second floating card
## (the previous AdvancedTooltip.gd autoload, removed) - release Alt and
## it swaps back, no clicks/pinning/second window.
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

const AFFIX_COLOR := Color(0.45, 0.65, 0.95)
const IMPLICIT_COLOR := Color(0.9, 0.75, 0.3)  # gold/yellow - Patch v3.8b: implicits are visually distinct from rolled explicit mods
const REQUIREMENT_UNMET_COLOR := Color(0.9, 0.25, 0.25)  # Patch v3.8d - border/title/bottom-text when the player doesn't meet an item's requirements
const MORE_MOD_COLOR := Color(0.85, 0.55, 0.95)
const CORRUPTED_BADGE_COLOR := Color(0.6, 0.2, 0.8)
const STAT_COLOR := Color(0.85, 0.85, 0.85)
const AMMO_INFO_COLOR := SUBTITLE_COLOR  # Magazine/Reload lines on ranged weapons - dimmer than the stat lines around them
const SUBTITLE_COLOR := Color(0.65, 0.65, 0.65)
const FLAVOR_COLOR := Color(0.75, 0.65, 0.45)
const MODIFIED_VALUE_COLOR := Color(0.4, 0.6, 1.0)  # a card value changed by a mod on the item itself (v4.10)
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

## Which of these is non-null decides what Alt Info shows, and what a
## post-Alt-release re-render falls back to.
var _current_item: Item = null
var _current_slate: Slate = null
var _current_ability: Ability = null
var _current_stat_sheet: StatSheet = null
var _showing_alt: bool = false

## Not @onready - ItemSlotButton builds a card via instantiate() and
## calls display_item()/etc. on it immediately, before it's ever added
## to a SceneTree, so @onready (NOTIFICATION_READY) would still be null.
func _content() -> VBoxContainer:
	return $Margin/Content

func display_item(item: Item) -> void:
	_current_item = item
	_current_slate = null
	_current_ability = null
	_showing_alt = false
	if not EventBus.item_rarity_changed.is_connected(_on_item_rarity_changed):
		EventBus.item_rarity_changed.connect(_on_item_rarity_changed)
	_render_item(item)

## Patch v3.9 - keeps a showing card's border/title color live if the
## item's rarity changes underneath it (e.g. a Cube craft while its
## hover tooltip is still up), instead of only updating on the next hover.
func _on_item_rarity_changed(item: Item) -> void:
	if item == _current_item and not _showing_alt:
		_render_item(item)

func display_slate(slate: Slate) -> void:
	_current_item = null
	_current_slate = slate
	_current_ability = null
	_showing_alt = false
	_render_slate(slate)

func display_ability(ability: Ability, stat_sheet: StatSheet = null) -> void:
	_current_item = null
	_current_slate = null
	_current_ability = ability
	_current_stat_sheet = stat_sheet
	_showing_alt = false
	_render_ability(ability, stat_sheet)

## Patch v3.8 Section 5: Alt is a HOLD - press while this card is showing
## swaps to Alt Info in place, release swaps back. No second window, no
## click-to-pin - matches this card's own native-tooltip lifecycle
## exactly (Godot handles show/hide/position, this only ever changes
## what's INSIDE it).
func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.keycode != KEY_ALT or key_event.echo:
		return
	if key_event.pressed and not _showing_alt:
		_showing_alt = true
		_render_alt_info()
	elif not key_event.pressed and _showing_alt:
		_showing_alt = false
		if _current_item:
			_render_item(_current_item)
		elif _current_slate:
			_render_slate(_current_slate)
		elif _current_ability:
			_render_ability(_current_ability, _current_stat_sheet)

func _render_item(item: Item) -> void:
	_clear()
	var requirements_met := _check_requirements_met(item)
	var rarity_color: Color = REQUIREMENT_UNMET_COLOR if not requirements_met else Constants.ITEM_RARITY_COLOR.get(item.rarity, Color.WHITE)
	_set_card_style(rarity_color, ITEM_BG, ITEM_CORNER_RADIUS, ITEM_BORDER_WIDTH)
	var badge_row := _add_type_badge("ITEM", rarity_color)
	if item.is_corrupted:
		badge_row.add_child(_make_badge("CORRUPTED", CORRUPTED_BADGE_COLOR))
	if item.icon_path != "":
		_add_title_with_icon(item.display_name, rarity_color, item.icon_path)
	else:
		_add_title(item.display_name, rarity_color)
	_add_subtitle(_item_type_line(item))
	_add_separator()
	if item is Weapon:
		for line in _build_attack_power_lines(item as Weapon):
			_add_attack_power_line(line)
		_add_weapon_value_lines(item as Weapon)
		for line in _ranged_info_lines(item as Weapon):
			_add_ammo_info_line(line)
	for line in _item_stat_lines(item):
		_add_stat_line(line)
	if item.max_sockets > 0:
		_add_socket_row(item.sockets, item.max_sockets)
	# Patch v3.8b: implicits (gold) then explicits (blue), with the
	# dividing line ONLY between the two groups - not shown at all if
	# either group is empty, and never shown before implicits.
	var implicits := item.affixes.filter(func(a: ItemAffix): return a.is_implicit)
	var explicits := item.affixes.filter(func(a: ItemAffix): return not a.is_implicit)
	for affix in implicits:
		_add_mod_line(_affix_text(affix, false), IMPLICIT_COLOR)
	if implicits.size() > 0 and explicits.size() > 0:
		_add_separator()
	for affix in explicits:
		_add_mod_line(_affix_text(affix, false), AFFIX_COLOR)
	if item.flavor_text != "":
		_add_separator()
		_add_flavor(item.flavor_text)
	# Patch v3.8d: requirements only ever appear on the main card when
	# UNMET - nothing is shown here at all if the player already meets
	# them (see _render_alt_info() for the always-shown version).
	if not requirements_met:
		_add_separator()
		for line in _requirement_lines(item):
			_add_mod_line(line, REQUIREMENT_UNMET_COLOR)

func _render_slate(slate: Slate) -> void:
	_clear()
	var rarity_color: Color = Constants.SLATE_RARITY_COLOR.get(slate.rarity, Color.WHITE)
	_set_card_style(rarity_color, SLATE_BG, SLATE_CORNER_RADIUS, SLATE_BORDER_WIDTH)
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

## Patch v3.8 Section 4: Motion Value/Predicted Damage/Scaling Grade
## removed from the main card (Scaling Grade moved to Alt Info); Cast
## Type added; status effects now show their real display name
## (Constants.STATUS_EFFECT_NAME), not the raw id.
func _render_ability(ability: Ability, stat_sheet: StatSheet) -> void:
	_clear()
	var element_color: Color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, AFFIX_COLOR)
	_set_card_style(element_color, ABILITY_BG, ABILITY_CORNER_RADIUS, ABILITY_BORDER_WIDTH)
	_add_type_badge("SPELL", element_color)
	_add_title(ability.display_name, element_color)
	_add_subtitle("Ability - %s (Rank %d/%d)" % [Constants.DAMAGE_TYPE_NAME.get(ability.damage_type, "?"), ability.rank, Ability.MAX_RANK])
	_add_separator()
	_add_spell_damage_line(ability, stat_sheet if stat_sheet else _stat_sheet_for_card())
	_add_stat_line("Cast Type: %s" % _get_cast_type_label(ability))
	_add_stat_line("Cooldown: %.1fs" % ability.get_effective_cooldown())
	_add_stat_line("Mana Cost: %.0f" % ability.resource_cost)
	_add_stat_line("Range: %.0fm" % ability.radius)
	_add_stat_line("Crit Chance: %.0f%%" % (ability.base_crit_chance * 100.0))
	if ability.applies_status_effects.size() > 0:
		var effect_names := ability.applies_status_effects.map(
			func(id): return Constants.STATUS_EFFECT_NAME.get(id, id)
		)
		_add_stat_line("Applies: %s" % ", ".join(effect_names))
	if ability.description != "":
		_add_separator()
		_add_flavor(ability.description)

## "<Type> Damage: min to max" per cast (non-crit) from the equipped
## Conduit's spell power range - Ability.predict_damage_range(). Skipped for
## non-damaging abilities (motion value 0, e.g. Blink/Purge).
func _add_spell_damage_line(ability: Ability, stat_sheet: StatSheet) -> void:
	if ability.motion_value <= 0.0 or stat_sheet == null:
		return
	var label := "%s Damage" % Constants.DAMAGE_TYPE_NAME.get(ability.damage_type, "?")
	var color: Color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
	if stat_sheet.conduit_spell_power_range.y <= 0.0:
		_add_mod_line("%s: requires a Conduit" % label, REQUIREMENT_UNMET_COLOR)
		return
	var range := ability.predict_damage_range(stat_sheet)
	_add_attack_power_line({"label": label, "lo": range.x, "hi": range.y, "color": color})

func _get_cast_type_label(ability: Ability) -> String:
	match ability.cast_type:
		Ability.CastType.INSTANT:
			return "Instant"
		Ability.CastType.CAST_TIME:
			return "%.1fs Cast" % ability.base_cast_time
		Ability.CastType.CHANNELED:
			return "Channeled"
	return "Instant"

## Patch v3.8 Section 5. Replaces the whole card content in place - no
## title/badge/border, just the requested lines, so it's visually obvious
## this is a different mode, not a taller version of the normal card.
## Roll-time code (ItemRoller/CraftingSystem) bakes " (Tier N)" into
## ItemAffix.description, so the main card can't just print it as-is: the
## main view strips the suffix, Alt Info restores it from affix.tier. Done
## here at display time rather than at the source so items already saved
## with the suffix are handled too. Implicits never carry a tier.
const TIER_SUFFIX := " (Tier "

func _affix_text(affix: ItemAffix, show_tier: bool) -> String:
	var text := affix.description
	var tier_at := text.rfind(TIER_SUFFIX)
	if tier_at != -1 and text.ends_with(")"):
		text = text.substr(0, tier_at)
	if show_tier and not affix.is_implicit and affix.tier > 0:
		text += " (Tier %d)" % affix.tier
	return text

func _add_alt_affix_tiers(item: Item) -> void:
	var explicits := item.affixes.filter(func(a: ItemAffix): return not a.is_implicit)
	if explicits.is_empty():
		return
	_add_separator()
	for affix in explicits:
		_add_mod_line(_affix_text(affix, true), AFFIX_COLOR)

func _render_alt_info() -> void:
	_clear()
	if _current_item is Weapon:
		var w := _current_item as Weapon
		_add_stat_line("Scaling Grade: %s" % Constants.grade_to_letter(w.scaling_grade))
		if w.primary_scaling_stat != "":
			_add_stat_line("Primary Scaling: %s" % w.primary_scaling_stat.capitalize())
		if w.secondary_scaling_stat != "":
			_add_stat_line("Secondary Scaling: %s" % w.secondary_scaling_stat.capitalize())
		_add_stat_line("Item Level: %d" % w.item_level)
		for line in _requirement_lines(w):
			_add_stat_line(line)
		_add_alt_affix_tiers(w)
	elif _current_item != null:
		_add_stat_line("Item Level: %d" % _current_item.item_level)
		for line in _requirement_lines(_current_item):
			_add_stat_line(line)
		_add_alt_affix_tiers(_current_item)
	elif _current_ability != null:
		_add_stat_line("Scaling Grade: %s" % Constants.grade_to_letter(_current_ability.scaling_grade))
		_add_stat_line("Motion Value: %.2f" % _current_ability.get_effective_motion_value())

## Bug fix (2026-09-06, user-reported): returned null whenever no Player
## node is in the scene tree at hover time, leaving the blue stat
## contribution number blank/zero. GameState.player_stat_sheet is the same
## StatSheet instance Player.gd assigns itself to at boot (autoloads/
## GameState.gd:31) - a reliable fallback for exactly this gap.
## Patch v3.8d, display-only - deliberately separate from EquipmentComponent.
## _requirement_block_reason()'s real equip gate (item_level/stat_
## requirement, unchanged this pass - see Item.gd's own comment). Sourced
## from GameState the same way _stat_sheet_for_card() is (GameState.
## player_level, kept live-synced by Player._on_leveled_up()) rather than
## a live Player reference, so shop/menu contexts get a real answer
## instead of unconditionally "met."
func _check_requirements_met(item: Item) -> bool:
	var stat_sheet := _stat_sheet_for_card()
	if stat_sheet == null:
		return true
	if GameState.player_level < item.level_requirement:
		return false
	if stat_sheet.get_stat(Constants.Stat.STRENGTH) < item.strength_requirement:
		return false
	if stat_sheet.get_stat(Constants.Stat.AGILITY) < item.agility_requirement:
		return false
	if stat_sheet.get_stat(Constants.Stat.INTELLECT) < item.intellect_requirement:
		return false
	return true

## Shared between the Alt Info panel (always shown) and the main card
## (shown only when unmet, in red - see _render_item()) - "Requires Level
## N" first, then a single combined "Requires X / Y / Z" line for
## whichever of Strength/Agility/Intellect are actually non-zero.
func _requirement_lines(item: Item) -> Array[String]:
	var lines: Array[String] = []
	if item.level_requirement > 1:
		lines.append("Requires Level %d" % item.level_requirement)
	var stat_parts: Array[String] = []
	if item.strength_requirement > 0:
		stat_parts.append("%d Strength" % item.strength_requirement)
	if item.agility_requirement > 0:
		stat_parts.append("%d Agility" % item.agility_requirement)
	if item.intellect_requirement > 0:
		stat_parts.append("%d Intellect" % item.intellect_requirement)
	if stat_parts.size() > 0:
		lines.append("Requires %s" % " / ".join(stat_parts))
	return lines

## Bug fix (2026-09-06, user-reported): returned null whenever no Player
## node is in the scene tree at hover time, leaving the blue stat
## contribution number blank/zero. The real trigger turned out to be
## narrower than "shop/menu contexts" - ItemSlotButton._make_custom_
## tooltip() calls display_item() on a freshly-instantiate()'d ItemCard
## BEFORE returning it, i.e. before Godot's tooltip system ever adds the
## card to the SceneTree, so get_tree() itself is null at that exact
## moment for EVERY hover, not just ones with no Player. Guarding only
## "is player null" (the brief's own proposed fix) still crashes on the
## unconditional get_tree() call before ever reaching that check - the
## tree itself has to be checked first. GameState.player_stat_sheet is
## the same StatSheet instance Player.gd assigns itself to at boot
## (autoloads/GameState.gd:31), a reliable fallback either way.
func _stat_sheet_for_card() -> StatSheet:
	# is_inside_tree() first: get_tree() on a node outside the tree returns
	# null but also prints an engine error with a backtrace - on every
	# tooltip build, since tooltip cards are built before being added.
	var tree := get_tree() if is_inside_tree() else null
	var player: Player = (tree.get_first_node_in_group("player") as Player) if tree else null
	if player:
		return player.stat_sheet
	return GameState.player_stat_sheet as StatSheet

## "<Type> Damage: lo to hi" - the item's own per-hit range: raw in white,
## or with this item's local increased Weapon Damage applied in blue. The
## character's Strength is deliberately NOT included - the card shows the
## item, the character screen shows damage with stats. Primary damage type
## always shown; extra lines only for a
## "gain_as_damage" affix (forward-compat - no ItemRoller.AFFIX_POOL entry
## produces one yet).
func _build_attack_power_lines(weapon: Weapon) -> Array:
	var lines := []
	var local_mult := weapon.get_local_multiplier("local_increased_weapon_damage")
	var range := weapon.get_damage_range()
	var primary_color: Color = Constants.DAMAGE_TYPE_COLOR.get(weapon.native_damage_type, Color.WHITE)
	lines.append({
		"label": "%s Damage" % Constants.DAMAGE_TYPE_NAME.get(weapon.native_damage_type, "?"),
		"lo": range.x,
		"hi": range.y,
		"color": primary_color,
	})
	for affix in weapon.affixes:
		if affix.stat_key == "gain_as_damage" and affix.damage_type != -1:
			var color: Color = Constants.DAMAGE_TYPE_COLOR.get(affix.damage_type, Color.WHITE)
			lines.append({
				"label": "%s Damage" % Constants.DAMAGE_TYPE_NAME.get(affix.damage_type, "?"),
				"lo": range.x * (affix.value / 100.0),
				"hi": range.y * (affix.value / 100.0),
				"color": color,
			})
	for line in lines:
		line["boosted_lo"] = line["lo"] * local_mult
		line["boosted_hi"] = line["hi"] * local_mult
	# Shotguns: show what ONE pellet hits for, times the pellet count.
	if weapon.is_ranged and weapon.pellet_count > 1:
		for line in lines:
			for key in ["lo", "hi", "boosted_lo", "boosted_hi"]:
				line[key] = line[key] / weapon.pellet_count
			line["pellets"] = weapon.pellet_count
	return lines

func _add_attack_power_line(line: Dictionary) -> void:
	var suffix := " x%d" % line["pellets"] if line.has("pellets") else ""
	var base_text := "%.0f to %.0f%s" % [line["lo"], line["hi"], suffix]
	var modified_text := ""
	if line.has("boosted_lo"):
		modified_text = "%.0f to %.0f%s" % [line["boosted_lo"], line["boosted_hi"], suffix]
	_add_value_line(line["label"], line["color"], base_text, modified_text)

## "Label: value" - one value only. When modified_text is non-empty and
## differs from base_text (a mod on this item changes it), the modified
## value replaces the base one and is shown in blue; otherwise the base
## value in white.
func _add_value_line(label: String, label_color: Color, base_text: String, modified_text: String = "") -> void:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	var is_modified := modified_text != "" and modified_text != base_text
	rtl.text = "[color=#%s]%s[/color]: [color=#%s]%s[/color]" % [
		label_color.to_html(false), label,
		(MODIFIED_VALUE_COLOR if is_modified else STAT_COLOR).to_html(false),
		modified_text if is_modified else base_text,
	]
	_content().add_child(rtl)

## Crit Chance, Spell Power, and Attack/Cast Speed, each with its local mod
## (v4.10) shown as a blue modified value. Local weapon damage and crit are
## real (Weapon._base_hit()); local spell damage, attack speed and cast
## speed are display-only for now.
func _add_weapon_value_lines(w: Weapon) -> void:
	if w.is_conduit:
		var spell_mult := w.get_local_multiplier("local_increased_spell_damage")
		_add_value_line("Spell Power", STAT_COLOR, "%.0f to %.0f" % [w.spell_power_min, w.spell_power_max],
			"%.0f to %.0f" % [w.spell_power_min * spell_mult, w.spell_power_max * spell_mult])
	_add_value_line("Crit Chance", STAT_COLOR, "%s%%" % _format_num(snapped(w.get_base_crit_chance() * 100.0, 0.1)),
		"%s%%" % _format_num(snapped(w.get_local_crit_chance() * 100.0, 0.1)))
	var attack_speed := w.get_local_multiplier("local_increased_attack_speed")
	if attack_speed > 1.0:
		_add_value_line("Attack Speed", STAT_COLOR, "1.00", "%.2f" % attack_speed)
	var cast_speed := w.get_local_multiplier("local_increased_cast_speed")
	if cast_speed > 1.0:
		_add_value_line("Cast Speed", STAT_COLOR, "1.00", "%.2f" % cast_speed)

## Magazine ("current / reserve") and Reload lines for firearms; bows get a
## single Draw line instead (v4.7), since they have no magazine and
## unlimited arrows. A weapon with
## no reload time (the crossbow - its delay is its shot cycle) skips Reload.
func _ranged_info_lines(weapon: Weapon) -> Array[String]:
	var lines: Array[String] = []
	if weapon.get_draw_time() > 0.0:
		lines.append("Draw: %ss" % _format_num(weapon.get_draw_time()))
		return lines
	if not weapon.is_ranged or weapon.ammo_type == Constants.AmmoType.ARROW or weapon.magazine_size <= 0:
		return lines
	lines.append("Magazine: %d / %d" % [weapon.get_current_magazine(), AmmoInventory.get_reserve(weapon.ammo_type)])
	if weapon.reload_per_shell:
		lines.append("Reload: per shell")
	elif weapon.reload_time > 0.0:
		lines.append("Reload: %ss" % _format_num(weapon.reload_time))
	return lines

func _add_ammo_info_line(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", AMMO_INFO_COLOR)
	_content().add_child(label)

func _format_num(v: float) -> String:
	return str(int(round(v))) if v == round(v) else "%.1f" % v

## Bottom-of-card row of small circles - filled (solid) for `sockets`
## (how many this specific rolled instance has, ItemRoller.roll()),
## outline-only for the rest up to `max_sockets` (the item type's overall
## cap - unaffected by this, still raised by Bore/Corruption exactly as
## before). Replaces the old plain "Sockets: %d" text line.
func _add_socket_row(sockets: int, max_sockets: int) -> void:
	var row := SocketRow.new()
	row.sockets = sockets
	row.max_sockets = max_sockets
	row.custom_minimum_size = Vector2(CARD_WIDTH, 24.0)
	_content().add_child(row)

class SocketRow extends Control:
	var sockets: int = 0
	var max_sockets: int = 0
	const SOCKET_RADIUS := 6.0
	const SOCKET_SPACING := 16.0
	const FILLED_COLOR := Color(0.7, 0.7, 0.8)
	const EMPTY_COLOR := Color(0.4, 0.4, 0.4)

	func _draw() -> void:
		var total_width: float = max_sockets * SOCKET_SPACING
		var start_x: float = (size.x - total_width) / 2.0 + SOCKET_SPACING / 2.0
		var y: float = size.y / 2.0
		for i in range(max_sockets):
			var center := Vector2(start_x + i * SOCKET_SPACING, y)
			if i < sockets:
				draw_circle(center, SOCKET_RADIUS, FILLED_COLOR)
			else:
				draw_arc(center, SOCKET_RADIUS, 0.0, TAU, 16, EMPTY_COLOR, 1.5)

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

## Patch v3.8 Section 3: Scaling Grade and the raw damage/socket-count
## text lines moved out of here (Scaling Grade -> Alt Info, damage -> the
## weapon damage lines built separately, sockets -> the socket row;
## Spell Power/Crit Chance/speeds -> _add_weapon_value_lines(), v4.10) -
## this only covers what's left: Infused type and the shared item-level/
## requirement lines every item type shows.
func _item_stat_lines(item: Item) -> Array[String]:
	var lines: Array[String] = []
	if item is Weapon:
		var w := item as Weapon
		if w.infused_damage_type != -1:
			lines.append("Infused: %s" % Constants.DAMAGE_TYPE_NAME.get(w.infused_damage_type, "?"))
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
		lines.append("Block Chance: %.0f%%" % (s.block_chance * 100.0))
	elif item is FigmentItem:
		var m := item as FigmentItem
		lines.append("Monster Damage: %.0f%%" % (m.enemy_damage_multiplier * 100.0))
		lines.append("Monster Life: %.0f%%" % (m.enemy_health_multiplier * 100.0))
		lines.append("Item Quantity: %.0f%% (no loot system yet - inert)" % (m.loot_quantity_multiplier * 100.0))
		lines.append("Item Rarity: %.0f%% (no loot system yet - inert)" % (m.loot_rarity_multiplier * 100.0))
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
## Returns the row the badge sits in, so a second badge (CORRUPTED) can sit
## beside it.
func _add_type_badge(text: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_make_badge(text, color))
	_content().add_child(row)
	return row

func _make_badge(text: String, color: Color) -> Label:
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
	return badge

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

func _add_flavor(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	label.add_theme_color_override("font_color", FLAVOR_COLOR)
	_content().add_child(label)
