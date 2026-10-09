extends Control
class_name CurrencyTabView
## The stash's Currency tab, laid out like Path of Exile's: every currency
## has its own fixed slot, grouped (Orbs, stones, fragments, Brands,
## Edicts), showing the total held. Empty slots show the currency faded.
## Storage is still the stash's CURRENCY GridInventory; this only shows it.
## Click a slot to take a stack (Shift or Ctrl: as much as fits); drop
## currency from the inventory anywhere on the tab to store it.

signal slot_clicked(id: StringName, take_all: bool)
signal currency_dropped(data: Dictionary)

const SLOT := 52.0
const PITCH := 58.0
const PAD := 18.0
const ORBS: Array[StringName] = [&"quickening", &"grafting", &"severance", &"reckoning", &"tempering", &"elevation",
	&"recasting", &"ascendant", &"absolution", &"opening", &"forging", &"anchoring"]
const STONES: Array[StringName] = [&"infusion_stone", &"shrivening_stone", &"shard_of_tharsis", &"crystallized_aether"]
const FRAGMENTS: Array[StringName] = [&"maw_fragment_ash", &"maw_fragment_tide", &"maw_fragment_storm", &"maw_fragment_hollow"]
const DAMAGE_BRANDS: Array[StringName] = [&"brand_kinetic", &"brand_piercing", &"brand_explosive", &"brand_fire", &"brand_cold",
	&"brand_lightning", &"brand_aetheric", &"brand_entropic", &"brand_pale"]
const DEFENCE_BRANDS: Array[StringName] = [&"brand_armor", &"brand_evasion", &"brand_ward", &"brand_resistance", &"brand_resilience", &"brand_mana"]
const EDICTS: Array[StringName] = [&"edict_prefix", &"edict_suffix", &"edict_spell", &"edict_attack"]
const OTHER_BRANDS: Array[StringName] = [&"brand_spell", &"brand_attack", &"brand_speed", &"brand_prefix", &"brand_suffix", &"brand_preservation"]
const COLUMNS := 12

## Each group: top-left in slot units, columns, ids.
var _groups: Array[Dictionary] = [
	{"at": Vector2(0, 0), "cols": 6, "ids": ORBS},
	{"at": Vector2(7, 0), "cols": 2, "ids": STONES},
	{"at": Vector2(10, 0), "cols": 2, "ids": FRAGMENTS},
	{"at": Vector2(0, 2.5), "cols": 5, "ids": DAMAGE_BRANDS},
	{"at": Vector2(6, 2.5), "cols": 3, "ids": DEFENCE_BRANDS},
	{"at": Vector2(10, 2.5), "cols": 2, "ids": EDICTS},
	{"at": Vector2(3, 5.0), "cols": 6, "ids": OTHER_BRANDS},
]

var inventory: GridInventory
var currency_hint: Callable
## Optional (id) -> bool: true fades that slot (a stash search miss).
var dimmed: Callable
var _slots: Dictionary = {}  # id -> CurrencySlot
var _frames: Array[Rect2] = []
var _extra_group := {"at": Vector2(0, 6.5), "cols": COLUMNS, "ids": [] as Array[StringName]}

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func set_inventory(inv: GridInventory) -> void:
	inventory = inv
	refresh()

## Builds the slots once (plus one per unlisted currency held), then
## updates every count.
func refresh() -> void:
	var extra: Array[StringName] = []
	if inventory:
		for e in inventory.get_entries():
			if e.is_currency() and not _slots.has(e.content) and not extra.has(e.content) and not _listed(e.content):
				extra.append(e.content)
	for id in extra:
		_extra_group["ids"].append(id)
	if _slots.is_empty() or not extra.is_empty():
		_layout()
	for id in _slots:
		_slots[id].count = inventory.count_of(id) if inventory else 0
		_slots[id].modulate.a = 0.3 if dimmed.is_valid() and dimmed.call(id) else 1.0

func _listed(id: StringName) -> bool:
	for g in _groups:
		if g["ids"].has(id):
			return true
	return false

func _layout() -> void:
	var groups := _groups.duplicate()
	if not _extra_group["ids"].is_empty():
		groups.append(_extra_group)
	_frames.clear()
	var extent := Vector2.ZERO
	for g in groups:
		var ids: Array = g["ids"]
		var cols: int = g["cols"]
		var origin: Vector2 = g["at"] * PITCH + Vector2(PAD, PAD)
		var rows := ceili(float(ids.size()) / cols)
		for i in ids.size():
			var id: StringName = ids[i]
			var slot: CurrencySlot = _slots.get(id)
			if slot == null:
				slot = CurrencySlot.new()
				slot.view = self
				slot.id = id
				add_child(slot)
				_slots[id] = slot
			slot.position = origin + Vector2(i % cols, i / cols) * PITCH
			slot.size = Vector2(SLOT, SLOT)
		var frame := Rect2(origin - Vector2(6, 6), Vector2(cols, rows) * PITCH - Vector2(PITCH - SLOT, PITCH - SLOT) + Vector2(12, 12))
		_frames.append(frame)
		extent = extent.max(frame.end)
	custom_minimum_size = extent + Vector2(PAD, PAD) - Vector2(6, 6)
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, custom_minimum_size)
	draw_rect(rect, Color(0.035, 0.04, 0.05, 0.95))
	draw_rect(rect.grow(-3), Color(AetherStyle.GOLD_DIM, 0.6), false, 1.5)
	draw_rect(rect.grow(-7), Color(AetherStyle.GOLD_FAINT, 0.35), false, 1.0)
	for frame in _frames:
		draw_rect(frame, Color(0.06, 0.07, 0.08, 0.9))
		draw_rect(frame, Color(AetherStyle.GOLD_FAINT, 0.5), false, 1.0)
	# Filigree corners.
	for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var c: Vector2 = rect.position + rect.size * corner
		var inward := Vector2(1.0 - 2.0 * corner.x, 1.0 - 2.0 * corner.y)
		AetherStyle.diamond(self, c + inward * 7.0, 4.0, AetherStyle.GOLD_DIM)

## "4999", "50K", "40.5K".
static func short_count(n: int) -> String:
	if n < 10000:
		return str(n)
	var k := n / 1000.0
	return ("%dK" % int(k)) if k >= 100.0 or is_equal_approx(k, floorf(k)) else "%.1fK" % k

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("grid_entry") and (data["grid_entry"] as GridInventory.Entry).is_currency()

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	currency_dropped.emit(data)

class CurrencySlot extends Button:
	var view: CurrencyTabView
	var id: StringName
	var count: int = 0:
		set(value):
			count = value
			if _icon:
				_icon.modulate.a = 1.0 if count > 0 else 0.22
			tooltip_text = "%s x%d" % [CurrencyText.name_of(id), count]
			queue_redraw()
	var _icon: ItemIcon
	var _label: Label

	func _ready() -> void:
		focus_mode = Control.FOCUS_NONE
		AetherStyle.style_slot_button(self, CurrencyTabView.slot_accent(id))
		_icon = ItemIcon.fill(self)
		_icon.content = id
		_icon.offset_left = 5
		_icon.offset_top = 5
		_icon.offset_right = -5
		_icon.offset_bottom = -5
		_label = Label.new()
		_label.position = Vector2(3, -1)
		_label.add_theme_font_override("font", AetherStyle.numbers())
		_label.add_theme_font_size_override("font_size", 15)
		_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.82))
		_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_label.add_theme_constant_override("outline_size", 4)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)
		count = count

	func _draw() -> void:
		if _label:
			_label.text = CurrencyTabView.short_count(count) if count > 0 else ""

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
			view.slot_clicked.emit(id, event.shift_pressed or event.ctrl_pressed)
			accept_event()

	func _make_custom_tooltip(_for_text: String) -> Object:
		var card: ItemCard = ItemSlotButton.ITEM_CARD_SCENE.instantiate()
		var hint := "Click to take a stack. Shift-click to take as much as fits." if count > 0 else "None stored."
		card.display_currency(id, count, hint)
		return card

	func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
		return view._can_drop_data(at_position, data)

	func _drop_data(at_position: Vector2, data: Variant) -> void:
		view._drop_data(at_position, data)

static func slot_accent(id: StringName) -> Color:
	var s := String(id)
	if s.begins_with("brand_"):
		return Color(0.6, 0.25, 0.25)
	if s.begins_with("edict_"):
		return Color(0.5, 0.4, 0.7)
	if s.begins_with("maw_fragment"):
		return Color(0.75, 0.45, 0.2)
	return AetherStyle.GOLD_DIM
