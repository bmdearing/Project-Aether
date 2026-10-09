extends GridContainer
class_name UniqueTabView
## The stash's Unique tab: one named slot per UniqueCatalog entry (Stash.uniques),
## Mythics first. A filled slot shows the item's card on hover; clicking it
## sends the item back to the inventory.

signal slot_clicked(id: String)

const ITEM_CARD_SCENE := preload("res://ui/item_card/ItemCard.tscn")
const SLOT_SIZE := Vector2(172, 58)
const COLUMNS := 3

var stash: Stash
## Optional (def, item) -> bool: true fades the slot (a stash search miss).
var dimmed: Callable

func _ready() -> void:
	columns = COLUMNS
	add_theme_constant_override("h_separation", 8)
	add_theme_constant_override("v_separation", 8)

func refresh() -> void:
	for child in get_children():
		child.queue_free()
	var defs := UniqueCatalog.DEFS.duplicate()
	defs.sort_custom(func(a, b): return a["rarity"] > b["rarity"])
	for def in defs:
		var slot := UniqueSlot.new()
		slot.def = def
		slot.item = stash.uniques.get(def["id"]) if stash else null
		slot.custom_minimum_size = SLOT_SIZE
		slot.tooltip_text = def["name"]
		slot.clicked.connect(func(): slot_clicked.emit(def["id"]))
		if dimmed.is_valid() and dimmed.call(def, slot.item):
			slot.modulate.a = 0.25
		add_child(slot)

class UniqueSlot extends Control:
	signal clicked
	var def: Dictionary
	var item: Item

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and item != null \
				and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
			clicked.emit()
			accept_event()

	func _make_custom_tooltip(_for_text: String) -> Object:
		# Empty slots preview the unique; null falls back to the plain name tooltip.
		var shown: Item = item if item else UniqueRoller.build(def, 1)
		if shown == null:
			return null
		var card: ItemCard = ITEM_CARD_SCENE.instantiate()
		card.display_item(shown)
		return card

	func _draw() -> void:
		var color: Color = Constants.ITEM_RARITY_COLOR.get(def["rarity"], Color.WHITE)
		var rect := Rect2(Vector2.ZERO, size)
		var filled := item != null
		draw_rect(rect, Color(color, 0.16) if filled else Color(0.04, 0.04, 0.05, 0.85))
		draw_rect(rect, Color(color, 0.9) if filled else Color(color, 0.25), false, 2.0 if filled else 1.0)
		var font := AetherStyle.serif()
		AetherStyle.text(self, font, Vector2(8, 24), def["name"], 13, color if filled else Color(color, 0.4), HORIZONTAL_ALIGNMENT_LEFT, size.x - 16)
		var sub := "Mythic" if def["rarity"] == Constants.ItemRarity.MYTHIC else "Unique"
		AetherStyle.text(self, font, Vector2(8, 46), sub if filled else "%s  ·  empty" % sub, 12, Color(0.75, 0.72, 0.66, 0.9 if filled else 0.35), HORIZONTAL_ALIGNMENT_LEFT, size.x - 16)
