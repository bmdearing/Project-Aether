extends CanvasLayer
class_name AbilityBar
## The four equipped spells as one engraved plate of gem-cut tiles: element
## tint and spell icon, Mana cost, key on a diamond below, a dial sweep while
## a spell recharges, dimmed when there isn't enough Mana. An invisible
## ItemSlotButton sits on each tile so hovering still shows the spell card.
## Casting happens in PlayerAbilityCast; this only displays.

const TILE := 70.0
const GAP := 6.0
const PAD := 10.0
const CUT := 10.0
## Plate centre, measured up from the bottom of the screen.
const CENTRE_FROM_BOTTOM := 120.0

const ERROR_FLASH_COLOR := Color(1.0, 0.25, 0.25)
const ERROR_TEXT_HOLD_SEC := 1.0
const ERROR_TEXT_FADE_SEC := 0.5
const ERROR_FLASH_SEC := 0.3

@onready var slot_row: HBoxContainer = $SlotRow

var _player: Player
var _plate: SkillPlate
var _slot_icons: Array[ItemSlotButton] = []
var _cast_error_label: Label
var _cast_error_tween: Tween
## The bar shows the stance page while a Spell Library stance is held.
var _showing_spell_page: bool = false

static func plate_size() -> Vector2:
	var count := AbilityLoadoutComponent.SLOT_COUNT
	return Vector2(count * TILE + (count - 1) * GAP + PAD * 2.0, TILE + PAD * 2.0)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_tree().get_first_node_in_group("player") as Player
	var size := plate_size()
	_plate = SkillPlate.new()
	_plate.bar = self
	_plate.anchor_left = 0.5
	_plate.anchor_right = 0.5
	_plate.anchor_top = 1.0
	_plate.anchor_bottom = 1.0
	_plate.offset_left = -size.x / 2.0
	_plate.offset_right = size.x / 2.0
	_plate.offset_top = -CENTRE_FROM_BOTTOM - size.y / 2.0
	_plate.offset_bottom = -CENTRE_FROM_BOTTOM + size.y / 2.0
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plate)
	move_child(_plate, 0)
	slot_row.anchor_left = 0.5
	slot_row.anchor_right = 0.5
	slot_row.offset_left = _plate.offset_left + PAD
	slot_row.offset_right = _plate.offset_right - PAD
	slot_row.offset_top = _plate.offset_top + PAD
	slot_row.offset_bottom = _plate.offset_bottom - PAD
	slot_row.add_theme_constant_override("separation", int(GAP))
	for i in range(AbilityLoadoutComponent.SLOT_COUNT):
		_build_slot()
	if is_instance_valid(_player):
		_player.ability_loadout.loadout_changed.connect(_refresh_all_slots)
	_build_cast_error_label()
	EventBus.ability_cast_failed.connect(_on_ability_cast_failed)
	_refresh_all_slots()

func _build_slot() -> void:
	var icon := ItemSlotButton.new()
	icon.custom_minimum_size = Vector2(TILE, TILE)
	icon.flat = true
	icon.show_icon = false
	icon.focus_mode = Control.FOCUS_NONE
	icon.mouse_filter = Control.MOUSE_FILTER_PASS  # hoverable for the card, doesn't eat clicks
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		icon.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	slot_row.add_child(icon)
	_slot_icons.append(icon)

func _build_cast_error_label() -> void:
	_cast_error_label = Label.new()
	_cast_error_label.anchor_left = 0.5
	_cast_error_label.anchor_right = 0.5
	_cast_error_label.anchor_top = 1.0
	_cast_error_label.anchor_bottom = 1.0
	_cast_error_label.offset_left = -200.0
	_cast_error_label.offset_right = 200.0
	_cast_error_label.offset_bottom = _plate.offset_top - 16.0
	_cast_error_label.offset_top = _cast_error_label.offset_bottom - 28.0
	_cast_error_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_cast_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cast_error_label.add_theme_font_override("font", AetherStyle.serif())
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
	if slot_index >= 0:
		_plate.flash(slot_index)
	if _cast_error_tween:
		_cast_error_tween.kill()
	_cast_error_label.text = reason
	_cast_error_label.modulate.a = 1.0
	_cast_error_label.visible = true
	_cast_error_tween = create_tween()
	_cast_error_tween.tween_interval(ERROR_TEXT_HOLD_SEC)
	_cast_error_tween.tween_property(_cast_error_label, "modulate:a", 0.0, ERROR_TEXT_FADE_SEC)
	_cast_error_tween.tween_callback(func(): _cast_error_label.visible = false)

func _process(_delta: float) -> void:
	visible = not AetherStyle.menu_open(get_tree())
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
		return
	var on_page := _player.caster_stance != null and _player.caster_stance.uses_spell_page()
	if on_page != _showing_spell_page:
		_showing_spell_page = on_page
		_refresh_all_slots()
	_plate.queue_redraw()

func _refresh_all_slots() -> void:
	for i in range(_slot_icons.size()):
		var ability := get_slot_ability(i)
		_slot_icons[i].ability = ability
		_slot_icons[i].text = ""
		_slot_icons[i].tooltip_text = ability.display_name if ability else ""

func get_slot_ability(index: int) -> Ability:
	return _player.ability_cast.get_bar_ability(index) if is_instance_valid(_player) else null

func get_player() -> Player:
	return _player

class SkillPlate extends Control:
	var bar: AbilityBar
	var _flash: Dictionary = {}  # slot index -> seconds left

	func flash(index: int) -> void:
		_flash[index] = AbilityBar.ERROR_FLASH_SEC

	func _process(delta: float) -> void:
		for i in _flash.keys():
			_flash[i] -= delta
			if _flash[i] <= 0.0:
				_flash.erase(i)

	func _draw() -> void:
		AetherStyle.plate(self, Rect2(Vector2.ZERO, size))
		var player := bar.get_player()
		for i in AbilityLoadoutComponent.SLOT_COUNT:
			var rect := Rect2(Vector2(AbilityBar.PAD + i * (AbilityBar.TILE + AbilityBar.GAP), AbilityBar.PAD), Vector2(AbilityBar.TILE, AbilityBar.TILE))
			_draw_tile(rect, i, bar.get_slot_ability(i), player)

	func _draw_tile(rect: Rect2, index: int, ability: Ability, player: Player) -> void:
		var shape := AetherStyle.facet(rect, AbilityBar.CUT)
		draw_colored_polygon(shape, AetherStyle.GLASS_LIGHT)
		var numbers := AetherStyle.numbers()
		var c := rect.get_center()
		var border := AetherStyle.GOLD
		if ability:
			var element: Color = Constants.DAMAGE_TYPE_COLOR.get(ability.damage_type, AetherStyle.TEXT)
			var cost := ability.get_mana_cost(player.stat_sheet) if player else 0.0
			var starved := player != null and player.mana.current_mana < cost
			var inner := PackedVector2Array()
			for v in shape:
				inner.append(c + (v - c) * 0.8)
			draw_colored_polygon(inner, Color(element, 0.14))
			AetherStyle.outline(self, inner, Color(element, 0.45), 1.0)
			SpellArt.draw(self, ability, rect.grow(-7.0))
			if player:
				var remaining := player.ability_cast.get_cooldown_remaining(ability)
				var total := ability.get_final_cooldown(player.get_action_speed_multiplier(), player.stat_sheet)
				if remaining > 0.05 and total > 0.0:
					AetherStyle.dial(self, rect.grow(-2), remaining / total)
					AetherStyle.text(self, numbers, Vector2(rect.position.x, c.y + 8.0), "%.1f" % remaining, 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
			if starved:
				draw_colored_polygon(shape, Color(0.05, 0.1, 0.35, 0.45))
			if ability.ability_id == "booming_blade" and GameState.booming_blade_on:
				border = element.lerp(Color.WHITE, 0.35)  # toggled on
				AetherStyle.outline(self, inner, Color(element, 0.9), 2.0)
			AetherStyle.text(self, numbers, Vector2(rect.end.x - 30.0, rect.position.y + 15.0), "%d" % roundi(cost), 12, Color(1, 0.4, 0.4) if starved else AetherStyle.MANA.lightened(0.45), HORIZONTAL_ALIGNMENT_RIGHT, 24)
		else:
			border = AetherStyle.GOLD_DIM
		if _flash.has(index):
			draw_colored_polygon(shape, Color(AbilityBar.ERROR_FLASH_COLOR, 0.35 * _flash[index] / AbilityBar.ERROR_FLASH_SEC))
			border = AbilityBar.ERROR_FLASH_COLOR
		AetherStyle.outline(self, shape, border, 1.8)
		AetherStyle.diamond(self, Vector2(c.x, rect.end.y), 9.0, AetherStyle.GLASS, AetherStyle.GOLD)
		AetherStyle.text(self, numbers, Vector2(c.x - 10.0, rect.end.y + 5.0), str(index + 1), 13, AetherStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 20)
