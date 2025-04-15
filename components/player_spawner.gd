extends Node

@export var multiplayer_player_scene: PackedScene
@export var player_group: String = "players"
# RaceLine reference no longer needed - now RaceLine references PlayerSpawner instead

signal player_spawned(id, player_instance, position_index)
signal all_players_spawned
signal late_player_spawned(id, player_instance)

var network_manager = null
var spawned_players = {}

@onready var spawner = MultiplayerSpawner.new()

func _ready():
	spawner.name = "MultiplayerSpawner"
	spawner.spawn_path = get_path()
	add_child(spawner)

	spawner.add_spawnable_scene(multiplayer_player_scene.resource_path)
	
	network_manager = get_node("/root/NetworkManager")
	if not network_manager:
		push_error("NetworkManager not found!")
		return
	
	# Connect to player connection signal for late joiners
	network_manager.player_connected.connect(_on_player_connected)

	call_deferred("delayed_spawn")

func delayed_spawn():
	if multiplayer.is_server():
		var player_ids = network_manager.players.keys()
		player_ids.sort()

		for i in range(player_ids.size()):
			var id = player_ids[i]
			var player_info = network_manager.players[id]
			try_spawn_player(id, player_info, i)
			
		# Wait a brief moment for all players to spawn before emitting the signal
		await get_tree().create_timer(0.2).timeout
		rpc("emit_all_players_spawned")
		
@rpc("authority", "reliable")
func emit_all_players_spawned():
	emit_signal("all_players_spawned")

func _on_player_connected(id):
	if multiplayer.is_server() and not spawned_players.has(id):
		var player_info = network_manager.players[id]
		var position_index = spawned_players.size()
		try_spawn_player(id, player_info, position_index)
		
		# Wait a moment to ensure the spawning is complete before emitting the signal
		await get_tree().create_timer(0.1).timeout
		
		if spawned_players.has(id):
			# Use RPC to ensure all clients receive this signal
			rpc("emit_late_player_spawned", id)

@rpc("authority", "reliable")
func emit_late_player_spawned(player_id):
	if spawned_players.has(player_id):
		emit_signal("late_player_spawned", player_id, spawned_players[player_id])

func try_spawn_player(id, player_info, position_index):
	if spawned_players.has(id):
		return
	
	if multiplayer.is_server():
		var player_scene_path = multiplayer_player_scene.resource_path
		var spawn_info = {
			"name": str(id),
			"player_id": id,
			"player_name": player_info.name,
			"player_color": player_info.color,
			"position_index": position_index
		}
		
		rpc("spawn_player", player_scene_path, spawn_info)
	
	print(multiplayer.get_unique_id(), ": Requested spawn for player: ", player_info.name, " with ID: ", id)

@rpc("authority", "call_local", "reliable")
func spawn_player(scene_path, spawn_info):
	print(multiplayer.get_unique_id(), ": Running spawn_player for player ID: ", spawn_info.player_id)
	var player_instance = load(scene_path).instantiate()
	
	if player_instance == null:
		push_error("Failed to spawn player instance for ID: " + str(spawn_info.player_id))
		return
	
	add_child(player_instance, true)
	
	await get_tree().process_frame

	if is_instance_valid(player_instance):
		player_instance.set_multiplayer_authority(spawn_info.player_id)
		print(multiplayer.get_unique_id(), ": Force claiming authority over player ID: ", spawn_info.player_id)
		
		player_instance.set_player_info(spawn_info.player_id, {
			"name": spawn_info.player_name, 
			"color": spawn_info.player_color
		})
		
		if not player_instance.is_in_group(player_group):
			player_instance.add_to_group(player_group)
		
		spawned_players[spawn_info.player_id] = player_instance
		
		# Signal position index for RaceLine to use
		emit_signal("player_spawned", spawn_info.player_id, player_instance, spawn_info.position_index)
		
		print(multiplayer.get_unique_id(), ": Spawned player: ", spawn_info.player_name, 
			" with ID: ", spawn_info.player_id, 
			" Authority: ", player_instance.is_multiplayer_authority())