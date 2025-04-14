extends Node

@export var multiplayer_player_scene: PackedScene
@export var race_line: RaceLine
@export var player_group: String = "players"

var network_manager = null
var spawned_players = {}

func _ready():
	network_manager = get_node("/root/NetworkManager")
	if not network_manager:
		push_error("NetworkManager not found!")
		return
	
	if not race_line:
		push_error("No RaceLine assigned to PlayerSpawner")
		return
	
	if multiplayer.is_server():
		# Host always spawns all players
		var player_ids = network_manager.players.keys()
		# Sort IDs to ensure consistent positioning
		player_ids.sort()
		
		for i in range(player_ids.size()):
			var id = player_ids[i]
			spawn_player(id, network_manager.players[id], i)
		
		# Listen for new players
		network_manager.player_connected.connect(_on_player_connected)
		network_manager.player_disconnected.connect(_on_player_disconnected)

func _on_player_connected(id, player_info):
	if multiplayer.is_server():
		# Determine position index based on existing players
		var position_index = spawned_players.size()
		spawn_player(id, player_info, position_index)

func _on_player_disconnected(id):
	if spawned_players.has(id):
		if is_instance_valid(spawned_players[id]):
			spawned_players[id].queue_free()
		spawned_players.erase(id)

func spawn_player(id, player_info, position_index):
	# Instance the player scene
	var player_instance = multiplayer_player_scene.instantiate()
	
	# Set up player info
	player_instance.set_player_info(id, player_info)
	
	# Add to group
	if not player_instance.is_in_group(player_group):
		player_instance.add_to_group(player_group)
	
	# Position the player using race_line
	var transform = race_line.get_start_position(position_index)
	player_instance.global_position = transform.origin
	player_instance.global_transform.basis = transform.basis
	
	# Set start position for respawning
	player_instance.start_position = transform.origin
	player_instance.start_rotation = transform.basis.get_rotation_quaternion()
	
	# Add to the game
	add_child(player_instance, true)
	spawned_players[id] = player_instance