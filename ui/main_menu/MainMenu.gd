extends Control
class_name MainMenu
## Entry point (project.godot's run/main_scene). Plain Control, not a
## CanvasLayer overlay - no gameplay runs underneath to overlay here.
##
## Continue and New Game open the save slot picker (SaveSlotPanel): Continue
## loads a slot (SaveManager.select_slot()) and goes to the Hub; New Game
## starts a new character, or a Level 90 Test Character, in a chosen slot. Settings are
## a shared SettingsPanel, saved separately by GameSettings.

@onready var continue_button: Button = $MainPanel/VBoxContainer/ContinueButton
@onready var new_game_button: Button = $MainPanel/VBoxContainer/NewGameButton
@onready var settings_button: Button = $MainPanel/VBoxContainer/SettingsButton
@onready var about_button: Button = $MainPanel/VBoxContainer/AboutButton
@onready var quit_button: Button = $MainPanel/VBoxContainer/QuitButton

@onready var main_panel: Control = $MainPanel
@onready var settings_panel: Control = $SettingsPanel
@onready var about_panel: Control = $AboutPanel

@onready var about_back_button: Button = $AboutPanel/VBoxContainer/AboutBackButton
@onready var music_player: AudioStreamPlayer = $MusicPlayer
var wiki_panel: Control
var wiki: Wiki
var new_game_panel: Control
var new_game: NewGamePanel
var slots_panel: Control
var slots: SaveSlotPanel
## The slot the New Game panel will start in.
var _pending_slot := 1

const MUSIC_PATH := "res://assets/music/lament.mp3"

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_play_music()
	continue_button.disabled = not SaveManager.has_any_save()
	continue_button.pressed.connect(_on_continue_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed)
	settings_button.pressed.connect(_show_panel.bind(settings_panel))
	about_button.pressed.connect(_show_panel.bind(about_panel))
	quit_button.pressed.connect(_on_quit_pressed)
	about_back_button.pressed.connect(_show_panel.bind(main_panel))
	var settings := SettingsPanel.new()
	settings.back_pressed.connect(_show_panel.bind(main_panel))
	_framed(settings_panel, settings)
	_build_wiki()
	_build_new_game()
	_build_slots()
	_restyle()

## ---- Look ------------------------------------------------------------------

const GOLD := Color(0.93, 0.76, 0.45)
const GOLD_DIM := Color(0.62, 0.5, 0.32)
const TEXT := Color(0.86, 0.84, 0.8)
const TEXT_DISABLED := Color(0.42, 0.41, 0.4)
const MENU_LEFT := 110.0
const VERSION := "v4.23"

## Left-column layout over the animated background: a dark gradient behind
## a large gold title, text buttons that light up and slide on hover, and a
## fade in from black.
func _restyle() -> void:
	var shade := TextureRect.new()
	var grad_tex := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.88))
	grad.set_color(1, Color(0, 0, 0, 0.0))
	grad.add_point(0.45, Color(0, 0, 0, 0.6))
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(0, 0)
	grad_tex.fill_to = Vector2(1, 0)
	shade.texture = grad_tex
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.anchor_right = 0.6
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	move_child(shade, $Vignette.get_index() + 1)

	var title := $TitleLabel as Label
	title.text = "PROJECT AETHER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.position = Vector2(MENU_LEFT, 150)
	title.size = Vector2(900, 90)
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.02))
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_shadow_color", Color(0.9, 0.55, 0.15, 0.35))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.add_theme_constant_override("shadow_outline_size", 28)
	move_child(title, get_child_count() - 1)

	var subtitle := Label.new()
	subtitle.text = "FIGMENTS  ·  MEMORY  ·  THE AETHER"
	subtitle.position = Vector2(MENU_LEFT + 4, 250)
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", GOLD_DIM)
	add_child(subtitle)
	var rule := ColorRect.new()
	rule.color = GOLD_DIM
	rule.position = Vector2(MENU_LEFT, 280)
	rule.size = Vector2(340, 1)
	add_child(rule)

	# Main menu: left-aligned column instead of a centred box.
	main_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main_panel.position = Vector2(MENU_LEFT - 18, 300)
	main_panel.size = Vector2(380, 400)
	var column := main_panel.get_child(0) as VBoxContainer
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_theme_constant_override("separation", 6)
	var delay := 0.35
	for b in column.get_children():
		if b is Button:
			_style_menu_button(b, delay)
			delay += 0.07

	(about_panel.get_node("VBoxContainer/BodyLabel") as Label).text = "Project Aether - a first-person action RPG of Figments: memories made into worlds.

Godot 4.7, GDScript. Endgame-first: a Memory Nexus hub with a Reality Engine that opens Figments, no campaign yet.

" + VERSION
	_style_plain_button(about_back_button)
	_framed(about_panel, about_panel.get_node("VBoxContainer"))

	var version := Label.new()
	version.text = VERSION
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.position = Vector2(-90, -40)
	version.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	add_child(version)

	var fade := ColorRect.new()
	fade.color = Color.BLACK
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	create_tween().tween_property(fade, "modulate:a", 0.0, 1.4).set_trans(Tween.TRANS_SINE)
	title.modulate.a = 0.0
	create_tween().tween_property(title, "modulate:a", 1.0, 1.6).set_delay(0.3)

func _style_menu_button(b: Button, delay: float) -> void:
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(340, 46)
	b.text = b.text.to_upper()
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_focus_color", GOLD)
	b.add_theme_color_override("font_pressed_color", Color(1, 0.9, 0.7))
	b.add_theme_color_override("font_disabled_color", TEXT_DISABLED)
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 18
	for s in ["normal", "disabled", "focus"]:
		b.add_theme_stylebox_override(s, empty)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.93, 0.76, 0.45, 0.08)
	hover.border_color = GOLD
	hover.border_width_left = 3
	hover.content_margin_left = 18
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.mouse_entered.connect(func():
		if not b.disabled:
			create_tween().tween_property(b, "position:x", 12.0, 0.12).set_trans(Tween.TRANS_QUAD))
	b.mouse_exited.connect(func(): create_tween().tween_property(b, "position:x", 0.0, 0.18).set_trans(Tween.TRANS_QUAD))
	b.modulate.a = 0.0
	create_tween().tween_property(b, "modulate:a", 1.0, 0.5).set_delay(delay)

func _style_plain_button(b: Button) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.1, 0.09, 0.08, 0.9)
	box.border_color = GOLD_DIM
	box.set_border_width_all(1)
	box.set_content_margin_all(8)
	b.add_theme_stylebox_override("normal", box)
	var hover := box.duplicate() as StyleBoxFlat
	hover.border_color = GOLD
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_color_override("font_hover_color", GOLD)

## Wraps a centred panel's content in a dark gold-edged frame.
func _framed(center: Control, content: Control) -> void:
	var frame := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.03, 0.035, 0.05, 0.92)
	box.border_color = GOLD_DIM
	box.set_border_width_all(1)
	box.set_content_margin_all(28)
	box.shadow_color = Color(0, 0, 0, 0.6)
	box.shadow_size = 18
	frame.add_theme_stylebox_override("panel", box)
	if content.get_parent():
		content.get_parent().remove_child(content)
	center.add_child(frame)
	frame.add_child(content)

## Loaded via load(), not preload() - the .mp3 has no .import config yet
## until Godot's asset pipeline processes it, and preload() resolves at
## script parse time, before that's guaranteed to have happened.
func _play_music() -> void:
	var stream: AudioStreamMP3 = load(MUSIC_PATH)
	if stream == null:
		return
	stream.loop = true
	music_player.stream = stream
	music_player.play()

func _show_panel(panel: Control) -> void:
	main_panel.visible = panel == main_panel
	settings_panel.visible = panel == settings_panel
	about_panel.visible = panel == about_panel
	wiki_panel.visible = panel == wiki_panel
	if new_game_panel:
		new_game_panel.visible = panel == new_game_panel
	if slots_panel:
		slots_panel.visible = panel == slots_panel
	if panel == wiki_panel:
		move_child(wiki_panel, get_child_count() - 1)
		wiki.refresh_character()

## The Wiki button (above Settings) and its panel: every Unique and Mythic
## with its drop odds, modifiers and corruption outcomes (Wiki).
func _build_wiki() -> void:
	var button := Button.new()
	button.name = "WikiButton"
	button.text = "Wiki"
	settings_button.add_sibling(button)
	settings_button.get_parent().move_child(button, settings_button.get_index())
	# Full screen with a dim backdrop: the panel is wide enough to reach the title.
	wiki_panel = Control.new()
	wiki_panel.name = "WikiPanel"
	wiki_panel.visible = false
	wiki_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(wiki_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wiki_panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wiki_panel.add_child(center)
	wiki = Wiki.new()
	wiki.back_pressed.connect(_show_panel.bind(main_panel))
	_framed(center, wiki)
	button.pressed.connect(_show_panel.bind(wiki_panel))

func _on_continue_pressed() -> void:
	slots.open(false)
	_show_panel(slots_panel)

func _build_slots() -> void:
	slots_panel = CenterContainer.new()
	slots_panel.name = "SaveSlotsPanel"
	slots_panel.visible = false
	slots_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(slots_panel)
	slots = SaveSlotPanel.new()
	slots.back_pressed.connect(_show_panel.bind(main_panel))
	slots.play_slot.connect(_play_slot)
	slots.new_character.connect(func(n: int):
		_pending_slot = n
		_open_new_game())
	slots.test_character.connect(_start_test_character)
	_framed(slots_panel, slots)

func _play_slot(n: int) -> void:
	SaveManager.select_slot(n)
	GameState.game_started = true
	LoadingScreen.change_scene(GameState.HUB_SCENE)

func _start_test_character(n: int) -> void:
	SaveManager.delete_save(n)
	SaveManager.select_slot(n)
	EndgameTestCharacter.build()
	GameState.game_started = true
	SaveManager.save_game()
	LoadingScreen.change_scene(GameState.HUB_SCENE)

func _build_new_game() -> void:
	new_game_panel = CenterContainer.new()
	new_game_panel.name = "NewGamePanel"
	new_game_panel.visible = false
	new_game_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(new_game_panel)
	new_game = NewGamePanel.new()
	new_game.back_pressed.connect(_show_panel.bind(main_panel))
	new_game.confirmed.connect(_start_new_game)
	_framed(new_game_panel, new_game)

func _open_new_game() -> void:
	new_game.reset()
	_show_panel(new_game_panel)

## New Game picks a slot first; filling a used slot asks there.
func _on_new_game_pressed() -> void:
	slots.open(true)
	_show_panel(slots_panel)

func _start_new_game(player_name: String, weapon_path: String, mode: GameState.GameMode) -> void:
	SaveManager.delete_save(_pending_slot)
	SaveManager.select_slot(_pending_slot)
	GameState.reset_to_defaults()
	GameState.player_name = player_name
	GameState.game_mode = mode
	GameState.weapon_set_refs = [[weapon_path], []]
	GameState.game_started = true
	SaveManager.save_game()
	LoadingScreen.change_scene(GameState.HUB_SCENE)

func _on_quit_pressed() -> void:
	SaveManager.save_game()
	get_tree().quit()
