extends Control

@onready var player_list = $VBoxContainer/PlayerList
@onready var start_button = $VBoxContainer/StartButton
@onready var back_button = $VBoxContainer/BackButton
@onready var ip_address_label = $VBoxContainer/ServerInfo/IPAddress
@onready var ready_button = $VBoxContainer/ReadyButton

var network_manager = null

func _ready():
	# Get the singleton instance of NetworkManager
	network_manager = get_node("/root/NetworkManager")
	
	# Connect signals
	if network_manager:
		network_manager.lobby_updated.connect(_on_lobby_updated)
		network_manager.game_started.connect(_on_game_started)
	
	# Update display
	update_lobby_display()
	
	# Show or hide buttons based on whether we're the host
	var is_host = multiplayer.is_server()
	start_button.visible = is_host
	
	# Display IP address if we're the host
	if is_host:
		ip_address_label.text = "Server IP: " + get_local_ip()
	else:
		ip_address_label.text = "Connected to server"

func get_local_ip():
	var ip = ""
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10.") or address.begins_with("172."):
			ip = address
			break
			
	if ip.is_empty():
		ip = "localhost"
		
	return ip

func update_lobby_display():
	# Clear the list
	for child in player_list.get_children():
		child.queue_free()
	
	# Add all players to the list
	for id in network_manager.players:
		var player_info = network_manager.players[id]
		var player_entry = HBoxContainer.new()
		
		# Color indicator
		var color_rect = ColorRect.new()
		color_rect.custom_minimum_size = Vector2(24, 24)
		color_rect.color = player_info.color
		player_entry.add_child(color_rect)
		
		# Player name
		var name_label = Label.new()
		name_label.text = player_info.name
		player_entry.add_child(name_label)
		
		# Ready status
		var ready_label = Label.new()
		ready_label.text = " [READY]" if player_info.ready else " [NOT READY]"
		ready_label.modulate = Color.GREEN if player_info.ready else Color.RED
		player_entry.add_child(ready_label)
		
		# Host indicator
		if id == 1:  # Host is always ID 1
			var host_label = Label.new()
			host_label.text = " [HOST]"
			player_entry.add_child(host_label)
		
		player_list.add_child(player_entry)
	
	# Update start button state
	if multiplayer.is_server():
		start_button.disabled = !network_manager.is_everyone_ready()

func _on_lobby_updated():
	update_lobby_display()

func _on_start_button_pressed():
	if multiplayer.is_server() and network_manager.is_everyone_ready():
		# Start the game on all clients
		network_manager.rpc("start_game")
		_on_game_started()

func _on_ready_button_pressed():
	var my_id = multiplayer.get_unique_id()
	var is_ready = !network_manager.players[my_id].ready
	
	# Update our ready status
	network_manager.rpc("set_player_ready", is_ready)

func _on_back_button_pressed():
	# Disconnect from the server
	network_manager.disconnect_from_game()
	
	# Return to main menu
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

func _on_game_started():
	# Change to the multiplayer game scene
	get_tree().change_scene_to_file("res://scenes/multiplayer_track.tscn")