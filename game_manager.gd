# game_manager.gd
class_name GameManager
extends Node

signal race_completed(player, time)
signal race_started

@export var race_line: RaceLine
@export var laps_to_win: int = 3
@export var restart_delay: float = 1.0
@export var race_start_delay: float = 2.0
@export var player_group: String = "players"  # Group name for players

var player_laps = {}
var race_started = false
var race_start_time = 0
var race_in_progress = false

func _ready():
	if race_line:
		race_line.pass_completed.connect(_on_lap_completed)
	else:
		push_error("No RaceLine assigned to GameManager")

	start_race()

func start_race():
	player_laps.clear()

	position_players_at_start()

	race_started = true
	race_in_progress = true
	race_start_time = Time.get_ticks_msec()
	print("Race started!")
	
	emit_signal("race_started")

func position_players_at_start():
	if race_line:
		# Use the race_line's built-in positioning method
		race_line.position_players_at_start(player_group)
	else:
		push_error("No race_line assigned to GameManager")

func _on_lap_completed(player):
	if not race_in_progress:
		return

	if not player_laps.has(player):
		player_laps[player] = 0

	player_laps[player] += 1

	print("Player " + player.name + " completed lap " + str(player_laps[player]))

	if player_laps[player] >= laps_to_win:
		_on_race_won(player)

func _on_race_won(player):
	race_in_progress = false

	var race_time = (Time.get_ticks_msec() - race_start_time) / 1000.0
	var player_name = "Unknown"
	
	# Get player name if available
	if "player_name" in player:
		player_name = player.player_name
	else:
		player_name = player.name
		
	print("Player " + player_name + " won the race in " + str(race_time) + " seconds!")

	emit_signal("race_completed", player, race_time)
	
	# Only the server should restart the race in multiplayer
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		restart_race()


func restart_race():
	get_tree().paused = true
	await get_tree().create_timer(restart_delay).timeout
	start_race()
	await get_tree().create_timer(race_start_delay).timeout
	get_tree().paused = false
