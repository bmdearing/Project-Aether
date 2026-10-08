extends Control
class_name LootLookCard
## The ItemCard of the drop the player is looking at (Player.loot_picker),
## beside the crosshair, with the pick-up key under it. Hold Alt for the
## card's details, same as in the inventory.

const ITEM_CARD_SCENE := preload("res://ui/item_card/ItemCard.tscn")
## Gap between the crosshair and the card's left edge.
const GAP := 64.0
const MARGIN := 12.0
## Share of the screen height kept clear at the bottom for the orbs and bars.
const BOTTOM_RESERVE := 0.17

var _card: ItemCard
var _prompt: Label
var _shown: LootPickup = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = ITEM_CARD_SCENE.instantiate()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	add_child(_card)
	_prompt = Label.new()
	_prompt.text = "%s  Pick up      Alt  Details" % _interact_key()
	_prompt.add_theme_font_size_override("font_size", 15)
	_prompt.add_theme_color_override("font_color", AetherStyle.TEXT)
	_prompt.add_theme_stylebox_override("normal", AetherStyle.glass_box(Color(AetherStyle.GOLD, 0.6), Color(0, 0, 0, 0.7), 1, 6.0))
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.visible = false
	add_child(_prompt)

func _process(_delta: float) -> void:
	var target := _current_target()
	if target != _shown:
		_shown = target
		if target and target.slate:
			_card.display_slate(target.slate)
		elif target:
			_card.display_item(target.item)
	_card.visible = target != null
	_prompt.visible = target != null
	if target:
		_place()

func _current_target() -> LootPickup:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or player.loot_picker == null:
		return null
	var target := player.loot_picker.target
	return target if is_instance_valid(target) and not target.is_queued_for_deletion() else null

## Right of the crosshair, vertically centred on it, kept on screen.
func _place() -> void:
	_card.reset_size()
	_prompt.reset_size()
	var view := get_viewport_rect().size
	var centre := view / 2.0
	var total_height := _card.size.y + 6.0 + _prompt.size.y
	var pos := Vector2(centre.x + GAP, centre.y - total_height / 2.0)
	pos.x = minf(pos.x, view.x - _card.size.x - MARGIN)
	pos.y = clampf(pos.y, MARGIN, maxf(view.y * (1.0 - BOTTOM_RESERVE) - total_height, MARGIN))
	_card.position = pos
	_prompt.position = Vector2(pos.x + (_card.size.x - _prompt.size.x) / 2.0, pos.y + _card.size.y + 6.0)

## The key bound to Interact, as a label ("E").
static func _interact_key() -> String:
	for event in InputMap.action_get_events("interact"):
		var key := event as InputEventKey
		if key:
			return OS.get_keycode_string(key.keycode if key.keycode != KEY_NONE else key.physical_keycode)
	return "Interact"
