extends RefCounted
class_name SlateSerializer
## Full-data serialize/deserialize for rolled Slates - same rationale as
## ItemSerializer (a rolled Slate has no resource_path to reference), but
## simpler: Slate has no subclasses, so no class-tag branching is needed.

static func to_dict(slate: Slate) -> Dictionary:
	if slate == null:
		return {}
	var modifiers := []
	for modifier in slate.modifiers:
		modifiers.append({
			"description": modifier.description,
			"stat_key": modifier.stat_key,
			"value": modifier.value,
			"value_min": modifier.value_min,
			"value_max": modifier.value_max,
			"is_more_multiplier": modifier.is_more_multiplier,
		})
	var shape := []
	for cell in slate.shape_cells:
		shape.append([cell.x, cell.y])
	return {
		"slate_id": slate.slate_id,
		"display_name": slate.display_name,
		"tag": slate.tag,
		"is_hybrid": slate.is_hybrid,
		"secondary_tag": slate.secondary_tag,
		"category_tag_override": slate.category_tag_override,
		"shape_cells": shape,
		"aether_cost": slate.aether_cost,
		"rarity": slate.rarity,
		"implicit_flavor_text": slate.implicit_flavor_text,
		"modifiers": modifiers,
	}

static func from_dict(d: Dictionary) -> Slate:
	if d.is_empty():
		return null
	var slate := Slate.new()
	slate.slate_id = d.get("slate_id", "")
	slate.display_name = d.get("display_name", "")
	slate.tag = d.get("tag", 0)
	slate.is_hybrid = d.get("is_hybrid", false)
	slate.secondary_tag = d.get("secondary_tag", 0)
	slate.category_tag_override = d.get("category_tag_override", "")
	slate.aether_cost = d.get("aether_cost", 1)
	slate.rarity = d.get("rarity", 0)
	slate.implicit_flavor_text = d.get("implicit_flavor_text", "")

	var shape: Array[Vector2i] = []
	for cell in d.get("shape_cells", []):
		if cell is Array and cell.size() == 2:
			shape.append(Vector2i(int(cell[0]), int(cell[1])))
	if shape.is_empty():
		shape.append(Vector2i.ZERO)  # appended, not a [..] literal - that's an untyped Array and fails the typed assignment
	slate.shape_cells = shape

	var modifiers: Array[SlateModifier] = []
	for m in d.get("modifiers", []):
		if m.get("stat_key", "") == "mastery":
			continue  # Mastery was removed in v4.8 - drop it from old saves
		var modifier := SlateModifier.new()
		modifier.description = ItemSerializer.migrate_stat_text(m.get("description", ""))
		modifier.stat_key = ItemSerializer.migrate_stat_key(m.get("stat_key", ""))
		modifier.value = m.get("value", 0.0)
		modifier.value_min = m.get("value_min", 0.0)
		modifier.value_max = m.get("value_max", 0.0)
		modifier.is_more_multiplier = m.get("is_more_multiplier", false)
		modifiers.append(modifier)
	slate.modifiers = modifiers

	return slate
