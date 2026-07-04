class_name RainController
extends GPUParticles3D

@export_category("Rain Appearance")
@export var rain_color_heavy : Color = Color(0.72, 0.82, 0.95)
@export var rain_color_light : Color = Color(0.88, 0.92, 0.98)
@export_range(0.0, 1.0) var opacity_heavy : float = 0.85
@export_range(0.0, 1.0) var opacity_light : float = 0.45

@export_category("Rain Amount")
@export_range(100, 10000) var max_amount : int = 6000
@export_range(100, 10000) var light_rain_amount : int = 800

# ── Internal state ─────────────────────────────────────────
var _current_intensity: float = 0.0
var _target_intensity:  float = 0.0
var _drizzle_blend:     float = 0.0
const FADE_SPEED := 1.2
var player: Node3D = null
var streak_material: ShaderMaterial = null

# Fix: reseed on a timer instead of every frame
const RESEED_INTERVAL := 0.15   # seconds between reseeds — fast enough to break patterns,
								 # slow enough to avoid stalling every frame
var _reseed_timer: float = 0.0

# Fix: dirty flag so shader params only push when values actually changed
var _shader_dirty: bool = false
var _last_color:   Color = Color(-1, -1, -1)   # sentinel — forces first push
var _last_opacity: float = -1.0

func _ready() -> void:
	emitting = false

	player = _find_player()
	if player:
		print("✅ Rain: player found – ", player.name)
	else:
		push_warning("Rain: player not found – rain will not follow the player.")

	var mesh = get_draw_pass_mesh(0)
	if mesh:
		var mat = mesh.surface_get_material(0)
		if mat is ShaderMaterial:
			streak_material = mat
		else:
			push_error("Rain: Draw pass material is not a ShaderMaterial!")
	else:
		push_error("Rain: No draw pass mesh assigned!")

	var proc_mat = process_material as ParticleProcessMaterial
	if proc_mat:
		proc_mat.gravity              = Vector3(0, -9.8, 0)
		proc_mat.emission_box_extents = Vector3(30, 4, 30)
		# ⚠️ Disable Local Coords manually in the Inspector!
	else:
		push_error("Rain: No ParticleProcessMaterial assigned!")

	print("✅ Rain system ready. Material: ", streak_material)

func _process(delta: float) -> void:
	_current_intensity = move_toward(_current_intensity, _target_intensity, delta * FADE_SPEED)
	if player:
		global_position = player.global_position + Vector3(0, 12, 0)
	_apply_intensity(_current_intensity, delta)

func set_precipitation(intensity: float, drizzle_blend: float = 0.0) -> void:
	_target_intensity = intensity
	_drizzle_blend    = drizzle_blend
	if streak_material == null: return

	# Fix: only recompute and push shader params when values actually changed
	var new_color:   Color = lerp(rain_color_heavy, rain_color_light, drizzle_blend)
	var new_opacity: float = lerp(opacity_heavy, opacity_light, drizzle_blend) * intensity

	if new_color != _last_color or abs(new_opacity - _last_opacity) > 0.001:
		streak_material.set_shader_parameter("rain_color",   new_color)
		streak_material.set_shader_parameter("drop_opacity", new_opacity)
		_last_color   = new_color
		_last_opacity = new_opacity

func _apply_intensity(t: float, delta: float) -> void:
	if t < 0.02:
		if emitting:
			print("🔴 Rain stopped emitting")
			emitting = false
		return

	if not emitting:
		print("🟢 Rain started emitting | intensity: %.2f | drizzle_blend: %.2f" % [t, _drizzle_blend])
		emitting = true
		# Force an immediate reseed when emitting starts
		seed = randi()
		_reseed_timer = 0.0

	# Fix: reseed on interval instead of every frame
	_reseed_timer += delta
	if _reseed_timer >= RESEED_INTERVAL:
		seed = randi()   # no randomize() needed — randi() is already pseudo-random
		_reseed_timer = 0.0

	var base_count: int = int(lerp(float(max_amount), float(light_rain_amount), _drizzle_blend))
	amount = max(int(float(base_count) * t), 100)

	lifetime = lerp(0.35, 0.2, t)

	var proc_mat = process_material as ParticleProcessMaterial
	if not proc_mat:
		push_error("Rain: No ParticleProcessMaterial assigned!")
		return

	proc_mat.lifetime_randomness  = 0.2

	var vel_min: float = lerp(20.0, 40.0, t)
	var vel_max: float = lerp(45.0, 65.0, t)
	proc_mat.initial_velocity_min = lerp(vel_min, 8.0,  _drizzle_blend)
	proc_mat.initial_velocity_max = lerp(vel_max, 18.0, _drizzle_blend)

	proc_mat.spread = lerp(3.0, 7.0, t)

# ── Auto‑find helpers ──────────────────────────────────────
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
