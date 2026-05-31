@tool
extends EditorPlugin

func _enter_tree():
	add_tool_menu_item("Add Weather System", _add_weather_system)

func _exit_tree():
	remove_tool_menu_item("Add Weather System")

func _add_weather_system():
	var scene = load("res://Scenes/weather_system.tscn")
	var instance = scene.instantiate()
	var selected = EditorInterface.get_selection().get_selected_nodes()
	if selected.size() > 0:
		selected[0].add_child(instance)
	else:
		# If nothing selected, add to the scene root as a fallback
		get_tree().get_edited_scene_root().add_child(instance)
