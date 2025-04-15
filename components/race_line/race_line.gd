class_name RaceLine
extends Node3D

signal pass_completed(player)

@export var starting_grid_width: float = 4.0  # Width of zigzag pattern
@export var grid_spacing: float = 2.0  # Space between cars in grid

@onready var entry_area = $Entry
@onready var exit_area = $Exit

var players_in_checkpoint = []


func _on_entry_body_entered(body):
	# TODO: Detect if it's a player indeed
	if not body in players_in_checkpoint:
		players_in_checkpoint.append(body)
		print("Player entered checkpoint: ", body.name)


func _on_exit_body_entered(body):
	# TODO: Detect if it's a player indeed
	if body in players_in_checkpoint:
		players_in_checkpoint.erase(body)
		emit_signal("pass_completed", body)
		print("Pass completed by: ", body.name)


func _ready():
	entry_area.body_entered.connect(_on_entry_body_entered)
	exit_area.body_entered.connect(_on_exit_body_entered)

# Returns a starting position for a player based on their position index
func get_start_position(position_index):
	var start_pos = global_position
	var forward_dir = get_global_transform().basis.z
	var right_dir = -get_global_transform().basis.x

	var row = position_index / 2
	var column = position_index % 2

	var offset = forward_dir * (row * grid_spacing + 5.0)
	offset += right_dir * (column * starting_grid_width - starting_grid_width/2)

	# Slightly above ground to prevent physics issues
	var position = start_pos + offset + Vector3(0, 2, 0)
	
	# Return a Transform3D with position and rotation facing start line
	var transform = Transform3D()
	transform.origin = position
	transform.basis = Basis.looking_at(-forward_dir, Vector3.UP)
	
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
		
		player.global_position = transform.origin
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
		
		print("Positioned player " + player.name + " at " + str(player.global_position))
