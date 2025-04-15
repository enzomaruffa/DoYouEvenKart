extends Control

@export var game_manager: GameManager

var network_manager = null
var race_positions = []

# UI elements
@onready var position_label = $VBoxContainer/PositionLabel
@onready var lap_label = $VBoxContainer/LapLabel
@onready var player_list = $VBoxContainer/PlayerList

# Add these signals to match with PlayerSpawner
func _on_player_spawned(_id, _player, _position_index):
	# Update UI whenever a new player is spawned
	update_ui()

func _on_all_players_spawned():
	# Update UI once all players are spawned
	update_ui()

func _ready():
	if not game_manager:
		push_error("No GameManager assigned to RaceUI")
		return
		
	# Get network manager
	network_manager = get_node_or_null("/root/NetworkManager")
	
	# Connect to all relevant signals
	game_manager.race_completed.connect(_on_race_completed)
	game_manager.race_started.connect(_on_race_started)
	game_manager.race_in_progress_update.connect(_on_race_update)

	# Connect to player spawn signals if available
	if game_manager.player_spawner:
		game_manager.player_spawner.player_spawned.connect(_on_player_spawned)
		game_manager.player_spawner.all_players_spawned.connect(_on_all_players_spawned)

	# Initial UI update
	update_ui()

func _process(_delta):
	if game_manager and game_manager.is_race_in_progress:
		update_ui()

func update_ui():
	# Update player position list
	update_race_positions()
	
	# Update player's position
	var local_player_id = multiplayer.get_unique_id()
	var local_position = get_player_position(local_player_id)
	
	position_label.text = "Position: " + str(local_position) + "/" + str(race_positions.size())
	
	# Update lap count
	var local_player = get_player_by_id(local_player_id)
	if local_player and game_manager.player_laps.has(local_player):
		var current_lap = game_manager.player_laps[local_player]
		lap_label.text = "Lap: " + str(current_lap) + "/" + str(game_manager.laps_to_win)
	else:
		lap_label.text = "Lap: 0/" + str(game_manager.laps_to_win)
	
	# Update player list
	update_player_list()

func update_race_positions():
	race_positions.clear()
	
	# Get all players
	var players = get_tree().get_nodes_in_group(game_manager.player_group)
	
	# Check for empty player list
	if players.size() == 0:
		return
	
	# Create a temporary array with player data for easier sorting
	var player_data = []
	for player in players:
		var lap_count = 0
		if game_manager.player_laps.has(player):
			lap_count = game_manager.player_laps[player]
			
		var player_name = player.name
		if "player_name" in player:
			player_name = player.player_name
			
		player_data.append({
			"player": player,
			"laps": lap_count,
			"name": player_name
		})
	
	# Sort the player data by lap count (descending)
	player_data.sort_custom(func(a, b):
		if a.laps == b.laps:
			return a.name < b.name  # Alphabetical as tiebreaker
		return a.laps > b.laps
	)
	
	# Extract just the player objects in the correct order
	for data in player_data:
		race_positions.append(data.player)

func get_player_position(player_id):
	for i in range(race_positions.size()):
		var player = race_positions[i]
		if "player_id" in player and player.player_id == player_id:
			return i + 1
	
	return race_positions.size()

func get_player_by_id(player_id):
	for player in race_positions:
		if "player_id" in player and player.player_id == player_id:
			return player
	
	return null

func update_player_list():
	# Clear the list
	for child in player_list.get_children():
		child.queue_free()
	
	# Add all players to the list
	for i in range(race_positions.size()):
		var player = race_positions[i]
		var player_entry = HBoxContainer.new()
		
		# Position number
		var position_label = Label.new()
		position_label.text = str(i + 1) + ". "
		player_entry.add_child(position_label)
		
		# Player name
		var name_label = Label.new()
		var player_name = player.name
		if "player_name" in player:
			player_name = player.player_name
		name_label.text = player_name
		player_entry.add_child(name_label)
		
		# Lap count
		var lap_label = Label.new()
		var lap_count = 0
		if game_manager.player_laps.has(player):
			lap_count = game_manager.player_laps[player]
		lap_label.text = " (Lap " + str(lap_count) + ")"
		player_entry.add_child(lap_label)
		
		# Highlight local player
		if "player_id" in player and player.player_id == multiplayer.get_unique_id():
			player_entry.modulate = Color.YELLOW
		
		player_list.add_child(player_entry)

func _on_race_completed(player, time):
	# Remove any existing victory label
	remove_victory_label()
	
	# Show a simple victory message
	var victory_label = Label.new()
	victory_label.name = "VictoryLabel"
	
	var winner_name = player.name
	if "player_name" in player:
		winner_name = player.player_name
		
	victory_label.text = winner_name + " wins in " + str(time) + " seconds!"
	victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	victory_label.add_theme_font_size_override("font_size", 32)
	
	# Place it in the center of the screen
	victory_label.anchor_left = 0.5
	victory_label.anchor_top = 0.5
	victory_label.anchor_right = 0.5
	victory_label.anchor_bottom = 0.5
	victory_label.offset_left = -200
	victory_label.offset_top = -50
	victory_label.offset_right = 200
	victory_label.offset_bottom = 50
	
	add_child(victory_label)
	
func _on_race_started():
	# Remove any existing victory label
	remove_victory_label()
	
	# Force update of the leaderboard
	update_ui()

func remove_victory_label():
	var existing_label = get_node_or_null("VictoryLabel")
	if existing_label:
		existing_label.queue_free()

func _on_race_update():
	# Called when the game_manager emits race_in_progress_update
	update_ui()
