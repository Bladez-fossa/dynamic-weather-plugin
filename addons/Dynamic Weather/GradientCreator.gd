extends Node

func _ready():
	var gradient = Gradient.new()
	gradient.colors = PackedColorArray([])

	gradient.add_point(0.0,  Color(0.005, 0.005, 0.012)) # midnight - almost black but not quite
	gradient.add_point(0.2,  Color(0.008, 0.008, 0.018)) # deep night
	gradient.add_point(0.4,  Color(0.02,  0.015, 0.035)) # pre-dawn
	gradient.add_point(0.5,  Color(0.6,  0.3,  0.15))
	gradient.add_point(0.6,  Color(0.4,  0.55, 0.8))
	gradient.add_point(0.8,  Color(0.15, 0.4,  0.8))
	gradient.add_point(1.0,  Color(0.05, 0.2,  0.6))

	var width = 256
	var height = 4

	# Create image manually
	var image = Image.create(width, height, false, Image.FORMAT_RGBA8)

	for x in range(width):
		var t = float(x) / (width - 1)
		var color = gradient.sample(t)

		for y in range(height):
			image.set_pixel(x, y, color)

	# Save as PNG
	var err = image.save_png("res://test_environment/sky_color_files/sun_zenith_gradient2.png")

	if err == OK:
		print("✅ PNG saved")
	else:
		print("❌ Save failed:", err)
