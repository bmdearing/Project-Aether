extends Resource
class_name MapTileset
## One Figment style (e.g. Dungeon / Cellblock): ground and wall textures,
## the doodads GeneratedMap dresses rooms with, and the lighting/atmosphere.
## Styles of one family share a doodad kit (entities/environment/doodads/<family>/).
## See documents' Tileset Plan for the family -> style list.

const STYLE_DIR := "res://data/tilesets/styles/"
const GROUND_SHADER := preload("res://shaders/wc3_ground.gdshader")

@export var id: String = ""
@export var display_name: String = ""
@export var family: String = ""
## Map layout rules for this Figment type - see MapLayout ("rooms",
## "open_field", "canyon").
@export var layout: String = "rooms"
## Looping ambience played on this map (Ambience.LOOPS), "" for none.
@export var ambience_id: String = ""

## Layout shape for this style, so styles sharing a layout kind still play
## differently. Zero (or -1 for chances) keeps the layout kind's default.
@export_group("Layout")
@export var grid_size: int = 0
@export var room_count: Vector2i = Vector2i.ZERO
## Lower = long winding chains, higher = bushy with dead ends.
@export var branch_stop_chance: float = -1.0
@export var cell_size: float = 0.0
## Rooms: per-axis footprint range, corridor width, wall height, pillar chance.
@export var room_size: Vector2 = Vector2.ZERO
@export var corridor_width: float = 0.0
@export var wall_height: float = 0.0
@export var pillar_chance: float = -1.0
## Rooms: rough rock outcrops along the walls (mines, caves).
@export var cave_walls: bool = false
## Open fields: mounds per cell and their size.
@export var mounds_per_cell: Vector2i = Vector2i(-1, -1)
@export var mound_scale: float = 1.0
## Canyons: pass width and cliff height multipliers.
@export var pass_width_scale: float = 1.0
@export var cliff_height_scale: float = 1.0
## Open fields: deep rivers (crossed at fords) and shallow streams (WaterBuilder).
@export var rivers: int = 0
@export var streams: int = 0

## Streets (City): street width, the chance a junction is a wider plaza.
@export var street_width: float = 0.0
@export_range(0.0, 1.0) var plaza_chance: float = -1.0

@export_group("City")
## Facades lining every street edge (front = +X), and grander ones that
## plazas and the boss courtyard prefer.
@export var buildings: Array[PackedScene] = []
@export var landmarks: Array[PackedScene] = []
## Fountains, statues and stalls in plazas; lamps along the streets.
@export var plaza_props: Array[PackedScene] = []
@export var street_lights: Array[PackedScene] = []
@export var building_scale: float = 1.0
## Trainyard: rails down the middle of every street.
@export var rails: bool = false
## Steam vents (SteamVent) scattered along street edges.
@export var steam_vents: int = 0
## Harbor: the far row's outer edge opens onto water instead of buildings.
@export var waterfront: bool = false
## Open fields: line the edge with buildings instead of ridges (Park).
@export var building_boundary: bool = false

@export_group("Ground")
@export var floor_albedo: Texture2D
@export var floor_normal: Texture2D
@export var floor_orm: Texture2D
@export var floor_wide: bool = true          # 2048 sheet with 16 variants; false = 1024 transition sheet
@export var patch_albedo: Texture2D          # optional second ground blended in as patches
@export var patch_normal: Texture2D
@export var patch_orm: Texture2D
@export var patch_wide: bool = true
@export_range(0.0, 1.0) var patch_amount: float = 0.0
@export var floor_tint: Color = Color.WHITE

@export_group("Walls")
@export var wall_albedo: Texture2D
@export var wall_normal: Texture2D
@export var wall_orm: Texture2D
@export var wall_wide: bool = true
@export var wall_tint: Color = Color.WHITE

@export_group("Pits")
## Clustered holes in the ground and wall shader (Pale family), and how far
## the ground sheets are pulled toward grey before tinting.
@export_range(0.0, 1.0) var floor_pit_amount: float = 0.0
@export_range(0.0, 1.0) var wall_pit_amount: float = 0.0
@export var pit_scale: float = 0.6
@export var pit_color: Color = Color(0.09, 0.06, 0.055)
@export_range(0.0, 1.0) var ground_desaturate: float = 0.0

@export_group("Doodads")
@export var archways: Array[PackedScene] = []  # one per doorway, fitted to its width
@export var wall_props: Array[PackedScene] = []
@export var floor_props: Array[PackedScene] = []
@export var clusters: Array[PackedScene] = []  # rocks/plants in corners and along edges
@export var wall_lights: Array[PackedScene] = []
## Reeds and lilypads along rivers and streams.
@export var water_props: Array[PackedScene] = []
@export var wall_props_per_room: Vector2i = Vector2i(2, 4)
@export var floor_props_per_room: Vector2i = Vector2i(0, 2)
@export var clusters_per_room: Vector2i = Vector2i(2, 4)
@export var lights_per_room: int = 2
## Multiplies the open layouts' loose scatter per cell (a forest wants more).
@export var scatter_scale: float = 1.0

@export_group("Atmosphere")
@export var background_color: Color = Color(0.05, 0.05, 0.06)
@export var ambient_color: Color = Color(0.4, 0.4, 0.45)
@export var ambient_energy: float = 0.4
@export var sun_energy: float = 0.0           # 0 = no directional light (indoor)
@export var sun_color: Color = Color.WHITE
@export var fog_color: Color = Color(0.1, 0.1, 0.1)
@export var fog_density: float = 0.0
@export var light_color: Color = Color(1.0, 0.7, 0.4)  # wall lights
@export var light_energy: float = 2.0
@export var light_range: float = 8.0
@export var room_light_energy: float = 0.0    # soft fill light above each room centre
## Time of day the clock is held at (0..1, 0.5 noon); -1 runs the normal day.
@export var fixed_time: float = -1.0

static func load_style(style_id: String) -> MapTileset:
	if style_id.is_empty() or not ResourceLoader.exists(STYLE_DIR + style_id + ".tres"):
		return null
	var style := load(STYLE_DIR + style_id + ".tres") as MapTileset
	if OS.is_debug_build() and style and STYLE_INFO.has(style_id) and STYLE_INFO[style_id] != [style.display_name, style.family]:
		push_warning("MapTileset.STYLE_INFO is out of date for %s" % style_id)
	return style

static var _ids := PackedStringArray()

static func all_ids() -> PackedStringArray:
	if not _ids.is_empty():
		return _ids
	var ids := PackedStringArray()
	for f in DirAccess.get_files_at(STYLE_DIR):
		if f.ends_with(".tres"):
			ids.append(f.get_basename())
		elif f.ends_with(".tres.remap"):
			ids.append(f.trim_suffix(".remap").get_basename())
	ids.sort()
	_ids = ids
	return ids

## Families in display order (Figment Tree, progress grid).
const FAMILIES: Array[String] = ["dungeon", "desert", "forest", "snow", "city", "pale"]

## Name and family per style, so menus, tooltips and Figment drops don't
## load a whole style (every texture and building scene it references).
## load_style() warns in debug builds when a style drifts from this.
const STYLE_INFO := {
	"city_downtown": ["Downtown", "city"],
	"city_harbor": ["Harbor", "city"],
	"city_park": ["Park", "city"],
	"city_residence": ["Residence", "city"],
	"city_trainyard": ["Trainyard", "city"],
	"desert_badlands": ["Badlands", "desert"],
	"desert_dunes": ["Dunes", "desert"],
	"dungeon_cellblock": ["Cellblock", "dungeon"],
	"dungeon_foundry_pit": ["Foundry Pit", "dungeon"],
	"dungeon_mine": ["Mine", "dungeon"],
	"dungeon_undercroft": ["Undercroft", "dungeon"],
	"forest_aspen": ["Aspen Grove", "forest"],
	"forest_hills": ["Hills", "forest"],
	"forest_plains": ["Plains", "forest"],
	"forest_river_valley": ["River Valley", "forest"],
	"pale_bone_flats": ["Bone Flats", "pale"],
	"pale_hollow_reach": ["Hollow Reach", "pale"],
	"pale_unbuilt": ["The Unbuilt", "pale"],
	"snow_frostwood": ["Frostwood", "snow"],
	"snow_frozen_crypt": ["Frozen Crypt", "snow"],
	"snow_glacier_pass": ["Glacier Pass", "snow"],
	"snow_tundra": ["Tundra", "snow"],
}

## Styles missing from STYLE_INFO fall back to loading the resource once.
static var _info_cache: Dictionary = {}

static func _info(style_id: String) -> Array:
	if STYLE_INFO.has(style_id):
		return STYLE_INFO[style_id]
	if not _info_cache.has(style_id):
		var style := load_style(style_id)
		_info_cache[style_id] = [style.display_name, style.family] if style else ["", ""]
	return _info_cache[style_id]

static func display_name_of(style_id: String) -> String:
	return _info(style_id)[0]

static func family_of(style_id: String) -> String:
	return _info(style_id)[1]

static func random_id() -> String:
	var ids := all_ids()
	return ids[randi() % ids.size()] if not ids.is_empty() else ""

func make_floor_material() -> ShaderMaterial:
	var mat := _ground_material(floor_albedo, floor_normal, floor_orm, floor_wide, floor_tint)
	if patch_albedo and patch_amount > 0.0:
		mat.set_shader_parameter("albedo_b", patch_albedo)
		mat.set_shader_parameter("normal_b", patch_normal)
		mat.set_shader_parameter("orm_b", patch_orm)
		mat.set_shader_parameter("wide_b", patch_wide)
		mat.set_shader_parameter("b_amount", patch_amount)
	_apply_pits(mat, floor_pit_amount)
	return mat

func make_wall_material() -> ShaderMaterial:
	var mat := _ground_material(wall_albedo, wall_normal, wall_orm, wall_wide, wall_tint)
	mat.set_shader_parameter("wall_mode", true)
	_apply_pits(mat, wall_pit_amount)
	return mat

func _apply_pits(mat: ShaderMaterial, amount: float) -> void:
	mat.set_shader_parameter("desaturate", ground_desaturate)
	if amount > 0.0:
		mat.set_shader_parameter("pit_amount", amount)
		mat.set_shader_parameter("pit_scale", pit_scale)
		mat.set_shader_parameter("pit_color", pit_color)

func _ground_material(albedo: Texture2D, normal: Texture2D, orm: Texture2D, wide: bool, tint: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("albedo_a", albedo)
	mat.set_shader_parameter("normal_a", normal)
	mat.set_shader_parameter("orm_a", orm)
	mat.set_shader_parameter("wide_a", wide)
	mat.set_shader_parameter("tint", tint)
	return mat

func make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = background_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient_color
	env.ambient_light_energy = ambient_energy
	if fog_density > 0.0:
		env.fog_enabled = true
		env.fog_light_color = fog_color
		env.fog_density = fog_density
	return env
