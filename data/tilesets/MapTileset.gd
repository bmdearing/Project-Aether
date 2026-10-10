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

@export_group("Doodads")
@export var archways: Array[PackedScene] = []  # one per doorway, fitted to its width
@export var wall_props: Array[PackedScene] = []
@export var floor_props: Array[PackedScene] = []
@export var clusters: Array[PackedScene] = []  # rocks/plants in corners and along edges
@export var wall_lights: Array[PackedScene] = []
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

static func load_style(style_id: String) -> MapTileset:
	if style_id.is_empty() or not ResourceLoader.exists(STYLE_DIR + style_id + ".tres"):
		return null
	return load(STYLE_DIR + style_id + ".tres") as MapTileset

static func all_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for f in DirAccess.get_files_at(STYLE_DIR):
		if f.ends_with(".tres"):
			ids.append(f.get_basename())
		elif f.ends_with(".tres.remap"):
			ids.append(f.trim_suffix(".remap").get_basename())
	ids.sort()
	return ids

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
	return mat

func make_wall_material() -> ShaderMaterial:
	var mat := _ground_material(wall_albedo, wall_normal, wall_orm, wall_wide, wall_tint)
	mat.set_shader_parameter("wall_mode", true)
	return mat

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
