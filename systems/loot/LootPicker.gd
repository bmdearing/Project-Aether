extends Node
class_name LootPicker
## Look-to-pick-up for gear drops (LootPicker on the Player). Each frame it
## finds the LootPickup in the "loot_look" group closest to the centre of the
## view, within REACH and in line of sight; Interact picks it up. The HUD
## shows the target's ItemCard (LootLookCard). Drops that are collected on
## touch (currency, fragments, Figments, Tomes, ammo) never join the group.

signal target_changed(pickup: LootPickup)

const REACH := 5.0
## How far off the view ray a drop may be and still count as looked at:
## BASE at the camera, growing with distance so far drops aren't pixel hunts.
const LOOK_RADIUS_BASE := 0.35
const LOOK_RADIUS_PER_METRE := 0.06

var target: LootPickup = null

var _player: Player

func _ready() -> void:
	_player = get_parent() as Player

func _physics_process(_delta: float) -> void:
	_set_target(_find_target())

func _set_target(pickup: LootPickup) -> void:
	if pickup == target:
		return
	if is_instance_valid(target):
		target.set_targeted(false)
	target = pickup
	if target:
		target.set_targeted(true)
	target_changed.emit(target)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and is_instance_valid(target):
		get_viewport().set_input_as_handled()
		pick_up_target()

## Picks up the current target. False when there's none or no room.
func pick_up_target() -> bool:
	if not is_instance_valid(target):
		return false
	var picked := target.try_pickup()
	if picked:
		_set_target(null)
	return picked

func _can_look() -> bool:
	if _player == null or _player.camera == null or not _player.health.is_alive():
		return false
	return not AetherStyle.menu_open(get_tree())

func _find_target() -> LootPickup:
	if not _can_look():
		return null
	var origin := _player.camera.global_position
	var forward := -_player.camera.global_transform.basis.z
	var best: LootPickup = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group(LootPickup.LOOK_GROUP):
		var pickup := node as LootPickup
		if pickup == null or pickup.is_queued_for_deletion():
			continue
		var to := pickup.global_position - origin
		var along := to.dot(forward)
		if along <= 0.0 or to.length() > REACH:
			continue
		var off := (to - forward * along).length()
		if off > LOOK_RADIUS_BASE + LOOK_RADIUS_PER_METRE * along:
			continue
		var score := off / along
		if score < best_score and _in_sight(origin, pickup):
			best = pickup
			best_score = score
	return best

## Nothing solid (walls, enemies) between the camera and the drop.
func _in_sight(origin: Vector3, pickup: LootPickup) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin, pickup.global_position, 1)
	query.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(pickup.global_position) < 0.4
