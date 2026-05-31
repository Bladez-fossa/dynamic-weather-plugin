class_name BaseCloudController
extends Node3D

# These will be automatically populated – derived classes can use them directly.
var weather_manager : Node = null
var sun_node : DirectionalLight3D = null
var moon_node : Node3D = null
var world_env : WorldEnvironment = null

func _ready() -> void:
	# 1. WeatherManager – find node with "WeatherUpdated" signal
	weather_manager = _find_node_with_signal("WeatherUpdated")
	if weather_manager:
		print("✅ BaseCloudController: connected to WeatherManager")
	else:
		push_warning("BaseCloudController: no node with 'WeatherUpdated' found.")

	# 2. Sun – DirectionalLight3D that has get_base_energy()
	sun_node = _find_sun()
	if sun_node:
		print("✅ BaseCloudController: sun node found.")
	else:
		push_warning("BaseCloudController: sun node not found.")

	# 3. Moon – try to find a node named "moon" (case-insensitive)
	moon_node = _find_moon()
	if moon_node:
		print("✅ BaseCloudController: moon node found.")
	else:
		# Not a warning – moon is optional for many clouds
		pass

	# 4. WorldEnvironment – try to find existing, or create one
	world_env = _find_world_environment()
	if not world_env:
		world_env = WorldEnvironment.new()
		world_env.name = "WorldEnvironment"
		add_child(world_env)
		print("✅ BaseCloudController: created a WorldEnvironment node.")

# ── Auto‑find helpers ─────────────────────────────────────────────────────────
func _find_node_with_signal(signal_name: String) -> Node:
	for child in get_tree().root.get_children():
		var found = _search_node(child, signal_name)
		if found:
			return found
	return null

func _search_node(node: Node, signal_name: String) -> Node:
	if node.has_signal(signal_name):
		return node
	for child in node.get_children():
		var found = _search_node(child, signal_name)
		if found:
			return found
	return null

func _find_sun() -> DirectionalLight3D:
	# Look for a DirectionalLight3D that has the get_base_energy method
	for child in get_tree().root.get_children():
		var found = _search_node_with_method(child, "get_base_energy")
		if found and found is DirectionalLight3D:
			return found as DirectionalLight3D
	# Fallback: try the common path "../Sun"
	var fallback = get_node_or_null("../Sun")
	if fallback and fallback is DirectionalLight3D:
		return fallback as DirectionalLight3D
	return null

func _search_node_with_method(node: Node, method: String) -> Node:
	if node.has_method(method):
		return node
	for child in node.get_children():
		var found = _search_node_with_method(child, method)
		if found:
			return found
	return null

func _find_moon() -> Node3D:
	# Look for a node named "moon" (common naming)
	var moon = get_node_or_null("../moon")
	if moon and moon is Node3D:
		return moon as Node3D
	# Otherwise, search the whole tree for a node named "moon" (case-insensitive)
	return _find_node_by_name(get_tree().root, "moon")

func _find_node_by_name(parent: Node, target_name: String) -> Node:
	for child in parent.get_children():
		if child.name.to_lower() == target_name.to_lower():
			return child
		var deeper = _find_node_by_name(child, target_name)
		if deeper:
			return deeper
	return null

func _find_world_environment() -> WorldEnvironment:
	for child in get_tree().root.get_children():
		var found = _search_node_of_type(child, WorldEnvironment)
		if found:
			return found as WorldEnvironment
	return null

func _search_node_of_type(node: Node, type: Variant) -> Node:
	if node is WorldEnvironment:
		return node
	for child in node.get_children():
		var found = _search_node_of_type(child, type)
		if found:
			return found
	return null
