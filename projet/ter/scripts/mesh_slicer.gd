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
	print("mesh vertexes count = ", mdt.get_vertex_count())
	print("mesh edge count = ", mdt.get_edge_count())
	print("mesh faces count = ", mdt.get_face_count())

	var intersection_points : PackedVector3Array = []
	var intersection_edges : Array = [] #sauvegarde les segments pour recréer les boucles

	var start := Time.get_ticks_msec()
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
			if visualizer.points_node2.visible:
				visualizer.show_points_3d(clip_tetrahedron, Color.YELLOW, visualizer.points_node2)
			var res := ClipPolygon.clip_polygon_3d(triangle, clip_tetrahedron, clip_indices)
			poly_left = res[0]
			if visualizer.points_node2.visible:
				visualizer.show_points_3d(poly_left, Color.BLACK, visualizer.points_node2)
			poly_right = res[1]
			if visualizer.points_node2.visible:
				for y in range(len(poly_right)):
					visualizer.show_points_3d(poly_right[y], Color.WHITE / (y+1), visualizer.points_node2)

		if poly_left.size() >= 3:
			add_poly_to_st(st_left, poly_left)
			if use_planes:
				for j in range(poly_left.size()):
					var p_curr = poly_left[j]
					var p_next = poly_left[(j + 1) % poly_left.size()]
					var dist_curr = abs(plane.distance_to(p_curr))
					var dist_next = abs(plane.distance_to(p_next))
					
					# recup les points
					if dist_curr < 0.001:
						intersection_points.append(p_curr)
					
					# recup les segments connectes pour concave
					if dist_curr < 0.001 and dist_next < 0.001:
						intersection_edges.append([p_curr, p_next])

		if use_planes:
			if poly_right.size() >= 3:
				add_poly_to_st(st_right, poly_right)
		else:
			for piece in poly_right:
				add_poly_to_st(st_right, piece)
	var delta := Time.get_ticks_msec() - start
	print("mesh slicing = ", delta, " ms")

	if use_planes && intersection_points.size() >= 3:
		# Utilisation de la nouvelle fonction qui gère le concave
		PieceCreator.fill_cut_hole_concave(st_left, intersection_edges, plane)
		PieceCreator.fill_cut_hole_concave(st_right, intersection_edges, -plane)
	else:
		var mdt2 = MeshDataTool.new()
		var array = st_left.commit_to_arrays()
		var arr_mesh = ArrayMesh.new()
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, array)
		mdt2.create_from_surface(arr_mesh, 0)
		var deduplicated_indexes: PackedInt32Array
		var deduplicated_points: PackedVector3Array
		print("point avant déduplication = ", mdt2.get_vertex_count())
		for v in range(mdt2.get_vertex_count()):
			var vertex := mdt2.get_vertex(v)
			if vertex not in deduplicated_points:
				deduplicated_indexes.append(v)
				deduplicated_points.append(vertex)
		print("point après déduplication = ", deduplicated_points.size())
		for i in range(0, len(clip_indices), 3):
			start = Time.get_ticks_msec()
			var triangle := [clip_tetrahedron[clip_indices[i]], clip_tetrahedron[clip_indices[i + 1]], clip_tetrahedron[clip_indices[i + 2]]]
			var ab = triangle[1] - triangle[0]
			var ac = triangle[2] - triangle[0]
			var normal = ac.cross(ab).normalized()
			var plane2 = Plane(normal, triangle[0])
			intersection_points.clear()
			for p in deduplicated_indexes:
				if ClipPolygon.distance_to_triangle(mdt2.get_vertex(p), triangle) < 0.001:
					intersection_points.append(mdt2.get_vertex(p))
			delta = Time.get_ticks_msec() - start
			print("compute intersection sans clipper = ", delta, " ms")
			print("intersection points sans clipper = ", intersection_points.size())
			start = Time.get_ticks_msec()
			for v in triangle:
				var inside := true
				var distances: Array[float] = []
				for v2 in range(mdt.get_vertex_count()):
					distances.append((mdt.get_vertex(v2) - v).length_squared())

				var closest_vertex := ClipPolygon.mins_arr(distances)
				print(closest_vertex)
				for closest_index in closest_vertex:
					if visualizer.points_node2.visible:
						visualizer.show_points_3d([mdt.get_vertex(closest_index)], Color.RED, visualizer.points_node2)

					for t in mdt.get_vertex_faces(closest_index):
						if visualizer.points_node2.visible:
							for j in range(3):
								visualizer.show_points_3d([mdt.get_vertex(mdt.get_face_vertex(t, j))], Color.PURPLE, visualizer.points_node2)
						var normal_t := mdt.get_face_normal(t)
						if normal_t.length_squared() == 0: continue
						if (v - mdt.get_vertex(closest_index)).dot(normal_t) > 0:
							inside = false
							break

				if inside:
					intersection_points.append(v)
			print("intersection points = ", intersection_points.size())
			delta = Time.get_ticks_msec() - start
			print("compute intersection clipper = ", delta, " ms")
			if intersection_points.size() >= 3:
				if visualizer.points_node2.visible:
					visualizer.show_points_3d(intersection_points, Color.RED, visualizer.points_node2)
				PieceCreator.fill_cut_hole(st_left, intersection_points, plane2)
				PieceCreator.fill_cut_hole(st_right, intersection_points, -plane2)

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
