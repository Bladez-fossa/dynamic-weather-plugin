extends BaseCloudController

# ── Stratus Behaviour ─────────────────────────────────────────────────────────
@export_category("Stratus Behaviour")
## Speed at which cloud coverage transitions to target. Higher = faster.
@export var coverage_speed : float = 1.5
## Speed at which precipitation intensity transitions. Higher = faster.
@export var precip_speed : float = 2.0

# ── Stratus Appearance ────────────────────────────────────────────────────────
@export_category("Stratus Appearance")
## How quickly clouds appear/disappear when coverage changes. Higher = slower fade.
@export var coverage_fade_range : float = 0.7
## Sharpness of cloud edges. Higher = softer.
@export var edge_softness : float = 0.20
## How much precipitation darkens the clouds. Higher = darker storm clouds.
@export var storm_darkness : float = 0.75
## Brightness of the sun highlight on cloud tops. Higher = brighter.
@export var light_brightness : float = 0.10
## How much the cloud underside erodes (ragged edges). Higher = more erosion.
@export var bottom_erosion : float = 0.15

# ── Internal state ────────────────────────────────────────────────────────────
var _coverage : float = 0.0
var _precipitation : float = 0.0
var _light_multiplier : float = 1.0
var target_coverage : float = 0.0
var target_precipitation : float = 0.0
var target_light_multiplier : float = 1.0

var _shells : Array[MeshInstance3D] = []
var _camera : Camera3D
var _shells_are_visible: bool = false

# Dirty flag – push static appearance uniforms only when the inspector changes them
var _appearance_dirty : bool = true

# Cache sun / moon to avoid duplicate computation
var _sun_direction : Vector3 = Vector3(0.0, 1.0, 0.0)
var _sun_energy    : float   = 1.0
var _moon_direction: Vector3 = Vector3(0.0, -1.0, 0.0)

const SHELL_COUNT = 1
const PLANE_SIZE = 3000.0
const SHELL_HEIGHT = 200.0

func _ready() -> void:
	super._ready()
	_camera = get_viewport().get_camera_3d()
	_coverage = target_coverage
	_precipitation = target_precipitation
	_light_multiplier = target_light_multiplier
	_generate_shells()

	if weather_manager:
		weather_manager.connect("WeatherUpdated", _on_weather_updated)
	else:
		push_error("StratusController: WeatherManager not found. Stratus clouds won't update.")

func _generate_shells() -> void:
	for i in SHELL_COUNT:
		var plane = PlaneMesh.new()
		plane.size = Vector2(PLANE_SIZE, PLANE_SIZE)
		# Reduced subdivisions from 40 → 10 (vertex displacement is low-frequency)
		plane.subdivide_width = 10
		plane.subdivide_depth = 10

		var mesh_instance = MeshInstance3D.new()
		mesh_instance.mesh = plane
		mesh_instance.position.y = SHELL_HEIGHT + (i * 15.0)
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var mat = ShaderMaterial.new()
		mat.shader = preload("res://Dynamic Weather/Shaders/stratus_shader.gdshader")
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

	_coverage = lerp(_coverage, target_coverage, coverage_speed * delta)
	_precipitation = lerp(_precipitation, target_precipitation, precip_speed * delta)
	_light_multiplier = lerp(_light_multiplier, target_light_multiplier, 0.02 * delta)

	if _coverage > 0.02:
		_set_shells_visible(true)
	elif _coverage < 0.005:
		_set_shells_visible(false)

	# Update cached sun / moon once (they change slowly)
	if sun_node:
		_sun_direction = sun_node.get_global_transform().basis.z.normalized()
		_sun_energy = sun_node.get_base_energy() if sun_node.has_method("get_base_energy") else sun_node.light_energy
	if moon_node:
		_moon_direction = -moon_node.get_global_transform().basis.z.normalized()

	_update_materials()
	_update_visibility()

func _update_visibility() -> void:
	if not _shells_are_visible and _coverage > 0.02:
		_set_shells_visible(true)
		_shells_are_visible = true
	elif _shells_are_visible and _coverage < 0.005:
		_set_shells_visible(false)
		_shells_are_visible = false

func _update_materials() -> void:
	for shell in _shells:
		if not shell.visible:
			continue

		var mat := shell.get_active_material(0) as ShaderMaterial
		if mat == null:
			continue

		# Dynamic uniforms – always pushed (weather values change every frame)
		mat.set_shader_parameter("sun_dir",          _sun_direction)
		mat.set_shader_parameter("sun_energy",       _sun_energy)
		mat.set_shader_parameter("moon_dir",         _moon_direction)
		mat.set_shader_parameter("cloud_coverage",   _coverage)
		mat.set_shader_parameter("precipitation",    _precipitation)
		mat.set_shader_parameter("light_multiplier", _light_multiplier)

		# Appearance uniforms – only push when dirty (inspector changes)
		if _appearance_dirty:
			mat.set_shader_parameter("coverage_fade_range", coverage_fade_range)
			mat.set_shader_parameter("edge_softness",       edge_softness)
			mat.set_shader_parameter("storm_darkness",      storm_darkness)
			mat.set_shader_parameter("light_brightness",    light_brightness)
			mat.set_shader_parameter("bottom_erosion",      bottom_erosion)

	_appearance_dirty = false

func _validate_property(_property: Dictionary) -> void:
	_appearance_dirty = true

func _set_shells_visible(state: bool) -> void:
	for shell in _shells:
		shell.visible = state

func set_weather(coverage: float, precip: float) -> void:
	target_coverage = coverage
	target_precipitation = precip

func _on_weather_updated(state) -> void:
	target_coverage = state.StratusWeight
	target_precipitation = state.Precipitation
	target_light_multiplier = state.LightMultiplier
