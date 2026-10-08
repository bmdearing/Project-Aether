extends Control
class_name StanceIndicator
## Bottom-right stance medallion: what holding RMB does with the current
## weapon (name above), the page (A/B) on a gem, a dial sweep with a
## countdown while the special recharges, and "RMB" below. Lights up while
## the stance is held; flashes red when a special is pressed early.

const RADIUS := 40.0
const NAME_HEIGHT := 24.0
const FOOT_HEIGHT := 18.0
const PAD := 12.0
const DENIED := Color(0.95, 0.2, 0.2)
const DENIED_FLASH := 0.35

var _player: Player
var _name: String = ""
var _glyph: String = ""
var _page: String = ""
var _cooldown: float = 0.0
var _cooldown_total: float = 0.0
var _denied: float = 0.0

static func box_size() -> Vector2:
	return Vector2((RADIUS + PAD) * 2.0, NAME_HEIGHT + (RADIUS + PAD) * 2.0 + FOOT_HEIGHT)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = box_size()
	_player = get_tree().get_first_node_in_group("player") as Player
	EventBus.stance_on_cooldown.connect(func(_p, _r): _denied = DENIED_FLASH)

func _process(delta: float) -> void:
	_denied = maxf(_denied - delta, 0.0)
	_refresh()
	queue_redraw()

func _refresh() -> void:
	visible = false
	if not is_instance_valid(_player):
		return
	var weapon := _player.get_active_weapon()
	if weapon == null:
		return
	var info := {}
	_page = ""
	if _player.shield_block and _player.shield_block.overrides_stance():
		info = {"name": "Raise Shield"}
	elif _player.caster_stance and _player.caster_stance.get_source():
		info = StanceInfo.for_conduit(_player.caster_stance.get_source())
		_page = _page_letter()
	elif weapon.is_ranged:
		var dual := StanceInfo.RANGED_B.has(weapon.weapon_type)
		info = StanceInfo.for_weapon(weapon, int(_player.weapon_stance.active_page) if dual else 0)
		_page = _page_letter() if dual else ""
	else:
		info = StanceInfo.for_weapon(weapon, int(_player.weapon_stance.active_page))
		_page = _page_letter()
	if info.is_empty():
		return
	visible = true
	_name = info.get("name", "")
	if _player.stance_attack and _player.stance_attack.is_stealthed():
		_name += " (hidden)"
	_glyph = _initials(info.get("name", ""))
	var behavior := _player.weapon_stance.get_ready_behavior()
	_cooldown = _player.weapon_stance.get_cooldown_remaining(behavior)
	_cooldown_total = behavior.cooldown_seconds if behavior else 0.0

func _page_letter() -> String:
	return "A" if _player.weapon_stance.active_page == WeaponStance.StancePage.A else "B"

static func _initials(text: String) -> String:
	var letters := ""
	for word in text.split(" ", false):
		if word[0] == word[0].to_upper():
			letters += word[0]
	if letters.length() == 1:
		return text.left(2)
	return letters.left(2) if letters != "" else text.left(2)

func _draw() -> void:
	if not visible:
		return
	var serif := AetherStyle.title()
	var numbers := AetherStyle.numbers()
	var c := Vector2(size.x / 2.0, NAME_HEIGHT + RADIUS + PAD)
	var r := RADIUS
	AetherStyle.text(self, serif, Vector2(c.x - 100.0, NAME_HEIGHT - 6.0), _name, 16, AetherStyle.GOLD, HORIZONTAL_ALIGNMENT_CENTER, 200.0)
	draw_circle(c, r + 10.0, Color(0, 0, 0, 0.35))
	draw_circle(c, r, AetherStyle.GLASS_LIGHT)
	var on_cooldown := _cooldown > 0.0
	if not on_cooldown:
		AetherStyle.text(self, serif, Vector2(c.x - r, c.y + 11.0), _glyph, 30, AetherStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
	elif _cooldown_total > 0.0:
		AetherStyle.dial(self, Rect2(c - Vector2(r - 1.0, r - 1.0), Vector2(r - 1.0, r - 1.0) * 2.0), _cooldown / _cooldown_total, true)
		AetherStyle.text(self, numbers, Vector2(c.x - r, c.y + 9.0), str(ceili(_cooldown)), 24, AetherStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
	var ring := AetherStyle.GOLD
	var width := 2.5
	if _denied > 0.0:
		ring = DENIED
	elif on_cooldown:
		ring = AetherStyle.GOLD_DIM
	elif _player.weapon_stance.is_active:
		ring = AetherStyle.GOLD_BRIGHT
		width = 3.5
		draw_arc(c, r + 2.0, 0, TAU, 56, Color(AetherStyle.GOLD_BRIGHT, 0.3), 6.0, true)
	draw_arc(c, r, 0, TAU, 56, ring, width, true)
	AetherStyle.ticks(self, c, r + 4.0, 48, 4, AetherStyle.GOLD_DIM)
	if _page != "":
		var gem := c + Vector2(-r * 0.78, -r * 0.78)
		AetherStyle.diamond(self, gem, 10.0, Color(0.25, 0.18, 0.06), AetherStyle.GOLD)
		AetherStyle.text(self, serif, gem + Vector2(-10, 5), _page, 13, AetherStyle.GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER, 20)
	AetherStyle.text(self, serif, Vector2(c.x - r, size.y - 2.0), AetherStyle.spaced("RMB"), 11, AetherStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
