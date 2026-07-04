class_name MoonSystem
extends Node3D

## Speed of the moon's orbit in radians per second. Higher = faster.
@export var orbit_speed : float = 0.1

## Axis around which the moon orbits (default Y = horizontal rotation).
@export var orbit_axis : Vector3 = Vector3(0, 1, 0)

func _process(delta: float) -> void:
	rotate(orbit_axis.normalized(), orbit_speed * delta)
