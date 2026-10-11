extends VBoxContainer
class_name SaveSlotPanel
## The three save slots (SaveManager.SLOT_COUNT). In "continue" mode each
## filled slot can be played or deleted; in "new" mode any slot can take a
## new character or a Level 90 Test Character (EndgameTestCharacter).
## Overwriting or deleting a filled slot asks first.

signal play_slot(slot: int)
signal new_character(slot: int)
signal test_character(slot: int)
signal back_pressed

const MODE_NAMES := {GameState.GameMode.CAMPAIGN: "Campaign", GameState.GameMode.FRAGMENTED_REALITY: "Fragmented Reality"}

var _new_mode := false
var _title: Label
var _rows: VBoxContainer

func _ready() -> void:
	custom_minimum_size = Vector2(720, 0)
	add_theme_constant_override("separation", 14)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", MainMenu.GOLD)
	add_child(_title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	add_child(_rows)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func(): back_pressed.emit())
	add_child(back)

func open(new_mode: bool) -> void:
	_new_mode = new_mode
	_title.text = "Choose a Slot for a New Character" if new_mode else "Continue"
	refresh()

func refresh() -> void:
	for child in _rows.get_children():
		child.queue_free()
	for n in range(1, SaveManager.SLOT_COUNT + 1):
		_rows.add_child(_build_row(n))

## "Slot 2 - Aria, Level 74, Fragmented Reality - Tier 6 cleared - 10 Oct 14:02"
static func describe(n: int, summary: Dictionary) -> String:
	if summary.is_empty():
		return "Slot %d - Empty" % n
	var who: String = summary["name"] if summary["name"] != "" else "Unnamed"
	var progress := "Tier %d cleared" % summary["best_tier"] if summary["best_tier"] > 0 else (
		"Levelling done" if summary["depth"] >= AreaLevel.DEPTHS else "Depth %d of %d" % [summary["depth"], AreaLevel.DEPTHS])
	var when := ""
	if summary["saved_at"] > 0:
		var t := Time.get_datetime_dict_from_unix_time(summary["saved_at"] + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
		when = " - %02d/%02d %02d:%02d" % [t["day"], t["month"], t["hour"], t["minute"]]
	return "Slot %d - %s, Level %d, %s - %s%s" % [n, who, summary["level"], MODE_NAMES.get(summary["mode"], "?"), progress, when]

func _build_row(n: int) -> Control:
	var summary := SaveManager.slot_summary(n)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = describe(n, summary)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", MainMenu.TEXT if not summary.is_empty() else MainMenu.TEXT_DISABLED)
	row.add_child(label)
	if _new_mode:
		_add_button(row, "New Character", func(): _confirm_overwrite(n, summary, func(): new_character.emit(n)))
		_add_button(row, "Level 90 Test", func(): _confirm_overwrite(n, summary, func(): test_character.emit(n)))
	else:
		var play := _add_button(row, "Play", func(): play_slot.emit(n))
		play.disabled = summary.is_empty()
		var delete := _add_button(row, "Delete", func(): _confirm("Delete Slot %d?" % n, "%s\nThis can't be undone." % describe(n, summary), "Delete", func():
			SaveManager.delete_save(n)
			refresh()))
		delete.disabled = summary.is_empty()
	return row

func _add_button(row: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	row.add_child(b)
	return b

func _confirm_overwrite(n: int, summary: Dictionary, then: Callable) -> void:
	if summary.is_empty():
		then.call()
		return
	_confirm("Overwrite Slot %d?" % n, "%s\nStarting here deletes it." % describe(n, summary), "Overwrite", then)

func _confirm(title: String, text: String, ok: String, then: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = text
	dialog.ok_button_text = ok
	dialog.cancel_button_text = "Cancel"
	dialog.confirmed.connect(then)
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()
