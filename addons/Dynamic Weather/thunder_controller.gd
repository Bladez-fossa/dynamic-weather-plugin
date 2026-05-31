class_name ThunderController
extends Node

# ── Audio resources ──────────────────────────────────────────
@export var thunder_sounds: Array[AudioStream] = []

# ── Timing & randomness ──────────────────────────────────────
@export var min_delay: float = 5.0
@export var max_delay: float = 20.0
@export var volume_min_db: float = -10.0
@export var volume_max_db: float = 0.0
@export var pitch_min: float = 0.9
@export var pitch_max: float = 1.1
@export_category("LIGHNING")

# ── Lightning flash ──────────────────────────────────────────
@export var lightning_light: Light3D                # drag the DirectionalLight3D here
@export var flash_duration: float = 0.15            # seconds the flash lasts

# ── Internals ────────────────────────────────────────────────
var _timer: Timer
var _player: AudioStreamPlayer
var _storm_active: bool = false

func _ready() -> void:
	# Audio setup
	_player = AudioStreamPlayer.new()
	_player.bus = "MASTER"
	add_child(_player)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_thunder_timeout)
	add_child(_timer)

	# Automatically find the WeatherManager anywhere in the scene
	var weather = _find_weather_manager()
	if weather:
		weather.StormStateChanged.connect(_on_storm_state_changed)
		print("✅ ThunderController auto‑connected to WeatherManager")
	else:
		push_warning("ThunderController: No node with 'StormStateChanged' signal found. " +
					 "Make sure a WeatherManager is present in the scene.")
	


# ── Recursive search for the storm signal ────────────────────
func _find_weather_manager() -> Node:
	for child in get_tree().root.get_children():
		var found = _search_node(child)
		if found:
			return found
			
	return null

func _search_node(node: Node) -> Node:
	if node.has_signal("StormStateChanged"):
		return node
	for child in node.get_children():
		var found = _search_node(child)
		if found:
			return found
	return null

# ── Signal from WeatherManager ───────────────────────────────
func _on_storm_state_changed(active: bool) -> void:
	_storm_active = active
	if active:
		_schedule_next_thunder()
	else:
		_timer.stop()
		if _player.playing:
			_player.stop()

# ── Thunder loop ─────────────────────────────────────────────
func _schedule_next_thunder() -> void:
	if not _storm_active:
		return
	var delay = randf_range(min_delay, max_delay)
	_timer.start(delay)

func _on_thunder_timeout() -> void:
	if not _storm_active or thunder_sounds.is_empty():
		return

	if lightning_light:
		print("LIGHNTING AWAY.........")
		_flash_lightning()
		
	var sound = thunder_sounds[randi() % thunder_sounds.size()]
	_player.stream = sound
	_player.volume_db = randf_range(volume_min_db, volume_max_db)
	_player.pitch_scale = randf_range(pitch_min, pitch_max)
	_player.play()
	_schedule_next_thunder()
	

func _flash_lightning() -> void:
	if not lightning_light:
		return
	print("⚡ base_energy at flash time: ", lightning_light.light_energy)
	# Randomise the intensity slightly so not every flash looks identical
	var base_energy := lightning_light.light_energy
	var flash_energy := base_energy * randf_range(0.8, 1.2)

	lightning_light.light_energy = 16.0
	lightning_light.visible = true
	print("⚡ Flash ON — visible: ", lightning_light.visible)
	await get_tree().create_timer(flash_duration).timeout
	print("⚡ Flash OFF — visible after await: ", lightning_light.visible)
	lightning_light.light_energy = flash_energy
	lightning_light.visible = true

	# After a short delay, turn it off
	await get_tree().create_timer(flash_duration).timeout
	lightning_light.visible = false
	lightning_light.light_energy = base_energy   # restore original energy
