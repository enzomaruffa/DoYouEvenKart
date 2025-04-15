class_name RaceLine
extends Node3D

signal pass_completed(player)

@export var starting_grid_width: float = 4.0  # Width of zigzag pattern
@export var grid_spacing: float = 2.0  # Space between cars in grid
@export var player_spawner: Node  # Reference to the PlayerSpawner

@onready var entry_area = $Entry
@onready var exit_area = $Exit

var players_in_checkpoint = []


func _on_entry_body_entered(body):
	# Only track actual player bodies
	if not body.is_in_group("players"):
		return
		
	if not body in players_in_checkpoint:
		players_in_checkpoint.append(body)
		print(multiplayer.get_unique_id(), ": Player entered checkpoint: ", body.name, " (", body, ")")


func _on_exit_body_entered(body):
	# Only track actual player bodies
	if not body.is_in_group("players"):
		return
		
	if body in players_in_checkpoint:
		players_in_checkpoint.erase(body)
		emit_signal("pass_completed", body)
		print(multiplayer.get_unique_id(), ": Pass completed by: ", body.name, " (", body, ")")


func _ready():
	entry_area.body_entered.connect(_on_entry_body_entered)
	exit_area.body_entered.connect(_on_exit_body_entered)
	
	if player_spawner:
		player_spawner.player_spawned.connect(_on_player_spawned)
		player_spawner.all_players_spawned.connect(_on_all_players_spawned)

# Called when PlayerSpawner emits player_spawned signal
func _on_player_spawned(id, player_instance, position_index):
	var transform = get_start_position(position_index)
	print(multiplayer.get_unique_id(), ": Positioning player ID: ", id, " at index: ", position_index)
	
	# Apply the transform - this happens on all clients since the spawn signal is local
	if player_instance and is_instance_valid(player_instance):
		player_instance.global_position = transform.origin
		player_instance.global_transform.basis = transform.basis
		
		# Set start position for respawning
		player_instance.start_position = transform.origin
		player_instance.start_rotation = transform.basis.get_rotation_quaternion()
		
		# If we're the server, notify all clients of the position (needed for late joiners)
		if multiplayer.is_server():
			rpc_id(id, "sync_player_position", id, transform.origin, transform.basis.get_rotation_quaternion())

@rpc("authority", "reliable")
func sync_player_position(player_id, pos, rot):
	# Find the player by ID and update position if needed (for late joiners)
	if not multiplayer.is_server():
		for player in get_tree().get_nodes_in_group("players"):
			if player.player_id == player_id:
				player.global_position = pos
				player.global_transform.basis = Basis(rot)
				player.start_position = pos
				player.start_rotation = rot

# Called when PlayerSpawner emits all_players_spawned signal
func _on_all_players_spawned():
	print("All players spawned and positioned")

# Returns a starting position for a player based on their position index
func get_start_position(position_index):
	var start_pos = position
	var forward_dir = get_global_transform().basis.z
	var right_dir = -get_global_transform().basis.x

	var row = position_index / 2
	var column = position_index % 2

	var offset = forward_dir * (row * grid_spacing + 5.0)
	offset += right_dir * (column * starting_grid_width - starting_grid_width/2)
	
	# Return a Transform3D with position and rotation facing start line
	var transform = Transform3D()
	transform.origin = start_pos + offset + Vector3(0, 2, 0)
	transform.basis = Basis.looking_at(-forward_dir)
	
	return transform

# Positions all players in the specified group at the starting grid
func position_players_at_start(player_group_name = "players"):
	var players = get_tree().get_nodes_in_group(player_group_name)

	if players.size() == 0:
		push_error("No players found in group: " + player_group_name)
		return

	for i in range(players.size()):
		var player = players[i]
		var transform = get_start_position(i)
		
		player.position = transform.origin
		player.global_transform.basis = transform.basis
		
		# Reset physics properties if available
		if player is RigidBody3D:
			player.linear_velocity = Vector3.ZERO
			player.angular_velocity = Vector3.ZERO
		elif "velocity" in player:
			player.velocity = Vector3.ZERO
			if "speed" in player:
				player.speed = 0.0
		
		# Store starting position for respawns if the player supports it
		if "start_position" in player:
			player.start_position = transform.origin
		if "start_rotation" in player:
			player.start_rotation = transform.basis.get_rotation_quaternion()
		
		print("Positioned player " + player.name + " at " + str(player.position))
