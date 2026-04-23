class_name PieceCreator
extends RefCounted

var pieces_node: Node3D
var use_planes: bool

func _init(pieces_n: Node3D, use_p: bool):
	pieces_node = pieces_n
	use_planes = use_p

func create_piece(m: Mesh, t: Transform3D, velocity: Vector3, offset: Vector3, is_left: bool, impact_point: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	if m.get_surface_count() == 0 or m.get_aabb().size.length() < 0.01:
		return null

	var new_body = RigidBody3D.new()
	var new_mesh_inst = MeshInstance3D.new()
	var new_shape = CollisionShape3D.new()

	new_mesh_inst.mesh = m
	new_shape.shape = m.create_convex_shape()

	var mesh_size = m.get_aabb().size	#si le morceau est plus petit que 5cm, on crée passs
	if mesh_size.length() < 0.1: 
		return null

	var mat := StandardMaterial3D.new()
	# Correction Aliasing : textures et ombres
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = Color.PURPLE if is_left else Color.PINK

	new_mesh_inst.material_override = mat
	new_body.add_child(new_mesh_inst)
	new_body.add_child(new_shape)

	pieces_node.add_child(new_body)
	new_body.global_transform = t
	new_body.global_translate(offset)
	new_body.linear_velocity = velocity
	if use_planes && impact_point != Vector3.ZERO:
		var push_direction = offset.normalized()
		var force = 2000.0 
		new_body.apply_impulse(push_direction * force)

	new_body.global_transform = t
	new_body.global_translate(offset)
	new_body.linear_velocity = velocity

	return new_mesh_inst
