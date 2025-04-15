extends Control

@onready var host_button = $VBoxContainer/HostButton
@onready var join_button = $VBoxContainer/JoinButton
@onready var ip_address = $VBoxContainer/IPAddress
@onready var port = $VBoxContainer/Port
@onready var player_name = $VBoxContainer/PlayerName
@onready var color_picker = $VBoxContainer/ColorPicker
@onready var error_label = $VBoxContainer/ErrorLabel

var network_manager = null

func _ready():
	network_manager = get_node("/root/NetworkManager")
	
	if network_manager:
		network_manager.connection_succeeded.connect(_on_connection_success)
		network_manager.connection_failed.connect(_on_connection_failed)
		network_manager.server_disconnected.connect(_on_server_disconnected)
	
	player_name.text = "Player" + str(randi() % 1000)
	
	var random_color = Color(randf(), randf(), randf())
	color_picker.color = random_color
	
	error_label.hide()

func _on_host_button_pressed():
	error_label.hide()
	
	if player_name.text.strip_edges().is_empty():
		error_label.text = "Please enter a player name"
		error_label.show()
		return
	
	if port.text.strip_edges().is_empty():
		error_label.text = "Please enter a port number"
		error_label.show()
		return
	
	var port_number = int(port.text.strip_edges())
	var error = network_manager.create_server(player_name.text, color_picker.color, port_number)
	
	if error != OK:
		error_label.text = "Could not create server"
		error_label.show()
		return
	
	# Switch to lobby scene
	get_tree().change_scene_to_file("res://ui/lobby.tscn")

func _on_join_button_pressed():
	error_label.hide()
	
	if player_name.text.strip_edges().is_empty():
		error_label.text = "Please enter a player name"
		error_label.show()
		return
	
	if ip_address.text.strip_edges().is_empty():
		error_label.text = "Please enter an IP address"
		error_label.show()
		return
	
	if port.text.strip_edges().is_empty():
		error_label.text = "Please enter a port number"
		error_label.show()
		return
	
	var ip = ip_address.text.strip_edges()
	var port_number = int(port.text.strip_edges())
	var error = network_manager.join_server(ip, port_number, player_name.text, color_picker.color)
	
	if error != OK:
		error_label.text = "Could not connect to server"
		error_label.show()
		return
	
	# Disable buttons while connecting
	host_button.disabled = true
	join_button.disabled = true
	error_label.text = "Connecting..."
	error_label.show()

func _on_connection_success():
	# Switch to lobby scene
	get_tree().change_scene_to_file("res://ui/lobby.tscn")

func _on_connection_failed():
	host_button.disabled = false
	join_button.disabled = false
	error_label.text = "Connection failed!"
	error_label.show()

func _on_server_disconnected():
	host_button.disabled = false
	join_button.disabled = false
	error_label.text = "Server disconnected!"
	error_label.show()