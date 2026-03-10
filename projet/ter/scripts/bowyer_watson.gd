extends Node3D

class_name BowyerWatson3D

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
