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
	"ready": false,
	"id": -1,
}

func _ready():
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func create_server(player_name, player_color, custom_port = DEFAULT_PORT):
	my_info.name = player_name
	my_info.color = player_color
	my_info.id = multiplayer.get_unique_id()
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(custom_port, MAX_PLAYERS)
	
	if error != OK:
		print(multiplayer.get_unique_id(), ": Failed to create server: ", error)
		return error
		
	multiplayer.multiplayer_peer = peer
	
	# Add our own player to the list
	rpc("register_player", my_info)
	return OK

func join_server(ip, port, player_name, player_color):
	my_info.name = player_name
	my_info.color = player_color
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, port)
	
	if error != OK:
		print(multiplayer.get_unique_id(), ": Failed to join server: ", error)
		return error
		
	multiplayer.multiplayer_peer = peer
	my_info.id = multiplayer.get_unique_id()
	return OK

func _on_player_connected(id):
	print(multiplayer.get_unique_id(), ": Player connected: ", id)
	# Request player info from the new client
	rpc_id(id, "register_player", my_info)

func _on_player_disconnected(id):
	print(multiplayer.get_unique_id(), ": Player disconnected: ", id)
	if players.has(id):
		players.erase(id)
		
	emit_signal("player_disconnected", id)
	emit_signal("lobby_updated")

func _on_connected_to_server():
	emit_signal("connection_succeeded")

func _on_connection_failed():
	print(multiplayer.get_unique_id(), ": Connection failed!")
	multiplayer.multiplayer_peer = null
	emit_signal("connection_failed")

func _on_server_disconnected():
	print(multiplayer.get_unique_id(), ": Server disconnected!")
	multiplayer.multiplayer_peer = null
	players.clear()
	emit_signal("server_disconnected")

@rpc("any_peer", "call_local", "reliable")
func register_player(info):
	var sender_id = multiplayer.get_remote_sender_id()

	print(multiplayer.get_unique_id(), ": Registering player: ", info)
	
	# Store player info
	add_player(info)
	
	# If we're the host, sync all existing players to the new player
	if multiplayer.is_server():
		for id in players:
			if id == multiplayer.get_unique_id():
				continue # Don't send our own info to ourselves
			rpc_id(id, "register_player", players[id])

func add_player(info):
	players[info.id] = info
	emit_signal("player_connected", info.id, info)
	emit_signal("lobby_updated")

@rpc("any_peer", "call_local", "reliable")
func set_player_ready(is_ready):
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
