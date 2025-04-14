# class_name NetworkManager
extends Node

signal player_connected(id, player_info)
signal player_disconnected(id)
signal server_disconnected
signal connection_failed
signal connection_succeeded
signal lobby_updated
signal game_started

const DEFAULT_PORT = 10567
const MAX_PLAYERS = 8

var peer = null
var players = {}
var players_ready = {}
var my_info = {
	"name": "",
	"color": Color.BLUE,
	"ready": false
}

func _ready():
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func create_server(player_name, player_color):
	my_info.name = player_name
	my_info.color = player_color
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT, MAX_PLAYERS)
	
	if error != OK:
		print("Failed to create server: ", error)
		return error
		
	multiplayer.multiplayer_peer = peer
	
	# Add our own player to the list
	add_player(1, my_info)
	return OK

func join_server(ip, player_name, player_color):
	my_info.name = player_name
	my_info.color = player_color
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, DEFAULT_PORT)
	
	if error != OK:
		print("Failed to join server: ", error)
		return error
		
	multiplayer.multiplayer_peer = peer
	return OK

func _on_player_connected(id):
	print("Player connected: ", id)
	# Request player info from the new client
	rpc_id(id, "register_player", my_info)

func _on_player_disconnected(id):
	print("Player disconnected: ", id)
	if players.has(id):
		players.erase(id)
		
	emit_signal("player_disconnected", id)
	emit_signal("lobby_updated")

func _on_connected_to_server():
	print("Connected to server!")
	emit_signal("connection_succeeded")

func _on_connection_failed():
	print("Connection failed!")
	multiplayer.multiplayer_peer = null
	emit_signal("connection_failed")

func _on_server_disconnected():
	print("Server disconnected!")
	multiplayer.multiplayer_peer = null
	players.clear()
	emit_signal("server_disconnected")

@rpc("any_peer", "call_local", "reliable")
func register_player(info):
	var sender_id = multiplayer.get_remote_sender_id()
	
	# Store player info
	add_player(sender_id, info)
	
	# If we're the host, sync all existing players to the new player
	if multiplayer.is_server():
		for id in players:
			rpc_id(sender_id, "register_player", players[id])

func add_player(id, info):
	players[id] = info
	emit_signal("player_connected", id, info)
	emit_signal("lobby_updated")

@rpc("any_peer", "call_local", "reliable")
func set_player_ready(is_ready):
	print("set_player_ready: ", is_ready)
	var sender_id = multiplayer.get_remote_sender_id()
	
	if sender_id == 0: # This is us
		my_info.ready = is_ready
		players[multiplayer.get_unique_id()].ready = is_ready
	else:
		players[sender_id].ready = is_ready
	
	emit_signal("lobby_updated")

func is_everyone_ready():
	# if players.size() < 2:
	# 	return false
		
	for id in players:
		if not players[id].ready:
			return false
	
	return true

@rpc("authority", "reliable")
func start_game():
	emit_signal("game_started")

func disconnect_from_game():
	if peer != null:
		peer.close()
		
	multiplayer.multiplayer_peer = null
	players.clear()
	players_ready.clear()
