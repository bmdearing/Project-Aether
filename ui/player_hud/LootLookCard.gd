extends Control
class_name LootLookCard
## The ItemCard of the drop the player is looking at (Player.loot_picker),
## beside the crosshair, with the pick-up key under it. Hold Alt for the
## card's details, same as in the inventory.
##
## A card takes 2-7 ms to build, and building it on screen when a drop was
## first looked at hitched. Cards for drops near the player are built ahead,
## hidden, one per frame; looking at one only shows it.

## Gap between the crosshair and the card's left edge.
const GAP := 64.0
const MARGIN := 12.0
## Share of the screen height kept clear at the bottom for the orbs and bars.
const BOTTOM_RESERVE := 0.17
## Drops this close to the player get their card built ahead.
const PREBUILD_RANGE := 14.0
const MAX_CARDS := 24

## The card on show; a blank hidden one when nothing is targeted.
var _card: ItemCard
var _blank: ItemCard
var _prompt: Label
var _shown: LootPickup = null
## pickup instance id -> {pickup: WeakRef, card: ItemCard, key: Array}
var _cards: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blank = _new_card()
	_card = _blank
	_prompt = Label.new()
	_prompt.text = "%s  Pick up      Alt  Details" % _interact_key()
	_prompt.add_theme_font_size_override("font_size", 15)
	_prompt.add_theme_color_override("font_color", AetherStyle.TEXT)
	_prompt.add_theme_stylebox_override("normal", AetherStyle.glass_box(Color(AetherStyle.GOLD, 0.6), Color(0, 0, 0, 0.7), 1, 6.0))
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.visible = false
	add_child(_prompt)

func _new_card() -> ItemCard:
	var card := ItemSlotButton.new_item_card()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.visible = false
	add_child(card)
	return card

func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	var target := _current_target(player)
	_drop_gone(player)
	if target != _shown:
		_card.visible = false
		_shown = target
		_card = _card_for(target) if target else _blank
	elif target and _cards.has(target.get_instance_id()) and _cards[target.get_instance_id()]["key"] != _key(target):
		# A weapon swap, gear change or stance change alters what the card says.
		_card.visible = false
		_card = _card_for(target)
	else:
		_prebuild_one(player)
	_card.visible = target != null
	_prompt.visible = target != null
	if target:
		_place()

func _current_target(player: Player) -> LootPickup:
	if player == null or player.loot_picker == null:
		return null
	var target := player.loot_picker.target
	return target if is_instance_valid(target) and not target.is_queued_for_deletion() else null

## What a built card depends on besides the drop itself.
func _key(pickup: LootPickup) -> Array:
	if pickup.item and not pickup.slate and pickup.currency_id == &"":
		return [ItemCompare.equipped_for(pickup.item), GameState.stance_page]
	return []

## The pickup's card, built now if it isn't built or is out of date.
func _card_for(pickup: LootPickup) -> ItemCard:
	var id := pickup.get_instance_id()
	var key := _key(pickup)
	var entry: Dictionary = _cards.get(id, {})
	if not entry.is_empty() and entry["key"] == key:
		return entry["card"]
	var card: ItemCard = entry["card"] if not entry.is_empty() else _new_card()
	if pickup.slate:
		card.display_slate(pickup.slate)
	elif pickup.currency_id != &"":
		card.display_currency(pickup.currency_id, pickup.currency_count)
	else:
		card.compare_against = key[0]
		card.display_item(pickup.item)
	_cards[id] = {"pickup": weakref(pickup), "card": card, "key": key}
	return card

## Builds the card of the nearest drop in range that has none yet.
func _prebuild_one(player: Player) -> void:
	if player == null or _cards.size() >= MAX_CARDS or AetherStyle.menu_open(get_tree()):
		return
	var best: LootPickup = null
	var best_d := PREBUILD_RANGE * PREBUILD_RANGE
	for node in get_tree().get_nodes_in_group(LootPickup.LOOK_GROUP):
		var pickup := node as LootPickup
		if pickup == null or pickup.is_queued_for_deletion() or _cards.has(pickup.get_instance_id()):
			continue
		var d := pickup.global_position.distance_squared_to(player.global_position)
		if d < best_d:
			best = pickup
			best_d = d
	if best:
		_card_for(best)

## Frees the cards of drops that were picked up, despawned or left far behind.
func _drop_gone(player: Player) -> void:
	for id in _cards.keys():
		var pickup := (_cards[id]["pickup"] as WeakRef).get_ref() as LootPickup
		var left := pickup != null and player != null and pickup != _shown \
				and pickup.global_position.distance_to(player.global_position) > PREBUILD_RANGE * 2.0
		if pickup == null or pickup.is_queued_for_deletion() or left:
			var card: ItemCard = _cards[id]["card"]
			if card == _card:
				_card = _blank
				_shown = null
			card.queue_free()
			_cards.erase(id)

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
