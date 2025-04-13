extends Node3D

signal pass_completed(player)

@onready var entry_area = $Entry
@onready var exit_area = $Exit

var players_in_checkpoint = []


func _on_entry_body_entered(body):
	# TODO: Detect if it's a player indeed
	if not body in players_in_checkpoint:
		players_in_checkpoint.append(body)
		print("Player entered checkpoint: ", body.name)


func _on_exit_body_entered(body):
	# TODO: Detect if it's a player indeed
	if body in players_in_checkpoint:
		players_in_checkpoint.erase(body)
		emit_signal("pass_completed", body)
		print("Pass completed by: ", body.name)


func _ready():
	entry_area.body_entered.connect(_on_entry_body_entered)
	exit_area.body_entered.connect(_on_exit_body_entered)
