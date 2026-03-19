extends Node3D

class_name VoronoiFracture

class Edge:
	var a: int
	var b: int
	
	func _init(a_: int, b_: int) -> void:
		self.a = a_
		self.b = b_
	
	func equals(edge: Edge) -> bool:
		return a == edge.a and b == edge.b

class Face:
	var a: int
	var b: int
	var c: int
	
	func _init(a_: int, b_: int, c_: int) -> void:
		var arr := [a_, b_, c_]
		arr.sort()
		self.a = arr[0]
		self.b = arr[1]
		self.c = arr[2]
	
	func equals(face: Face) -> bool:
		return a == face.a and b == face.b and c == face.b
	
	func key() -> String:
		return "%d_%d_%d" % [a, b, c]

class Tetrahedron:
	var a: int
	var b: int
	var c: int
	var d: int
	
	var circumcenter: Vector3
	var circumradius: float
	
	func _init(a_: int, b_: int, c_: int, d_: int, points: Array[Vector3]) -> void:
		self.a = a_
		self.b = b_
		self.c = c_
		self.d = d_
		compute_circumsphere(points)
		
	func compute_circumsphere(points: Array[Vector3]) -> void:
		var v0: Vector3 = points[a]
		var v1: Vector3 = points[b]
		var v2: Vector3 = points[c]
		var v3: Vector3 = points[d]
		
		var row1: Vector3 = v1 - v0
		var squareLen1: float = row1.length_squared()
		var row2: Vector3 = v2 - v0
		var squareLen2: float = row2.length_squared()
		var row3: Vector3 = v3 - v0
		var squareLen3: float = row3.length_squared()
		
		var det: float = row1.x * (row2.y * row3.z - row3.y * row2.z) - row1.y * (row2.x * row3.z - row3.x * row2.z) + row1.z * (row2.x * row3.y - row3.x * row2.y)
		
		var invDet: float = 1.0 / (2 * det)
		circumcenter = v0 + invDet * (squareLen3 * (row1.cross(row2)) + squareLen2 * (row3.cross(row1)) + squareLen1 * (row2.cross(row3)))
		
		circumradius = (circumcenter - v0).length()

const EPSILON := 1e-6

var points: PackedVector3Array = []
var tetrahedralization: Array[Tetrahedron] = []
var voronoi_vertices: Array[Vector3] = []
var voronoi_cells: Dictionary[int, Array] = {}

#==================== Bowyer Watson Functions ==============================

func bowyer_watson(point_list: PackedVector3Array) -> void:
	points = point_list.duplicate()
	tetrahedralization.clear()
	
	var super_tet_indices = _create_super_tetrahedron()
	
	for i in range(points.size() - 4):
		_insert_one_point(i)
	
	var to_remove: Array[Tetrahedron] = []
	
	for t in tetrahedralization:
		if t.a in super_tet_indices or t.b in super_tet_indices or t.c in super_tet_indices or t.d in super_tet_indices:
			to_remove.append(t)
	
	for t in to_remove:
		tetrahedralization.erase(t)
	

func _create_super_tetrahedron() -> Array:
	var min_v = points[0]
	var max_v = points[0]
	
	for v in points:
		min_v = min_v.min(v)
		max_v = max_v.max(v)
	
	var size = (max_v - min_v).length() * 10.0
	var center = (min_v + max_v) * 0.5
	
	var i0 = points.size()
	points.append(center + Vector3(-size, -size, -size))
	
	var i1 = points.size()
	points.append(center + Vector3(size, -size, size))
	
	var i2 = points.size()
	points.append(center + Vector3(-size, size, size))
	
	var i3 = points.size()
	points.append(center + Vector3(size, size, -size))
	
	var super_tet = Tetrahedron.new(i0, i1, i2, i3, points)
	tetrahedralization.append(super_tet)
	
	return [i0, i1, i2, i3]

func _insert_one_point(point_index: int):
	var point = points[point_index]
	var bad_tets: Array[Tetrahedron] = []
	
	for t in tetrahedralization:
		if point.distance_to(t.circumcenter) < t.circumradius:
			bad_tets.append(t)
	
	var face_count: Dictionary[String, int] = {}
	
	for t in bad_tets:
		var faces: Array[Face] = [
			Face.new(t.a, t.b, t.c),
			Face.new(t.a, t.b, t.d),
			Face.new(t.a, t.c, t.d),
			Face.new(t.b, t.c, t.d)
		]
		
		for f in faces:
			var k: String = f.key()
			if face_count.has(k):
				face_count[k] += 1
			else:
				face_count[k] = 1
	
	for t in bad_tets:
		tetrahedralization.erase(t)
	
	for key in face_count.keys():
		if face_count[key] == 1:
			var parts = key.split("_")
			var a = int(parts[0])
			var b = int(parts[1])
			var c = int(parts[2])
			
			var new_tet = Tetrahedron.new(a, b, c, point_index, points)
			tetrahedralization.append(new_tet)

#======================= Voronoi Dual Functions ===============================

func build_point_to_tetrahedra() -> Dictionary[int, Array]:
	var map: Dictionary[int, Array] = {}
	
	for i in range(points.size()):
		map[i] = []
	
	for t in tetrahedralization:
		map[t.a].append(t)
		map[t.b].append(t)
		map[t.c].append(t)
		map[t.d].append(t)
	
	return map

func build_tetrahedra_adjacency() -> Dictionary[int, Array]:
	var tetrahedra_adjacency: Dictionary[int, Array] = {}
	var face_to_tetrahedra: Dictionary[String, int] = {}
	for i in range(tetrahedralization.size()):
		tetrahedra_adjacency[i] = []
		var t = tetrahedralization[i]
		var faces: Array[Face] = [
			Face.new(t.a, t.b, t.c),
			Face.new(t.a, t.b, t.d),
			Face.new(t.a, t.c, t.d),
			Face.new(t.b, t.c, t.d)
		]
		
		for f in faces:
			var k: String = f.key()
			if face_to_tetrahedra.has(k):
				var neighbor = face_to_tetrahedra[k]
				tetrahedra_adjacency[neighbor].append(i)
				tetrahedra_adjacency[i].append(neighbor)
			else:
				face_to_tetrahedra[k] = i
	
	return tetrahedra_adjacency

func sort_vertices_around_edge(vertices: Array, edge_key: String) -> Array[int]:
	var parts = edge_key.split("_")
	var a = int(parts[0])
	var b = int(parts[1])
	
	var pa: Vector3 = voronoi_vertices[a]
	var pb: Vector3 = voronoi_vertices[b]
	
	var axis: Vector3 = (pb - pa).normalized()
	
	var tmp := Vector3(1, 0, 0)
	if abs(axis.dot(tmp)) > 0.9:
		tmp = Vector3(0, 1, 0)
	
	var u: Vector3 = axis.cross(tmp).normalized()
	var v: Vector3 = axis.cross(u).normalized()
	
	var angles: Array[Array] = []
	
	for i in vertices:
		var p = voronoi_vertices[i]
		var vec = p - pa
		
		var x: float = vec.dot(u)
		var y: float = vec.dot(v)
		var angle: float = atan2(y, x)
		
		angles.append([angle, i])
	
	angles.sort_custom(func(a, b): return a[0] < b[0])
	
	var result: Array[int] = []
	for angle in angles:
		result.append(angle[1])
	
	return result

func compute_voronoi_diagram() -> void:
	var tetrahedra_adjacency: Dictionary[int, Array] = build_tetrahedra_adjacency()
	var cell_edges: Array[Array] = []
	
	for t in tetrahedralization:
		voronoi_vertices.append(t.circumcenter)
	
	for i in range(tetrahedralization.size()):
		for neighbor in tetrahedra_adjacency[i]:
			if neighbor > i:
				cell_edges.append([i, neighbor])
	
	var edge_to_tetrahedra: Dictionary[String, Array] = {}
	for i in (tetrahedralization.size()):
		var t = tetrahedralization[i]
		var edges: Array[Array] = [
			[t.a, t.b], [t.a, t.c], [t.a, t.d],
			[t.b, t.c], [t.b, t.d], [t.c, t.d]
		]
		for e in edges:
			e.sort()
			var key: String = str(e[0]) + "_" + str(e[1])
			if not edge_to_tetrahedra.has(key):
				edge_to_tetrahedra[key] = []
			edge_to_tetrahedra[key].append(i)
	
	var voronoi_faces: Dictionary[String, Array] = {}
	for key in edge_to_tetrahedra.keys():
		var incident_tetrahedra = edge_to_tetrahedra[key]
		if incident_tetrahedra.size() < 2:
			continue
		
		incident_tetrahedra = sort_vertices_around_edge(incident_tetrahedra, key)
		voronoi_faces[key] = incident_tetrahedra
	
	for site in range(points.size()):
		voronoi_cells[site] = []
	
	for key in voronoi_faces.keys():
		var parts = key.split("_")
		var a = int(parts[0])
		var b = int(parts[1])
		voronoi_cells[a].append(voronoi_faces[key])
		voronoi_cells[b].append(voronoi_faces[key])

#========================= VORONOI FRACTURE ==============================

static func _extract_triangles(mesh: ArrayMesh) -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array] = []
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var triangle_indices = arrays[Mesh.ARRAY_INDEX]
 
		if triangle_indices == null or triangle_indices.is_empty():
			#Case when triangles are unindexed
			var i: int = 0
			while i + 2 < vertices.size():
				var triangle := PackedVector3Array([vertices[i], vertices[i+1], vertices[i+2]])
				result.append(triangle)
				i += 3
		else:
			var j: int = 0
			while j + 2 < triangle_indices.size():
				var triangle := PackedVector3Array([
					vertices[triangle_indices[j]],
					vertices[triangle_indices[j+1]],
					vertices[triangle_indices[j+2]]
				])
				result.append(triangle)
				j += 3
	return result

static func _build_cutting_plane(triangle: PackedVector3Array) -> Dictionary:
	var v0: Vector3 = triangle[0]
	var v1: Vector3 = triangle[1]
	var v2: Vector3 = triangle[2]
	var n: Vector3 = (v1 - v0).cross(v2 - v0)
	n = n.normalized()
	return {"point": v0, "normal": n}

static func _aabb_of_voronoi_cell(cell_faces: Array) -> AABB:
	var aabb := AABB()
	var first := true
	for face in cell_faces:
		for v: Vector3 in face:
			if first:
				aabb = AABB(v, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(v)
	return aabb.grow(EPSILON) #Expand slightly the bounding box for overlapping errors

static func _aabb_intersects_triangle(aabb: AABB, triangle: PackedVector3Array) -> bool:
	var triangle_min := triangle[0].min(triangle[1]).min(triangle[2])
	var triangle_max := triangle[0].max(triangle[1]).max(triangle[2])
	var triangle_aabb := AABB(triangle_min, triangle_max - triangle_min)
	return aabb.intersects(triangle_aabb)

static func _triangulate_polygon(poly: PackedVector3Array) -> Array:
	var triangles: Array = []
	var count: int = poly.size()
	if count < 3:
		return triangles
	var v0: Vector3 = poly[0]
	for i in range(1, count - 1):
		triangles.append(PackedVector3Array([v0, poly[i], poly[i + 1]]))
	return triangles

static func _poly_normal(poly: PackedVector3Array) -> Vector3:
	var n := Vector3.ZERO
	var count: int = poly.size()
	for i in count:
		var cur: Vector3  = poly[i]
		var next: Vector3 = poly[(i + 1) % count]
		n.x += (cur.y - next.y) * (cur.z + next.z)
		n.y += (cur.z - next.z) * (cur.x + next.x)
		n.z += (cur.x - next.x) * (cur.y + next.y)
	var norm: float = n.length()
	if norm < EPSILON:
		return Vector3.UP
	return n / norm
 
func fracture(mesh: ArrayMesh, cells: Dictionary) -> Array:
	var triangles: Array[PackedVector3Array] = _extract_triangles(mesh)
	var results: Array[ArrayMesh] = []
 
	for key: int in cells.keys():
		var seed: Vector3 = points[key]
		var cell_faces_by_indices: Array = cells[key]
		var cell_faces: Array = []
		for face_by_indices: Array[int] in cell_faces_by_indices:
			var face: PackedVector3Array = []
			for ti in face_by_indices:
				face.append(voronoi_vertices[ti])
			cell_faces.append(face)
		
 
		# AABB of this cell for fast triangle rejection
		var cell_aabb := _aabb_of_voronoi_cell(cell_faces)
		
		for triangle in triangles:
			# Fast reject: skip triangles whose AABB doesn't touch the cell AABB
			if not _aabb_intersects_triangle(cell_aabb, triangle):
				continue
			
			var cutting_plane = _build_cutting_plane(triangle)
			
			for fi in range(cell_faces.size()):
				var face: PackedVector3Array = cell_faces[fi]
				var clipped_face = Geometry3D.clip_polygon(face, -cutting_plane)
				cell_faces[fi] = clipped_face
 
	return results

#========================= DEBUG FUNCTIONS ===============================

func create_debug_mesh() -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.clear_surfaces()
	
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	for t in tetrahedralization:
		var vertices = [
			points[t.a],
			points[t.b],
			points[t.c],
			points[t.d]
		]
		
		_draw_edge(mesh, vertices[0], vertices[1])
		_draw_edge(mesh, vertices[0], vertices[2])
		_draw_edge(mesh, vertices[0], vertices[3])
		_draw_edge(mesh, vertices[1], vertices[2])
		_draw_edge(mesh, vertices[1], vertices[3])
		_draw_edge(mesh, vertices[2], vertices[3])
	
	mesh.surface_end()
	
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.GREEN
	instance.material_override = mat
	
	return instance

func create_debug_voronoi_mesh() -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.clear_surfaces()
	
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	for key in voronoi_cells.keys():
		var faces: Array = voronoi_cells[key]
		for f in faces:
			for i in range(f.size() - 1):
				_draw_edge(mesh, voronoi_vertices[f[i]], voronoi_vertices[f[i+1]])
			_draw_edge(mesh, voronoi_vertices[f[f.size()-1]], voronoi_vertices[f[0]])
	
	mesh.surface_end()
	
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.RED
	instance.material_override = mat
	
	return instance

func _draw_edge(mesh: ImmediateMesh, a: Vector3, b: Vector3):
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(b)
