class_name CumulusSystem
extends BaseCloudController

# ── Cumulus Behaviour ───────────────────────────────────────────────────────────
@export_category("Cumulus Behaviour")

## Number of cloud billboards to spawn.
@export var cloud_count : int = 20

## Radius within which clouds are randomly placed (centered around the node).
@export var spawn_radius : float = 800.0

## Base height of the cloud layer.
@export var cloud_height : float = 250.0

## Maximum random vertical offset for each cloud.
@export var height_variance : float = 40.0

## Minimum scale of a cloud billboard.
@export var min_scale : float = 80.0

## Maximum scale of a cloud billboard.
@export var max_scale : float = 200.0

## Target coverage value (0-1) that the clouds smoothly move toward.
@export var target_coverage : float = 0.0

## Speed at which the cloud coverage transitions. Higher = faster.
@export var coverage_speed : float = 0.5

# ── Wind Settings ────────────────────────────────────────────────────────────────
@export_category("Cumulus Wind")

## Base wind speed that drives cloud drift and shader animation.
@export var wind_speed : float = 0.15

## Compass direction of the wind in degrees (0 = east, 90 = north, etc.).
@export var wind_angle_degrees : float = 45.0

## Amount of turbulent internal churn in the cloud shapes.
@export var turbulence : float = 0.4

# ── Internal state ───────────────────────────────────────────────────────────────
var _clouds : Array[MeshInstance3D] = []
var _cloud_base_positions : Array[Vector3] = []
var _cloud_seeds : Array[float] = []           # store seeds to avoid shader read-back
var _camera : Camera3D
var _coverage : float = 0.0
var _sun_dir : Vector3 = Vector3(0, 1, 0)
var _sun_energy : float = 1.0
var _wind_time : float = 0.0
var _wind_dir : Vector2 = Vector2.ONE.normalized()

# Dirty trackers – only push when values change
var _last_sun_dir    : Vector3 = Vector3(0, 0, 0)
var _last_sun_energy : float   = -1.0
var _last_coverage   : float   = -1.0
var _appearance_dirty : bool = true   # for wind_speed / turbulence (inspector changes)

const CLOUD_SHADER_PATH = "res://Dynamic Weather/Shaders/cumulus_shader.gdshader"

func _ready() -> void:
	super._ready()
	_camera = get_viewport().get_camera_3d()
	_coverage = target_coverage

	_wind_dir = Vector2(cos(deg_to_rad(wind_angle_degrees)), sin(deg_to_rad(wind_angle_degrees))).normalized()
	_generate_clouds()
	_update_materials()

	if weather_manager:
		weather_manager.connect("WeatherUpdated", _on_weather_updated)
		print("✅ Cumulus: connected to WeatherManager")
	else:
		push_error("Cumulus: WeatherManager not found. Cumulus clouds won't update.")

func _generate_clouds() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 42
	for i in cloud_count:
		var angle = (float(i) / float(cloud_count)) * TAU
		angle += rng.randf_range(-0.3, 0.3) * TAU / float(cloud_count)
		var dist = rng.randf_range(spawn_radius * 0.3, spawn_radius)
		var pos = Vector3(
			cos(angle) * dist,
			cloud_height + rng.randf_range(-height_variance, height_variance),
			sin(angle) * dist
		)
		var quad = QuadMesh.new()
		var size = rng.randf_range(min_scale, max_scale)
		quad.size = Vector2(size, size * 0.6)
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.mesh = quad
		mesh_instance.position = pos
		_cloud_base_positions.append(pos)
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var seed = rng.randf_range(0.0, 100.0)
		_cloud_seeds.append(seed)

		var mat = ShaderMaterial.new()
		mat.shader = load(CLOUD_SHADER_PATH)
		mat.set_shader_parameter("cloud_seed", seed)
		mat.set_shader_parameter("cloud_scale", rng.randf_range(0.8, 1.4))
		mesh_instance.set_surface_override_material(0, mat)

		add_child(mesh_instance)
		_clouds.append(mesh_instance)

func _process(delta: float) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
		return

	var cam_pos = _camera.global_position
	global_position = Vector3(cam_pos.x, 0.0, cam_pos.z)

	_coverage = lerp(_coverage, target_coverage, coverage_speed * delta)
	var visible := _coverage > 0.02
	for cloud in _clouds:
		cloud.visible = visible

	_wind_time += delta
	_move_clouds()

	# Sun – only refresh if direction or energy changed meaningfully
	if sun_node:
		var new_dir = sun_node.get_global_transform().basis.z.normalized()
		var new_energy = sun_node.get_base_energy() if sun_node.has_method("get_base_energy") else sun_node.light_energy

		if new_dir.distance_squared_to(_last_sun_dir) > 0.0001:
			_sun_dir = new_dir
			_last_sun_dir = new_dir

		if abs(new_energy - _last_sun_energy) > 0.005:
			_sun_energy = new_energy
			_last_sun_energy = new_energy

	_update_materials()

func _update_materials() -> void:
	var coverage_changed = abs(_coverage - _last_coverage) > 0.005
	for i in _clouds.size():
		if not _clouds[i].visible: continue
		var mat := _clouds[i].get_active_material(0) as ShaderMaterial
		if mat == null: continue

		mat.set_shader_parameter("sun_dir",       _sun_dir)
		mat.set_shader_parameter("sun_energy",    _sun_energy)

		if coverage_changed:
			mat.set_shader_parameter("cloud_coverage", _coverage)

		mat.set_shader_parameter("wind_time",    _wind_time)

		if _appearance_dirty:
			mat.set_shader_parameter("wind_speed", wind_speed)
			mat.set_shader_parameter("wind_dir",   _wind_dir)
			mat.set_shader_parameter("turbulence",  turbulence)

	if coverage_changed:
		_last_coverage = _coverage
	_appearance_dirty = false

func _validate_property(_property: Dictionary) -> void:
	_appearance_dirty = true

func _on_weather_updated(state) -> void:
	target_coverage = state.CumulusWeight

func _move_clouds() -> void:
	var wind_3d = Vector3(_wind_dir.x, 0.0, _wind_dir.y)

	for i in _clouds.size():
		var cloud = _clouds[i]
		var base_pos = _cloud_base_positions[i]
		var seed_val = _cloud_seeds[i]   # no shader read-back

		var drift_speed = wind_speed * (0.8 + seed_val * 0.004) * 20.0
		var drift_offset = wind_3d * _wind_time * drift_speed
		var new_pos = base_pos + drift_offset

		var horizontal = Vector2(new_pos.x, new_pos.z)
		if horizontal.length() > spawn_radius * 1.5:
			_cloud_base_positions[i] = base_pos - wind_3d * spawn_radius * 2.0
			new_pos = _cloud_base_positions[i]

		cloud.position = new_pos
