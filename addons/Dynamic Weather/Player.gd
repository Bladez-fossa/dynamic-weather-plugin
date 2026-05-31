extends CharacterBody3D

@export var MOVE_SPEED: float = 50.0
@export var JUMP_SPEED: float = 2.0
@export var ACCELERATION: float = 10.0  # Add smooth acceleration
@export var AIR_CONTROL: float = 0.3    # Add air control

@export var first_person: bool = false : 
	set(p_value):
		first_person = p_value
		if first_person:
			var tween: Tween = create_tween()
			tween.tween_property($CameraManager/Arm, "spring_length", 0.0, .33)
			tween.tween_callback($Body.set_visible.bind(false))
		else:
			$Body.visible = true
			create_tween().tween_property($CameraManager/Arm, "spring_length", 6.0, .33)

@export var gravity_enabled: bool = true :
	set(p_value):
		gravity_enabled = p_value
		if not gravity_enabled:
			velocity.y = 0
			
@export var collision_enabled: bool = true :
	set(p_value):
		collision_enabled = p_value
		$CollisionShapeBody.disabled = ! collision_enabled
		$CollisionShapeRay.disabled = ! collision_enabled

var mouse_captured: bool = true
var target_velocity: Vector3 = Vector3.ZERO


func _physics_process(p_delta) -> void:
	var direction: Vector3 = get_camera_relative_input()
	var target_h_veloc: Vector2 = Vector2(direction.x, direction.z) * MOVE_SPEED
	
	if Input.is_key_pressed(KEY_SHIFT):
		target_h_veloc *= 2
	
	# Apply acceleration for smoother movement
	var target_vel = Vector3(target_h_veloc.x, velocity.y, target_h_veloc.y)
	
	if is_on_floor():
		# Ground movement
		velocity = velocity.lerp(target_vel, ACCELERATION * p_delta)
	else:
		# Air movement (reduced control)
		var air_target = Vector3(target_h_veloc.x, velocity.y, target_h_veloc.y)
		velocity = velocity.lerp(air_target, ACCELERATION * AIR_CONTROL * p_delta)
	
	if gravity_enabled:
		velocity.y -= 40 * p_delta
	
	move_and_slide()


# Returns the input vector relative to the camera. Forward is always the direction the camera is facing
func get_camera_relative_input() -> Vector3:
	var input_dir: Vector3 = Vector3.ZERO
	
	# WASD movement
	if Input.is_key_pressed(KEY_A): # Left
		input_dir -= %Camera3D.global_transform.basis.x
	if Input.is_key_pressed(KEY_D): # Right
		input_dir += %Camera3D.global_transform.basis.x
	if Input.is_key_pressed(KEY_W): # Forward
		input_dir -= %Camera3D.global_transform.basis.z
	if Input.is_key_pressed(KEY_S): # Backward
		input_dir += %Camera3D.global_transform.basis.z
	
	# Vertical movement (useful when gravity is disabled)
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE): # Up
		velocity.y += JUMP_SPEED + MOVE_SPEED * 0.016
	if Input.is_key_pressed(KEY_Q): # Down
		velocity.y -= JUMP_SPEED + MOVE_SPEED * 0.016
	
	# Speed adjustment
	if Input.is_key_pressed(KEY_KP_ADD) or Input.is_key_pressed(KEY_EQUAL):
		MOVE_SPEED = clamp(MOVE_SPEED + 0.5, 5, 9999)
	if Input.is_key_pressed(KEY_KP_SUBTRACT) or Input.is_key_pressed(KEY_MINUS):
		MOVE_SPEED = clamp(MOVE_SPEED - 0.5, 5, 9999)
	
	return input_dir.normalized() if input_dir.length() > 0 else input_dir


func _input(p_event: InputEvent) -> void:
	if p_event is InputEventMouseButton and p_event.pressed:
		if p_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			MOVE_SPEED = clamp(MOVE_SPEED + 5, 5, 9999)
		elif p_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			MOVE_SPEED = clamp(MOVE_SPEED - 5, 5, 9999)
	
	elif p_event is InputEventKey:
		if p_event.pressed:
			if p_event.keycode == KEY_V:
				first_person = ! first_person
			elif p_event.keycode == KEY_G:
				gravity_enabled = ! gravity_enabled
			elif p_event.keycode == KEY_C:
				collision_enabled = ! collision_enabled
			elif p_event.keycode == KEY_ESCAPE:
				toggle_mouse_capture()
			elif p_event.keycode == KEY_P:
				capture_mouse()

		elif p_event.keycode in [ KEY_Q, KEY_E, KEY_SPACE ]:
			velocity.y = 0


func toggle_mouse_capture() -> void:
	mouse_captured = !mouse_captured
	if mouse_captured:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func capture_mouse() -> void:
	mouse_captured = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true
