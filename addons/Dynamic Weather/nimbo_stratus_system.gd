class_name NimboStratus
extends BaseCloudController

# ── Nimbostratus Behaviour ──────────────────────────────────────────────────────
@export_category("Nimbostratus Behaviour")
@export var coverage_speed : float = 1.4
@export var precip_speed : float = 0.015
@export var light_speed : float = 0.08
@export var ambient_base_energy : float = 0.3
@export var ambient_dim_min : float = 0.05
@export var sun_dim_min : float = 0.0
@export var coverage_dim_threshold : float = 0.3

# ── Nimbostratus Appearance ────────────────────────────────────────────────────
@export_category("Nimbostratus Appearance")
@export var storm_darkness : float = 0.65
@export var bottom_erosion : float = 0.22
@export var edge_softness  : float = 0.30
@export var coverage_fade_range : float = 0.65
@export var light_brightness : float = 0.10

# ── Internal state ────────────────────────────────────────────────────────────
var _coverage : float = 0.0
var _precipitation : float = 0.0
var _light_multiplier : float = 1.0

var target_coverage : float = 0.0
var target_precipitation : float = 0.0
var target_light_multiplier : float = 1.0

var _shells : Array[MeshInstance3D] = []
var _camera : Camera3D
var _appearance_dirty : bool = true  # push appearance uniforms once then only on change

const SHELL_COUNT   = 4
const PLANE_SIZE    = 3000.0
const SHELL_HEIGHTS = [80.0, 90.0, 103.0, 120.0]

# ──────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	super._ready()

	_camera = get_viewport().get_camera_3d()

	if weather_manager:
		weather_manager.connect("WeatherUpdated", _on_weather_updated)
		print("✅ Nimbostratus: connected to WeatherManager")
	else:
		push_error("Nimbostratus: WeatherManager not found.")

	if sun_node and sun_node.has_method("apply_cloud_dimming"):
		print("✅ Nimbostratus: sun node found and ready for dimming.")
	else:
		push_warning("Nimbostratus: sun node missing or lacks apply_cloud_dimming.")

	_generate_shells()
	_update_shell_materials(Vector3(0.0, 1.0, 0.0))

# ── Shell generation ──────────────────────────────────────────────────────────
func _generate_shells() -> void:
	for i in SHELL_COUNT:
		var plane = PlaneMesh.new()
		plane.size = Vector2(PLANE_SIZE, PLANE_SIZE)

		# Fix 3: reduced subdivisions — displacement is low-frequency,
		# high subdivs were wasted vertex budget on Vega 8
		var subdivs = [8, 10, 12, 16][i]
		plane.subdivide_width  = subdivs
		plane.subdivide_depth  = subdivs

		var mesh_instance = MeshInstance3D.new()
		mesh_instance.mesh = plane
		mesh_instance.position.y = SHELL_HEIGHTS[i]
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.name = "NimboShell_%d" % i

		var mat = ShaderMaterial.new()
		mat.shader = preload("res://Dynamic Weather/Shaders/nimboStratus_shell.gdshader")
		mat.set_shader_parameter("layer_index", float(i))
		mesh_instance.set_surface_override_material(0, mat)

		add_child(mesh_instance)
		_shells.append(mesh_instance)

# ── Per‑frame update ──────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
		return

	var cam_pos = _camera.global_position
	global_position = Vector3(cam_pos.x, global_position.y, cam_pos.z)

	var sun_direction = Vector3(0.0, 1.0, 0.0)
	if sun_node:
		sun_direction = -sun_node.get_global_transform().basis.z.normalized()

	_coverage         = lerp(_coverage,          target_coverage,          coverage_speed * delta)
	_precipitation    = lerp(_precipitation,      target_precipitation,     precip_speed   * delta)
	_light_multiplier = lerp(_light_multiplier,   target_light_multiplier,  light_speed    * delta)

	# ── Coverage‑driven dimming ──────────────────────────────────────────────
	var dim_t := clampf(
		(_coverage - coverage_dim_threshold) / (1.0 - coverage_dim_threshold),
		0.0, 1.0
	)

	if world_env and world_env.environment:
		var target_ambient = lerp(ambient_base_energy, ambient_dim_min, dim_t)
		world_env.environment.ambient_light_energy = target_ambient * _light_multiplier

	if sun_node and sun_node.has_method("apply_cloud_dimming"):
		sun_node.apply_cloud_dimming(dim_t, _light_multiplier)

	# Fix 4: only activate as many shells as coverage needs
	var active_shells : int
	if _coverage < 0.3:
		active_shells = 1
	elif _coverage < 0.6:
		active_shells = 2
	elif _coverage < 0.85:
		active_shells = 3
	else:
		active_shells = SHELL_COUNT

	for i in _shells.size():
		_shells[i].visible = (i < active_shells) and (_coverage > 0.02)

	_update_shell_materials(sun_direction)

func _update_shell_materials(sun_dir: Vector3) -> void:
	for shell in _shells:
		if not shell.visible:
			continue   # skip invisible shells entirely — no point pushing uniforms

		var mat := shell.get_active_material(0) as ShaderMaterial
		if mat == null:
			continue

		# Fix 1: dynamic uniforms pushed every frame
		mat.set_shader_parameter("sun_dir",          sun_dir.normalized())
		mat.set_shader_parameter("cloud_coverage",   _coverage)
		mat.set_shader_parameter("precipitation",    _precipitation)
		mat.set_shader_parameter("light_multiplier", _light_multiplier)

		# Fix 1: appearance uniforms only pushed when something changed
		if _appearance_dirty:
			mat.set_shader_parameter("storm_darkness",      storm_darkness)
			mat.set_shader_parameter("bottom_erosion",      bottom_erosion)
			mat.set_shader_parameter("edge_softness",       edge_softness)
			mat.set_shader_parameter("coverage_fade_range", coverage_fade_range)
			mat.set_shader_parameter("light_brightness",    light_brightness)

	_appearance_dirty = false

func _set_shells_visible(state: bool) -> void:
	for shell in _shells:
		shell.visible = state

# ── Godot calls this when any @export value changes in the Inspector ──────────
func _validate_property(_property: Dictionary) -> void:
	_appearance_dirty = true

# ── Public API ────────────────────────────────────────────────────────────────
func set_weather(coverage: float, precip: float) -> void:
	target_coverage      = coverage
	target_precipitation = precip

func trigger_lightning() -> void:
	target_light_multiplier = 2.5
	await get_tree().process_frame
	await get_tree().process_frame
	target_light_multiplier = 1.0

func _on_weather_updated(state) -> void:
	target_coverage          = state.NimboWeight
	target_precipitation     = state.Precipitation
	target_light_multiplier  = state.LightMultiplier

func get_weather_light_multiplier() -> float:
	return _light_multiplier
