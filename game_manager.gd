# game_manager.gd
class_name GameManager
extends Node

signal race_completed(player, time)
signal race_started
signal race_in_progress_update

@export var race_line: RaceLine
@export var laps_to_win: int = 3
@export var restart_delay: float = 1.0
@export var race_start_delay: float = 2.0
@export var player_group: String = "players" # Group name for players

@onready var player_spawner = $"PlayerSpawner"
@onready var network_manager = get_node_or_null("/root/NetworkManager")
@onready var multiplayer_synchronizer = $MultiplayerSynchronizer

var player_laps = {}
var has_race_started = false
var race_start_time = 0
var is_race_in_progress = false

func _ready():
	if race_line:
		race_line.pass_completed.connect(_on_lap_completed)
	else:
		push_error("No RaceLine assigned to GameManager")
	
	player_spawner.all_players_spawned.connect(start_race)
	print(multiplayer.get_unique_id(), "- Waiting for player spawner to finish")
	
	# Set up MultiplayerSynchronizer for player_laps (Enhancement from Option A)
	if !multiplayer_synchronizer:
		multiplayer_synchronizer = MultiplayerSynchronizer.new()
		multiplayer_synchronizer.name = "MultiplayerSynchronizer"
		add_child(multiplayer_synchronizer)
	
	# Set up synchronizer for race state
	var sync_config = SceneReplicationConfig.new()
	sync_config.add_property("is_race_in_progress")
	multiplayer_synchronizer.replication_config = sync_config

func start_race():
	player_laps.clear()

	position_players_at_start()

	has_race_started = true
	is_race_in_progress = true
	race_start_time = Time.get_ticks_msec()
	print(multiplayer.get_unique_id(), "- Race started!")
	
	emit_signal("race_started")

func position_players_at_start():
	if race_line:
		# Use the race_line's built-in positioning method
		race_line.position_players_at_start(player_group)
	else:
		push_error("No race_line assigned to GameManager")

func _on_lap_completed(player):
	if not is_race_in_progress:
		return

	if not player_laps.has(player):
		player_laps[player] = 0

	player_laps[player] += 1

	# Get player name if available
	var player_name = player.name
	if "player_name" in player:
		player_name = player.player_name
		
	print(multiplayer.get_unique_id(), "- Player " + player_name + " completed lap " + str(player_laps[player]))
	
	# Debug info for host to check player_laps dictionary
	if network_manager and network_manager.is_server():
		print(multiplayer.get_unique_id(), "- [LAP DEBUG] Lap completed by " + player_name)
		print(multiplayer.get_unique_id(), "- [LAP DEBUG] player_laps dictionary now contains " + str(player_laps.size()) + " entries:")
		for p in player_laps.keys():
			var p_name = "Unknown"
			if is_instance_valid(p):
				p_name = p.name
				if "player_name" in p:
					p_name = p.player_name
			else:
				p_name = "INVALID REFERENCE"
			print(multiplayer.get_unique_id(), "- [LAP DEBUG] - " + p_name + ": " + str(player_laps[p]) + " laps")

	# In multiplayer, make sure player_laps is synced to all clients
	if multiplayer.has_multiplayer_peer():
		rpc("sync_player_laps", player.get_path(), player_laps[player])

	if player_laps[player] >= laps_to_win:
		_on_race_won(player)

func _on_race_won(player):
	is_race_in_progress = false

	var race_time = (Time.get_ticks_msec() - race_start_time) / 1000.0
	var player_name = "Unknown"
	
	# Get player name if available
	if "player_name" in player:
		player_name = player.player_name
	else:
		player_name = player.name
		
	print(multiplayer.get_unique_id(), "- Player " + player_name + " won the race in " + str(race_time) + " seconds!")

	emit_signal("race_completed", player, race_time)
	
	# Only the server should restart the race in multiplayer
	if network_manager and network_manager.is_server():
		restart_race()


func restart_race():
	get_tree().paused = true
	
	await get_tree().create_timer(restart_delay).timeout
	
	# Reset player physics completely before starting new race
	reset_all_players()
	
	start_race()
	
	await get_tree().create_timer(race_start_delay).timeout
	get_tree().paused = false
	
func reset_all_players():
	var players = get_tree().get_nodes_in_group(player_group)
	for player in players:
		if player.has_method("reset_physics"):
			player.reset_physics()
		
		# Directly reset physics properties
		if "velocity" in player:
			player.velocity = Vector3.ZERO
		if "speed" in player:
			player.speed = 0.0
	
@rpc("authority", "call_local", "reliable")
func sync_player_laps(player_path, lap_count):
	# Get the player node from path
	var player = get_node_or_null(player_path)
	if player:
		# Update lap count in player_laps dictionary
		player_laps[player] = lap_count
			
# Called every frame to ensure leaderboard is always up-to-date
func _process(_delta):
	if network_manager and network_manager.is_server() and is_race_in_progress:
		if Engine.get_frames_drawn() % 30 == 0: # Twice per second
			sync_all_player_laps()
			
func sync_all_player_laps():
	if not network_manager.is_server():
		return
		
	for player in player_laps.keys():
		if is_instance_valid(player) and player.has_method("get_path"):
			rpc("sync_player_laps", player.get_path(), player_laps[player])
	
	emit_signal("race_in_progress_update")