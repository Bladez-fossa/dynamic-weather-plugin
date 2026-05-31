extends GPUParticles3D

@export_category("Snow Appearance")
@export var snow_base_color  : Color = Color(0.92, 0.96, 1.0, 1.0)
@export_range(0.0, 1.0) var flake_softness  : float = 0.45
@export_range(0.0, 1.0) var flake_arm_blend : float = 0.28

@export_category("Snow Amount")
@export_range(100, 10000) var min_amount : int = 200
@export_range(100, 10000) var max_amount : int = 2200

var player:         Node3D = null
var flake_material: ShaderMaterial = null

var _current_coverage: float = 0.0
var _target_coverage:  float = 0.0
var _wind:             float = 0.0
const FADE_SPEED := 0.8

# Fix: dirty tracking to avoid redundant shader pushes
var _last_snow_color: Color = Color(-1, -1, -1)
var _last_wind:       float = -999.0   # sentinel forces first push

func _ready() -> void:
	emitting = false

	player = _find_player()
	if player:
		print("✅ Snow: player found – ", player.name)
	else:
		push_warning("Snow: no player node found. Snow will not follow the player.")

	if flake_material == null:
		var mesh := get_draw_pass_mesh(0)
		if mesh == null:
			push_error("SnowSystem: No draw pass mesh on GPUParticles3D!")
			return
		var mat := mesh.surface_get_material(0)
		if mat is ShaderMaterial:
			flake_material = mat as ShaderMaterial
		else:
			push_error("SnowSystem: Surface 0 material is not a ShaderMaterial.")
			return

	_update_static_shader_params()
	print("✅ SnowSystem ready. ShaderMaterial: ", flake_material)

func _update_static_shader_params() -> void:
	if not flake_material:
		return
	flake_material.set_shader_parameter("softness",  flake_softness)
	flake_material.set_shader_parameter("arm_blend", flake_arm_blend)

# Called from inspector edits — Godot fires this automatically for @export changes
func _validate_property(_property: Dictionary) -> void:
	_update_static_shader_params()

func _process(delta: float) -> void:
	_current_coverage = move_toward(_current_coverage, _target_coverage, delta * FADE_SPEED)

	if player:
		global_position = player.global_position + Vector3(0, 18, 0)

	# Fix: only update wind direction when wind value actually changed
	if absf(_wind - _last_wind) > 0.01:
		var proc_mat := process_material as ParticleProcessMaterial
		if proc_mat:
			proc_mat.direction = Vector3(_wind * 0.35, -1.0, 0.0).normalized()
		_last_wind = _wind

	_apply_coverage(_current_coverage)

func set_snow(coverage: float, wind_strength: float = 0.0) -> void:
	_target_coverage = clampf(coverage, 0.0, 1.0)
	_wind            = clampf(wind_strength, -1.0, 1.0)

func _apply_coverage(t: float) -> void:
	if t < 0.02:
		if emitting:
			print("❄️ Snow stopped emitting")
			emitting = false
		return

	if not emitting:
		print("❄️ Snow started emitting | coverage: ", t)
		emitting = true

	amount = int(lerp(float(min_amount), float(max_amount), t))

	# Fix: only push snow_color when alpha changes meaningfully —
	# coverage lerps slowly so most frames the color is identical
	if flake_material:
		var new_alpha = lerp(0.6, 1.0, t)
		var new_color := Color(snow_base_color.r, snow_base_color.g,
							   snow_base_color.b, new_alpha)
		if new_color.a - _last_snow_color.a > 0.005 \
		or new_color.r != _last_snow_color.r:   # catches inspector color change
			flake_material.set_shader_parameter("snow_color", new_color)
			_last_snow_color = new_color

# ── Auto‑find helpers ─────────────────────────────────────────
func _find_player() -> Node3D:
	var found = _find_node_by_name(get_tree().root, "player")
	if found and found is Node3D:
		return found as Node3D
	var cam = get_viewport().get_camera_3d()
	if cam and cam.get_parent() is Node3D:
		return cam.get_parent() as Node3D
	return null

func _find_node_by_name(parent: Node, target: String) -> Node:
	for child in parent.get_children():
		if child.name.to_lower() == target.to_lower():
			return child
		var deeper = _find_node_by_name(child, target)
		if deeper:
			return deeper
	return null
