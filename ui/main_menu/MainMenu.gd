extends Control
class_name MainMenu
## Entry point (project.godot's run/main_scene). Plain Control, not a
## CanvasLayer overlay - no gameplay runs underneath to overlay here.
##
## SaveManager loads any existing save into GameState at boot, before
## this scene shows, so Continue (gated on SaveManager.has_save()) just
## goes straight to the Hub. New Game resets GameState to defaults and
## deletes the save file, so a stale Continue can't reappear. Settings are
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

const MUSIC_PATH := "res://assets/music/lament.mp3"

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_play_music()
	continue_button.disabled = not SaveManager.has_save()
	continue_button.pressed.connect(_on_continue_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed)
	settings_button.pressed.connect(_show_panel.bind(settings_panel))
	about_button.pressed.connect(_show_panel.bind(about_panel))
	quit_button.pressed.connect(_on_quit_pressed)
	about_back_button.pressed.connect(_show_panel.bind(main_panel))
	var settings := SettingsPanel.new()
	settings.back_pressed.connect(_show_panel.bind(main_panel))
	settings_panel.add_child(settings)

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

func _on_continue_pressed() -> void:
	GameState.game_started = true
	get_tree().change_scene_to_file(GameState.HUB_SCENE)

func _on_new_game_pressed() -> void:
	GameState.reset_to_defaults()
	SaveManager.delete_save()
	GameState.game_started = true
	get_tree().change_scene_to_file(GameState.HUB_SCENE)

func _on_quit_pressed() -> void:
	SaveManager.save_game()
	get_tree().quit()
