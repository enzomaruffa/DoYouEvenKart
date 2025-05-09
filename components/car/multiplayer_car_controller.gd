extends CharacterBody3D

# Car properties
const MAX_SPEED = 25.0
const MAX_REVERSE_SPEED = 15.0
const ACCELERATION = 15.0
const BRAKE_FORCE = 25.0
const MAX_STEERING_ANGLE = 140.0
const STEERING_SPEED = 3.0
const FRICTION = 0.02
const GRIP = 0.7
const RESPAWN_HEIGHT = -30.0
const GRAVITY_ALIGNMENT_STRENGTH = 5.0
const GRAVITY_ALIGNMENT_MAX_ANGLE = 60.0

# Improved bumping parameters
const BUMP_FORCE = 15.0 # Increased from 10.0 for more noticeable bumps
const BUMP_COOLDOWN = 0.15 # Decreased from 0.2 for more responsive bumping
const BUMP_UPWARD_FORCE = 5.0 # Increased upward force for more dramatic bumps
const BUMP_TILT_FACTOR = 0.15 # How much the car tilts when bumped
const BUMP_VELOCITY_FACTOR = 0.3 # How much relative velocity affects bump strength

# Get the gravity from the project settings to be synced with RigidBody nodes
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# Car state
var speed = 0.0
var steering_angle = 0.0
var car_mesh
var start_position = Vector3()
var start_rotation = Quaternion()
var is_respawning = false
var respawn_timer = 0.0
var bump_cooldown_timer = 0.0

# Collision properties
@export var collision_weight = 1.0
@export var collision_bounce = 1.0

# Player info
var player_name = "Player"
var player_color = Color.BLUE
var player_id = 0

# Multiplayer synchronization
var sync_pos = Vector3()
var sync_rot = Quaternion()
var sync_velocity = Vector3()
var sync_timer = 0.0
const SYNC_INTERVAL = 0.05

# Added: Last collision data for better bump detection
var last_collisions = []
var pending_bumps = []

# Get network manager for helper functions (Option A implementation)
@onready var network_manager = get_node_or_null("/root/NetworkManager")

# Helper functions for standardized authority checks (Option A implementation)
func is_server() -> bool:
	return network_manager != null && network_manager.is_server()

func is_authority_for_player(player_id: int) -> bool:
	return multiplayer.get_unique_id() == player_id

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

	# Only enable camera for local player (player we have authority over)
	$Camera3D.current = is_multiplayer_authority()

	# Improved collision setup
	collision_layer = 3 # 0b11 (layer 1 and 2)
	collision_mask = 3 # 0b11 (detect layer 1 and 2)

	# Added: Ensure we detect collisions
	set_safe_margin(0.05) # Better collision detection

	print(player_name, " ready with authority: ", is_multiplayer_authority())

func apply_ground_alignment(delta):
	var target_up = get_floor_normal()
	var car_up = transform.basis.y

	var dot_product = target_up.dot(car_up)

	if abs(dot_product) < 0.99:
		# Calculate the angle between current up and target up
		var angle = car_up.angle_to(target_up)

		# Only apply correction if angle is significant
		if angle > 0.01: # About 0.57 degrees
			# Calculate alignment factor based on angle
			var alignment_factor = clamp(angle / deg_to_rad(GRAVITY_ALIGNMENT_MAX_ANGLE), 0.0, 1.0)

			# Create a rotation to align with the ground
			var axis = car_up.cross(target_up).normalized()
			if axis.length() > 0.001: # Avoid zero cross product
				var correction_rotation = Quaternion(axis, angle * alignment_factor * GRAVITY_ALIGNMENT_STRENGTH * delta)

				# Apply the rotation
				global_transform.basis = Basis(correction_rotation) * global_transform.basis

func _physics_process(delta):
	# Process pending bumps first - allows bumps to be applied even when not the authority
	process_pending_bumps()

	# Modified interpolation for non-authority players
	# This preserves velocity-based movement after bumps while still syncing position
	if not is_multiplayer_authority():
		# Only interpolate if we're not currently being bumped
		if bump_cooldown_timer <= 0:
			global_position = global_position.lerp(sync_pos, 0.2) # Slower interpolation
			global_transform.basis = Basis(global_transform.basis.get_rotation_quaternion().slerp(sync_rot, 0.2))
		else:
			# When recently bumped, apply velocity instead of pure interpolation
			global_position += velocity * delta
			# Only gradually blend back to sync position
			global_position = global_position.lerp(sync_pos, 0.05) # Very subtle correction
			global_transform.basis = Basis(global_transform.basis.get_rotation_quaternion().slerp(sync_rot, 0.1))
		return

	# Update bump cooldown timer
	if bump_cooldown_timer > 0:
		bump_cooldown_timer -= delta

	# Check if car needs to respawn
	if global_position.y < RESPAWN_HEIGHT:
		respawn()

	# Handle respawning animation/delay if currently respawning
	if is_respawning:
		respawn_timer -= delta
		if respawn_timer <= 0:
			is_respawning = false
		return # Skip physics while respawning

	# Apply gravity when not on floor
	if not is_on_floor():
		velocity.y -= gravity * delta * 1.2 # Slightly stronger gravity for better feel
	else:
		velocity.y = -0.1 # Small negative value to keep car grounded

	# Get input
	var brake_input = Input.get_action_strength("ui_down") # S key
	var accelerate_input = Input.get_action_strength("ui_up") # W key
	var steer_input = Input.get_action_strength("ui_left") - Input.get_action_strength("ui_right") # D - A keys

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
			speed -= ACCELERATION * 0.7 * delta # Reverse is slightly slower
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
		target_steering = - target_steering

	# Smoother steering
	steering_angle = lerp(steering_angle, target_steering, STEERING_SPEED * delta)

	# Calculate forward and sideways movement direction
	var forward_direction = - transform.basis.z
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
		velocity.y = -0.1 # Small negative value to keep car grounded

	apply_ground_alignment(delta)

	# Apply some sideways friction/grip
	var sideways_velocity = right_direction.dot(Vector3(velocity.x, 0, velocity.z)) * right_direction
	velocity.x -= sideways_velocity.x * GRIP * delta * (abs(speed) / MAX_SPEED)
	velocity.z -= sideways_velocity.z * GRIP * delta * (abs(speed) / MAX_SPEED)

	# Clear last collisions list
	last_collisions = []

	# Finally move the character
	move_and_slide()

	# Check for collisions with other cars after moving
	check_car_collisions()

	# Sync position with other players
	sync_timer -= delta
	if sync_timer <= 0:
		sync_timer = SYNC_INTERVAL
		rpc("sync_state", global_position, global_transform.basis.get_rotation_quaternion(), velocity)

# Make speed accessible for collision detection
func get_speed():
	return abs(speed)

# REFACTORED COLLISION SYSTEM (Option A Implementation)
# Instead of immediate_bump, we now use a cleaner approach with server validation

# Client detects collision and requests validation
func check_car_collisions():
	# Skip if we're on cooldown
	if bump_cooldown_timer > 0:
		return

	# Get all collisions
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()

		# Only interested in other cars (CharacterBody3D)
		if collider is CharacterBody3D and collider != self:
			# Skip if we've already processed this collision
			if last_collisions.has(collider):
				continue

			# Add to last_collisions to prevent processing multiple times
			last_collisions.append(collider)

			# Calculate impact direction (from collider to us)
			var impact_dir = (global_position - collider.global_position).normalized()
			impact_dir.y = 0 # Keep bump on horizontal plane

			# Calculate relative velocity for more dynamic collisions
			var rel_velocity = velocity - collider.velocity
			var rel_speed = rel_velocity.length()

			# STATIONARY CAR DETECTION: Check if collider is stationary or slow-moving
			var is_target_stationary = false
			if collider.has_method("get_speed"):
				# If we have access to speed property
				is_target_stationary = collider.get_speed() < 2.0
			else:
				# Otherwise estimate from velocity
				is_target_stationary = collider.velocity.length() < 2.0

			# DYNAMIC FORCE CALCULATION: Adjust for stationary targets
			var impact_force = BUMP_FORCE * 2.0 * (1 + abs(speed) / MAX_SPEED)
			impact_force += rel_speed * BUMP_VELOCITY_FACTOR

			# Construct collision data
			var collision_data = {
				"source_id": player_id,
				"target_id": collider.player_id,
				"source_path": get_path(),
				"target_path": collider.get_path(),
				"impact_dir": impact_dir,
				"impact_force": impact_force,
				"rel_speed": rel_speed,
				"is_target_stationary": is_target_stationary,
				"timestamp": Time.get_ticks_msec()
			}

			# Send collision data to server for validation
			rpc_id(1, "request_collision_validation", collision_data)

			# Set cooldown immediately to prevent multiple collisions
			bump_cooldown_timer = BUMP_COOLDOWN

			# Break after first collision
			break

# Server receives collision request and validates it
@rpc("any_peer", "reliable")
func request_collision_validation(collision_data):
	var sender_id = multiplayer.get_remote_sender_id()
	
	# Only server should validate
	if not is_server():
		return
		
	# Validate that sender is the source
	if sender_id != collision_data.source_id:
		print("Collision validation failed: Sender ID mismatch")
		return
	
	# Basic validation passed, broadcast validated collision to all clients
	rpc("apply_validated_collision", collision_data)

# All clients apply validated collision
@rpc("authority", "call_local", "reliable")
func apply_validated_collision(collision_data):
	# Get the source and target nodes
	var source = get_node_or_null(collision_data.source_path)
	var target = get_node_or_null(collision_data.target_path)
	
	if not source or not target:
		return
	
	# Apply the bump effect to the target
	apply_bump_effect(target, -collision_data.impact_dir, collision_data.impact_force, collision_data.is_target_stationary)
	
	# Apply reduced effect to the source
	apply_bump_effect(source, collision_data.impact_dir, collision_data.impact_force * 0.7, false)

# Apply bump effects to a car
func apply_bump_effect(car, impact_dir, impact_force, is_stationary):
	# Safety check
	if not is_instance_valid(car):
		return
	
	# Apply force to the car
	car.velocity += impact_dir * impact_force
	
	# Apply enhanced upward force
	var impact_strength = impact_force / 10.0
	var extra_upward = clamp(impact_strength, 1.0, 3.0)
	car.velocity.y += BUMP_UPWARD_FORCE * extra_upward
	
	# Apply position offset to kickstart physics
	car.global_position += impact_dir.normalized() * 0.15
	
	# Apply tilt effect
	if car.has_method("apply_bump_tilt"):
		car.apply_bump_tilt(impact_dir * impact_force)
	
	# For stationary cars, inject some speed to overcome inertia
	if is_stationary and "speed" in car:
		# Convert some of the force to forward/backward speed
		var forward_dir = - car.transform.basis.z
		var force_projection = impact_dir.dot(forward_dir)
		
		# Set speed directly to overcome inertia
		if force_projection < 0:
			car.speed = -5.0 # Backward speed
		else:
			car.speed = 5.0 # Forward speed
	
	# Set bump cooldown
	car.bump_cooldown_timer = BUMP_COOLDOWN

# Legacy support for pending bumps
func process_pending_bumps():
	if pending_bumps.size() > 0:
		for bump in pending_bumps:
			# Apply the bump
			velocity += bump.force
			# Add upward force for more dynamic bumps
			velocity.y += BUMP_UPWARD_FORCE

			# Apply a small position offset to kickstart physics
			global_position += bump.force.normalized() * 0.1

		# Clear pending bumps
		pending_bumps = []

func respawn():
	if is_respawning:
		return # Already respawning

	# Set respawning flag and timer
	is_respawning = true
	respawn_timer = 1.0 # 1 second respawn delay

	# Reset vehicle physics
	velocity = Vector3.ZERO
	speed = 0.0
	steering_angle = 0.0

	# Reset position and rotation
	global_position = start_position
	# Apply a small upward offset to avoid getting stuck in the ground
	global_position.y += 0.5
	global_transform.basis = Basis(start_rotation)

	# Sync this respawn with all clients
	rpc("sync_respawn")

	print("Car respawned!")

@rpc("any_peer")
func sync_position(pos, rot):
	# Used for initial positioning to prevent jumps
	global_position = pos
	global_transform.basis = Basis(rot)
	
	# Also update sync values for smoother interpolation
	sync_pos = pos
	sync_rot = rot
	velocity = Vector3.ZERO
	speed = 0.0
	
func reset_physics():
	# Reset all physics state
	velocity = Vector3.ZERO
	speed = 0.0
	steering_angle = 0.0
	bump_cooldown_timer = 0.0
	
	# Force position update to all clients
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer():
		rpc("sync_state", global_position, global_transform.basis.get_rotation_quaternion(), Vector3.ZERO)
	
@rpc("any_peer", "unreliable")
func sync_state(pos, rot, vel):
	if not is_multiplayer_authority():
		sync_pos = pos
		sync_rot = rot
		sync_velocity = vel
		
		# Immediately update position slightly for more responsive feel
		global_position = global_position.lerp(sync_pos, 0.3)
		global_transform.basis = Basis(global_transform.basis.get_rotation_quaternion().slerp(sync_rot, 0.3))

@rpc("any_peer", "reliable")
func sync_respawn():
	# For non-authority clients, instantly position at start
	if not is_multiplayer_authority():
		global_position = start_position
		global_position.y += 0.5 # Small offset to prevent ground sticking
		global_transform.basis = Basis(start_rotation)
		sync_pos = start_position
		sync_rot = start_rotation
		sync_velocity = Vector3.ZERO

		# Visual effect could be added here
		print("Remote car respawned!")

func set_player_info(id, info):
	player_id = id
	player_name = info.name
	player_color = info.color

	# Always set the authority - the spawner will override this with the correct authority
	var peer_id = multiplayer.get_unique_id()
	# Log info about the player authority setup
	print(peer_id, ": Processing player_info for player: ", player_name, " (ID: ", id, ") Local ID: ", peer_id)

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

		# Update camera (only for the player that matches this client's ID)
		$Camera3D.current = is_multiplayer_authority()

		# Extra debug for camera assignment
		if is_multiplayer_authority():
			print(multiplayer.get_unique_id(), ": ✓ Camera set active for player: ", player_name, " (ID: ", player_id, ")")
		else:
			print(multiplayer.get_unique_id(), ": ✗ Camera set inactive for player: ", player_name, " (ID: ", player_id, ")")

	print(multiplayer.get_unique_id(), ": Set player info: ", player_name, " (ID: ", str(player_id), ")")

# Apply a small tilt to the car mesh for visual feedback during bumps
func apply_bump_tilt(force):
	if not car_mesh:
		return

	# Calculate tilt axis (perpendicular to both force and up vector)
	var force_horizontal = Vector3(force.x, 0, force.z).normalized()
	var up_vector = Vector3(0, 1, 0)
	var tilt_axis = force_horizontal.cross(up_vector).normalized()

	# Skip if we couldn't determine a valid axis
	if tilt_axis.length() < 0.1:
		return

	# Calculate tilt amount based on force strength (capped)
	var tilt_strength = clamp(force.length() * 0.01 * BUMP_TILT_FACTOR, 0, 0.15)

	# Create a temporary rotation basis
	var temp_basis = Basis(tilt_axis, tilt_strength)

	# Apply the rotation to the car mesh
	car_mesh.rotation = temp_basis.get_euler() + Vector3(0, 0, 0)

	# Create a tween to smoothly reset the tilt
	var tween = create_tween()
	tween.tween_property(car_mesh, "rotation", Vector3(0, 0, 0), 0.8).set_ease(Tween.EASE_OUT)