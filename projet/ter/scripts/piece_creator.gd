class_name PieceCreator
extends RefCounted

var pieces_node: Node3D
var use_planes: bool

func _init(pieces_n: Node3D, use_p: bool):
	pieces_node = pieces_n
	use_planes = use_p

static func fill_cut_hole(st: SurfaceTool, points: PackedVector3Array, plane: Plane):
	var start := Time.get_ticks_msec()
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

	var delta := Time.get_ticks_msec() - start
	print("fill_cut_hole = ", delta, " ms")
	#LA IL FAUT RAJOUTER POUR LES UVs MAIS DUR A OPTI

#pour les meshs concaves !!!
static func fill_cut_hole_concave(st: SurfaceTool, edges: Array, plane: Plane):
	var start := Time.get_ticks_msec()
	if edges.is_empty(): return

	# on fait des boucles avec les aretes
	var loops := []
	var remaining_edges = edges.duplicate()

	while remaining_edges.size() > 0:
		var current_loop = PackedVector3Array()
		var edge = remaining_edges.pop_front()
		current_loop.append(edge[0])
		current_loop.append(edge[1])

		var closed = false
		while not closed and remaining_edges.size() > 0:
			var found_next = false
			var last_pt = current_loop[-1]
			for i in range(remaining_edges.size()):
				var e = remaining_edges[i]
				if last_pt.distance_to(e[0]) < 0.001:
					current_loop.append(e[1])
					remaining_edges.remove_at(i)
					found_next = true
					break
				elif last_pt.distance_to(e[1]) < 0.001:
					current_loop.append(e[0])
					remaining_edges.remove_at(i)
					found_next = true
					break
			if not found_next:
				break
			if current_loop[0].distance_to(current_loop[-1]) < 0.001:
				closed = true
		loops.append(current_loop)

	# plan proj
	var v_up := plane.normal.cross(Vector3.RIGHT if abs(plane.normal.x) < 0.9 else Vector3.FORWARD).normalized()
	var v_right := plane.normal.cross(v_up).normalized()

	# on triangule chaque trous
	for loop in loops:
		var loop_points = loop
		#enleve le dernier point car pas necessaire
		if loop_points.size() > 0 and loop_points[0].distance_to(loop_points[-1]) < 0.001:
			loop_points.remove_at(loop_points.size() - 1)
			
		if loop_points.size() < 3:
			continue

		var points_2d := PackedVector2Array()
		for p in loop_points:
			points_2d.append(Vector2(p.dot(v_right), p.dot(v_up)))

		var indices := Geometry2D.triangulate_polygon(points_2d)
		if indices.is_empty():
			continue

		for i in range(0, indices.size(), 3):
			st.add_vertex(loop_points[indices[i]])
			st.add_vertex(loop_points[indices[i+1]])
			st.add_vertex(loop_points[indices[i+2]])

	var delta := Time.get_ticks_msec() - start
	print("fill_cut_hole_concave = ", delta, " ms")


func create_piece(m: Mesh, t: Transform3D, velocity: Vector3, offset: Vector3, is_left: bool, impact_point: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var start := Time.get_ticks_msec()

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

	var delta := Time.get_ticks_msec() - start
	print("create_piece = ", delta, " ms")

	return new_mesh_inst
