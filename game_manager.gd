# game_manager.gd
class_name GameManager
extends Node

signal race_completed(player, time)

@export var race_line: RaceLine
@export var laps_to_win: int = 3
@export var restart_delay: float = 1.0
@export var race_start_delay: float = 2.0
@export var player_group: String = "players"  # Group name for players
@export var starting_grid_width: float = 5.0  # Width of zigzag pattern
@export var grid_spacing: float = 2.0  # Space between cars in grid

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

func position_players_at_start():
	var players = get_tree().get_nodes_in_group(player_group)

	if players.size() == 0:
		push_error("No players found in group: " + player_group)
		return

	var start_pos = race_line.global_position
	var forward_dir = -race_line.get_global_transform().basis.x  # Use -X as forward
	var right_dir = -race_line.get_global_transform().basis.z    # Use -Z as right

	for i in range(players.size()):
		var player = players[i]

		var row = i / 2
		var column = i % 2

		var offset = forward_dir * (row * grid_spacing)
		offset += right_dir * (column * starting_grid_width - starting_grid_width/2)

		player.global_position = start_pos + offset + Vector3(0, 2, 0)  # Slightly above ground

		player.look_at(start_pos)

		if player is RigidBody3D:
			player.linear_velocity = Vector3.ZERO
			player.angular_velocity = Vector3.ZERO

		print("Positioned player " + player.name + " at " + str(player.global_position))

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
	print("Player " + player.name + " won the race in " + str(race_time) + " seconds!")

	emit_signal("race_completed", player, race_time)

	restart_race()


func restart_race():
	get_tree().paused = true
	await get_tree().create_timer(restart_delay).timeout
	start_race()
	await get_tree().create_timer(race_start_delay).timeout
	get_tree().paused = false
