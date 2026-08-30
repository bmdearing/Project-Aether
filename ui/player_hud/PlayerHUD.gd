extends CanvasLayer
class_name PlayerHUD
## Always-on readout of Life/Mana/Ward and the active weapon. Life and
## Mana are circular `StatOrb`s flanking the ability bar (Ward renders as
## a ring around the Life orb); XP is a notched, multi-color-gradient bar
## below the ability bar near the very bottom of the screen, with a level
## badge at its left end - GW2-style layout, per user reference. The
## gradient is a fixed-width texture revealed by a shrinking clip window
## (not stretched to fit), so the color at a given point along the bar
## stays put as it fills, same as GW2's. Placeholder art throughout,
## matching the rest of the project.
##
## Life/Mana/Ward push-update via their component's *_changed signal. The
## initial read is deferred via call_deferred() since HealthComponent's
## current_health assignment is itself deferred - a synchronous read here
## would catch it before that runs and show an empty orb for a frame.
##
## Weapon swaps listen to EventBus.weapon_swapped and play a brief
## flash/scale-punch Tween on the weapon icon.
##
## A top-left row of colored chips shows the player's own active status
## effects (Section 09), built/removed live off EventBus.status_effect_
## applied/_expired - the same signals StatusEffectComponent emits for
## Enemy's floating head icons.

const ABILITY_BAR_HALF_WIDTH := 136.0
const ORB_GAP := 16.0
const ORB_BOTTOM_OFFSET := -20.0
const ORB_HEIGHT := 108.0  # must match StatOrb's own computed min size (radius*2 + 16)

const XP_BAR_HEIGHT := 18.0
const XP_BAR_BOTTOM_OFFSET := -2.0
const XP_BAR_RIGHT_MARGIN := 24.0
const LEVEL_BADGE_SIZE := 30.0
const LEVEL_BADGE_GAP := 8.0
const XP_BAR_LEFT_MARGIN := 24.0 + LEVEL_BADGE_SIZE + LEVEL_BADGE_GAP  # screen edge -> badge -> bar start

const HEALTH_COLOR := Color(0.75, 0.15, 0.15)
const MANA_COLOR := Color(0.25, 0.45, 0.85)
const WARD_COLOR := Color(0.55, 0.55, 0.95)
const EMPTY_BG_COLOR := Color(0.12, 0.12, 0.14, 0.85)
const WEAPON_ICON_SIZE := 56.0
const SWAP_PUNCH_DURATION := 0.2

const STATUS_ROW_TOP_MARGIN := 16.0
const STATUS_ROW_LEFT_MARGIN := 16.0
const STATUS_CHIP_HEIGHT := 26.0
const STATUS_CHIP_MIN_WIDTH := 76.0
const STATUS_CHIP_GAP := 6.0
## Fixed stops along the bar, not tied to fill level - GW2's XP bar reads
## as a spectrum you reveal, not a color that changes with progress.
const XP_GRADIENT_COLORS := [
	Color(0.25, 0.5, 0.95),
	Color(0.25, 0.75, 0.75),
	Color(0.4, 0.8, 0.35),
	Color(0.9, 0.85, 0.25),
	Color(0.95, 0.55, 0.2),
	Color(0.85, 0.25, 0.4),
]

@onready var weapon_indicator: HBoxContainer = $WeaponIndicator

var _player: Player
var _life_orb: StatOrb
var _mana_orb: StatOrb
var _xp_fill_clip: Control
var _xp_label: Label
var _level_badge_label: Label
var _weapon_icon: ItemSlotButton
var _weapon_name_label: Label
var _gold_label: Label
var _last_gold: int = -1
var _status_row: HBoxContainer
var _status_chips: Dictionary = {}  # effect_id -> Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_tree().get_first_node_in_group("player") as Player

	_life_orb = _build_orb(HEALTH_COLOR, "Life", -ABILITY_BAR_HALF_WIDTH - ORB_GAP - ORB_HEIGHT, -ABILITY_BAR_HALF_WIDTH - ORB_GAP)
	_life_orb.ring_color = WARD_COLOR
	_mana_orb = _build_orb(MANA_COLOR, "Mana", ABILITY_BAR_HALF_WIDTH + ORB_GAP, ABILITY_BAR_HALF_WIDTH + ORB_GAP + ORB_HEIGHT)

	_build_xp_bar()
	_build_weapon_indicator()
	_build_gold_label()
	_build_status_row()

	if is_instance_valid(_player):
		_player.health.health_changed.connect(_on_health_changed)
		_player.mana.mana_changed.connect(_on_mana_changed)
		_player.ward.ward_changed.connect(_on_ward_changed)
		_player.experience.xp_changed.connect(_on_xp_changed)
		EventBus.weapon_swapped.connect(_on_weapon_swapped)
		EventBus.status_effect_applied.connect(_on_status_effect_applied)
		EventBus.status_effect_expired.connect(_on_status_effect_expired)
		call_deferred("_initial_refresh")

func _initial_refresh() -> void:
	if not is_instance_valid(_player):
		return
	_on_health_changed(_player.health.current_health, _player.health.max_health)
	_on_mana_changed(_player.mana.current_mana, _player.mana.max_mana)
	_on_ward_changed(_player.ward.current_ward, _player.ward.max_ward)
	_on_xp_changed(_player.experience.xp, _player.experience.xp_to_next_level())
	_refresh_weapon_indicator()

func _build_orb(color: Color, prefix: String, offset_left: float, offset_right: float) -> StatOrb:
	var orb := StatOrb.new()
	orb.fill_color = color
	orb.label_prefix = prefix
	orb.anchor_left = 0.5
	orb.anchor_right = 0.5
	orb.anchor_top = 1.0
	orb.anchor_bottom = 1.0
	orb.offset_left = offset_left
	orb.offset_right = offset_right
	orb.offset_bottom = ORB_BOTTOM_OFFSET
	orb.offset_top = ORB_BOTTOM_OFFSET - ORB_HEIGHT
	orb.grow_vertical = 0
	add_child(orb)
	return orb

## Spans from just right of the level badge to near the right screen edge
## (GW2's actual proportions - not just matching the ability-bar-group's
## own narrower width like the first pass here did).
func _build_xp_bar() -> void:
	var root := Control.new()
	root.anchor_left = 0.0
	root.anchor_right = 1.0
	root.anchor_top = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = XP_BAR_LEFT_MARGIN
	root.offset_right = -XP_BAR_RIGHT_MARGIN
	root.offset_bottom = XP_BAR_BOTTOM_OFFSET
	root.offset_top = XP_BAR_BOTTOM_OFFSET - XP_BAR_HEIGHT
	root.grow_horizontal = 2
	root.grow_vertical = 0
	add_child(root)

	var bg := ColorRect.new()
	bg.color = EMPTY_BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	# A clip window whose anchor_right grows with fill fraction, over a
	# FIXED-width gradient texture (not one that stretches to fit) - so
	# filling the bar reveals more of the same spectrum instead of
	# squishing it, matching how GW2's bar actually behaves.
	var fill_clip := Control.new()
	fill_clip.clip_contents = true
	fill_clip.anchor_left = 0.0
	fill_clip.anchor_top = 0.0
	fill_clip.anchor_right = 0.0
	fill_clip.anchor_bottom = 1.0
	fill_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fill_clip)
	_xp_fill_clip = fill_clip

	# The bar itself is now full-width (percentage-anchored, resolution-
	# independent), so its rendered pixel width isn't known until runtime -
	# computed here from the viewport rather than a compile-time constant.
	var bar_width: float = get_viewport().get_visible_rect().size.x - XP_BAR_LEFT_MARGIN - XP_BAR_RIGHT_MARGIN
	var gradient_rect := TextureRect.new()
	gradient_rect.texture = _build_xp_gradient_texture()
	gradient_rect.anchor_left = 0.0
	gradient_rect.anchor_top = 0.0
	gradient_rect.anchor_bottom = 1.0
	gradient_rect.offset_right = bar_width
	gradient_rect.stretch_mode = TextureRect.STRETCH_SCALE
	gradient_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill_clip.add_child(gradient_rect)

	var notches := NotchedBar.new()
	notches.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(notches)

	# In line with the bar itself (overlapping it), not floating above it -
	# an outline keeps it readable over every gradient color it crosses.
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(label)
	_xp_label = label

	_build_level_badge(root)

func _build_xp_gradient_texture() -> GradientTexture1D:
	var gradient := Gradient.new()
	# Gradient requires offsets.size() == colors.size() - without setting
	# offsets too, they stay at the default 2-element [0.0, 1.0] against
	# 6 colors, producing a garbled/reversed-looking result rather than
	# an even left-to-right spectrum.
	var count := XP_GRADIENT_COLORS.size()
	var offsets := PackedFloat32Array()
	for i in range(count):
		offsets.append(float(i) / float(count - 1))
	gradient.offsets = offsets
	gradient.colors = PackedColorArray(XP_GRADIENT_COLORS)
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 512
	return texture

## Sits just left of the bar's own left edge (like GW2's level circle
## overlapping the start of the XP bar), not inside its fillable area.
func _build_level_badge(xp_bar_root: Control) -> void:
	var badge := Control.new()
	badge.anchor_left = 0.0
	badge.anchor_right = 0.0
	badge.anchor_top = 0.5
	badge.anchor_bottom = 0.5
	badge.offset_left = -LEVEL_BADGE_SIZE - LEVEL_BADGE_GAP
	badge.offset_right = -LEVEL_BADGE_GAP
	badge.offset_top = -LEVEL_BADGE_SIZE / 2.0
	badge.offset_bottom = LEVEL_BADGE_SIZE / 2.0
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_bar_root.add_child(badge)

	var bg := ColorRect.new()
	bg.color = EMPTY_BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(bg)

	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(label)
	_level_badge_label = label

## Gold has no single owning component with a *_changed signal (spent/
## granted from several unrelated places) - polled in _process() instead.
func _build_gold_label() -> void:
	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 14)
	_gold_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	_gold_label.text = "Gold: %d" % GameState.gold
	weapon_indicator.add_child(_gold_label)

## Top-left row of colored chips, one per active status effect (Section
## 09) - built/removed live via EventBus.status_effect_applied/_expired,
## same push-update style as the orbs/XP bar above.
func _build_status_row() -> void:
	_status_row = HBoxContainer.new()
	_status_row.anchor_left = 0.0
	_status_row.anchor_top = 0.0
	_status_row.offset_left = STATUS_ROW_LEFT_MARGIN
	_status_row.offset_top = STATUS_ROW_TOP_MARGIN
	_status_row.add_theme_constant_override("separation", STATUS_CHIP_GAP)
	_status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_row)

func _on_status_effect_applied(target: Node, effect_id: String, _stacks: int) -> void:
	if target != _player or _status_chips.has(effect_id):
		return
	var chip := Label.new()
	chip.text = Constants.STATUS_EFFECT_NAME.get(effect_id, effect_id.capitalize())
	chip.custom_minimum_size = Vector2(STATUS_CHIP_MIN_WIDTH, STATUS_CHIP_HEIGHT)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_theme_font_size_override("font_size", 13)
	var dmg_type: Constants.DamageType = Constants.STATUS_EFFECT_DAMAGE_TYPE.get(effect_id, Constants.DamageType.KINETIC)
	var box := StyleBoxFlat.new()
	box.bg_color = Constants.DAMAGE_TYPE_COLOR.get(dmg_type, Color.WHITE)
	box.set_corner_radius_all(4)
	chip.add_theme_stylebox_override("normal", box)
	chip.add_theme_color_override("font_color", Constants.get_contrasting_text_color(box.bg_color))
	_status_row.add_child(chip)
	_status_chips[effect_id] = chip

func _on_status_effect_expired(target: Node, effect_id: String) -> void:
	if target != _player or not _status_chips.has(effect_id):
		return
	_status_chips[effect_id].queue_free()
	_status_chips.erase(effect_id)

func _process(_delta: float) -> void:
	if GameState.gold != _last_gold:
		_last_gold = GameState.gold
		_gold_label.text = "Gold: %d" % GameState.gold

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
	_life_orb.set_value(current, max_value)

func _on_mana_changed(current: float, max_value: float) -> void:
	_mana_orb.set_value(current, max_value)

func _on_ward_changed(current: float, max_value: float) -> void:
	_life_orb.set_ring_value(current, max_value)
	if is_instance_valid(_player):
		_life_orb.set_value(_player.health.current_health, _player.health.max_health)

## needed is always > 0 (XP_BASE * XP_GROWTH^n never reaches 0), unlike
## Life/Mana's max_value which can legitimately be 0 (no Ward gear, e.g.).
## Level shows in the badge now, not this text - xp_changed always fires
## after any level-up processing (ExperienceComponent.add_xp()), so
## _player.experience.level is already the current value here.
func _on_xp_changed(current: float, needed: float) -> void:
	_xp_fill_clip.anchor_right = clamp(current / needed, 0.0, 1.0)
	_xp_label.text = "%.0f / %.0f XP" % [current, needed]
	_level_badge_label.text = str(_player.experience.level)

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
	var text_color := Constants.get_contrasting_text_color(box.bg_color)
	_weapon_icon.add_theme_color_override("font_color", text_color)
	_weapon_icon.add_theme_color_override("font_hover_color", text_color)
	_weapon_icon.add_theme_color_override("font_pressed_color", text_color)

func _play_swap_flash() -> void:
	_weapon_icon.scale = Vector2(0.7, 0.7)
	_weapon_icon.modulate = Color(1.6, 1.6, 1.6)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_weapon_icon, "scale", Vector2.ONE, SWAP_PUNCH_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_weapon_icon, "modulate", Color.WHITE, SWAP_PUNCH_DURATION)
