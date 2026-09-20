extends CanvasLayer
class_name PlayerHUD
## Always-on readout of Life/Mana/Ward and the active weapon. Life and
## Mana are circular `StatOrb`s flanking the ability bar (Ward renders as
## an inset vertical strip along the right edge of the Life orb, see
## StatOrb.set_ward_value()); XP is a notched bar below the ability bar
## near the very bottom of the screen, with a level badge at its left end
## - GW2-style layout, per user reference. The fill is a fixed-size
## `ColorRect` (unstretched) running xp_bar.gdshader - a moving yellow/
## gold/orange gradient with twinkling stars (user direction, 2026-08-30,
## replacing the previous static 6-color rainbow `GradientTexture1D`) -
## revealed by a shrinking clip window, so the animation at a given point
## along the bar stays put as it fills rather than resampling/squishing.
## Placeholder art otherwise, matching the rest of the project.
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
const ORB_HEIGHT := 132.0  # must match StatOrb's own computed min size (radius*2 + 16)

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
const XP_BAR_SHADER := preload("res://ui/player_hud/xp_bar.gdshader")

## Screen-edge vignette (Implementation Brief v4.1). Invisible at full health
## in normal play (the brief's DO NOT) - it only shows in a Figment, below
## LOW_HEALTH_FRACTION life, or as a brief flash on taking damage.
const VIGNETTE_SHADER := preload("res://assets/shaders/vignette.gdshader")
const VIGNETTE_NORMAL_INTENSITY := 0.0
const VIGNETTE_FIGMENT_INTENSITY := 0.35
const VIGNETTE_LOW_HEALTH_INTENSITY := 0.6
const VIGNETTE_DAMAGE_FLASH_INTENSITY := 0.5
const VIGNETTE_LOW_HEALTH_FRACTION := 0.3
const VIGNETTE_LOW_HEALTH_COLOR := Color(0.55, 0.0, 0.02)
const VIGNETTE_FLASH_DECAY_PER_SEC := 2.5
const VIGNETTE_BLEND_SPEED := 6.0
## Ammo counter above the weapon indicator (Implementation Brief v4.2):
## magazine large, reserve small, "RELOADING" while a reload runs. Hidden
## unless a ranged weapon is equipped; bows show an infinity sign (arrows
## are unlimited and have no magazine).
const AMMO_BOX_WIDTH := 160.0
const AMMO_EMPTY_COLOR := Color(1.0, 0.2, 0.2)
var _ammo_box: VBoxContainer
var _magazine_label: Label
var _reserve_label: Label
var _reload_label: Label
var _vignette: ColorRect
var _vignette_material: ShaderMaterial
var _vignette_intensity: float = 0.0
var _vignette_flash: float = 0.0
var _vignette_last_health: float = -1.0

## Patch v3.5 Section 3: small icon + quantity, top-right corner - shows
## "0" plainly rather than hiding when empty.
const THROWABLE_ICON_SIZE := 40.0
const THROWABLE_MARGIN := 16.0

## User request (2026-08-30): "tween between the experience bar that they
## had to the experience that they end up at... show it filling up."
const XP_FILL_TWEEN_DURATION := 0.5

## Patch v3.8b: inverse of the health bar's damage trail - the trail here
## shows the INCOMING gain instantly (bright), and the main fill tweens up
## to meet it, rather than the main fill dropping instantly and a trail
## lingering behind. A brighter/more saturated version of the shader's own
## gold/amber, not a different hue.
const XP_TRAIL_COLOR_MODULATE := Color(1.5, 1.25, 0.7)

@onready var weapon_indicator: HBoxContainer = $WeaponIndicator

var _player: Player
var _life_orb: StatOrb
var _mana_orb: StatOrb
var _xp_fill_clip: Control
var _xp_trail_clip: Control
var _xp_label: Label
var _xp_tween: Tween
## -1 = not yet initialized (the deferred startup call in _ready() should
## snap the bar to wherever a loaded save's XP already is, not tween up
## from empty).
var _xp_last_needed: float = -1.0
var _level_badge_label: Label
var _weapon_icon: ItemSlotButton
var _weapon_name_label: Label
var _gold_label: Label
var _last_gold: int = -1
var _status_row: HBoxContainer
var _status_chips: Dictionary = {}  # effect_id -> Label
var _hit_marker: HitMarker
var _throwable_icon: TextureRect
var _throwable_count_label: Label

## User request (2026-08-31): floating enemy health bars on hover/in-
## combat, plus a special top-of-screen bar for boss-rank enemies.
const ENEMY_HEALTH_BAR_HEIGHT_OFFSET := 2.2  # world-space Y above the enemy's own origin
const ENEMY_HOVER_MAX_RANGE := 30.0
var _enemy_bars: Dictionary = {}  # Enemy instance id (int) -> EnemyHealthBar
var _boss_bar: BossHealthBar

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_tree().get_first_node_in_group("player") as Player

	_life_orb = _build_orb(HEALTH_COLOR, "Life", -ABILITY_BAR_HALF_WIDTH - ORB_GAP - ORB_HEIGHT, -ABILITY_BAR_HALF_WIDTH - ORB_GAP)
	_life_orb.ward_color = WARD_COLOR
	_mana_orb = _build_orb(MANA_COLOR, "Mana", ABILITY_BAR_HALF_WIDTH + ORB_GAP, ABILITY_BAR_HALF_WIDTH + ORB_GAP + ORB_HEIGHT)

	_build_vignette()
	_build_ammo_display()
	_build_xp_bar()
	_build_weapon_indicator()
	_build_gold_label()
	_build_status_row()
	_build_crosshair()
	_build_hit_marker()
	_build_stance_indicator()
	_build_throwable_indicator()

	if is_instance_valid(_player):
		_player.health.health_changed.connect(_on_health_changed)
		_player.health.health_changed.connect(_update_vignette_on_health_changed)
		EventBus.reload_started.connect(_on_reload_started)
		EventBus.reload_finished.connect(_on_reload_finished)
		EventBus.reload_interrupted.connect(_on_reload_finished)
		EventBus.ammo_changed.connect(_on_ammo_changed)
		_player.mana.mana_changed.connect(_on_mana_changed)
		_player.ward.ward_changed.connect(_on_ward_changed)
		_player.experience.xp_changed.connect(_on_xp_changed)
		EventBus.weapon_swapped.connect(_on_weapon_swapped)
		EventBus.status_effect_applied.connect(_on_status_effect_applied)
		EventBus.status_effect_expired.connect(_on_status_effect_expired)
		EventBus.hit_landed.connect(_hit_marker.show_hit)
		EventBus.throwable_used.connect(_on_throwable_used)
		call_deferred("_initial_refresh")

## Implementation Brief v3.4 Section 1: a CenterContainer holding the
## static cross - full-rect anchored so its center always lands on
## screen center regardless of resolution.
func _build_crosshair() -> void:
	var container := CenterContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var crosshair := Crosshair.new()
	crosshair.custom_minimum_size = Vector2(40, 40)
	container.add_child(crosshair)
	add_child(container)

func _build_hit_marker() -> void:
	_hit_marker = HitMarker.new()
	_hit_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_hit_marker)

func _build_stance_indicator() -> void:
	var indicator := StanceIndicator.new()
	indicator.offset_left = 16.0
	indicator.offset_bottom = -16.0
	indicator.offset_top = -40.0
	indicator.offset_right = 200.0
	add_child(indicator)

func _build_throwable_indicator() -> void:
	var root := Control.new()
	root.anchor_left = 1.0
	root.anchor_right = 1.0
	root.offset_left = -THROWABLE_ICON_SIZE - THROWABLE_MARGIN
	root.offset_right = -THROWABLE_MARGIN
	root.offset_top = THROWABLE_MARGIN
	root.offset_bottom = THROWABLE_MARGIN + THROWABLE_ICON_SIZE
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var bg := ColorRect.new()
	bg.color = EMPTY_BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	_throwable_icon = TextureRect.new()
	_throwable_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_throwable_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_throwable_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_throwable_icon)

	_throwable_count_label = Label.new()
	_throwable_count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_throwable_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_throwable_count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_throwable_count_label.add_theme_font_size_override("font_size", 14)
	_throwable_count_label.add_theme_color_override("font_color", Color.WHITE)
	_throwable_count_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_throwable_count_label.add_theme_constant_override("outline_size", 3)
	_throwable_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_throwable_count_label)

func _on_throwable_used(_throwable_type: String) -> void:
	_refresh_throwable_indicator()

func _refresh_throwable_indicator() -> void:
	var stack: ThrowableStack = _player.active_throwable if is_instance_valid(_player) else null
	if stack == null:
		_throwable_icon.texture = null
		_throwable_count_label.text = "0"
		return
	_throwable_icon.texture = stack.icon
	_throwable_count_label.text = str(stack.quantity)

func _initial_refresh() -> void:
	if not is_instance_valid(_player):
		return
	_on_health_changed(_player.health.current_health, _player.health.max_health)
	_on_mana_changed(_player.mana.current_mana, _player.mana.max_mana)
	_on_ward_changed(_player.ward.current_ward, _player.ward.max_ward)
	_on_xp_changed(_player.experience.xp, _player.experience.xp_to_next_level())
	_refresh_weapon_indicator()
	_refresh_throwable_indicator()

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

	# The bar itself is now full-width (percentage-anchored, resolution-
	# independent), so its rendered pixel width isn't known until runtime -
	# computed here from the viewport rather than a compile-time constant.
	var bar_width: float = get_viewport().get_visible_rect().size.x - XP_BAR_LEFT_MARGIN - XP_BAR_RIGHT_MARGIN

	# Patch v3.8b: trail layer sits BEHIND the main fill and snaps its own
	# clip window instantly to the new ratio on every XP gain - the main
	# fill_clip below tweens up to meet it, so the gap between the two
	# reads as a bright "incoming XP" sliver that shrinks as the real fill
	# catches up (inverse of the health bar's damage-trail, which drops
	# the main fill instantly and lets a trail linger behind instead).
	var trail_clip := Control.new()
	trail_clip.clip_contents = true
	trail_clip.anchor_left = 0.0
	trail_clip.anchor_top = 0.0
	trail_clip.anchor_right = 0.0
	trail_clip.anchor_bottom = 1.0
	trail_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(trail_clip)
	_xp_trail_clip = trail_clip

	var trail_gradient_rect := ColorRect.new()
	trail_gradient_rect.color = Color.WHITE
	trail_gradient_rect.material = ShaderMaterial.new()
	(trail_gradient_rect.material as ShaderMaterial).shader = XP_BAR_SHADER
	trail_gradient_rect.modulate = XP_TRAIL_COLOR_MODULATE
	trail_gradient_rect.anchor_left = 0.0
	trail_gradient_rect.anchor_top = 0.0
	trail_gradient_rect.anchor_bottom = 1.0
	trail_gradient_rect.offset_right = bar_width
	trail_gradient_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trail_clip.add_child(trail_gradient_rect)

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

	var gradient_rect := ColorRect.new()
	gradient_rect.color = Color.WHITE  # shader fully replaces this - just needs an opaque quad to shade
	gradient_rect.material = ShaderMaterial.new()
	(gradient_rect.material as ShaderMaterial).shader = XP_BAR_SHADER
	gradient_rect.anchor_left = 0.0
	gradient_rect.anchor_top = 0.0
	gradient_rect.anchor_bottom = 1.0
	gradient_rect.offset_right = bar_width
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
	_update_enemy_health_bars()
	_update_vignette(_delta)

## User request (2026-08-31): "a health bar on enemies when I hover over
## them... hangs while we're in combat and disappears when they lose
## track of me/I am out of combat for 5 seconds" - qualifying condition
## is hover (crosshair raycast) OR Enemy.is_in_combat() (see that
## function's own header). Boss-rank enemies get the special top-of-
## screen BossHealthBar instead of a floating one, never both.
func _update_enemy_health_bars() -> void:
	if not is_instance_valid(_player) or _player.camera == null:
		return
	var camera := _player.camera
	var hovered_id := _get_hovered_enemy_id(camera)

	var seen_ids := {}
	var active_boss: Enemy = null
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy == null or not enemy.health.is_alive():
			continue
		var id := enemy.get_instance_id()
		if not (id == hovered_id or enemy.is_in_combat()):
			continue
		if enemy.rank == Constants.EnemyRank.BOSS:
			if active_boss == null:
				active_boss = enemy
			continue
		seen_ids[id] = true
		var bar: EnemyHealthBar = _enemy_bars.get(id)
		if bar == null:
			bar = EnemyHealthBar.new()
			add_child(bar)
			_enemy_bars[id] = bar
		bar.set_enemy_name(enemy.get_display_name())
		var rarity_component := enemy.get_node_or_null("EnemyRarityComponent") as EnemyRarityComponent
		bar.set_name_color(rarity_component.get_name_color() if rarity_component else Color.WHITE)
		bar.set_health(enemy.health.current_health, enemy.health.max_health)
		var world_pos := enemy.global_position + Vector3(0, ENEMY_HEALTH_BAR_HEIGHT_OFFSET, 0)
		if camera.is_position_behind(world_pos):
			bar.visible = false
		else:
			bar.visible = true
			bar.position = camera.unproject_position(world_pos) - bar.size / 2.0

	for id in _enemy_bars.keys():
		if not seen_ids.has(id):
			_enemy_bars[id].queue_free()
			_enemy_bars.erase(id)

	_update_boss_bar(active_boss)

func _update_boss_bar(boss: Enemy) -> void:
	if boss == null:
		if _boss_bar:
			_boss_bar.visible = false
		return
	if _boss_bar == null:
		_boss_bar = BossHealthBar.new()
		add_child(_boss_bar)
	_boss_bar.visible = true
	_boss_bar.set_boss_name(boss.get_display_name())
	_boss_bar.set_health(boss.health.current_health, boss.health.max_health)

func _get_hovered_enemy_id(camera: Camera3D) -> int:
	var origin := camera.global_position
	var forward := -camera.global_transform.basis.z
	var space_state := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * ENEMY_HOVER_MAX_RANGE)
	query.exclude = [_player.get_rid()]
	var result := space_state.intersect_ray(query)
	if result and result.get("collider") is Enemy:
		return (result["collider"] as Enemy).get_instance_id()
	return -1

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

func _build_ammo_display() -> void:
	_ammo_box = VBoxContainer.new()
	_ammo_box.anchor_left = 1.0
	_ammo_box.anchor_right = 1.0
	_ammo_box.anchor_top = 1.0
	_ammo_box.anchor_bottom = 1.0
	_ammo_box.offset_left = -AMMO_BOX_WIDTH - 20.0
	_ammo_box.offset_right = -20.0
	_ammo_box.offset_top = -196.0
	_ammo_box.offset_bottom = -92.0
	_ammo_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ammo_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ammo_box.alignment = BoxContainer.ALIGNMENT_END
	_ammo_box.add_theme_constant_override("separation", -4)
	_ammo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ammo_box.visible = false
	add_child(_ammo_box)
	_magazine_label = _make_ammo_label(44)
	_reserve_label = _make_ammo_label(20)
	_reload_label = _make_ammo_label(14)
	_reload_label.text = "RELOADING"
	_reload_label.visible = false

func _make_ammo_label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ammo_box.add_child(label)
	return label

func _update_ammo_display(weapon: Weapon) -> void:
	if weapon == null or not weapon.is_ranged:
		_ammo_box.visible = false
		return
	_ammo_box.visible = true
	var magazine := _player.ranged_attack.get_current_magazine()
	if magazine < 0:  # no magazine: bows
		_magazine_label.text = "∞"
		_reserve_label.text = ""
		_magazine_label.modulate = Color.WHITE
		return
	_magazine_label.text = str(magazine)
	_reserve_label.text = "/ %d" % AmmoInventory.get_reserve(weapon.ammo_type)
	_magazine_label.modulate = AMMO_EMPTY_COLOR if magazine == 0 else Color.WHITE

func _on_reload_started(_weapon: Weapon) -> void:
	_reload_label.visible = true

func _on_reload_finished(_weapon: Weapon) -> void:
	_reload_label.visible = false
	_update_ammo_display(_player.get_active_weapon())

func _on_ammo_changed(ammo_type: int, _reserve: int) -> void:
	var weapon: Weapon = _player.get_active_weapon()
	if weapon and weapon.ammo_type == ammo_type:
		_update_ammo_display(weapon)

## Full-screen ColorRect behind every other HUD element (added first).
func _build_vignette() -> void:
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_material = ShaderMaterial.new()
	_vignette_material.shader = VIGNETTE_SHADER
	_vignette_material.set_shader_parameter("intensity", 0.0)
	_vignette.material = _vignette_material
	add_child(_vignette)
	move_child(_vignette, 0)

func _update_vignette_on_health_changed(current: float, _max_value: float) -> void:
	if _vignette_last_health >= 0.0 and current < _vignette_last_health:
		_vignette_flash = VIGNETTE_DAMAGE_FLASH_INTENSITY
	_vignette_last_health = current

func _update_vignette(delta: float) -> void:
	var base := VIGNETTE_FIGMENT_INTENSITY if GameState.active_map != null else VIGNETTE_NORMAL_INTENSITY
	var color := Color.BLACK
	if is_instance_valid(_player) and _player.health.max_health > 0.0:
		var fraction: float = _player.health.current_health / _player.health.max_health
		if fraction < VIGNETTE_LOW_HEALTH_FRACTION:
			var danger: float = 1.0 - fraction / VIGNETTE_LOW_HEALTH_FRACTION
			base = lerpf(base, VIGNETTE_LOW_HEALTH_INTENSITY, danger)
			color = Color.BLACK.lerp(VIGNETTE_LOW_HEALTH_COLOR, danger)
	_vignette_flash = move_toward(_vignette_flash, 0.0, VIGNETTE_FLASH_DECAY_PER_SEC * delta)
	_vignette_intensity = lerpf(_vignette_intensity, max(base, _vignette_flash), clamp(VIGNETTE_BLEND_SPEED * delta, 0.0, 1.0))
	_vignette_material.set_shader_parameter("intensity", _vignette_intensity)
	_vignette_material.set_shader_parameter("vignette_color", color)

func _on_health_changed(current: float, max_value: float) -> void:
	_life_orb.set_value(current, max_value)

func _on_mana_changed(current: float, max_value: float) -> void:
	_mana_orb.set_value(current, max_value)

func _on_ward_changed(current: float, max_value: float) -> void:
	_life_orb.set_ward_value(current, max_value)
	if is_instance_valid(_player):
		_life_orb.set_value(_player.health.current_health, _player.health.max_health)

## needed is always > 0 (XP_BASE * XP_GROWTH^n never reaches 0), unlike
## Life/Mana's max_value which can legitimately be 0 (no Ward gear, e.g.).
## Level shows in the badge now, not this text - xp_changed always fires
## after any level-up processing (ExperienceComponent.add_xp()), so
## _player.experience.level is already the current value here.
##
## User request (2026-08-30): tween the fill from where it was to where
## it ends up, instead of snapping instantly. ExperienceComponent.add_xp()
## only emits xp_changed once per call even if it crossed a level (it
## loops internally and fires after the loop, see its own comments) - so
## a level-up shows up here as `needed` having changed since the last
## call. When that happens, fill the OLD bar the rest of the way to 1.0
## first, snap back to empty, then fill toward the new target - the
## classic "level up" bar animation - rather than jumping straight to
## whatever (probably smaller-looking) ratio the new level starts at.
func _on_xp_changed(current: float, needed: float) -> void:
	var at_max_level: bool = _player.experience.is_max_level()
	_xp_label.text = "MAX LEVEL" if at_max_level else "%.0f / %.0f XP" % [current, needed]
	_level_badge_label.text = str(_player.experience.level)
	var target_ratio: float = 1.0 if at_max_level else clamp(current / needed, 0.0, 1.0)

	if _xp_last_needed < 0.0:
		_xp_fill_clip.anchor_right = target_ratio
		_xp_trail_clip.anchor_right = target_ratio
		_xp_last_needed = needed
		return

	if _xp_tween and _xp_tween.is_valid():
		_xp_tween.kill()
	_xp_tween = create_tween()
	if needed != _xp_last_needed:
		# Old bar's trail leaps to full immediately (an "incoming" amount
		# large enough to top it off); once the catch-up tween below
		# finishes filling it, both layers reset to empty and the trail
		# immediately shows the NEW target so the fill tween that follows
		# has something to visibly catch up to, same as the normal case.
		_xp_trail_clip.anchor_right = 1.0
		_xp_tween.tween_property(_xp_fill_clip, "anchor_right", 1.0, XP_FILL_TWEEN_DURATION) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_xp_tween.tween_callback(func():
			_xp_fill_clip.anchor_right = 0.0
			_xp_trail_clip.anchor_right = target_ratio)
	else:
		_xp_trail_clip.anchor_right = target_ratio
	_xp_tween.tween_property(_xp_fill_clip, "anchor_right", target_ratio, XP_FILL_TWEEN_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	_xp_last_needed = needed

func _on_weapon_swapped(player: Node) -> void:
	if player != _player:
		return
	_refresh_weapon_indicator()
	_play_swap_flash()

func _refresh_weapon_indicator() -> void:
	var weapon: Weapon = _player.get_active_weapon()
	_update_ammo_display(weapon)
	_reload_label.visible = _player.ranged_attack.is_reloading()
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
