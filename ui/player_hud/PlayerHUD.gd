extends CanvasLayer
class_name PlayerHUD
## Always-on readout of Health/Mana/Ward and the currently active weapon,
## user-requested ("see their health, mana, what weapon is equipped, show
## what it looks like when they swap"). Bars are plain ColorRect fills
## (background + a foreground rect whose width scales with current/max
## via anchor_right) - same placeholder-art convention as everything else
## in this project, no real art/textures anywhere yet.
##
## Health/Mana/Ward push-update via their component's own *_changed
## signal (WardComponent didn't have one before this - added to match
## Health/Mana's existing pattern) rather than polling per-frame. The
## initial read is deferred via call_deferred() rather than done inline
## in _ready() - HealthComponent's current_health assignment is itself
## deferred (see its own header comment on why), so reading it
## synchronously here would catch it before that's run and show 0 HP for
## a frame.
##
## Weapon swaps listen to EventBus.weapon_swapped (new - Player.gd's
## _active_weapon_slot was private and nothing outside Player needed to
## know when it changed before now) and play a brief flash/scale-punch
## Tween on the weapon icon so a swap is visibly readable on the HUD
## itself, not just the 3D viewmodel mesh swap that already existed.

const BAR_WIDTH := 200.0
const BAR_HEIGHT := 22.0
const HEALTH_COLOR := Color(0.75, 0.15, 0.15)
const MANA_COLOR := Color(0.25, 0.45, 0.85)
const WARD_COLOR := Color(0.55, 0.55, 0.95)
const EMPTY_BG_COLOR := Color(0.12, 0.12, 0.14, 0.85)
const WEAPON_ICON_SIZE := 56.0
const SWAP_PUNCH_DURATION := 0.2

@onready var bars: VBoxContainer = $Bars
@onready var weapon_indicator: HBoxContainer = $WeaponIndicator

var _player: Player
var _health_fill: ColorRect
var _health_label: Label
var _mana_fill: ColorRect
var _mana_label: Label
var _ward_fill: ColorRect
var _ward_bar_root: Control
var _ward_label: Label
var _weapon_icon: ItemSlotButton
var _weapon_name_label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_tree().get_first_node_in_group("player") as Player

	var health_bar := _build_bar(HEALTH_COLOR)
	bars.add_child(health_bar["root"])
	_health_fill = health_bar["fill"]
	_health_label = health_bar["label"]

	var mana_bar := _build_bar(MANA_COLOR)
	bars.add_child(mana_bar["root"])
	_mana_fill = mana_bar["fill"]
	_mana_label = mana_bar["label"]

	var ward_bar := _build_bar(WARD_COLOR)
	bars.add_child(ward_bar["root"])
	_ward_bar_root = ward_bar["root"]
	_ward_fill = ward_bar["fill"]
	_ward_label = ward_bar["label"]

	_build_weapon_indicator()

	if is_instance_valid(_player):
		_player.health.health_changed.connect(_on_health_changed)
		_player.mana.mana_changed.connect(_on_mana_changed)
		_player.ward.ward_changed.connect(_on_ward_changed)
		EventBus.weapon_swapped.connect(_on_weapon_swapped)
		call_deferred("_initial_refresh")

func _initial_refresh() -> void:
	if not is_instance_valid(_player):
		return
	_on_health_changed(_player.health.current_health, _player.health.max_health)
	_on_mana_changed(_player.mana.current_mana, _player.mana.max_mana)
	_on_ward_changed(_player.ward.current_ward, _player.ward.max_ward)
	_refresh_weapon_indicator()

func _build_bar(color: Color) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)

	var bg := ColorRect.new()
	bg.color = EMPTY_BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var fill := ColorRect.new()
	fill.color = color
	fill.anchor_left = 0.0
	fill.anchor_top = 0.0
	fill.anchor_right = 1.0
	fill.anchor_bottom = 1.0
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fill)

	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(label)

	return {"root": root, "fill": fill, "label": label}

func _build_weapon_indicator() -> void:
	_weapon_icon = ItemSlotButton.new()
	_weapon_icon.custom_minimum_size = Vector2(WEAPON_ICON_SIZE, WEAPON_ICON_SIZE)
	_weapon_icon.pivot_offset = Vector2(WEAPON_ICON_SIZE, WEAPON_ICON_SIZE) / 2.0
	_weapon_icon.clip_text = true
	_weapon_icon.mouse_filter = Control.MOUSE_FILTER_PASS  # still hoverable for the stat-card tooltip, doesn't need to be clickable here
	weapon_indicator.add_child(_weapon_icon)

	_weapon_name_label = Label.new()
	_weapon_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	weapon_indicator.add_child(_weapon_name_label)

func _on_health_changed(current: float, max_value: float) -> void:
	_update_bar(_health_fill, _health_label, "HP", current, max_value)

func _on_mana_changed(current: float, max_value: float) -> void:
	_update_bar(_mana_fill, _mana_label, "MP", current, max_value)

func _on_ward_changed(current: float, max_value: float) -> void:
	_update_bar(_ward_fill, _ward_label, "Ward", current, max_value)
	_ward_bar_root.visible = max_value > 0.0

func _update_bar(fill: ColorRect, label: Label, prefix: String, current: float, max_value: float) -> void:
	var fraction: float = current / max_value if max_value > 0.0 else 0.0
	fill.anchor_right = clamp(fraction, 0.0, 1.0)
	label.text = "%s %.0f/%.0f" % [prefix, current, max_value]

func _on_weapon_swapped(player: Node) -> void:
	if player != _player:
		return
	_refresh_weapon_indicator()
	_play_swap_flash()

func _refresh_weapon_indicator() -> void:
	var weapon: Weapon = _player.get_active_weapon()
	_weapon_icon.item = weapon
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(4)
	if weapon:
		_weapon_icon.tooltip_text = weapon.display_name
		box.bg_color = Constants.DAMAGE_TYPE_COLOR.get(weapon.native_damage_type, Color.WHITE)
		_weapon_name_label.text = weapon.display_name
	else:
		_weapon_icon.tooltip_text = ""
		box.bg_color = EMPTY_BG_COLOR
		_weapon_name_label.text = "No weapon"
	_weapon_icon.add_theme_stylebox_override("normal", box)
	_weapon_icon.add_theme_stylebox_override("hover", box)
	_weapon_icon.add_theme_stylebox_override("pressed", box)

func _play_swap_flash() -> void:
	_weapon_icon.scale = Vector2(0.7, 0.7)
	_weapon_icon.modulate = Color(1.6, 1.6, 1.6)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_weapon_icon, "scale", Vector2.ONE, SWAP_PUNCH_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_weapon_icon, "modulate", Color.WHITE, SWAP_PUNCH_DURATION)
