class_name Sunsystem
extends DirectionalLight3D

@export_range(0.0, 1.0) var time_of_day: float = 0.5   # start at noon (0.5)
@export var day_length: float = 120.0
@onready var time_label: Label = $"../CanvasLayer/TimeLabel"

# ── Weather integration ──────────────────────────────────────
var _cloud_dim_t : float = 0.0
var _cloud_mult  : float = 1.0

# NEW: stores the pure sun brightness (before cloud dimming)
var _base_energy: float = 1.0

func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta / day_length, 1.0)

	var angle = time_of_day * TAU
	rotation_degrees.x = rad_to_deg(angle) + 90.0

	# sun_dir is the light's FORWARD vector (direction it shines)
	var sun_dir = global_transform.basis.z
	# sun_height = altitude of the sun: +1 at noon, -1 at midnight
	var sun_height = sun_dir.y
	_base_energy = smoothstep(-0.1, 0.15, sun_height)   # 1.0 during day, 0.0 at night

	# Dim the actual light energy with clouds (keep the base energy separate)
	var nimbo_factor = lerp(1.0, 0.0, _cloud_dim_t)
	light_energy = _base_energy * nimbo_factor * _cloud_mult
	shadow_opacity = smoothstep(0.0, 0.2, sun_height)
	visible = true

## Returns the undimmed sun energy (for cloud shaders to use directly)
func get_base_energy() -> float:
	return _base_energy

func apply_cloud_dimming(dim_t: float, light_mult: float) -> void:
	_cloud_dim_t = dim_t
	_cloud_mult  = light_mult
