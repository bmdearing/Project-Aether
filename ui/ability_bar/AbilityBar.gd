extends CanvasLayer
class_name AbilityBar
## Always-on HUD readout of the player's 4 equipped abilities - icon
## colored by damage type, a top-down cooldown wipe overlay, remaining
## seconds, and Mana cost, per slot. Slots are built in code since all 4
## are structurally identical.
##
## Purely a display - casting happens via PlayerAbilityCast reading
## ability_1..4 directly. Hovering a slot shows the same ItemCard stat
## card Abilities/Inventory use, though nothing here is clickable -
## equip/unequip lives in AbilitiesScreen. Refreshes on
## AbilityLoadoutComponent.loadout_changed.

const SLOT_SIZE := 64.0
const EMPTY_COLOR := Color(0.2, 0.2, 0.22)
const COOLDOWN_OVERLAY_COLOR := Color(0, 0, 0, 0.75)

@onready var slot_row: HBoxContainer = $SlotRow

## Cast-failure feedback (Patch v4.3): the failing slot flashes red and the
## reason ("Not enough Mana", "On cooldown", "Interrupted"...) fades in above
## the bar. Lives here rather than in PlayerHUD because this is the node that
## owns the slot controls.
const ERROR_FLASH_COLOR := Color(1.0, 0.25, 0.25)
const ERROR_TEXT_HOLD_SEC := 1.0
const ERROR_TEXT_FADE_SEC := 0.5
var _cast_error_label: Label
var _cast_error_tween: Tween

var _player: Player
var _slot_icons: Array[ItemSlotButton] = []
var _slot_overlays: Array[ColorRect] = []
var _slot_cooldown_labels: Array[Label] = []
var _slot_cost_labels: Array[Label] = []
## The bar shows the stance page while a Spell Library stance is held.
var _showing_spell_page: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_tree().get_first_node_in_group("player") as Player
	for i in range(AbilityLoadoutComponent.SLOT_COUNT):
		_build_slot(i + 1)
	if is_instance_valid(_player):
		_player.ability_loadout.loadout_changed.connect(_refresh_all_slots)
	_build_cast_error_label()
	EventBus.ability_cast_failed.connect(_on_ability_cast_failed)
	_refresh_all_slots()

func _build_cast_error_label() -> void:
	_cast_error_label = Label.new()
	_cast_error_label.anchor_left = 0.5
	_cast_error_label.anchor_right = 0.5
	_cast_error_label.anchor_top = 1.0
	_cast_error_label.anchor_bottom = 1.0
	_cast_error_label.offset_left = -200.0
	_cast_error_label.offset_right = 200.0
	_cast_error_label.offset_top = -118.0
	_cast_error_label.offset_bottom = -90.0
	_cast_error_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_cast_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cast_error_label.add_theme_font_size_override("font_size", 18)
	_cast_error_label.add_theme_color_override("font_color", ERROR_FLASH_COLOR)
	_cast_error_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_cast_error_label.add_theme_constant_override("outline_size", 5)
	_cast_error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cast_error_label.visible = false
	add_child(_cast_error_label)

func _on_ability_cast_failed(caster: Node, ability: Ability, reason: String) -> void:
	if not caster is Player or not is_instance_valid(_player):
		return
	var slot_index := _player.ability_loadout.slots.find(ability) % AbilityLoadoutComponent.SLOT_COUNT if ability else -1
	if slot_index >= 0 and slot_index < slot_row.get_child_count():
		var slot_node := slot_row.get_child(slot_index)
		var flash := create_tween()
		flash.tween_property(slot_node, "modulate", ERROR_FLASH_COLOR, 0.1)
		flash.tween_property(slot_node, "modulate", Color.WHITE, 0.2)
	if _cast_error_tween:
		_cast_error_tween.kill()
	_cast_error_label.text = reason
	_cast_error_label.modulate.a = 1.0
	_cast_error_label.visible = true
	_cast_error_tween = create_tween()
	_cast_error_tween.tween_interval(ERROR_TEXT_HOLD_SEC)
	_cast_error_tween.tween_property(_cast_error_label, "modulate:a", 0.0, ERROR_TEXT_FADE_SEC)
	_cast_error_tween.tween_callback(func(): _cast_error_label.visible = false)

func _build_slot(key_number: int) -> void:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot_row.add_child(slot)

	var icon := ItemSlotButton.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.clip_text = true
	icon.mouse_filter = Control.MOUSE_FILTER_PASS  # still hoverable for the tooltip card, but doesn't eat clicks
	slot.add_child(icon)

	var overlay := ColorRect.new()
	overlay.color = COOLDOWN_OVERLAY_COLOR
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.anchor_top = 0.0
	slot.add_child(overlay)

	var cooldown_label := Label.new()
	cooldown_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cooldown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cooldown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cooldown_label.add_theme_color_override("font_color", Color.WHITE)
	slot.add_child(cooldown_label)

	var cost_label := Label.new()
	cost_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	cost_label.offset_left = -28
	cost_label.offset_top = -18
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_label.add_theme_font_size_override("font_size", 12)
	cost_label.add_theme_color_override("font_color", Color(0.6, 0.75, 0.95))
	slot.add_child(cost_label)

	var key_label := Label.new()
	key_label.text = str(key_number)
	key_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	key_label.offset_left = 4
	key_label.offset_top = 0
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_label.add_theme_font_size_override("font_size", 12)
	key_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	slot.add_child(key_label)

	_slot_icons.append(icon)
	_slot_overlays.append(overlay)
	_slot_cooldown_labels.append(cooldown_label)
	_slot_cost_labels.append(cost_label)

func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
		return
	var on_page := _player.caster_stance != null and _player.caster_stance.uses_spell_page()
	if on_page != _showing_spell_page:
		_showing_spell_page = on_page
		_refresh_all_slots()
	for i in range(_slot_icons.size()):
		_update_slot_cooldown(i)

func _refresh_all_slots() -> void:
	for i in range(_slot_icons.size()):
		_refresh_slot(i)

func _refresh_slot(index: int) -> void:
	var icon := _slot_icons[index]
	var cost_label := _slot_cost_labels[index]
	var ability: Ability = _player.ability_cast.get_bar_ability(index) if is_instance_valid(_player) else null
	icon.ability = ability

	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(4)
	if ability:
		icon.text = ability.display_name
		icon.tooltip_text = ability.display_name
		box.bg_color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
		cost_label.text = "%.0f" % ability.get_mana_cost(_player.stat_sheet)
	else:
		icon.text = ""
		icon.tooltip_text = ""
		box.bg_color = EMPTY_COLOR
		cost_label.text = ""
	icon.add_theme_stylebox_override("normal", box)
	icon.add_theme_stylebox_override("hover", box)
	icon.add_theme_stylebox_override("pressed", box)
	var text_color := Constants.get_contrasting_text_color(box.bg_color)
	icon.add_theme_color_override("font_color", text_color)
	icon.add_theme_color_override("font_hover_color", text_color)
	icon.add_theme_color_override("font_pressed_color", text_color)

func _update_slot_cooldown(index: int) -> void:
	var ability: Ability = _player.ability_cast.get_bar_ability(index)
	var overlay := _slot_overlays[index]
	var label := _slot_cooldown_labels[index]
	if ability == null or not is_instance_valid(_player.ability_cast):
		overlay.anchor_top = 0.0
		label.text = ""
		return
	var remaining := _player.ability_cast.get_cooldown_remaining(ability)
	var total := ability.get_final_cooldown(_player.get_action_speed_multiplier(), _player.stat_sheet)
	var fraction := remaining / total if total > 0.0 else 0.0
	overlay.anchor_top = 1.0 - clamp(fraction, 0.0, 1.0)
	label.text = "%.1f" % remaining if remaining > 0.05 else ""
