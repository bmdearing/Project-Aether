extends Control
class_name StanceIndicator
## Implementation Brief v3.4 Section 4 (2026-08-31): small bottom-left HUD
## readout for the active stance PAGE (A/B, see WeaponStance.
## toggle_stance_page()) - not the RMB-hold "is stance active" state,
## which has no dedicated indicator of its own (the camera FOV
## zoom/arm ready-pose already read as feedback for that). Hidden
## entirely for ranged weapons per the brief - "ranged has no dual
## stance." "Current stance name" (per the brief's own wording) has no
## dedicated name field on StanceBehavior to show - the active weapon's
## own weapon_type stands in for it, the closest real "name" this project
## has for what's currently equipped.

var _label: Label
var _player: Player

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 16)
	add_child(_label)
	_player = get_tree().get_first_node_in_group("player") as Player
	if is_instance_valid(_player):
		_player.weapon_stance.stance_page_changed.connect(func(_page): _refresh())
		EventBus.weapon_swapped.connect(func(_p): _refresh())
		_player.equipment.equipment_changed.connect(_refresh)
	_refresh()

## The Behaviors tab can change what RMB does without any signal firing.
func _process(_delta: float) -> void:
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(_player):
		visible = false
		return
	var weapon := _player.get_active_weapon()
	if weapon == null:
		visible = false
		return
	if _player.shield_block and _player.shield_block.overrides_stance():
		visible = true
		_label.text = "RMB - Raise Shield"
		return
	var conduit := _player.caster_stance.get_source() if _player.caster_stance else null
	if conduit:
		visible = true
		var page := int(_player.weapon_stance.active_page)
		_label.text = "Stance %s - %s" % ["A" if page == 0 else "B", StanceInfo.for_conduit(conduit).get("name", conduit.weapon_type)]
		return
	if weapon.is_ranged:
		var dual := StanceInfo.RANGED_B.has(weapon.weapon_type)
		var aim := StanceInfo.for_weapon(weapon, int(_player.weapon_stance.active_page) if dual else 0)
		visible = not aim.is_empty()
		_label.text = "Aim - %s" % aim.get("name", "")
		return
	visible = true
	var page := int(_player.weapon_stance.active_page)
	var info := StanceInfo.for_weapon(weapon, page)
	_label.text = "Stance %s - %s" % ["A" if page == 0 else "B", info.get("name", weapon.weapon_type)]
	if _player.stance_attack and _player.stance_attack.is_stealthed():
		_label.text += " (hidden)"
