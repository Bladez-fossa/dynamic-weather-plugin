class_name RainAudioController
extends Node

# ── Audio resources ──────────────────────────────────────────
@export var light_rain_sound: AudioStream   # gentle rain
@export var heavy_rain_sound: AudioStream   # storm rain
@export var crossfade_speed: float = 2.0    # how fast to blend between light/heavy

# ── Internals ────────────────────────────────────────────────
var _player_light: AudioStreamPlayer
var _player_heavy: AudioStreamPlayer
var _rain_intensity: float = 0.0
var _drizzle_blend: float = 0.0

func _ready() -> void:
	# Two players for seamless cross‑fading
	_player_light = AudioStreamPlayer.new()
	_player_light.bus = "MASTER"
	_player_light.stream = light_rain_sound
	_player_light.volume_db = -80.0   # silent
	add_child(_player_light)

	_player_heavy = AudioStreamPlayer.new()
	_player_heavy.bus = "MASTER"
	_player_heavy.stream = heavy_rain_sound
	_player_heavy.volume_db = -80.0
	add_child(_player_heavy)

	# Start both players looping (inaudible at first)
	if light_rain_sound:
		_player_light.play()
	if heavy_rain_sound:
		_player_heavy.play()

	# Automatically find WeatherManager and connect to its WeatherUpdated signal
	var weather = _find_weather_manager()
	if weather and weather.has_signal("WeatherUpdated"):
		weather.WeatherUpdated.connect(_on_weather_updated)
		print("✅ RainAudioController auto‑connected to WeatherManager")
	else:
		push_warning("RainAudioController: WeatherUpdated signal not found. Rain sounds won't update.")

# ── Recursive search (same as ThunderController) ──────────────
func _find_weather_manager() -> Node:
	for child in get_tree().root.get_children():
		var found = _search_node(child)
		if found:
			return found
	return null

func _search_node(node: Node) -> Node:
	if node.has_signal("WeatherUpdated"):
		return node
	for child in node.get_children():
		var found = _search_node(child)
		if found:
			return found
	return null

# ── Weather callback ─────────────────────────────────────────
func _on_weather_updated(state) -> void:
	_rain_intensity = state.RainIntensity
	_drizzle_blend = state.DrizzleBlend

func _process(_delta: float) -> void:
	# Calculate linear amplitudes (0..1)
	var light_amp = lerp(0.0, 1.0, 1.0 - _drizzle_blend) * _rain_intensity
	var heavy_amp = lerp(0.0, 1.0, _drizzle_blend) * _rain_intensity

	# Convert to dB safely – no zero → no -inf → no NaN
	var light_target = linear_to_db(max(light_amp, 0.001))
	var heavy_target = linear_to_db(max(heavy_amp, 0.001))

	# Smooth volume adjustment
	_player_light.volume_db = lerp(_player_light.volume_db, light_target, crossfade_speed * _delta)
	_player_heavy.volume_db = lerp(_player_heavy.volume_db, heavy_target, crossfade_speed * _delta)
