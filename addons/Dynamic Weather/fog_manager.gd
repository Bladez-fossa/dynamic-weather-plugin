# FogManager.gd
extends Node

@export var world_env: WorldEnvironment
@export var sun: DirectionalLight3D

# ── Shared fog colours ─────────────────────────────────────────────
@export_group("Shared")
@export var day_fog_color:   Color = Color(0.80, 0.82, 0.85)   # slightly brighter white-grey
@export var night_fog_color: Color = Color(0.25, 0.28, 0.35)  # dark bluish grey

# ── Exponential Fog – storm override ──────────────────────────────
@export_group("Exponential Fog — Storm Override")
@export var storm_density_max:  float = 2.0    # very high to hide horizon at full storm
@export var storm_sky_affect:   float = 0.9    # blends sky into fog colour
@export var storm_sun_multiplier: float = 0.2  # dim the sun to 20% at full storm

# ── Exponential Fog – original (fallback / mild weather) ──────────
@export_group("Exponential Fog — Legacy")
@export var density_max:    float = 0.2
@export var sky_affect_max: float = 0.15
@export var sun_scatter_max: float = 0.8

# ── Volumetric Fog ─────────────────────────────────────────────────
@export_group("Volumetric Fog")
@export var vol_density_max:   float = 0.5
@export var vol_emission_mult: float = 0.5
@export var vol_anisotropy:    float = 0.6
@export var vol_length:        float = 256.0

# ── Debug / override ───────────────────────────────────────────────
@export_group("Debug")
@export var _force_volumetric: bool = false   # force volumetric even on integrated GPU

# ── Internal state ─────────────────────────────────────────────────
var _is_forward_plus: bool = false
var _use_volumetric:  bool = false
var _fog_t:           float = 0.0

# ── Ready ──────────────────────────────────────────────────────────
func _ready() -> void:
	var renderer: String = ProjectSettings.get_setting("rendering/renderer/rendering_method")
	_is_forward_plus = renderer != "gl_compatibility"

	# Decide whether to use volumetric based on GPU type (volumetric is heavy)
	if _is_forward_plus and not _force_volumetric:
		var device_name: String = RenderingServer.get_video_adapter_name().to_lower()
		var is_integrated = device_name.contains("intel") or device_name.contains("vega") \
						 or device_name.contains("radeon rx vega") or device_name.contains("uhd")
		_use_volumetric = not is_integrated
	else:
		_use_volumetric = _force_volumetric

	# Connect to the weather orchestrator
	var orchestrator = get_node_or_null("../CloudOrchestrator")
	if orchestrator and orchestrator.has_signal("WeatherUpdated"):
		orchestrator.connect("WeatherUpdated", _on_weather_updated)
	else:
		push_warning("FogManager: could not find CloudOrchestrator with WeatherUpdated signal!")

	print("✅ FogManager ready | Forward+: ", _is_forward_plus, " | Volumetric: ", _use_volumetric)

# ── Weather signal handler ─────────────────────────────────────────
func _on_weather_updated(state: Object) -> void:
	if state == null: return
	var nimbo: float = state.get("NimboWeight") if state.get("NimboWeight") != null else 0.0
	var t: float = state.get("StormWeight") if state.get("StormWeight") != null else 0.0

	# Smooth transition
	_fog_t = move_toward(_fog_t, t, 0.02) if t > _fog_t else move_toward(_fog_t, t, 0.01)

	_apply(_fog_t, nimbo)

# ── Main apply ─────────────────────────────────────────────────────
func _apply(t: float, nimbo: float) -> void:
	var env := world_env.environment
	if env == null: return

	# 1. Dim ambient and sun light to darken the scene
	env.ambient_light_energy = lerpf(1.0, 0.15, t)

	if sun:
		sun.light_energy = lerpf(1.0, storm_sun_multiplier, t)

	var sun_up   := clampf(-sun.basis.z.y, 0.0, 1.0) if sun else 1.0
	var fog_color: Color = lerp(night_fog_color, day_fog_color, sun_up)

	# 2. Branch between volumetric and exponential
	if _use_volumetric:
		_apply_volumetric(env, t, nimbo, sun_up, fog_color)
	else:
		_apply_exponential(env, t, nimbo, sun_up, fog_color)

	# 3. Push fog density into the sky shader's built‑in horizon fog
	var sky := env.sky
	if sky and sky.sky_material is ShaderMaterial:
		var mat := sky.sky_material as ShaderMaterial
		mat.set_shader_parameter("fog_density", t * 0.8)

# ── Exponential fog implementation ─────────────────────────────────
func _apply_exponential(env: Environment, t: float, _nimbo: float, sun_up: float, fog_color: Color) -> void:
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL

	# Use the new storm density for massive horizon blindness
	env.fog_density       = t * storm_density_max
	env.fog_light_color   = fog_color
	env.fog_sun_scatter   = t * sun_scatter_max * sun_up
	env.fog_sky_affect    = t * storm_sky_affect * sun_up

	# Optional: also set the legacy density parameter if you want to keep it for non‑storm use
	# env.fog_density       = t * density_max   # old behaviour

# ── Volumetric fog implementation (Forward+ only) ──────────────────
func _apply_volumetric(env: Environment, t: float, nimbo: float, sun_up: float, fog_color: Color) -> void:
	env.volumetric_fog_enabled       = true
	env.volumetric_fog_density       = t * vol_density_max
	env.volumetric_fog_albedo        = fog_color
	env.volumetric_fog_emission      = fog_color * vol_emission_mult
	env.volumetric_fog_emission_energy = lerpf(0.3, 0.8, sun_up)
	env.volumetric_fog_anisotropy    = lerp(vol_anisotropy, 0.0, nimbo)
	env.volumetric_fog_length        = vol_length

	# Volumetric fog sky affect – makes it visible against the sky
	env.volumetric_fog_sky_affect    = t * 0.4
