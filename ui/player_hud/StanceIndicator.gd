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
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 16)
	add_child(_label)
	_player = get_tree().get_first_node_in_group("player") as Player
	if is_instance_valid(_player):
		_player.weapon_stance.stance_page_changed.connect(func(_page): _refresh())
		EventBus.weapon_swapped.connect(func(_p): _refresh())
		_player.equipment.equipment_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(_player):
		visible = false
		return
	var weapon := _player.get_active_weapon()
	if weapon == null or weapon.is_ranged:
		visible = false
		return
	visible = true
	var page_name := "A" if _player.weapon_stance.active_page == WeaponStance.StancePage.A else "B"
	_label.text = "Stance %s - %s" % [page_name, weapon.weapon_type]
