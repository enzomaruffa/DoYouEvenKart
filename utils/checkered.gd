extends Node3D

# Creates a world-space checkered pattern where each square 
# is exactly checker_size units in the world (e.g., 1 meter squares)
func create_uv_based_checkered_material(checker_size = 1.0, color1 = Color(0.1, 0.1, 0.1), color2 = Color(0.9, 0.9, 0.9)):
	var material = StandardMaterial3D.new()
	
	# Create a simple 2x2 checkered texture (4 pixels total)
	var img = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, color1)
	img.set_pixel(1, 0, color2)
	img.set_pixel(0, 1, color2)
	img.set_pixel(1, 1, color1)
	
	var texture = ImageTexture.create_from_image(img)
	
	material.albedo_texture = texture
	
	# Disable texture filtering for sharp edges
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	
	# Calculate UV scale based on mesh size and desired checker size
	var ground_mesh = $StaticBody3D/GroundMesh
	var mesh_size = ground_mesh.mesh.get_aabb().size
	
	# If we want 1 meter checkers on a 10x10 plane, we need 10 checkers
	var checkers_x = mesh_size.x / checker_size
	var checkers_z = mesh_size.z / checker_size
	
	# Set UV scale to get the right number of checkers
	material.uv1_scale = Vector3(checkers_x/2, checkers_z/2, 1.0)
	
	return material

func _ready():
	var ground_mesh = $StaticBody3D/GroundMesh
	
	# Create a checkered material where each square is 2 units (meters) in size
	var material = create_uv_based_checkered_material(2.0)
	
	# Apply material to mesh
	ground_mesh.material_override = material
	
	print("World-space checkered material applied!")
