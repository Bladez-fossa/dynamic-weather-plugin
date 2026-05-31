extends GPUParticles3D

@export var weather_manager: Node3D

@export_group("Appearance")
@export var max_opacity: float = 0.28
@export var day_color:   Color = Color(0.60, 0.63, 0.68)
@export var night_color: Color = Color(0.18, 0.20, 0.25)

@export_group("Driver")
@export var sun: DirectionalLight3D

var _fog_mat: ShaderMaterial
var _target_opacity:  float = 0.0
var _current_opacity: float = 0.0

func _ready() -> void:
	# Fixed amount — never change at runtime
	amount  = 40
	emitting = true

	# Grab shader material from draw pass
	var mesh = get_draw_pass_mesh(0)
	if mesh == null:
		push_error("LocalFog: No draw pass mesh assigned!")
		return
	_fog_mat = mesh.surface_get_material(0) as ShaderMaterial
	if _fog_mat == null:
		push_error("LocalFog: Draw pass mesh has no ShaderMaterial!")
		return

	# Start invisible
	_fog_mat.set_shader_parameter("opacity", 0.0)

	# Connect signal
	if weather_manager == null:
		push_error("LocalFog: weather_manager not assigned!")
		return
	weather_manager.connect("WeatherUpdated", _on_weather_updated)
	print("✅ LocalFog ready")

func _on_weather_updated(state: Object) -> void:
	if state == null:
		return
	var w = state.get("NimboWeight")
	var nimbo: float = float(w) if w != null else 0.0
	_target_opacity = clampf(nimbo, 0.0, 1.0) * max_opacity

func _process(delta: float) -> void:
	_current_opacity = lerpf(_current_opacity, _target_opacity, delta * 0.4)

	if _fog_mat == null:
		return

	# Day/night color blend
	var sun_up: float = 1.0
	if sun:
		sun_up = clampf(-sun.basis.z.y, 0.0, 1.0)

	var color : Color= lerp(night_color, day_color, sun_up)
	_fog_mat.set_shader_parameter("fog_color", color)
	_fog_mat.set_shader_parameter("opacity", _current_opacity)

	# Hide node entirely when fully clear — saves draw calls
	visible = _current_opacity > 0.005
