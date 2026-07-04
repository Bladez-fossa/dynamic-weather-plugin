class_name StormFog
extends BaseCloudController

@export var day_fog_color: Color = Color(0.78, 0.80, 0.84, 1.0)
@export var night_fog_color: Color = Color(0.10, 0.12, 0.18, 1.0)  # dark blue-grey

var _mesh_instance: MeshInstance3D = null
var _current_alpha: float = 0.0
var _target_alpha: float  = 0.0
var _camera: Camera3D = null

func _ready() -> void:
	super._ready()   # finds sun_node and weather_manager automatically

	_camera = get_viewport().get_camera_3d()
	if not _camera:
		push_error("FogVolume: No active camera found!")
		return

	# Reparent to camera (deferred to avoid tree modification in _ready)
	call_deferred("_reparent_to_camera")

	# Connect to WeatherManager using inherited weather_manager
	if weather_manager and weather_manager.has_signal("WeatherUpdated"):
		weather_manager.connect("WeatherUpdated", _on_weather_updated)
		print("✅ FogVolume: connected to WeatherManager")
	else:
		push_warning("FogVolume: WeatherManager not found – fog won't react to weather.")

func _reparent_to_camera() -> void:
	var parent = get_parent()
	if parent:
		parent.remove_child(self)
	if _camera:
		_camera.add_child(self)
		transform = Transform3D.IDENTITY
		_mesh_instance = _find_mesh_instance()
	if _mesh_instance:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://Dynamic Weather/Shaders/fog_volumee.gdshader")
		_mesh_instance.material_override = mat
		print("✅ Shader material assigned")
	else:
		push_error("FogVolume: No MeshInstance3D child found!")

func _find_mesh_instance() -> MeshInstance3D:
	for child in get_children():
		if child is MeshInstance3D:
			return child
	return null

func _on_weather_updated(state: Object) -> void:
	if state == null: return
	var nimbo: float = state.get("NimboWeight") if state.get("NimboWeight") != null else 0.0
	_target_alpha = clampf(nimbo * 0.5, 0.0, 0.5)

func _process(delta: float) -> void:
	if not _mesh_instance:
		return

	_current_alpha = lerpf(_current_alpha, _target_alpha, delta * 0.8)

	# Use inherited sun_node instead of the old 'sun' export
	var sun_up := clampf(-sun_node.basis.z.y, 0.0, 1.0) if sun_node else 1.0
	if Engine.get_process_frames() % 120 == 0:
		print("sun_up: ", sun_up, " | _current_alpha: ", _current_alpha)

	var fog_colour = lerp(night_fog_color, day_fog_color, sun_up)

	var mat := _mesh_instance.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("storm_weight", _current_alpha)
		mat.set_shader_parameter("fog_color", fog_colour)
