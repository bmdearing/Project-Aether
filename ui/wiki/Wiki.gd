extends VBoxContainer
class_name Wiki
## The Wiki (main menu and pause menu): tabs for Uniques, Modifiers, Lenses,
## Corruption, Status Effects and Monsters. Pages are built the first time
## they're opened.

signal back_pressed

const PAGES := ["Uniques", "Modifiers", "Lenses", "Corruption", "Status Effects", "Monsters"]
const PAGE_HEIGHT := 650.0

var uniques: UniqueWiki
var modifiers: ModifierWiki
var corruption: CorruptionWiki
var statuses: StatusWiki
var monsters: MonsterWiki
var lenses: LensWiki
var current_page: String = "Uniques"

var _tabs: HBoxContainer
var _holder: Control

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "Wiki"
	AetherStyle.title_label(title, 26)
	add_child(title)
	_tabs = HBoxContainer.new()
	add_child(_tabs)
	for page in PAGES:
		var b := Button.new()
		b.text = page
		b.toggle_mode = true
		b.pressed.connect(show_page.bind(page))
		_tabs.add_child(b)
	_holder = VBoxContainer.new()
	_holder.custom_minimum_size = Vector2(UniqueWiki.WIDTH, PAGE_HEIGHT)
	add_child(_holder)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(140, 0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func(): back_pressed.emit())
	add_child(back)
	show_page("Uniques")

func show_page(page: String) -> void:
	current_page = page
	for b in _tabs.get_children():
		b.button_pressed = b.text == page
	if page == "Uniques" and uniques == null:
		uniques = UniqueWiki.new()
		_holder.add_child(uniques)
	elif page == "Modifiers" and modifiers == null:
		modifiers = ModifierWiki.new()
		_holder.add_child(modifiers)
	elif page == "Corruption" and corruption == null:
		corruption = CorruptionWiki.new()
		_holder.add_child(corruption)
	elif page == "Status Effects" and statuses == null:
		statuses = StatusWiki.new()
		_holder.add_child(statuses)
	elif page == "Monsters" and monsters == null:
		monsters = MonsterWiki.new()
		_holder.add_child(monsters)
	elif page == "Lenses" and lenses == null:
		lenses = LensWiki.new()
		_holder.add_child(lenses)
	var by_page := {"Uniques": uniques, "Modifiers": modifiers, "Corruption": corruption, "Status Effects": statuses, "Monsters": monsters, "Lenses": lenses}
	for name in by_page:
		if by_page[name]:
			by_page[name].visible = name == page

## Re-reads the character for the Uniques page's Magic Find.
func refresh_character() -> void:
	if uniques:
		uniques.refresh_character()
