extends CanvasLayer
class_name PlayerHUD
## Always-on HUD: Life/Mana orbs (Ward as a strip on the Life orb) beside the
## ability bar, the XP bar along the bottom, the weapon plate, status chips
## and enemy health bars.
##
## The XP fill is a fixed-size shader rect revealed by a clip window, so the
## animation doesn't stretch as it fills.
##
## The initial orb read is deferred because HealthComponent sets
## current_health deferred too.

const ORB_RADIUS := 64.0
const ORB_GAP := 18.0

const XP_BAR_HEIGHT := 10.0
const XP_BAR_BOTTOM_OFFSET := -1.0
const LEVEL_BADGE_SIZE := 34.0

const HEALTH_COLOR := Color(0.75, 0.15, 0.15)
const MANA_COLOR := Color(0.25, 0.45, 0.85)
const WARD_COLOR := Color(0.55, 0.55, 0.95)
const EMPTY_BG_COLOR := Color(0.12, 0.12, 0.14, 0.85)
const WEAPON_PLATE_SIZE := Vector2(222, 74)
const WEAPON_PLATE_MARGIN := 20.0
const WEAPON_PLATE_BOTTOM := 24.0
const SWAP_PUNCH_DURATION := 0.2

const STATUS_ROW_TOP_MARGIN := 16.0
const STATUS_ROW_LEFT_MARGIN := 16.0
const STATUS_CHIP_HEIGHT := 26.0
const STATUS_CHIP_MIN_WIDTH := 76.0
const STATUS_CHIP_GAP := 6.0
const XP_BAR_SHADER := preload("res://ui/player_hud/xp_bar.gdshader")

## Screen-edge vignette: only shows in a Figment, below LOW_HEALTH_FRACTION
## life, or as a flash on taking damage.
const VIGNETTE_SHADER := preload("res://assets/shaders/vignette.gdshader")
const VIGNETTE_NORMAL_INTENSITY := 0.0
const VIGNETTE_FIGMENT_INTENSITY := 0.35
const VIGNETTE_LOW_HEALTH_INTENSITY := 0.6
const VIGNETTE_DAMAGE_FLASH_INTENSITY := 0.5
const VIGNETTE_LOW_HEALTH_FRACTION := 0.3
const VIGNETTE_LOW_HEALTH_COLOR := Color(0.55, 0.0, 0.02)
const VIGNETTE_FLASH_DECAY_PER_SEC := 2.5
const VIGNETTE_BLEND_SPEED := 6.0
## Ammo counter: magazine large, reserve small. Ranged weapons only; bows
## show an infinity sign.
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

## The trail jumps to the new XP instantly and the main fill tweens up to it.
const XP_TRAIL_COLOR_MODULATE := Color(1.5, 1.25, 0.7)

@onready var weapon_indicator: HBoxContainer = $WeaponIndicator

var _player: Player
var _life_orb: StatOrb
var _mana_orb: StatOrb
var _xp_fill_clip: Control
var _xp_trail_clip: Control
var _xp_label: Label
var _xp_tween: Tween
## -1 until the first update, which snaps instead of tweening.
var _xp_last_needed: float = -1.0
var _level_badge: LevelBadge
var _weapon_icon: ItemSlotButton
var _weapon_plate: WeaponPlate
var _last_gold: int = -1
var _status_row: HBoxContainer
var _status_chips: Dictionary = {}  # effect_id -> Label
var _hit_marker: HitMarker
var _throwable_icon: TextureRect
var _throwable_count_label: Label
var _enemy_counter_label: Label

## User request (2026-08-31): floating enemy health bars on hover/in-
## combat, plus a special top-of-screen bar for boss-rank enemies.
const ENEMY_HEALTH_BAR_HEIGHT_OFFSET := 0.3  # metres above the top of the enemy's body
const ENEMY_HOVER_MAX_RANGE := 30.0
var _enemy_bars: Dictionary = {}  # Enemy instance id (int) -> EnemyHealthBar
var _boss_bar: BossHealthBar

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_tree().get_first_node_in_group("player") as Player

	var orb_box := StatOrb.box_size(ORB_RADIUS)
	var orb_offset := AbilityBar.plate_size().x / 2.0 + ORB_GAP
	_life_orb = _build_orb(AetherStyle.LIFE, "Life", -orb_offset - orb_box.x, -orb_offset)
	_mana_orb = _build_orb(AetherStyle.MANA, "Mana", orb_offset, orb_offset + orb_box.x)

	_build_vignette()
	_build_ammo_display()
	_build_xp_bar()
	_build_weapon_indicator()
	_build_status_row()
	_build_crosshair()
	_build_hit_marker()
	_build_stance_indicator()
	add_child(ComposureBar.new())
	add_child(StanceChargeBar.new())
	add_child(BarrierBar.new())
	_build_throwable_indicator()
	_build_enemy_counter()
	EventBus.enemy_count_changed.connect(_on_enemy_count_changed)
	add_child(LootLookCard.new())
	add_child(Minimap.new())
	add_child(Compass.new())
	_build_inventory_full_label()
	EventBus.inventory_full.connect(_on_inventory_full)

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
		_player.equipment.equipment_changed.connect(_refresh_weapon_indicator)
		EventBus.status_effect_applied.connect(_on_status_effect_applied)
		EventBus.status_effect_expired.connect(_on_status_effect_expired)
		EventBus.hit_landed.connect(_hit_marker.show_hit)
		EventBus.throwable_used.connect(_on_throwable_used)
		call_deferred("_initial_refresh")

## Full-rect CenterContainer so the cross stays centred at any resolution.
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
	# Bottom right, just left of the weapon plate.
	var indicator := StanceIndicator.new()
	var box := StanceIndicator.box_size()
	indicator.anchor_left = 1.0
	indicator.anchor_right = 1.0
	indicator.anchor_top = 1.0
	indicator.anchor_bottom = 1.0
	indicator.offset_right = -WEAPON_PLATE_MARGIN - WEAPON_PLATE_SIZE.x - 18.0
	indicator.offset_left = indicator.offset_right - box.x
	indicator.offset_bottom = -16.0
	indicator.offset_top = indicator.offset_bottom - box.y
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

	var bg := Panel.new()
	bg.add_theme_stylebox_override("panel", AetherStyle.slot_box(AetherStyle.GOLD_DIM))
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
	orb.radius = ORB_RADIUS
	# Globe centres line up with the skill plate's centre.
	var box := StatOrb.box_size(ORB_RADIUS)
	orb.offset_top = -AbilityBar.CENTRE_FROM_BOTTOM - ORB_RADIUS - StatOrb.FRAME_PAD
	orb.offset_bottom = orb.offset_top + box.y
	orb.grow_vertical = 0
	add_child(orb)
	return orb

## Edge-to-edge along the very bottom (Guild Wars 2 style): a glass track
## with the animated gold fill, notches every 5% (heavier every 20%), the
## XP count just above its centre and the level in a diamond above its
## left end.
func _build_xp_bar() -> void:
	var root := Control.new()
	root.anchor_left = 0.0
	root.anchor_right = 1.0
	root.anchor_top = 1.0
	root.anchor_bottom = 1.0
	root.offset_bottom = XP_BAR_BOTTOM_OFFSET
	root.offset_top = XP_BAR_BOTTOM_OFFSET - XP_BAR_HEIGHT
	root.grow_horizontal = 2
	root.grow_vertical = 0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.04, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var bar_width: float = get_viewport().get_visible_rect().size.x

	# The trail sits behind the main fill and snaps to each new ratio; the
	# main fill tweens up to meet it, so incoming XP reads as a bright sliver.
	var trail_clip := Control.new()
	trail_clip.clip_contents = true
	trail_clip.anchor_right = 0.0
	trail_clip.anchor_bottom = 1.0
	trail_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(trail_clip)
	_xp_trail_clip = trail_clip
	var trail_gradient_rect := ColorRect.new()
	trail_gradient_rect.material = ShaderMaterial.new()
	(trail_gradient_rect.material as ShaderMaterial).shader = XP_BAR_SHADER
	trail_gradient_rect.modulate = XP_TRAIL_COLOR_MODULATE
	trail_gradient_rect.anchor_bottom = 1.0
	trail_gradient_rect.offset_right = bar_width
	trail_gradient_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trail_clip.add_child(trail_gradient_rect)

	# A clip window over a fixed-width gradient, so filling reveals more of
	# it instead of squishing it.
	var fill_clip := Control.new()
	fill_clip.clip_contents = true
	fill_clip.anchor_right = 0.0
	fill_clip.anchor_bottom = 1.0
	fill_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fill_clip)
	_xp_fill_clip = fill_clip
	var gradient_rect := ColorRect.new()
	gradient_rect.material = ShaderMaterial.new()
	(gradient_rect.material as ShaderMaterial).shader = XP_BAR_SHADER
	gradient_rect.anchor_bottom = 1.0
	gradient_rect.offset_right = bar_width
	gradient_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill_clip.add_child(gradient_rect)

	var notches := NotchedBar.new()
	notches.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(notches)

	var label := Label.new()
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.offset_left = -150.0
	label.offset_right = 150.0
	label.offset_top = -19.0
	label.offset_bottom = -2.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", AetherStyle.numbers())
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", AetherStyle.TEXT_DIM)
	label.add_theme_color_override("font_shadow_color", AetherStyle.SHADOW)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(label)
	_xp_label = label

	_build_level_badge(root)

## A gold diamond above the bar's left end.
func _build_level_badge(xp_bar_root: Control) -> void:
	var badge := LevelBadge.new()
	badge.offset_left = 10.0
	badge.offset_right = 10.0 + LEVEL_BADGE_SIZE
	badge.offset_bottom = -4.0
	badge.offset_top = -4.0 - LEVEL_BADGE_SIZE
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_bar_root.add_child(badge)
	_level_badge = badge

class LevelBadge extends Control:
	var level: int = 1:
		set(value):
			level = value
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		AetherStyle.diamond(self, c, size.x / 2.0, AetherStyle.GLASS_SOLID, AetherStyle.GOLD)
		AetherStyle.diamond(self, c, size.x / 2.0 - 4.0, Color(0, 0, 0, 0), AetherStyle.GOLD_FAINT)
		AetherStyle.text(self, AetherStyle.numbers(), Vector2(0, c.y + 6.0), str(level), 16, AetherStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, size.x)

var _inventory_full_label: Label
var _inventory_full_tween: Tween

func _build_inventory_full_label() -> void:
	_inventory_full_label = Label.new()
	_inventory_full_label.text = "Inventory full"
	_inventory_full_label.add_theme_font_size_override("font_size", 22)
	_inventory_full_label.add_theme_color_override("font_color", Color(0.95, 0.45, 0.35))
	_inventory_full_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_inventory_full_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_inventory_full_label.position.y += 80
	_inventory_full_label.modulate.a = 0.0
	_inventory_full_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_inventory_full_label)

func _on_inventory_full(_content: Resource) -> void:
	if _inventory_full_tween:
		_inventory_full_tween.kill()
	_inventory_full_label.modulate.a = 1.0
	_inventory_full_tween = create_tween()
	_inventory_full_tween.tween_interval(1.5)
	_inventory_full_tween.tween_property(_inventory_full_label, "modulate:a", 0.0, 0.5)

## Top-left chips, one per active status effect on the player.
func _build_status_row() -> void:
	_status_row = HBoxContainer.new()
	_status_row.anchor_left = 0.0
	_status_row.anchor_top = 0.0
	_status_row.offset_left = STATUS_ROW_LEFT_MARGIN
	_status_row.offset_top = STATUS_ROW_TOP_MARGIN
	_status_row.add_theme_constant_override("separation", STATUS_CHIP_GAP)
	_status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_row)

## "Enemies: remaining / total" under the status chips. Hidden until
## GeneratedMap reports a count.
func _build_enemy_counter() -> void:
	_enemy_counter_label = Label.new()
	_enemy_counter_label.add_theme_font_override("font", AetherStyle.serif())
	_enemy_counter_label.add_theme_color_override("font_color", AetherStyle.GOLD)
	_enemy_counter_label.offset_left = STATUS_ROW_LEFT_MARGIN
	_enemy_counter_label.offset_top = STATUS_ROW_TOP_MARGIN + STATUS_CHIP_HEIGHT + 8.0
	_enemy_counter_label.add_theme_font_size_override("font_size", 16)
	_enemy_counter_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_enemy_counter_label.add_theme_constant_override("outline_size", 4)
	_enemy_counter_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_counter_label.visible = false
	add_child(_enemy_counter_label)

func _on_enemy_count_changed(remaining: int, total: int) -> void:
	_enemy_counter_label.text = "Enemies: %d / %d" % [remaining, total]
	_enemy_counter_label.visible = true

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
	var accent: Color = Constants.DAMAGE_TYPE_COLOR.get(dmg_type, Color.WHITE)
	chip.add_theme_stylebox_override("normal", AetherStyle.glass_box(accent, AetherStyle.GLASS_LIGHT.lerp(accent, 0.18), 1, 6.0))
	chip.add_theme_font_override("font", AetherStyle.serif())
	chip.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.35))
	_status_row.add_child(chip)
	_status_chips[effect_id] = chip

func _on_status_effect_expired(target: Node, effect_id: String) -> void:
	if target != _player or not _status_chips.has(effect_id):
		return
	_status_chips[effect_id].queue_free()
	_status_chips.erase(effect_id)

func _process(_delta: float) -> void:
	visible = not AetherStyle.menu_open(get_tree())
	# Gold changes in many unrelated places, so it's polled.
	if GameState.gold != _last_gold:
		_last_gold = GameState.gold
		_weapon_plate.gold = GameState.gold
		_weapon_plate.queue_redraw()
	_update_enemy_health_bars()
	_update_vignette(_delta)

## Floating bars for enemies under the crosshair or in combat. Bosses use
## BossHealthBar instead.
func _update_enemy_health_bars() -> void:
	if not is_instance_valid(_player) or _player.camera == null:
		return
	var camera := _player.camera
	var hovered_id := _get_hovered_enemy_id(camera)

	var seen_ids := {}
	var active_boss: Enemy = null
	# An Ascendant takes the boss-style bar when no boss is fighting you.
	var boss_fighting := false
	for node in get_tree().get_nodes_in_group("enemy"):
		var e := node as Enemy
		if e and e.rank == Constants.EnemyRank.BOSS and e.health.is_alive() and e.is_in_combat():
			boss_fighting = true
			break
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy == null or not enemy.health.is_alive():
			continue
		var id := enemy.get_instance_id()
		if not (id == hovered_id or enemy.is_in_combat()):
			continue
		var rarity_component := enemy.rarity_component
		var ascendant := rarity_component != null and rarity_component.rarity == Constants.EnemyRarity.ASCENDANT
		if enemy.rank == Constants.EnemyRank.BOSS or (ascendant and not boss_fighting and active_boss == null):
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
		bar.set_name_color(rarity_component.get_name_color() if rarity_component else Color.WHITE)
		bar.set_affix_text(rarity_component.get_affix_names() if rarity_component else "")
		bar.set_health(enemy.health.current_health, enemy.health.max_health)
		bar.set_ward(enemy.get_ward(), enemy.get_ward_max())
		var world_pos := enemy.global_position + Vector3(0, enemy.body_height + ENEMY_HEALTH_BAR_HEIGHT_OFFSET, 0)
		if camera.is_position_behind(world_pos) or not _has_line_of_sight(camera, enemy):
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
	var rarity_component := boss.rarity_component
	var ascendant := rarity_component != null and rarity_component.rarity == Constants.EnemyRarity.ASCENDANT
	_boss_bar.set_name_color(rarity_component.get_name_color() if ascendant else AetherStyle.GOLD_BRIGHT)
	_boss_bar.set_subtitle(rarity_component.get_affix_names() if ascendant else "")
	_boss_bar.set_health(boss.health.current_health, boss.health.max_health)
	_boss_bar.set_ward(boss.get_ward(), boss.get_ward_max())
	var marks: Array[float] = []
	if boss.boss_brain:
		marks = boss.boss_brain.phase_thresholds
	_boss_bar.set_phase_marks(marks)


## True when the camera can see the enemy's head or middle. Other enemies in
## the way don't count as cover, only walls and props do.
func _has_line_of_sight(camera: Camera3D, enemy: Enemy) -> bool:
	var space_state := _player.get_world_3d().direct_space_state
	var origin := camera.global_position
	for height in [enemy.body_height * 0.9, enemy.body_height * 0.5]:
		var target := enemy.global_position + Vector3(0, height, 0)
		var exclude: Array[RID] = [_player.get_rid()]
		var blocked := false
		for i in 4:
			var query := PhysicsRayQueryParameters3D.create(origin, target)
			query.exclude = exclude
			var hit := space_state.intersect_ray(query)
			if hit.is_empty():
				break
			if hit.get("collider") is Enemy:
				exclude.append((hit["collider"] as Enemy).get_rid())
				continue
			blocked = true
			break
		if not blocked:
			return true
	return false
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

## Engraved plate at the bottom right: weapon name in its rarity colour, its
## type, the worn weapon set and gold. An invisible slot button covers it so
## hovering shows the weapon's card.
func _build_weapon_indicator() -> void:
	weapon_indicator.visible = false
	_weapon_plate = WeaponPlate.new()
	_weapon_plate.anchor_left = 1.0
	_weapon_plate.anchor_right = 1.0
	_weapon_plate.anchor_top = 1.0
	_weapon_plate.anchor_bottom = 1.0
	_weapon_plate.offset_right = -WEAPON_PLATE_MARGIN
	_weapon_plate.offset_left = -WEAPON_PLATE_MARGIN - WEAPON_PLATE_SIZE.x
	_weapon_plate.offset_bottom = -WEAPON_PLATE_BOTTOM
	_weapon_plate.offset_top = -WEAPON_PLATE_BOTTOM - WEAPON_PLATE_SIZE.y
	_weapon_plate.pivot_offset = WEAPON_PLATE_SIZE / 2.0
	_weapon_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_weapon_plate)
	_weapon_icon = ItemSlotButton.new()
	_weapon_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_weapon_icon.flat = true
	_weapon_icon.show_icon = false
	_weapon_icon.focus_mode = Control.FOCUS_NONE
	_weapon_icon.mouse_filter = Control.MOUSE_FILTER_PASS  # hoverable for the card, not clickable
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		_weapon_icon.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_weapon_plate.add_child(_weapon_icon)

class WeaponPlate extends Control:
	var weapon_name: String = ""
	var item: Item
	var weapon_type: String = ""
	var name_color: Color = AetherStyle.TEXT
	var set_text: String = ""
	var gold: int = 0

	func _draw() -> void:
		AetherStyle.plate(self, Rect2(Vector2.ZERO, size))
		var serif := AetherStyle.serif()
		var numbers := AetherStyle.numbers()
		var text_width := size.x - (66.0 if item else 24.0)
		if item:
			IconArt.draw(self, item, Rect2(size.x - 54.0, 8.0, 42.0, 42.0))
		AetherStyle.text(self, serif, Vector2(14, 28), weapon_name, 17, name_color, HORIZONTAL_ALIGNMENT_LEFT, text_width)
		AetherStyle.text(self, serif, Vector2(14, 47), weapon_type, 12, AetherStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, text_width)
		AetherStyle.text(self, numbers, Vector2(14, size.y - 10.0), set_text, 12, AetherStyle.GOLD_DIM)
		AetherStyle.text(self, numbers, Vector2(14, size.y - 10.0), "Gold  %s" % _thousands(gold), 12, AetherStyle.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 28.0)

	static func _thousands(n: int) -> String:
		var s := str(absi(n))
		var out := ""
		while s.length() > 3:
			out = "," + s.right(3) + out
			s = s.left(s.length() - 3)
		return ("-" if n < 0 else "") + s + out

func _build_ammo_display() -> void:
	_ammo_box = VBoxContainer.new()
	_ammo_box.anchor_left = 1.0
	_ammo_box.anchor_right = 1.0
	_ammo_box.anchor_top = 1.0
	_ammo_box.anchor_bottom = 1.0
	_ammo_box.offset_left = -AMMO_BOX_WIDTH - 20.0
	_ammo_box.offset_right = -20.0
	_ammo_box.offset_bottom = -WEAPON_PLATE_BOTTOM - WEAPON_PLATE_SIZE.y - 6.0
	_ammo_box.offset_top = _ammo_box.offset_bottom - 104.0
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
	label.add_theme_font_override("font", AetherStyle.numbers())
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

## Tweens the fill. A level-up shows as `needed` changing since the last
## call: the old bar fills to the end, resets, then fills to the new value.
func _on_xp_changed(current: float, needed: float) -> void:
	var at_max_level: bool = _player.experience.is_max_level()
	_xp_label.text = "MAX LEVEL" if at_max_level else "%.0f / %.0f XP" % [current, needed]
	_level_badge.level = _player.experience.level
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
		# Trail tops off the old bar; after the catch-up both reset and the
		# trail jumps to the new target.
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
	_weapon_icon.tooltip_text = weapon.display_name if weapon else ""
	_weapon_plate.weapon_name = weapon.display_name if weapon else "No weapon"
	_weapon_plate.item = weapon
	_weapon_plate.weapon_type = weapon.weapon_type if weapon else ""
	_weapon_plate.name_color = Constants.ITEM_RARITY_COLOR.get(weapon.rarity, AetherStyle.TEXT) if weapon else AetherStyle.TEXT_DIM
	_weapon_plate.set_text = "Set %s" % ("A" if _player.equipment.active_weapon_set == 0 else "B")
	_weapon_plate.gold = GameState.gold
	_weapon_plate.queue_redraw()

func _play_swap_flash() -> void:
	_weapon_plate.scale = Vector2(0.92, 0.92)
	_weapon_plate.modulate = Color(1.6, 1.5, 1.2)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_weapon_plate, "scale", Vector2.ONE, SWAP_PUNCH_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_weapon_plate, "modulate", Color.WHITE, SWAP_PUNCH_DURATION)
