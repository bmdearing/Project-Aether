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

var _player: Player
var _slot_icons: Array[ItemSlotButton] = []
var _slot_overlays: Array[ColorRect] = []
var _slot_cooldown_labels: Array[Label] = []
var _slot_cost_labels: Array[Label] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_tree().get_first_node_in_group("player") as Player
	for i in range(AbilityLoadoutComponent.SLOT_COUNT):
		_build_slot(i + 1)
	if is_instance_valid(_player):
		_player.ability_loadout.loadout_changed.connect(_refresh_all_slots)
	_refresh_all_slots()

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
	for i in range(_slot_icons.size()):
		_update_slot_cooldown(i)

func _refresh_all_slots() -> void:
	for i in range(_slot_icons.size()):
		_refresh_slot(i)

func _refresh_slot(index: int) -> void:
	var icon := _slot_icons[index]
	var cost_label := _slot_cost_labels[index]
	var ability: Ability = _player.ability_loadout.get_equipped(index) if is_instance_valid(_player) else null
	icon.ability = ability

	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(4)
	if ability:
		icon.text = ability.display_name
		icon.tooltip_text = ability.display_name
		box.bg_color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, Color.WHITE)
		cost_label.text = "%.0f" % ability.resource_cost
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
	var ability: Ability = _player.ability_loadout.get_equipped(index)
	var overlay := _slot_overlays[index]
	var label := _slot_cooldown_labels[index]
	if ability == null or not is_instance_valid(_player.ability_cast):
		overlay.anchor_top = 0.0
		label.text = ""
		return
	var remaining := _player.ability_cast.get_cooldown_remaining(ability)
	var total := ability.get_effective_cooldown()
	var fraction := remaining / total if total > 0.0 else 0.0
	overlay.anchor_top = 1.0 - clamp(fraction, 0.0, 1.0)
	label.text = "%.1f" % remaining if remaining > 0.05 else ""
