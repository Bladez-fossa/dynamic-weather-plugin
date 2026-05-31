extends BaseCloudController

@export var coverage_speed: float = 1.2
@export var precip_speed: float = 2.0

@export_group("Cloud Appearance")
@export_range(0.5, 3.0) var puff_scale: float = 0.75
@export_range(0.5, 3.0) var puff_contrast: float = 1.8
@export_range(0.0, 1.0) var gap_sharpness: float = 0.80

@export_group("Mesh Setup")
@export var plane_size: float = 3000.0
@export var shell_heights: Array[float] = [180.0, 210.0]

@export_group("Cloud Grouping")
@export_range(0.0, 1.0) var clump_strength: float = 0.5
@export_range(0.0, 2.0) var warp_strength: float = 0.9

@export_group("Wind")
@export var wind_dir: Vector2 = Vector2(1.0, 0.3)
@export_range(0.0, 10.0) var wind_speed: float = 1.0

@export_group("Sky Coverage")
@export_range(0.0, 1.0) var min_coverage_threshold: float = 0.72
@export_range(-0.5, 1.0) var max_coverage_threshold: float = 0.20
@export_range(0.05, 0.5) var coverage_smoothness: float = 0.12

@export_group("Weather Transition Targets")
@export_range(0.5, 3.0) var target_puff_scale: float = 0.75
@export_range(0.5, 3.0) var target_puff_contrast: float = 1.8
@export_range(0.0, 1.0) var target_gap_sharpness: float = 0.80
@export_range(0.0, 1.0) var target_clump_strength: float = 0.5
@export_range(0.0, 2.0) var target_warp_strength: float = 0.9
@export var target_wind_dir: Vector2 = Vector2(1.0, 0.3)
@export_range(0.0, 10.0) var target_wind_speed: float = 1.0
@export_range(0.1, 3.0) var shape_speed: float = 0.5

var _coverage: float = 0.0
var _precipitation: float = 0.0
var _light_multiplier: float = 1.0
var target_coverage: float = 0.0
var target_precipitation: float = 0.0
var target_light_multiplier: float = 1.0
var _first_update: bool = true
var _appearance_dirty: bool = true  # only push static uniforms when they change

var _shells: Array[MeshInstance3D] = []
var _camera: Camera3D

func _ready() -> void:
	super._ready()
	_camera = get_viewport().get_camera_3d()
	_coverage = target_coverage
	_precipitation = target_precipitation
	_light_multiplier = target_light_multiplier
	_generate_shells()
	_set_shells_visible(false)

	if weather_manager:
		weather_manager.connect("WeatherUpdated", _on_weather_updated)
		print("✅ Altocumulus: connected to WeatherManager")
	else:
		push_error("Altocumulus: WeatherManager not found.")

func _generate_shells() -> void:
	for shell in _shells:
		shell.queue_free()
	_shells.clear()

	for i in shell_heights.size():
		var plane = PlaneMesh.new()
		plane.size = Vector2(plane_size, plane_size)
		# Fix: dropped from 60×60 to 12×12 — domain warp displacement is
		# low-frequency so extra verts bought nothing but vertex shader cost
		plane.subdivide_width  = 12
		plane.subdivide_depth  = 12

		var mesh_instance = MeshInstance3D.new()
		mesh_instance.mesh = plane
		mesh_instance.position.y = shell_heights[i]
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.name = "AltoShell_%d" % i

		var mat = ShaderMaterial.new()
		mat.shader = preload("res://Dynamic Weather/Shaders/altocumulus.gdshader")
		mat.set_shader_parameter("shell_layer", float(i))
		mesh_instance.set_surface_override_material(0, mat)

		add_child(mesh_instance)
		_shells.append(mesh_instance)

func _process(delta: float) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
		return

	var cam_pos = _camera.global_position
	global_position = Vector3(cam_pos.x, global_position.y, cam_pos.z)

	_coverage         = lerp(_coverage,         target_coverage,         coverage_speed * delta)
	_precipitation    = lerp(_precipitation,    target_precipitation,    precip_speed * delta)
	_light_multiplier = lerp(_light_multiplier, target_light_multiplier, 0.02 * delta)

	puff_scale     = lerp(puff_scale,     target_puff_scale,     shape_speed * delta)
	puff_contrast  = lerp(puff_contrast,  target_puff_contrast,  shape_speed * delta)
	gap_sharpness  = lerp(gap_sharpness,  target_gap_sharpness,  shape_speed * delta)
	clump_strength = lerp(clump_strength, target_clump_strength, shape_speed * delta)
	warp_strength  = lerp(warp_strength,  target_warp_strength,  shape_speed * delta)
	wind_dir       = wind_dir.lerp(target_wind_dir, shape_speed * delta)
	wind_speed     = lerp(wind_speed,     target_wind_speed,     shape_speed * delta)

	# Shape params change every frame during transitions — mark dirty so
	# _update_materials knows to push them
	_appearance_dirty = true
	_update_materials()

func _update_materials() -> void:
	var sun_direction = Vector3(0.0, 1.0, 0.0)
	var sun_energy    = 1.0
	if sun_node:
		sun_direction = sun_node.get_global_transform().basis.z.normalized()
		sun_energy    = sun_node.get_base_energy() if sun_node.has_method("get_base_energy") \
						else sun_node.light_energy

	var moon_direction = Vector3(0.0, -1.0, 0.0)
	if moon_node:
		moon_direction = -moon_node.get_global_transform().basis.z.normalized()

	for shell in _shells:
		# Skip invisible shells entirely
		if not shell.visible:
			continue

		var mat := shell.get_active_material(0) as ShaderMaterial
		if mat == null:
			continue

		# Dynamic uniforms — change every frame
		mat.set_shader_parameter("sun_dir",        sun_direction)
		mat.set_shader_parameter("sun_energy",     sun_energy)
		mat.set_shader_parameter("moon_dir",       moon_direction)
		mat.set_shader_parameter("cloud_coverage", _coverage)
		mat.set_shader_parameter("precipitation",  _precipitation)
		mat.set_shader_parameter("light_multiplier", _light_multiplier)
		mat.set_shader_parameter("wind_dir",       wind_dir)
		mat.set_shader_parameter("wind_speed",     wind_speed)

		# Shape uniforms — only during transitions, settled fast via shape_speed
		if _appearance_dirty:
			mat.set_shader_parameter("puff_scale",             puff_scale)
			mat.set_shader_parameter("puff_contrast",          puff_contrast)
			mat.set_shader_parameter("gap_sharpness",          gap_sharpness)
			mat.set_shader_parameter("clump_strength",         clump_strength)
			mat.set_shader_parameter("warp_strength",          warp_strength)
			mat.set_shader_parameter("min_coverage_threshold", min_coverage_threshold)
			mat.set_shader_parameter("max_coverage_threshold", max_coverage_threshold)
			mat.set_shader_parameter("coverage_smoothness",    coverage_smoothness)

	_appearance_dirty = false

func _validate_property(_property: Dictionary) -> void:
	_appearance_dirty = true

func _set_shells_visible(state: bool) -> void:
	for shell in _shells:
		shell.visible = state

func _on_weather_updated(state) -> void:
	target_coverage         = state.AltocumulusWeight
	target_precipitation    = state.Precipitation
	target_light_multiplier = state.LightMultiplier

	target_puff_contrast  = lerp(1.8, 0.8,  state.Precipitation)
	target_gap_sharpness  = lerp(0.80, 0.20, state.Precipitation)
	target_puff_scale     = lerp(0.75, 1.6,  state.Precipitation)
	target_warp_strength  = lerp(0.9,  1.5,  state.Precipitation)
	target_clump_strength = lerp(0.3,  0.8,  state.AltocumulusWeight)

	if _first_update:
		_coverage         = target_coverage
		_precipitation    = target_precipitation
		_light_multiplier = target_light_multiplier
		puff_scale        = target_puff_scale
		puff_contrast     = target_puff_contrast
		gap_sharpness     = target_gap_sharpness
		clump_strength    = target_clump_strength
		warp_strength     = target_warp_strength
		wind_dir          = target_wind_dir
		wind_speed        = target_wind_speed
		_first_update     = false
		_set_shells_visible(true)
