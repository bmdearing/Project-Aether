extends Node
## Implementation Brief v4.8 repair pass - Prowess/Finesse/Resolve ->
## Strength/Agility/Intellect across every data .tres, plus Mastery removal:
##  - item stat requirements (prowess_requirement -> strength_requirement...)
##  - weapon primary/secondary_scaling_stat values
##  - affix/modifier stat_keys and affix_ids (flat_*, generic_of_*)
##  - player_baseline.tres raw stat fields
##  - "+N Prowess" style descriptions/display names (whole words only)
##  - hand-authored palette Slates still carrying pre-v3.8 six-stat keys
##    (flat_vitality/instinct/arcane/enigma - missed by
##    repair_stat_migration.gd), mapped the same way v3.8 intended:
##    Vitality -> Strength, Instinct -> Agility, Arcane/Enigma -> Intellect
##  - "mastery" Slate modifiers removed (re-saved through ResourceSaver so
##    the sub_resource and its array reference go together)
## Plain line edits otherwise, so the rest of each file is untouched.
## Idempotent. Weapon affix files named generic_of_<old stat>.tres are
## renamed separately (git mv) - see PATCH_NOTES.md v4.8.
## Run: Godot --headless --path . res://tools/repair_v48_stat_rename.tscn --quit-after 5

const DIRS := [
	"res://data/weapons/instances/",
	"res://data/armor/instances/",
	"res://data/shields/instances/",
	"res://data/items/instances/",
	"res://data/slates/instances/",
	"res://data/stats/instances/",
	"res://data/affixes/weapons/",
]
const SLATE_DIR := "res://data/slates/instances/"

## Exact "key = " prefixes at the start of a line.
const FIELD_RENAMES := {
	"prowess_requirement = ": "strength_requirement = ",
	"finesse_requirement = ": "agility_requirement = ",
	"resolve_requirement = ": "intellect_requirement = ",
	"prowess = ": "strength = ",
	"finesse = ": "agility = ",
	"resolve = ": "intellect = ",
}
## Quoted values, only on the listed field lines.
const VALUE_FIELDS := ["primary_scaling_stat", "secondary_scaling_stat", "stat_key", "affix_id"]
const VALUE_RENAMES := {
	"\"prowess\"": "\"strength\"",
	"\"finesse\"": "\"agility\"",
	"\"resolve\"": "\"intellect\"",
	"\"flat_prowess\"": "\"flat_strength\"",
	"\"flat_finesse\"": "\"flat_agility\"",
	"\"flat_resolve\"": "\"flat_intellect\"",
	"\"generic_of_prowess\"": "\"generic_of_strength\"",
	"\"generic_of_finesse\"": "\"generic_of_agility\"",
	"\"generic_of_resolve\"": "\"generic_of_intellect\"",
}
## Pre-v3.8 keys - only ever left behind in the hand-authored Slates.
const LEGACY_SLATE_KEYS := {
	"\"flat_vitality\"": "\"flat_strength\"",
	"\"flat_instinct\"": "\"flat_agility\"",
	"\"flat_arcane\"": "\"flat_intellect\"",
	"\"flat_enigma\"": "\"flat_intellect\"",
}
const TEXT_FIELDS := ["description", "display_name"]
const WORD_RENAMES := {"Prowess": "Strength", "Finesse": "Agility", "Resolve": "Intellect"}
const LEGACY_SLATE_WORDS := {"Vitality": "Strength", "Instinct": "Agility", "Arcane": "Intellect", "Enigma": "Intellect"}

var _counts := {}

func _ready() -> void:
	call_deferred("_run")

func _bump(label: String) -> void:
	_counts[label] = _counts.get(label, 0) + 1

func _run() -> void:
	var files_changed := 0
	for path in _all_tres():
		var text := FileAccess.get_file_as_string(path)
		var out := _rewrite(text, path.begins_with(SLATE_DIR))
		if out != text:
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string(out)
			f.close()
			files_changed += 1
	var mastery_removed := _strip_mastery()
	print("V48_REPAIR files_changed=%d mastery_modifiers_removed=%d" % [files_changed, mastery_removed])
	for label in _counts:
		print("  %s: %d" % [label, _counts[label]])
	get_tree().quit()

func _all_tres() -> Array[String]:
	var out: Array[String] = []
	for dir_path in DIRS:
		_collect(dir_path, out)
	return out

func _collect(dir_path: String, out: Array[String]) -> void:
	for file_name in DirAccess.get_files_at(dir_path):
		if file_name.ends_with(".tres"):
			out.append(dir_path + file_name)
	for sub in DirAccess.get_directories_at(dir_path):
		_collect(dir_path + sub + "/", out)

func _rewrite(text: String, is_slate: bool) -> String:
	var lines := text.split("\n")
	for i in lines.size():
		var line: String = lines[i]
		for old_prefix in FIELD_RENAMES:
			if line.begins_with(old_prefix):
				line = FIELD_RENAMES[old_prefix] + line.substr(old_prefix.length())
				_bump(old_prefix.strip_edges())
		var field := line.get_slice(" = ", 0)
		if field in VALUE_FIELDS:
			for old_value in VALUE_RENAMES:
				if line.ends_with(old_value):
					line = line.trim_suffix(old_value) + VALUE_RENAMES[old_value]
					_bump("%s %s" % [field, old_value])
			if is_slate and field == "stat_key":
				for old_value in LEGACY_SLATE_KEYS:
					if line.ends_with(old_value):
						line = line.trim_suffix(old_value) + LEGACY_SLATE_KEYS[old_value]
						_bump("slate legacy %s" % old_value)
		if field in TEXT_FIELDS:
			var words: Dictionary = WORD_RENAMES.duplicate()
			if is_slate:
				words.merge(LEGACY_SLATE_WORDS)
			for word in words:
				var regex := RegEx.create_from_string("\\b%s\\b" % word)
				var replaced := regex.sub(line, words[word], true)
				if replaced != line:
					line = replaced
					_bump("%s word %s" % [field, word])
		lines[i] = line
	return "\n".join(lines)

func _strip_mastery() -> int:
	var removed := 0
	for file_name in DirAccess.get_files_at(SLATE_DIR):
		if not file_name.ends_with(".tres"):
			continue
		var path := SLATE_DIR + file_name
		var slate := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Slate
		if slate == null:
			continue
		var kept: Array[SlateModifier] = []
		for modifier in slate.modifiers:
			if modifier.stat_key == "mastery":
				removed += 1
			else:
				kept.append(modifier)
		if kept.size() != slate.modifiers.size():
			slate.modifiers = kept
			ResourceSaver.save(slate, path)
	return removed
