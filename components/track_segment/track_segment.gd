# track_segment.gd
@tool
class_name TrackSegment
extends StaticBody3D

@export var track_material: TrackMaterial
@export var custom_mesh: Mesh:
	set(value):
		custom_mesh = value
		_update_mesh()
@export var use_mesh_for_collision: bool = true:
	set(value):
		use_mesh_for_collision = value
		_update_collision()
@export var use_checkered_pattern: bool = false:
	set(value):
		use_checkered_pattern = value
		_update_material()

func _enter_tree():
	print(name, "TrackSegment: Entering tree")
	if Engine.is_editor_hint():
		_ensure_children()
		_update_mesh()
		_update_material()
		_update_collision()

func _ready():
	print(name, "TrackSegment: Ready")
	_ensure_children()
	_update_mesh()
	_update_material()
	_update_collision()

func _ensure_children():
	print(name, "TrackSegment: Ensuring children")
	if not has_node("CollisionShape3D"):
		var collision = CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		add_child(collision)
		if Engine.is_editor_hint():
			collision.owner = get_tree().edited_scene_root

	print(name, "TrackSegment: Ensuring children - CollisionShape3D added")
	if not has_node("MeshInstance3D"):
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "MeshInstance3D"
		add_child(mesh_instance)
		if Engine.is_editor_hint():
			mesh_instance.owner = get_tree().edited_scene_root

func _update_mesh():
	print(name, "TrackSegment: Updating mesh")
	if not has_node("MeshInstance3D"):
		return

	if custom_mesh:
		$MeshInstance3D.mesh = custom_mesh
		$MeshInstance3D.transform = Transform3D.IDENTITY
		_update_material()

func _update_material():
	print(name, "TrackSegment: Updating material")
	if not has_node("MeshInstance3D") or not custom_mesh:
		return

	if use_checkered_pattern:
		$MeshInstance3D.material_override = create_checkered_material()
	elif track_material and track_material.visual_material:
		$MeshInstance3D.material_override = track_material.visual_material

func create_checkered_material():
	var material = StandardMaterial3D.new()

	# Create a simple 2x2 checkered texture
	var img = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(0.1, 0.1, 0.1))
	img.set_pixel(1, 0, Color(0.9, 0.9, 0.9))
	img.set_pixel(0, 1, Color(0.9, 0.9, 0.9))
	img.set_pixel(1, 1, Color(0.1, 0.1, 0.1))

	var texture = ImageTexture.create_from_image(img)
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	# Set UV scale based on mesh size
	var mesh_size = custom_mesh.get_aabb().size
	var checker_size = 1.0 # Default to 1 unit squares
	var checkers_x = mesh_size.x / checker_size
	var checkers_z = mesh_size.z / checker_size
	material.uv1_scale = Vector3(checkers_x / 2, checkers_z / 2, 1.0)

	return material

func _update_collision():
	print(name, "TrackSegment: Updating collision")
	if not has_node("CollisionShape3D") or not custom_mesh:
		return

	if use_mesh_for_collision:
		var shape = ConcavePolygonShape3D.new()
		var mesh_faces = custom_mesh.get_faces()
		if mesh_faces.size() > 0:
			shape.set_faces(mesh_faces)
			$CollisionShape3D.shape = shape
			$CollisionShape3D.transform = Transform3D.IDENTITY

func get_track_material() -> TrackMaterial:
	return track_material