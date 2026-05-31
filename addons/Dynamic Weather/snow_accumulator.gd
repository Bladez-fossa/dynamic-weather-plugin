class_name SnowAccumulator
extends Node3D

## ── tunables ──────────────────────────────────────────────────
@export var accumulate_rate: float = 0.005
@export var melt_rate: float = 0.002
@export var melt_curve_power: float = 1.4

## ── internal ──────────────────────────────────────────────────
var accumulation: float = 0.0
var _snow_intensity: float = 0.0
var _ground_materials: Array[ShaderMaterial] = []


func _ready() -> void:
	call_deferred("_scan_and_override_ground")


func _process(delta: float) -> void:
	_update_accumulation(delta)

	for mat in _ground_materials:
		if mat and mat.shader:
			mat.set_shader_parameter("snow_accumulation", accumulation)

	if Engine.get_process_frames() % 60 == 0:
		print("❄️ accumulation: %.3f" % accumulation)


func set_intensity(intensity: float) -> void:
	_snow_intensity = clampf(intensity, 0.0, 1.0)


func clear() -> void:
	accumulation = 0.0


func _update_accumulation(delta: float) -> void:
	if _snow_intensity > 0.01:
		accumulation += _snow_intensity * accumulate_rate * delta
	else:
		var melt = melt_rate * pow(accumulation, melt_curve_power) * delta
		accumulation -= melt
	accumulation = clampf(accumulation, 0.0, 1.0)


func _scan_and_override_ground() -> void:
	var shader_path := "res://test_environment/snow_overlay.gdshader"
	if not ResourceLoader.exists(shader_path):
		push_error("SnowAccumulator: shader not found at: " + shader_path)
		return

	var shader := load(shader_path) as Shader
	if not shader:
		push_error("SnowAccumulator: failed to load shader.")
		return

	var nodes := get_tree().get_nodes_in_group("snow_ground")
	for node in nodes:
		if node is GeometryInstance3D:
			var mat := ShaderMaterial.new()
			mat.shader = shader

			var has_texture := false
			if node is MeshInstance3D and node.mesh:
				var orig_mat = node.mesh.surface_get_material(0)
				if orig_mat is StandardMaterial3D and orig_mat.albedo_texture:
					mat.set_shader_parameter("ground_texture", orig_mat.albedo_texture)
					has_texture = true

			mat.set_shader_parameter("use_ground_texture", has_texture)
			node.material_override = mat
			_ground_materials.append(mat)
			print("✅ Snow material applied to: ", node.name)

	if _ground_materials.is_empty():
		push_warning("SnowAccumulator: no GeometryInstance3D nodes found in group 'snow_ground'.")
	else:
		print("✅ Overridden %d ground meshes." % _ground_materials.size())
