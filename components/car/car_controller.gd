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

# Add these properties to your car_controller.gd
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

func _ready():
	# Assume there's a MeshInstance3D as a child named "CarMesh"
	car_mesh = $CarMesh
	
	# Store initial position and rotation for respawning
	start_position = global_position
	start_rotation = global_transform.basis.get_rotation_quaternion()

# Add this function to your _physics_process after the gravity application
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
	# Check if car needs to respawn
	if global_position.y < RESPAWN_HEIGHT:
		respawn()
	
	# Handle respawning animation/delay if currently respawning
	if is_respawning:
		respawn_timer -= delta
		if respawn_timer <= 0:
			is_respawning = false
		return  # Skip physics while respawning
	
	# Apply gravity when not on floor (stronger gravity for better feel)
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
