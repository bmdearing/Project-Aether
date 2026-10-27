extends Control
class_name PlayerStatusRow
## The player's status effects and buffs in the HUD's top-left corner: one
## icon each (StatusIcons), buffs first, then everything else in the order it
## landed. Timed ones have a bar under the icon draining with the time left
## and the seconds under that; ones with no duration (auras, Grevane's Debt)
## show the icon alone. Stacks sit in the icon's corner.

const ICON := 34.0
const GAP := 6.0
const BAR_HEIGHT := 3.0
const TIME_FONT_SIZE := 13

var player: Player

## id -> the longest time left seen since it last went up, so the bar shows a
## share of the full duration and refills when the effect is refreshed.
var _full: Dictionary = {}
var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = AetherStyle.numbers()

func _process(_delta: float) -> void:
	queue_redraw()

## What to show this frame: {"id", "left" (seconds, < 0 = no timer), "stacks"}.
func entries() -> Array[Dictionary]:
	var buffs: Array[Dictionary] = []
	var rest: Array[Dictionary] = []
	if player == null or not is_instance_valid(player):
		return buffs
	var cast := player.ability_cast
	if cast:
		if cast.has_frost_armor():
			buffs.append({"id": "frost_armor", "left": cast.frost_armor_remaining(), "stacks": 1})
		for a in cast.active_auras():
			var aura_id := "death_shroud" if a.ability_id == "death_shroud" else "aura:" + a.ability_id
			buffs.append({"id": aura_id, "left": -1.0, "stacks": 1})
		for id in GameState.toggled_spells:
			buffs.append({"id": id, "left": -1.0, "stacks": 1})
	if player.stance_attack and player.stance_attack.flow_stacks > 0:
		buffs.append({"id": "flow", "left": -1.0, "stacks": player.stance_attack.flow_stacks})
	var uniques := player.unique_effects
	if uniques:
		for id in uniques.timed_more:
			buffs.append({"id": String(id), "left": float(uniques.timed_more[id]["left"]), "stacks": 1})
		if uniques.has(UniqueEffects.DEBT) and uniques.debt_stacks > 0:
			buffs.append({"id": "debt", "left": -1.0, "stacks": uniques.debt_stacks})
	var effects := player.status_effects
	if effects:
		for id in effects.active_effects():
			var entry := {"id": id, "left": effects.remaining(id), "stacks": effects.stacks(id)}
			if StatusIcons.is_buff(id):
				buffs.append(entry)
			else:
				rest.append(entry)
	buffs.append_array(rest)
	return buffs

func _draw() -> void:
	var shown := entries()
	var ids: Array[String] = []
	for e in shown:
		ids.append(e["id"])
	for id in _full.keys():
		if not ids.has(id):
			_full.erase(id)
	var x := 0.0
	for e in shown:
		var id: String = e["id"]
		var left: float = e["left"]
		var rect := Rect2(x, 0.0, ICON, ICON)
		StatusIcons.draw(self, id, rect)
		if left >= 0.0:
			if left > float(_full.get(id, 0.0)) + 0.05:
				_full[id] = left
			var full: float = _full.get(id, left)
			var bar := Rect2(x, ICON + 2.0, ICON, BAR_HEIGHT)
			draw_rect(bar, Color(0, 0, 0, 0.6))
			if full > 0.0:
				draw_rect(Rect2(bar.position, Vector2(ICON * clampf(left / full, 0.0, 1.0), BAR_HEIGHT)), StatusIcons.colour_of(id))
			var text := time_text(left)
			var at := Vector2(x, ICON + BAR_HEIGHT + 4.0 + TIME_FONT_SIZE)
			draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_CENTER, ICON, TIME_FONT_SIZE, 4, Color(0, 0, 0, 0.9))
			draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_CENTER, ICON, TIME_FONT_SIZE, Color(0.95, 0.93, 0.88))
		var n: int = e["stacks"]
		if n > 1:
			var s := str(n)
			var fs := 15
			var at := Vector2(x + ICON - fs * 0.6 * s.length() - 1.0, ICON - 2.0)
			draw_string_outline(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.95))
			draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		x += ICON + GAP

## Tenths under 10 s (short stuns read properly), whole seconds above.
static func time_text(left: float) -> String:
	return "%.1f" % left if left < 10.0 else str(ceili(left))
