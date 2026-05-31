
@tool
extends WorldEnvironment
@export var weather_manager : Node
@export var nimbostratus_system : Node 


func _ready() -> void:
	
	# Force initial shader state
	environment.sky.sky_material.set_shader_parameter('light_multiplier', 1.0)
	environment.sky.sky_material.set_shader_parameter('cloud_coverage', 0.0)
	if weather_manager and not Engine.is_editor_hint():
		call_deferred("_connect_weather")

func _connect_weather() -> void:
	if weather_manager.has_signal("WeatherUpdated"):
		weather_manager.connect("WeatherUpdated", _on_weather_updated)
		print("Sky controller connected to weather manager")
	else:
		print("WeatherUpdated signal not found in WeatherManager")

func _process(delta: float) -> void:

	var sun_dir = $"../Sun".get_global_transform().basis.z; # This is our forward direction pointing towards the sun
	var moon_basis = $"../moon".get_global_transform().basis;
	var moon_dir = moon_basis.z; # This is our forward direction pointing towards the moon
	var mat = environment.sky.sky_material
	mat.set_shader_parameter('sun_dir', sun_dir); # Update sky material with sun direction
	mat.set_shader_parameter('moon_dir', moon_dir); # Update sky material with moon direction
	mat.set_shader_parameter('moon_world_to_object', moon_basis.inverse()); # The world to object matrix is the inverse of the basis (which is object to world)

	
func _on_weather_updated(state) -> void:
	
	var mat = environment.sky.sky_material
	mat.set_shader_parameter('cloud_coverage', state.CloudCoverage)
	mat.set_shader_parameter("cirrus_weight", state.CirrusWeight)
	mat.set_shader_parameter('fog_density',      state.FogDensity)
	mat.set_shader_parameter('precipitation',    state.Precipitation)
	mat.set_shader_parameter('light_multiplier', state.LightMultiplier)
	mat.set_shader_parameter("nimbo_lod", get_lod_tier())
	mat.set_shader_parameter("nimbo_turbulence", state.Precipitation)
	

	# Pull sun_direction from the actual Sun node, same as _process does
	var sun_dir = $"../Sun".get_global_transform().basis.z
	#if nimbostratus_system:
		#nimbostratus_system.set_weather(state.CloudCoverage, state.Precipitation)
		#nimbostratus_system.sun_direction = sun_dir


# LOD tier function — matches your proposal's algorithm exactly
func get_lod_tier() -> int:
	var fps = Engine.get_frames_per_second()
	if RenderingServer.get_rendering_device() == null: # Compatibility mode
		return 2
	elif fps < 40:
		return 1
	else:
		return 0
		


# Lightning: call this from your storm WeatherStatex	
##func trigger_lightning():
	#var tween = create_tween()
	## spike to 2.5, hold 2 frames, fade back to state value
	#tween.tween_method(func(v): 
		#environment.sky.sky_material.set_shader_parameter("light_multiplier", v),
		#2.5, state.LightMultiplier, 0.12)
