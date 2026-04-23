class_name MeshSlicer
extends RefCounted

var use_planes: bool
var clip_tetrahedron: PackedVector3Array
var clip_indices: Array[int]
var visualizer: Visualizer  

func _init(use_p: bool, clip_tet: PackedVector3Array, clip_ind: Array[int], vis: Visualizer):
	use_planes = use_p
	clip_tetrahedron = clip_tet
	clip_indices = clip_ind
	visualizer = vis

func slice_object(mesh_instance: MeshInstance3D, points: PackedVector3Array, depth: int, piece_creator: PieceCreator):
	if depth <= 0 or mesh_instance == null:
		return

	var array_mesh: ArrayMesh
	if mesh_instance.mesh is PrimitiveMesh:
		array_mesh = ArrayMesh.new()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_instance.mesh.get_mesh_arrays())
	else:
		array_mesh = mesh_instance.mesh

	if points.size() < 2: return
	var p1 = points[0]
	var p2 = points[1]
	var plane_normal = (p1 - p2).normalized()
	plane_normal = (plane_normal + Vector3(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), randf_range(-0.1, 0.1))).normalized() #on rajoute un peu d'aléatoire
	var plane_point = (p1 + p2) / 2.0 #on trouve le centre du plan (sinon par defaut c'est l'origine du monde)
	var plane := Plane(plane_normal, plane_point)

	points.remove_at(0)
	points.remove_at(0)

	var st_left := SurfaceTool.new()
	var st_right := SurfaceTool.new()
	st_left.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_right.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mdt = MeshDataTool.new()
	mdt.create_from_surface(array_mesh, 0)

	var intersection_points : PackedVector3Array = []

	for i in range(mdt.get_face_count()):
		var v1 := mdt.get_vertex(mdt.get_face_vertex(i, 0))
		var v2 := mdt.get_vertex(mdt.get_face_vertex(i, 1))
		var v3 := mdt.get_vertex(mdt.get_face_vertex(i, 2))
		var triangle := PackedVector3Array([v1, v2, v3])

		var poly_left
		var poly_right	
		if use_planes:
			poly_left = Geometry3D.clip_polygon(triangle, plane)
			poly_right = Geometry3D.clip_polygon(triangle, -plane)
		else:
			visualizer.show_points_3d(clip_tetrahedron, Color.YELLOW, visualizer.points_node2)
			var res := ClipPolygon.clip_polygon_3d(triangle, clip_tetrahedron, clip_indices)
			poly_left = res[0]
			visualizer.show_points_3d(poly_left, Color.BLACK, visualizer.points_node2)
			poly_right = res[1]
			for y in range(len(poly_right)):
				visualizer.show_points_3d(poly_right[y], Color.WHITE / (y+1), visualizer.points_node2)

		if poly_left.size() >= 3:
			add_poly_to_st(st_left, poly_left)
			if use_planes:
				for p in poly_left:
					if abs(plane.distance_to(p)) < 0.001:
						intersection_points.append(p)

		if use_planes:
			if poly_right.size() >= 3:
				add_poly_to_st(st_right, poly_right)
		else:
			for piece in poly_right:
				add_poly_to_st(st_right, piece)

	if use_planes && intersection_points.size() >= 3:
		fill_cut_hole(st_left, intersection_points, plane)
		fill_cut_hole(st_right, intersection_points, -plane)
	else:
		for i in range(0, len(clip_indices), 3):
			#i = 2 * 3
			var triangle := [clip_tetrahedron[clip_indices[i]], clip_tetrahedron[clip_indices[i + 1]], clip_tetrahedron[clip_indices[i + 2]]]
			var ab = triangle[1] - triangle[0]
			var ac = triangle[2] - triangle[0]
			var normal = ac.cross(ab).normalized()
			#var normal = ab.cross(ac).normalized()
			#print("normal = ", normal)
			var plane2 = Plane(normal, triangle[0])
			intersection_points.clear()
			var mdt2 = MeshDataTool.new()
			var array = st_left.commit_to_arrays()
			var arr_mesh = ArrayMesh.new()
			arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, array)
			mdt2.create_from_surface(arr_mesh, 0)
			#var mean = (triangle[2] + triangle[1] + triangle[2]) / 3
			#print("points = ", mdt2.get_vertex_count())
			# TODO dé-dupliquer les points (pour améliorer les perfs)
			for p in range(mdt2.get_vertex_count()):
				#print(ClipPolygon.distance_to_triangle(mdt2.get_vertex(p), triangle))
				#if abs(Plane(normal, mean).distance_to(mdt2.get_vertex(p))) < 0.001 \
					#&& ClipPolygon.distance_to_triangle(mdt2.get_vertex(p), triangle) < 0.001:
				if ClipPolygon.distance_to_triangle(mdt2.get_vertex(p), triangle) < 0.001:
					intersection_points.append(mdt2.get_vertex(p))
			print("intersection_points.size() = ", intersection_points.size())
			if intersection_points.size() >= 3:
				visualizer.show_points_3d(intersection_points, Color.RED, visualizer.points_node2)
				fill_cut_hole(st_left, intersection_points, plane2)
				fill_cut_hole(st_right, intersection_points, -plane2)
			#break

	var mesh_left = finalize_st(st_left)
	var mesh_right = finalize_st(st_right)

	var parent_body = mesh_instance.get_parent()
	var velocity = parent_body.linear_velocity if parent_body is RigidBody3D else Vector3.ZERO
	var trans = mesh_instance.global_transform

	var mi3d_left = piece_creator.create_piece(mesh_left, trans, velocity, plane.normal * 0.005, true, plane_point)
	var mi3d_right = piece_creator.create_piece(mesh_right, trans, velocity, -plane.normal * 0.005, false, plane_point)

	if use_planes:
		parent_body.queue_free()

		if points.size() >= 2:
			if mi3d_left: slice_object(mi3d_left, points.duplicate(), depth - 1, piece_creator)
			if mi3d_right: slice_object(mi3d_right, points.duplicate(), depth - 1, piece_creator)

func fill_cut_hole(st: SurfaceTool, points: PackedVector3Array, plane: Plane):
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

func finalize_st(st: SurfaceTool) -> Mesh:
	st.index()
	st.generate_normals()
	#st.generate_tangents() #il faut les Uvs pour ça
	return st.commit()

func add_poly_to_st(st: SurfaceTool, poly: PackedVector3Array):
	# fan triangulation
	for i in range(1, poly.size() - 1):
		st.add_vertex(poly[0])
		st.add_vertex(poly[i])
		st.add_vertex(poly[i+1])
