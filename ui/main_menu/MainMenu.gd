extends Control
class_name MainMenu
## Entry point (project.godot's run/main_scene). Plain Control, not a
## CanvasLayer overlay - no gameplay runs underneath to overlay here.
##
## SaveManager loads any existing save into GameState at boot, before
## this scene shows, so Continue (gated on SaveManager.has_save()) just
## goes straight to the Hub. New Game resets GameState to defaults and
## deletes the save file, so a stale Continue can't reappear. Settings
## write straight to GameState + the engine and persist via the same
## save file regardless of Continue/New Game.

@onready var continue_button: Button = $MainPanel/VBoxContainer/ContinueButton
@onready var new_game_button: Button = $MainPanel/VBoxContainer/NewGameButton
@onready var settings_button: Button = $MainPanel/VBoxContainer/SettingsButton
@onready var about_button: Button = $MainPanel/VBoxContainer/AboutButton
@onready var quit_button: Button = $MainPanel/VBoxContainer/QuitButton

@onready var main_panel: Control = $MainPanel
@onready var settings_panel: Control = $SettingsPanel
@onready var about_panel: Control = $AboutPanel

@onready var mouse_sensitivity_slider: HSlider = $SettingsPanel/VBoxContainer/MouseSensitivitySlider
@onready var master_volume_slider: HSlider = $SettingsPanel/VBoxContainer/MasterVolumeSlider
@onready var fullscreen_checkbox: CheckBox = $SettingsPanel/VBoxContainer/FullscreenCheckBox
@onready var settings_back_button: Button = $SettingsPanel/VBoxContainer/SettingsBackButton
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
	settings_back_button.pressed.connect(_show_panel.bind(main_panel))
	about_back_button.pressed.connect(_show_panel.bind(main_panel))

	mouse_sensitivity_slider.value = GameState.mouse_sensitivity
	master_volume_slider.value = GameState.master_volume
	fullscreen_checkbox.button_pressed = GameState.fullscreen
	mouse_sensitivity_slider.value_changed.connect(_on_mouse_sensitivity_changed)
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	fullscreen_checkbox.toggled.connect(_on_fullscreen_toggled)

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

func _on_mouse_sensitivity_changed(value: float) -> void:
	GameState.mouse_sensitivity = value

func _on_master_volume_changed(value: float) -> void:
	GameState.master_volume = value
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(max(value, 0.0001)))

func _on_fullscreen_toggled(enabled: bool) -> void:
	GameState.fullscreen = enabled
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
