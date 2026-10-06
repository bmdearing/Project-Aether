extends Node
## Builds one wrapper scene per model in tools/mdx_pipeline/models.json:
## the converted .glb + a HumanoidAnimTree instance (same layout as
## UALHumanoidModel.tscn), rooted on MdxModel.gd with per-geoset materials
## built from the model's .mdxmeta.json sidecar and the .dds files beside it.
## Run after convert_all.js:
##   Godot --headless --path . res://tools/build_mdx_wrappers.tscn --quit-after 20
## Prints every geoset left untextured (texture not shipped with the model).

const MANIFEST_PATH := "res://tools/mdx_pipeline/models.json"
const OUT_DIR := "res://entities/enemies/models/"
const ANIM_TREE_SCENE := "res://entities/enemies/base/HumanoidAnimTree.tscn"
const MODEL_SCRIPT := "res://entities/enemies/models/MdxModel.gd"
const UNTEXTURED_COLOR := Color(0.4, 0.4, 0.42)
const ALPHA_SCISSOR := 0.5

enum Filter { NONE, TRANSPARENT, BLEND, ADDITIVE, ADD_ALPHA, MODULATE }

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	for entry in manifest["models"]:
		_build_wrapper(entry)
	get_tree().quit()

func _build_wrapper(entry: Dictionary) -> void:
	var mdx_path := "res://" + String(entry["mdx"])
	var dir := mdx_path.get_base_dir() + "/"
	var glb_path := mdx_path.get_basename() + ".glb"
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(mdx_path.get_basename() + ".mdxmeta.json"))

	var root := Node3D.new()
	root.name = _scene_name(entry["unit"])
	root.set_script(load(MODEL_SCRIPT))

	var model := (load(glb_path) as PackedScene).instantiate()
	model.name = "Model"
	root.add_child(model)
	model.owner = root

	var tree := (load(ANIM_TREE_SCENE) as PackedScene).instantiate() as AnimationTree
	tree.name = "AnimationTree"
	root.add_child(tree)
	tree.owner = root
	tree.anim_player = NodePath("../Model/AnimationPlayer")

	var materials := {}
	var hidden := {}
	var always_hidden := PackedInt32Array()
	var untextured: Array[String] = []
	for g in meta["geosets"]:
		var index := int(g["index"])
		var filter := int(g["filter_mode"])
		var diffuse = g["textures"]["diffuse"]
		var black: bool = diffuse == null and String(g["sources"]["diffuse"] if g["sources"]["diffuse"] != null else "").containsn("Black32")
		if diffuse == null and not black:
			if filter >= Filter.BLEND:
				always_hidden.append(index)  # an effect card with no texture renders as a solid sheet
			untextured.append("%d%s" % [index, " (hidden fx)" if filter >= Filter.BLEND else ""])
		materials[index] = _build_material(dir, g, black)
		for clip in g["visibility"]:
			if not g["visibility"][clip]:
				if not hidden.has(clip):
					hidden[clip] = PackedInt32Array()
				hidden[clip].append(index)

	root.set("geoset_materials", materials)
	root.set("hidden_geosets", hidden)
	root.set("always_hidden", always_hidden)
	root.set("idle_clip", String(meta["idle_sequence"]))

	var packed := PackedScene.new()
	var err := packed.pack(root)
	var out_path := OUT_DIR + root.name + ".tscn"
	if err == OK:
		err = ResourceSaver.save(packed, out_path)
	print("%s -> %s (%s)" % [entry["unit"], out_path, error_string(err)])
	print("  untextured geosets: ", ", ".join(untextured) if not untextured.is_empty() else "none")
	root.free()

func _build_material(dir: String, g: Dictionary, black: bool) -> Material:
	var tex: Dictionary = g["textures"]
	var mat: BaseMaterial3D
	if tex["diffuse"] == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = Color.BLACK if black else UNTEXTURED_COLOR
	else:
		mat = ORMMaterial3D.new() if tex["orm"] != null else StandardMaterial3D.new()
		mat.albedo_texture = _texture(dir, tex["diffuse"])
		if tex["normal"] != null:
			mat.normal_enabled = true
			mat.normal_texture = _texture(dir, tex["normal"])
		if tex["orm"] != null:
			(mat as ORMMaterial3D).orm_texture = _texture(dir, tex["orm"])
		if tex["emissive"] != null and tex["emissive"] != tex["diffuse"]:
			mat.emission_enabled = true
			mat.emission = Color.BLACK  # the default ADD operator sums color + texture: black leaves the texture alone
			mat.emission_texture = _texture(dir, tex["emissive"])

	match int(g["filter_mode"]):
		Filter.TRANSPARENT:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.alpha_scissor_threshold = ALPHA_SCISSOR
		Filter.BLEND:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		Filter.ADDITIVE, Filter.ADD_ALPHA:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		Filter.MODULATE:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	if g["two_sided"]:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if g["unshaded"]:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

func _texture(dir: String, file: String) -> Texture2D:
	var tex := load(dir + file) as Texture2D
	if tex == null:
		push_error("build_mdx_wrappers: failed to load %s" % (dir + file))
	return tex

## "unchartered_cutthroat" -> "UncharteredCutthroatModel"
func _scene_name(unit: String) -> String:
	return unit.to_pascal_case() + "Model"
