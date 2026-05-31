extends Node

# ── Noise settings ────────────────────────────────────────────────────────────
## Lower = slower, lazier weather changes. Higher = faster, more erratic.
@export var noise_speed: float = 0.015
## Seed — change this to get a completely different weather history
@export var noise_seed: int = 42
## How low precipitation can go (0.0 = allows full clear sky)
@export var min_precipitation: float = 0.0
## How high precipitation can go (1.0 = allows full storm)
@export var max_precipitation: float = 1.0

# ── Throttle ──────────────────────────────────────────────────────────────────
## Only push to WeatherManager when precipitation shifts by at least this much
@export var update_threshold: float = 0.02
## Minimum time (seconds) between two weather pushes – prevents rapid jitter
@export var min_push_interval: float = 0.5

# ── Internal ──────────────────────────────────────────────────────────────────
var _noise: FastNoiseLite
var _noise_time: float = 0.0
var _last_pushed: float = -1.0
var _reusable_state: WeatherState
var _weather_manager: Node         # cached reference to WeatherManager
var _time_since_push: float = 99.0  # start large so first push goes through

func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = noise_seed
	_noise.frequency = 1.0

	_reusable_state = WeatherState.new()

	# Try to find the WeatherManager – look for a sibling node with the signal
	_weather_manager = _find_weather_manager()
	if _weather_manager:
		_push_state()   # initial state push
	else:
		push_error("CloudOrchestrator: WeatherManager not found – weather will not update.")
		# fallback to old behaviour
		_push_state()
		get_parent().SetWeather(_reusable_state)

func _process(delta: float) -> void:
	_noise_time += delta * noise_speed
	_time_since_push += delta

	# Generate precipitation value from noise
	var raw: float = (_noise.get_noise_1d(_noise_time) + 1.0) * 0.5
	var biased: float = pow(raw, 1.0)
	var new_precip = lerpf(min_precipitation, max_precipitation, biased)

	# Only push if the change is big enough AND enough time has passed
	if absf(new_precip - _last_pushed) >= update_threshold and _time_since_push >= min_push_interval:
		_push_state()
		_last_pushed = new_precip
		_time_since_push = 0.0

func _push_state() -> void:
	var p := _last_pushed   # use the actual value we're pushing

	# Compute cloud weights directly from precipitation
	_reusable_state.CirrusWeight      = clampf(1.0 - p * 3.0, 0.0, 0.5)
	_reusable_state.CumulusWeight     = clampf(1.0 - absf(p - 0.3) * 3.0, 0.0, 0.7)
	_reusable_state.AltocumulusWeight = clampf(1.0 - absf(p - 0.6) * 4.0, 0.0, 0.6)
	_reusable_state.StratusWeight     = clampf(1.0 - absf(p - 0.42) * 5.5, 0.0, 0.75)
	_reusable_state.NimboWeight       = clampf((p - 0.45) * 5.0, 0.0, 0.9)

	_reusable_state.Precipitation   = p
	_reusable_state.LightMultiplier = lerpf(1.0, 0.3, p)
	_reusable_state.FogDensity      = lerpf(0.0, 0.5, p)
	_reusable_state.WindSpeed       = lerpf(1.0, 6.0, p)
	_reusable_state.Humidity        = p
	_reusable_state.CloudCoverage   = maxf(
		_reusable_state.CirrusWeight,
		maxf(_reusable_state.CumulusWeight,
		maxf(_reusable_state.AltocumulusWeight,
		maxf(_reusable_state.StratusWeight, _reusable_state.NimboWeight)))
	)

	if _weather_manager:
		_weather_manager.SetWeather(_reusable_state)
	else:
		# fallback – only if WeatherManager was not auto‑found
		get_parent().SetWeather(_reusable_state)

# ── Auto‑find WeatherManager (same method as ThunderController) ────────────────
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
