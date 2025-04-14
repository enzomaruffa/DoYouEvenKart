extends CharacterBody3D

# Car properties
const MAX_SPEED = 25.0
const MAX_REVERSE_SPEED = 15.0  # Maximum reverse speed (lower than forward)
const ACCELERATION = 15.0
const BRAKE_FORCE = 25.0
const MAX_STEERING_ANGLE = 140.0  # In degrees
const STEERING_SPEED = 3.0
const FRICTION = 0.02
const GRIP = 0.7  # How much car resists sliding sideways (higher = less slide)
const RESPAWN_HEIGHT = -30.0  # Y position below which the car will respawn
const GRAVITY_ALIGNMENT_STRENGTH = 5.0  # How quickly the car rights itself
const GRAVITY_ALIGNMENT_MAX_ANGLE = 60.0  # Maximum angle before full correction force is applied

# Get the gravity from the project settings to be synced with RigidBody nodes
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# Car state
var speed = 0.0
var steering_angle = 0.0  # Current steering angle
var car_mesh  # Reference to the car's mesh for rotation
var start_position = Vector3()  # Starting position for respawning
var start_rotation = Quaternion()  # Starting rotation for respawning
var is_respawning = false
var respawn_timer = 0.0

# Player info
var player_name = "Player"
var player_color = Color.BLUE
var player_id = 0
var is_local_player = false

# Multiplayer synchronization
var sync_pos = Vector3()
var sync_rot = Quaternion()
var sync_velocity = Vector3()
var sync_timer = 0.0
const SYNC_INTERVAL = 0.05 # Synchronize every 50ms

func _ready():
	# Set up car mesh
	car_mesh = $CarMesh
	
	# Store initial position and rotation for respawning
	start_position = global_position
	start_rotation = global_transform.basis.get_rotation_quaternion()
	
	# Set car color
	if car_mesh:
		var material = StandardMaterial3D.new()
		material.albedo_color = player_color
		car_mesh.set_surface_override_material(0, material)
	
	# Create player name label
	var label_3d = Label3D.new()
	label_3d.name = "Label3D"
	label_3d.text = player_name
	label_3d.position = Vector3(0, 1.0, 0)
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.font_size = 24
	add_child(label_3d)
	
	# Only enable camera for local player
	$Camera3D.current = is_multiplayer_authority()
	
	# Hide other players' cameras
	if not is_multiplayer_authority():
		$Camera3D.clear_current()
		
	print("Player ready: ", player_name, " (ID: ", str(player_id), ") Authority: ", is_multiplayer_authority())

func apply_ground_alignment(delta):
	var target_up = get_floor_normal()
	var car_up = transform.basis.y

	var dot_product = target_up.dot(car_up)

	if abs(dot_product) < 0.99:
		# Calculate the angle between current up and target up
		var angle = car_up.angle_to(target_up)

		# Only apply correction if angle is significant
		if angle > 0.01:  # About 0.57 degrees
			# Calculate alignment force based on angle
			var alignment_factor = clamp(angle / deg_to_rad(GRAVITY_ALIGNMENT_MAX_ANGLE), 0.0, 1.0)

			# Create a rotation to align with the ground
			var axis = car_up.cross(target_up).normalized()
			if axis.length() > 0.001:  # Avoid zero cross product
				var correction_rotation = Quaternion(axis, angle * alignment_factor * GRAVITY_ALIGNMENT_STRENGTH * delta)

				# Apply the rotation
				global_transform.basis = Basis(correction_rotation) * global_transform.basis

func _physics_process(delta):
	if not is_multiplayer_authority():
		# Interpolate position for non-local players
		global_position = global_position.lerp(sync_pos, 0.5)
		global_transform.basis = Basis(global_transform.basis.get_rotation_quaternion().slerp(sync_rot, 0.5))
		return
	
	# Check if car needs to respawn
	if global_position.y < RESPAWN_HEIGHT:
		respawn()
	
	# Handle respawning animation/delay if currently respawning
	if is_respawning:
		respawn_timer -= delta
		if respawn_timer <= 0:
			is_respawning = false
		return  # Skip physics while respawning
	
	# Apply gravity when not on floor
	if not is_on_floor():
		velocity.y -= gravity * delta * 1.2  # Slightly stronger gravity for better feel
	else:
		velocity.y = -0.1  # Small negative value to keep car grounded
	
	# Get input
	var brake_input = Input.get_action_strength("ui_down")  # S key
	var accelerate_input = Input.get_action_strength("ui_up")  # W key
	var steer_input = Input.get_action_strength("ui_left") - Input.get_action_strength("ui_right")  # D - A keys
	
	# Calculate acceleration/deceleration/reverse
	if accelerate_input > 0:
		# If we're moving backwards, apply stronger braking force first
		if speed < 0:
			speed += BRAKE_FORCE * 1.5 * delta
		else:
			speed += ACCELERATION * delta
	elif brake_input > 0:
		# If we're moving forwards, brake first
		if speed > 0:
			speed -= BRAKE_FORCE * delta
		else:
			# We're already stopped or moving backwards, so accelerate backwards
			speed -= ACCELERATION * 0.7 * delta  # Reverse is slightly slower
	else:
		# Apply natural deceleration (friction)
		speed *= (1.0 - FRICTION)
		# Apply extra friction when almost stopped to prevent creeping
		if abs(speed) < 0.5:
			speed *= 0.8
	
	# Clamp speed based on direction
	if speed > 0:
		speed = min(speed, MAX_SPEED)
	else:
		speed = max(speed, -MAX_REVERSE_SPEED)
	
	# Handle steering
	var target_steering = steer_input * MAX_STEERING_ANGLE
	
	# Steering is more limited at higher speeds, and reversed when going backwards
	var speed_factor = clamp(abs(speed) / MAX_SPEED, 0.1, 1.0)
	var max_angle_at_speed = MAX_STEERING_ANGLE * (1.0 - speed_factor * 0.5)
	target_steering = clamp(target_steering, -max_angle_at_speed, max_angle_at_speed)
	
	# Reverse steering when going backwards
	if speed < 0:
		target_steering = -target_steering
	
	# Smoother steering
	steering_angle = lerp(steering_angle, target_steering, STEERING_SPEED * delta)
	
	# Calculate forward and sideways movement direction
	var forward_direction = -transform.basis.z
	var right_direction = transform.basis.x
	
	# Convert steering angle to rotation
	var rotation_angle = deg_to_rad(steering_angle) * delta * abs(speed) * 0.1
	
	# Rotate the car based on steering
	if car_mesh and abs(speed) > 0.1:
		rotate_y(rotation_angle)
	
	# Calculate velocity
	velocity.x = forward_direction.x * speed
	velocity.z = forward_direction.z * speed

	if not is_on_floor():
		velocity.y -= gravity * delta * 1.2
	else:
		velocity.y = -0.1  # Small negative value to keep car grounded

	apply_ground_alignment(delta)
	
	# Apply some sideways friction/grip
	var sideways_velocity = right_direction.dot(Vector3(velocity.x, 0, velocity.z)) * right_direction
	velocity.x -= sideways_velocity.x * GRIP * delta * (abs(speed) / MAX_SPEED)
	velocity.z -= sideways_velocity.z * GRIP * delta * (abs(speed) / MAX_SPEED)
	
	# Finally move the character
	move_and_slide()
	
	# Sync position with other players
	sync_timer -= delta
	if sync_timer <= 0:
		sync_timer = SYNC_INTERVAL
		rpc("sync_state", global_position, global_transform.basis.get_rotation_quaternion(), velocity)

func respawn():
	if is_respawning:
		return  # Already respawning
		
	# Set respawning flag and timer
	is_respawning = true
	respawn_timer = 1.0  # 1 second respawn delay
	
	# Reset vehicle physics
	velocity = Vector3.ZERO
	speed = 0.0
	steering_angle = 0.0
	
	# Reset position and rotation
	global_position = start_position
	# Apply a small upward offset to avoid getting stuck in the ground
	global_position.y += 0.5
	global_transform.basis = Basis(start_rotation)
	
	# You could add respawn effects here
	print("Car respawned!")

@rpc("any_peer", "unreliable")
func sync_state(pos, rot, vel):
	if not is_multiplayer_authority():
		sync_pos = pos
		sync_rot = rot
		sync_velocity = vel

func set_player_info(id, info):
	player_id = id
	player_name = info.name
	player_color = info.color
	
	# Set authority based on the ID
	set_multiplayer_authority(id)
	
	# Update visuals if the node is already ready
	if is_inside_tree():
		# Set car color
		if car_mesh:
			var material = StandardMaterial3D.new()
			material.albedo_color = player_color
			car_mesh.set_surface_override_material(0, material)
		
		# Update player name label
		var label = get_node_or_null("Label3D")
		if label:
			label.text = player_name
			
		# Update camera (only for local player)
		$Camera3D.current = is_multiplayer_authority()
		
	print("Set player info: ", player_name, " (ID: ", str(player_id), ")")