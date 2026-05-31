@tool
extends Node

@export var width: int = 512
@export var height: int = 512
@export var noise_seed: int = 42
@export var noise_period: float = 64.0
@export var noise_octaves: int = 4
@export var noise_gain: float = 0.5        # persistence → gain in FastNoiseLite

func _ready() -> void:
	generate()
	if not Engine.is_editor_hint():
		queue_free()

func generate() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 1.0 / noise_period
	noise.fractal_octaves = noise_octaves
	noise.fractal_gain = noise_gain               # correct property name

	var image := Image.create(width, height, false, Image.FORMAT_L8)
	for y in height:
		for x in width:
			var v: float = noise.get_noise_2d(x, y)   # fixed method name
			v = v * 0.5 + 0.5                         # remap -1..1 to 0..1
			image.set_pixel(x, y, Color(v, v, v))

	var path := "res://test_environment/noise_texture.png"
	var err := image.save_png(path)
	if err == OK:
		print("✅ Noise texture saved to: ", path)
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().scan()
	else:
		push_error("Failed to save noise texture: ", err)
