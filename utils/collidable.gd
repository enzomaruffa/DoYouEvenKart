extends Node3D

@export var collision_weight = 1.0  # How much this object affects others when colliding (1.0 = normal)
@export var collision_bounce = 1.0  # How bouncy collisions are (1.0 = normal)

func _ready():
	# Add parent to collidable group
	get_parent().add_to_group("collidable")
	
	# Set up properties on parent if it can access them
	if get_parent().has_method("set"):
		if get_parent().get("collision_weight") == null:
			get_parent().set("collision_weight", collision_weight)
		
		if get_parent().get("collision_bounce") == null:
			get_parent().set("collision_bounce", collision_bounce)

func apply_bump(bump_force):
	# If parent is a physics body, apply the force directly
	if get_parent() is PhysicsBody3D:
		if get_parent().has_method("apply_central_impulse"):
			get_parent().apply_central_impulse(bump_force)
		elif get_parent().has_method("immediate_bump"):
			get_parent().immediate_bump(bump_force)
		elif get_parent() is CharacterBody3D:
			get_parent().velocity += bump_force