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
	var start := Time.get_ticks_msec()

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

	var delta := Time.get_ticks_msec() - start
	print("avant mesh slicing = ", delta, " ms")
	start = Time.get_ticks_msec()
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
				for p in poly_left:
					if abs(plane.distance_to(p)) < 0.001:
						intersection_points.append(p)

		if use_planes:
			if poly_right.size() >= 3:
				add_poly_to_st(st_right, poly_right)
		else:
			for piece in poly_right:
				add_poly_to_st(st_right, piece)
	delta = Time.get_ticks_msec() - start
	print("mesh slicing = ", delta, " ms")

	if use_planes && intersection_points.size() >= 3:
		PieceCreator.fill_cut_hole(st_left, intersection_points, plane)
		PieceCreator.fill_cut_hole(st_right, intersection_points, -plane)
	else:
		start = Time.get_ticks_msec()
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
		var insides: Array[bool]
		for point in clip_tetrahedron:
			#v = triangle[1]
			#if ClipPolygon.is_point_inside_mesh(v, mdt2):
			var inside := true
			var distances: Array[float] = []
			for p in mdt.get_vertex_count():
				distances.append((mdt.get_vertex(p) - point).length_squared())

			var closest_vertex := ClipPolygon.mins_arr(distances)
			print(closest_vertex)
			var deduplicated_faces: PackedInt32Array
			for closest_index in closest_vertex:
				for t in mdt.get_vertex_faces(closest_index):
					if t not in deduplicated_faces:
						deduplicated_faces.append(t)
			print("face après déduplication = ", deduplicated_faces.size())
			#for closest_index in closest_vertex:
				#if visualizer.points_node2.visible:
					#visualizer.show_points_3d([mdt.get_vertex(closest_index)], Color.RED, visualizer.points_node2)
				#print("closest_vertex is ", closest_vertex)

				#print(mdt.get_vertex_faces(closest_index))
				# TODO dédupliquer indice face
			for t in deduplicated_faces:
			#for t in mdt.get_vertex_faces(closest_index):
				if visualizer.points_node2.visible:
					for j in range(3):
						visualizer.show_points_3d([mdt.get_vertex(mdt.get_face_vertex(t, j))], Color.PURPLE, visualizer.points_node2)
				var normal_t := mdt.get_face_normal(t)
				if normal_t.length_squared() == 0: continue
				if (point - mdt.get_vertex(mdt.get_face_vertex(t, 0))).dot(normal_t) > 0:
					inside = false
					break

			#if inside:
				#print("v ", v, " is inside the mesh")
				#intersection_points.append(v)
			insides.append(inside)
			#break
		delta = Time.get_ticks_msec() - start
		print("deduplications = ", delta, " ms")
		for i in range(0, len(clip_indices), 3):
			start = Time.get_ticks_msec()
			var indices := [clip_indices[i], clip_indices[i + 1], clip_indices[i + 2]]
			#i = 2 * 3
			var triangle := [clip_tetrahedron[indices[0]], clip_tetrahedron[indices[1]], clip_tetrahedron[indices[2]]]
			var ab = triangle[1] - triangle[0]
			var ac = triangle[2] - triangle[0]
			var normal = ac.cross(ab).normalized()
			#var normal = ab.cross(ac).normalized()
			#print("normal = ", normal)
			var plane2 = Plane(normal, triangle[0])
			intersection_points.clear()
			#var mean = (triangle[2] + triangle[1] + triangle[2]) / 3
			#print("points = ", mdt2.get_vertex_count())
			for p in deduplicated_indexes:
				#print(ClipPolygon.distance_to_triangle(mdt2.get_vertex(p), triangle))
				#if abs(Plane(normal, mean).distance_to(mdt2.get_vertex(p))) < 0.001 \
					#&& ClipPolygon.distance_to_triangle(mdt2.get_vertex(p), triangle) < 0.001:
				if ClipPolygon.distance_to_triangle(mdt2.get_vertex(p), triangle) < 0.001:
					intersection_points.append(mdt2.get_vertex(p))
			delta = Time.get_ticks_msec() - start
			print("compute intersection sans clipper = ", delta, " ms")
			print("intersection points sans clipper = ", intersection_points.size())
			start = Time.get_ticks_msec()
			for v in indices:
				if insides[v]:
					intersection_points.append(clip_tetrahedron[v])
			print("intersection points = ", intersection_points.size())
			delta = Time.get_ticks_msec() - start
			print("compute intersection clipper = ", delta, " ms")
			if intersection_points.size() >= 3:
				if visualizer.points_node2.visible:
					visualizer.show_points_3d(intersection_points, Color.RED, visualizer.points_node2)
				PieceCreator.fill_cut_hole(st_left, intersection_points, plane2)
				PieceCreator.fill_cut_hole(st_right, intersection_points, -plane2)
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

# ==================================================================================================
# Voronoi slicing API
# ==================================================================================================

const EPSILON := 1e-5

func voronoi_slicing(mesh_instance: MeshInstance3D, vd: VoronoiDiagram3D, piece_creator: PieceCreator) -> void:
	if mesh_instance == null:
		return
	
	var array_mesh: ArrayMesh
	if mesh_instance.mesh is PrimitiveMesh:
		array_mesh = ArrayMesh.new()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_instance.mesh.get_mesh_arrays())
	else:
		array_mesh = mesh_instance.mesh
	
	var parent_body = mesh_instance.get_parent()
	var velocity = parent_body.linear_velocity if parent_body is RigidBody3D else Vector3.ZERO
	var transform = mesh_instance.global_transform
	
	var triangles_normals_couple : Array = _extract_triangles_and_normals(array_mesh)
	var triangles: Array[PackedVector3Array] = triangles_normals_couple[0]
	for cell in vd.cells:
		var updated_cell : VoronoiDiagram3D.VoronoiCell = cell
		#var cell_aabb := _aabb_of_voronoi_cell(cell)
		for ti in triangles.size():
			var triangle : PackedVector3Array = triangles[ti]
			#if not _aabb_intersects_triangle(cell_aabb, triangle):
				#continue
			
			var cutting_plane: Plane = _build_cutting_plane(triangle)
			var segments : Array = []
			var new_faces : Array[VoronoiDiagram3D.VoronoiFace] = []
			for face in updated_cell.faces:
				var polygon: PackedVector3Array = face.vertices
				var clipped_result := _clip_polygon_by_plane(polygon, -cutting_plane)
				polygon = clipped_result[0]
				if polygon.size() < 3:
					continue
				var new_face := VoronoiDiagram3D.VoronoiFace.new()
				new_face.vertices = polygon
				new_face.normal = face.normal
				new_faces.append(new_face)
				
				var new_segment : PackedVector3Array = clipped_result[1]
				if new_segment.size() == 2:
					segments.append(new_segment)
			if not segments.is_empty():
				var cap_face := VoronoiDiagram3D.VoronoiFace.new()
				cap_face.vertices = _stitch_segments_into_polygon(segments)
				cap_face.normal = cutting_plane.normal
				new_faces.append(cap_face)
			updated_cell.faces = new_faces
		if updated_cell.faces.is_empty():
			continue   # cell completely outside of the mesh
		var new_mesh : ArrayMesh = _build_cell_array_mesh(updated_cell)
		piece_creator.create_piece(new_mesh, transform, velocity, Vector3.ZERO, false)

static func _build_cell_array_mesh(cell: VoronoiDiagram3D.VoronoiCell) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
 
	for face in cell.faces:
		var polygon = face.vertices
		var triangles := _triangulate_polygon(polygon)
		for triangle: PackedVector3Array in triangles:
			var a = triangle[0]
			var b = triangle[1]
			var c = triangle[2]
			var normal = (c - a).cross(b - a).normalized()
			if face.normal.dot(normal) > 0: # même sens
				vertices.append(a)
				vertices.append(b)
				vertices.append(c)
				normals.append(normal)
				normals.append(normal)
				normals.append(normal)
			else:
				vertices.append(c)
				vertices.append(b)
				vertices.append(a)
				normals.append(-normal)
				normals.append(-normal)
				normals.append(-normal)

	if vertices.is_empty():
		return null
	
	var mesh := ArrayMesh.new()
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals # Per-face normal
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _stitch_segments_into_polygon(segments: Array) -> PackedVector3Array:
	if segments.is_empty():
		return PackedVector3Array()
	
	var chain := PackedVector3Array()
	var remaining : Array = segments.duplicate()
	
	chain.append(remaining[0][0])
	chain.append(remaining[0][1])
	remaining.remove_at(0)
	
	while not remaining.is_empty():
		var tail : Vector3 = chain[chain.size() - 1]
		var found := false
		for si in remaining.size():
			var segment : Array = remaining[si]
			if segment[0].distance_squared_to(tail) < EPSILON * EPSILON:
				if not segment[1].distance_squared_to(chain[0]) < EPSILON * EPSILON:
					chain.append(segment[1])
				remaining.remove_at(si)
				found = true
				break
			elif segment[1].distance_squared_to(tail) < EPSILON * EPSILON:
				if not segment[0].distance_squared_to(chain[0]) < EPSILON * EPSILON:
					chain.append(segment[0])
				remaining.remove_at(si)
				found = true
				break
		if not found:
			break
	return chain

static func _aabb_of_voronoi_cell(cell: VoronoiDiagram3D.VoronoiCell) -> AABB:
	var aabb := AABB()
	var first := true
	for face in cell.faces:
		for v: Vector3 in face.vertices:
			if first:
				aabb = AABB(v, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(v)
	return aabb.grow(EPSILON)

static func _aabb_intersects_triangle(aabb: AABB, triangle: PackedVector3Array) -> bool:
	var triangle_min := triangle[0].min(triangle[1]).min(triangle[2])
	var triangle_max := triangle[0].max(triangle[1]).max(triangle[2])
	var triangle_aabb := AABB(triangle_min, triangle_max - triangle_min)
	return aabb.intersects(triangle_aabb)

## Sutherland-Hodgman clip of a convex polygon against one half-space (plane.normal side = inside).
## Returns [clipped_polygon: PackedVector3Array, clip_edge: PackedVector3Array]
## clip_edge has 0 or 2 vertices marking the newly introduced edge on the plane.
func _clip_polygon_by_plane(polygon: PackedVector3Array, plane: Plane) -> Array:
	var result := PackedVector3Array()
	var clip_points := PackedVector3Array()
	
	var n := polygon.size()
	if n == 0:
		return [result, clip_points]
	
	for i in n:
		var current : Vector3 = polygon[i]
		var next : Vector3 = polygon[(i + 1) % n]
		
		var distance_current : float = plane.distance_to(current)
		var distance_next : float = plane.distance_to(next)
		
		var current_inside : bool = distance_current >= -EPSILON
		var next_inside : bool = distance_next >= -EPSILON
		
		if current_inside:
			result.append(current)
		elif n == 2:
			continue
		
		if current_inside != next_inside:
			# Compute intersection between clipping plane and segment using weighted linear interpolation
			var t : float = distance_current / (distance_current - distance_next)
			var inter : Vector3 = current.lerp(next, t)
			result.append(inter)
			clip_points.append(inter)
			if n == 2:
				break
	return [result, clip_points]

static func _build_cutting_plane(triangle: PackedVector3Array) -> Plane:
	var v0: Vector3 = triangle[0]
	var v1: Vector3 = triangle[1]
	var v2: Vector3 = triangle[2]
	var n: Vector3 = (v2 - v0).cross(v1 - v0).normalized()

	return Plane(n, v0)

## Returns an Array of triangles from the original mesh
static func _extract_triangles_and_normals(mesh: ArrayMesh) -> Array:
	var triangles : Array[PackedVector3Array] = [] # Contains trios of vertices forming triangles
	var triangles_normals : Array[PackedVector3Array] = [] # Contains trios of normals each corresponding to a vertex in the triangle
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var triangle_indices = arrays[Mesh.ARRAY_INDEX]
		
		if triangle_indices == null or triangle_indices.is_empty():
			#Case when triangles are unindexed
			var i: int = 0
			while i + 2 < vertices.size():
				var triangle := PackedVector3Array([vertices[i], vertices[i+1], vertices[i+2]])
				var vertices_normals := PackedVector3Array([normals[i], normals[i+1], normals[i+2]])
				triangles.append(triangle)
				triangles_normals.append(vertices_normals)
				i += 3
		else:
			var j: int = 0
			while j + 2 < triangle_indices.size():
				var triangle := PackedVector3Array([
					vertices[triangle_indices[j]],
					vertices[triangle_indices[j+1]],
					vertices[triangle_indices[j+2]]
				])
				var vertices_normals := PackedVector3Array([
					normals[triangle_indices[j]],
					normals[triangle_indices[j+1]],
					normals[triangle_indices[j+2]]
				])
				triangles.append(triangle)
				triangles_normals.append(vertices_normals)
				j += 3
	return [triangles, triangles_normals]

static func _triangulate_polygon(polygon: PackedVector3Array) -> Array[PackedVector3Array]:
	var triangles: Array[PackedVector3Array] = []
	var count: int = polygon.size()
	if count < 3:
		return triangles
	var v0: Vector3 = polygon[0]
	for i in range(1, count - 1):
		triangles.append(PackedVector3Array([v0, polygon[i], polygon[i + 1]]))
	return triangles # Array[Array[PackedVector3Array]: triangles, Array[PackedVector3Array]: vertices normals]
