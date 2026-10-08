extends CanvasLayer
class_name CharacterScreen
## Read-only character sheet (`C`); doesn't pause the game. All 3 stats come from gear, Slates and level
## (see StatSheet.gd), so this just displays live totals via
## StatSummaryBuilder (shared with InventoryScreen's own stats column).
##
## Patch v3.8b: PrimaryStatsRow's 3 large STRENGTH/AGILITY/INTELLECT labels are
## a PoE-style "the 3 stats that matter" header, always freshly computed
## in _refresh() - "live on gear equip/unequip" is automatic since
## PauseMenu._toggle_screen() never lets this and InventoryScreen be open
## at the same time (equipping requires closing this screen first).

@onready var offense_list: VBoxContainer = $CenterContainer/VBox/Columns/OffenseColumn/OffenseList
@onready var defense_list: VBoxContainer = $CenterContainer/VBox/Columns/DefenseColumn/DefenseList
@onready var misc_list: VBoxContainer = $CenterContainer/VBox/Columns/MiscColumn/MiscList
@onready var close_button: Button = $CenterContainer/VBox/CloseButton
@onready var strength_label: Label = $CenterContainer/VBox/PrimaryStatsRow/StrengthLabel
@onready var agility_label: Label = $CenterContainer/VBox/PrimaryStatsRow/AgilityLabel
@onready var intellect_label: Label = $CenterContainer/VBox/PrimaryStatsRow/IntellectLabel

var _is_open: bool = false
var _refresh_timer: float = 0.0
const REFRESH_INTERVAL := 0.5  # the game keeps running underneath, so stats can change

func _ready() -> void:
	layer = AetherStyle.SCREEN_LAYER  # above the HUD
	AetherStyle.style_screen(self)
	AetherStyle.wrap_in_plate($CenterContainer/VBox, 24)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("character_screen")
	add_to_group("blocking_menu")
	close_button.pressed.connect(close)

func is_open() -> bool:
	return _is_open

func open() -> void:
	_is_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()

func close() -> void:
	_is_open = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	if not _is_open:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_INTERVAL
		_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _refresh() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	StatSummaryBuilder.refresh(offense_list, defense_list, misc_list, player)
	if player == null:
		return
	var stats: StatSheet = player.stat_sheet
	strength_label.text = "STRENGTH: %d" % round(stats.get_stat(Constants.Stat.STRENGTH))
	agility_label.text = "AGILITY: %d" % round(stats.get_stat(Constants.Stat.AGILITY))
	intellect_label.text = "INTELLECT: %d" % round(stats.get_stat(Constants.Stat.INTELLECT))
