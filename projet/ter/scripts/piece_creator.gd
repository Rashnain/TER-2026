class_name PieceCreator
extends RefCounted

var pieces_node: Node3D
var use_planes: bool

func _init(pieces_n: Node3D, use_p: bool):
	pieces_node = pieces_n
	use_planes = use_p

static func fill_cut_hole(st: SurfaceTool, points: PackedVector3Array, plane: Plane):
	if points.size() < 3: return
	# calcul centre du trou
	var center := Vector3.ZERO
	for p in points: center += p
	center /= points.size()
	# creation du plan pour projeter les points
	var v_up := plane.normal.cross(Vector3.RIGHT if abs(plane.normal.x) < 0.9 else Vector3.FORWARD).normalized()
	var v_right := plane.normal.cross(v_up).normalized()
	# on tri les points pour faire le contour correctement
	var sorted_points := Array(points)
	sorted_points.sort_custom(func(a, b):
		var da = a - center
		var db = b - center
		return atan2(da.dot(v_up), da.dot(v_right)) < atan2(db.dot(v_up), db.dot(v_right))
	)
	# on passe les point3D en 2D pour faciliter
	var points_2d := PackedVector2Array()
	for p in sorted_points:
		points_2d.append(Vector2(p.dot(v_right), p.dot(v_up)))
	# ear clipping -> renvoie une liste d'indice par trois pour les triangles
	var indices := Geometry2D.triangulate_polygon(points_2d)
	if indices.is_empty():
		return
	# on assemble
	for i in range(0, indices.size(), 3):
		var p1 = sorted_points[indices[i]]
		var p2 = sorted_points[indices[i+1]]
		var p3 = sorted_points[indices[i+2]]
		st.add_vertex(p1)
		st.add_vertex(p2)
		st.add_vertex(p3)
	
	#LA IL FAUT RAJOUTER POUR LES UVs MAIS DUR A OPTI

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
