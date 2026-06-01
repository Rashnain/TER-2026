## 3D Voronoi Diagram computed from a Delaunay Tetrahedralization.
##
## Each Voronoi cell corresponds to one input (user) point.
## Voronoi vertices = circumcentres of DT tetrahedra
## Voronoi edges = dual of DT faces (connect two circumcentres of adjacent tets)
## Voronoi faces = dual of DT edges (polygon around one DT edge)
##
## Usage:
##   var vd := VoronoiDiagram3D.new()
##   vd.build(dt, aabb)      # dt : DelaunayTetrahedralization3D
##   var cell := vd.cells[i] # VoronoiCell for user-point i

class_name VoronoiDiagram3D

# ==================================================================================================
# Data structures
# ==================================================================================================

## One face of a Voronoi cell, a convex polygon in 3-D space.
##
## vertices      - ordered polygon vertices (convex, coplanar)
## normal        - outward-pointing unit normal of the face
## neighbour_idx - index of the neighbouring cell sharing this face
## is_boundary   - true when this face was introduced by the AABB clip
class VoronoiFace:
	var vertices := PackedVector3Array()
	var normal := Vector3.ZERO
	var neighbour_idx := -1
	var is_boundary := false

## One complete Voronoi cell, a closed convex polyhedron.
##
## site       - the user point this cell surrounds
## site_index - 0-based user-point index (matches dt.get_user_point)
## faces      - all faces of the cell (VoronoiFace[])
class VoronoiCell:
	var site := Vector3.ZERO
	var site_index : int = -1
	var faces : Array[VoronoiFace] = []

# ==================================================================================================
# Data state
# ==================================================================================================

## One VoronoiCell per user point
var cells : Array[VoronoiCell] = []

## Stored Bounding box of the mesh to fracture
var bounding_box := AABB()

# ==================================================================================================
# Constants
# ==================================================================================================

const EPSILON := 1e-5

# ==================================================================================================
# Build
# ==================================================================================================

## Build the full Voronoi diagram from a completed DT.
## Call after dt.insert_points() has returned.
func build(dt: DelaunayTetrahedralization3D, aabb: AABB) -> void:
	cells.clear()
	bounding_box = aabb
	# 1. Circumcentre cache
	# Map from Tetrahedron reference to Vector3 circumcentre.
	# (dt._circumcentre() already caches internally, but we need a global index.)
	var tet_index : Dictionary = {}   # Tetrahedron -> int index
	var tet_cc := PackedVector3Array()
	for i in dt.tetrahedra.size():
		var tet : DelaunayTetrahedralization3D.Tetrahedron = dt.tetrahedra[i]
		tet_index[tet] = i
		tet_cc.append(dt.circumcentre(tet))
	
	# 2. Build one cell per user point 
	for ui in dt.n_user_points:
		var cell := VoronoiCell.new()
		cell.site = dt.get_user_point(ui)
		cell.site_index = ui
		
		var global_idx := ui + 4 # sentinel offset
		
		# Collect the star (all tets incident to this user point)
		var star : Array = dt.get_star(ui)
		
		# 3. Build Voronoi faces: dual of DT edges incident to this point 
		# For each neighbour vertex v of ui, the shared DT edge (ui-v) is dual to
		# a Voronoi face polygon. The polygon vertices are the circumcentres of 
		# all tets in the star that also contain v, ordered angularly around the edge.
		
		var done_neighbours : Dictionary = {}
		
		for tet in star:
			for local_v in 4:
				var v : int = tet.vertices[local_v]
				if v == global_idx:
					continue
				if done_neighbours.has(v):
					continue
				done_neighbours[v] = true
				
				# Gather all tetrahedra in the star that also contain v
				var ring_tets : Array = []
				for st in star:
					if st.local_index(v) != -1:
						ring_tets.append(st)
				
				if ring_tets.size() < 3:
					continue # degenerate case
				
				# Raw polygon vertices = unordered circumcentres of ring_tets
				var raw_points := PackedVector3Array()
				for rt in ring_tets:
					raw_points.append(tet_cc[tet_index[rt]])
				
				# Order the polygon vertices angularly around the DT edge ui-v
				var ordered := _order_polygon_around_edge(raw_points, dt.points[global_idx], dt.points[v])
				
				var face := VoronoiFace.new()
				face.vertices = ordered
				
				# Outward normal: from cell site toward neighbour site
				if v >= 4:
					# Neighbour is another user point
					face.normal = (dt.points[v] - cell.site).normalized()
					face.neighbour_idx = v - 4
				else:
					# Neighbour is a sentinel - boundary face before clipping
					face.normal = (dt.points[v] - cell.site).normalized()
					face.neighbour_idx = -1
					face.is_boundary = true
				
				cell.faces.append(face)
		cells.append(cell)

# ==================================================================================================
# Polygon ordering
# ==================================================================================================

## Sort polygon vertices angularly around the axis defined by edge (p_from to p_to).
func _order_polygon_around_edge(points: PackedVector3Array, p_from: Vector3, p_to: Vector3) -> PackedVector3Array:
	if points.size() < 3:
		return points
	
	var axis : Vector3 = (p_to - p_from).normalized()
	var centre := _centroid(points)
	
	# Build a local 2-D frame perpendicular to the axis
	var u : Vector3 = points[0] - centre
	u -= axis * axis.dot(u)
	if u.length_squared() < EPSILON * EPSILON:
		u = axis.cross(Vector3.UP)
		if u.length_squared() < EPSILON * EPSILON:
			u = axis.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := axis.cross(u).normalized()
	
	# Compute angle of each point in the local frame
	var angles : Array[float] = []
	for p in points:
		var d := p - centre
		d -= axis * axis.dot(d)
		var angle : float = atan2(v.dot(d), u.dot(d))
		angles.append(angle)
	
	# Sort indices by angle
	var indices : Array = range(points.size())
	indices.sort_custom(func(ia, ib): return angles[ia] < angles[ib])
	
	var result := PackedVector3Array()
	for i in indices:
		result.append(points[i])
	return result

func _centroid(points: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for p in points:
		c += p
	return c / float(points.size())

# ==================================================================================================
# AABB clipping  (Sutherland-Hodgman in 3-D, half-space per AABB plane)
# ==================================================================================================

## Clip a VoronoiCell so all its faces lie within aabb.
## Adds new cap faces wherever the AABB planes cut through the cell.
func _clip_cell_to_aabb(cell: VoronoiCell, aabb: AABB) -> VoronoiCell:
	# Six half-spaces of the AABB
	var planes := _aabb_planes(aabb)
	
	# Represent the cell as a list of (vertices, neighbour_idx, is_boundary) tuples.
	# We work face-by-face, clipping each polygon against all 6 planes.
	# Simultaneously we track the "cap" polygons introduced on each AABB plane.
	
	# caps[plane_i] = list of intersection segments that will become the cap polygon
	var cap_segments : Array = [] # cap_segments[i] = Array of Vector3 pairs
	for i in 6:
		cap_segments.append([])
	
	var clipped_faces : Array[VoronoiFace] = []
	
	for face in cell.faces:
		var polygon : PackedVector3Array = face.vertices
		
		for pi in planes.size():
			var plane : Plane = planes[pi]
			var clipped_result := _clip_polygon_by_plane(polygon, plane)
			polygon = clipped_result[0]
			if polygon.size() < 3:
				break   # face entirely clipped away
			
			var new_segment : PackedVector3Array = clipped_result[1] # 0 or 2 vertices
			for pj in range(pi+1, planes.size()):
				if new_segment.size() != 2:
					break
				var next_plane : Plane = planes[pj]
				new_segment = _clip_polygon_by_plane(new_segment, next_plane)[0]
			if new_segment.size() == 2:
				cap_segments[pi].append([new_segment[0], new_segment[1]])
		
		if polygon.size() >= 3:
			var nf := VoronoiFace.new()
			nf.vertices = polygon
			nf.normal = face.normal
			nf.neighbour_idx = face.neighbour_idx
			nf.is_boundary = face.is_boundary
			clipped_faces.append(nf)
	
	# Build cap faces: for each AABB plane collect all clipped edges, stitch them
	# into a polygon and add a boundary face.
	for pi in planes.size():
		var segments : Array = cap_segments[pi]
		if segments.is_empty():
			continue
		var cap_polygon := _gather_segments_into_polygon(segments)
		if cap_polygon.size() < 3:
			continue
		# Order the cap polygon
		var plane : Plane = planes[pi]
		cap_polygon = _order_polygon_around_edge(cap_polygon, cell.site, cell.site + plane.normal)
		
		var clipped_face := VoronoiFace.new()
		clipped_face.vertices = cap_polygon
		clipped_face.normal = -plane.normal
		clipped_face.neighbour_idx = -1
		clipped_face.is_boundary = true
		clipped_faces.append(clipped_face)
	
	cell.faces = clipped_faces
	return cell

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

## Given an array of segments (each a [Vector3, Vector3] pair), gather them
## into a polygon.
func _gather_segments_into_polygon(segments: Array) -> PackedVector3Array:
	if segments.is_empty():
		return PackedVector3Array()
	
	var polygon := PackedVector3Array()
	var remaining : Array = segments.duplicate()
	
	# Start with first segment
	polygon.append(remaining[0][0])
	polygon.append(remaining[0][1])
	remaining.remove_at(0)
	
	while not remaining.is_empty():
		var found := false
		for si in remaining.size():
			var segment : Array = remaining[si]
			for v in polygon:
				if v.distance_squared_to(segment[0]) < EPSILON:
					polygon.append(segment[1])
					remaining.remove_at(si)
					found = true
					break
				elif v.distance_squared_to(segment[1]) < EPSILON:
					polygon.append(segment[0])
					remaining.remove_at(si)
					found = true
					break
			if found:
				break
		if not found:
			# We search if the gap found in the chain is not caused by missing segments between new
			# clipped points of 2 different faces. A phenomenon that appears when one face is clipped
			# against several planes of the AABB and the unconnected points lie on 2 planes at the
			# same time.
			for si in remaining.size():
				var segment : Array = remaining[si]
				for v in polygon:
					if ((abs(v[0] - segment[0][0]) < EPSILON and abs(v[1] - segment[0][1]) < EPSILON)\
					or (abs(v[0] - segment[0][0]) < EPSILON and abs(v[2] - segment[0][2]) < EPSILON)\
					or (abs(v[1] - segment[0][1]) < EPSILON and abs(v[2] - segment[0][2]) < EPSILON))\
					or ((abs(v[0] - segment[1][0]) < EPSILON and abs(v[1] - segment[1][1]) < EPSILON)\
					or (abs(v[0] - segment[1][0]) < EPSILON and abs(v[2] - segment[1][2]) < EPSILON)\
					or (abs(v[1] - segment[1][1]) < EPSILON and abs(v[2] - segment[1][2]) < EPSILON)):
						polygon.append(segment[0])
						polygon.append(segment[1])
						remaining.remove_at(si)
						found = true
						break
				if found:
					break
			if not found:
				break # error real gap found
	return polygon

## Return the six inward-facing planes of an AABB.
func _aabb_planes(aabb: AABB) -> Array:
	var lo : Vector3 = aabb.position
	var hi : Vector3 = aabb.end
	return [
		Plane(Vector3(1, 0, 0), lo.x),
		Plane(Vector3(-1, 0, 0), -hi.x),
		Plane(Vector3(0, 1, 0), lo.y),
		Plane(Vector3(0, -1, 0), -hi.y),
		Plane(Vector3(0, 0, -1), lo.z),
		Plane(Vector3(0, 0, 1), -hi.z)
	]

# ==================================================================================================
# Helper functions
# ==================================================================================================

func _collect_vertices(cell: VoronoiCell) -> PackedVector3Array:
	var seen := []
	var result := PackedVector3Array()
	for face in cell.faces:
		for v in face.vertices:
			for s in seen:
				if s.distance_squared_to(v) < EPSILON * EPSILON:
					break
				seen.append(v)
				result.append(v)
	return result

# ==================================================================================================
# Fracture helpers
# ==================================================================================================

## Return the face shared between cell[a] and cell[b], or null.
func get_shared_face(cell_a_idx: int, cell_b_idx: int) -> VoronoiFace:
	if cell_a_idx >= cells.size():
		return null
	var cell : VoronoiCell = cells[cell_a_idx]
	for face in cell.faces:
		if face.neighbour_idx == cell_b_idx:
			return face
	return null

## Build an ArrayMesh for a single Voronoi cell (triangulated fan from centroid).
## Useful for fracture previewing or physics mesh creation.
func build_cell_mesh(cell_idx: int) -> ArrayMesh:
	if cell_idx >= cells.size():
		return null
	
	var cell : VoronoiCell = cells[cell_idx]
	
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	
	var vertices_count := 0
	
	for face in cell.faces:
		if face.vertices.size() < 3:
			continue
		var poly : PackedVector3Array = face.vertices
		var n : Vector3 = face.normal
		# Ensure the normal actually points away from the site
		var to_face : Vector3 = poly[0] - cell.site
		if to_face.dot(n) < 0.0:
			n = -n
		
		# Fan triangulation around poly[0]
		for i in range(1, poly.size() - 1):
			positions.append(poly[0])
			positions.append(poly[i])
			positions.append(poly[i + 1])
			normals.append(n)
			normals.append(n)
			normals.append(n)
			indices.append(vertices_count)
			indices.append(vertices_count + 1)
			indices.append(vertices_count + 2)
			vertices_count += 3
	
	if positions.is_empty():
		return null
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Build meshes for all cells and return them as an Array[ArrayMesh].
func build_all_meshes() -> Array:
	var meshes : Array = []
	for i in cells.size():
		meshes.append(build_cell_mesh(i))
	return meshes

# ==================================================================================================
# DEBUG Functions
# ==================================================================================================

## Debug: draw all Voronoi edges as an ImmediateMesh.
func draw_voronoi_edges(colour: Color = Color(1.0, 0.0, 0.0)) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var seen : Dictionary = {}
	
	for cell in cells.slice(0,1):
		cell = _clip_cell_to_aabb(cell, bounding_box)
		if cell.faces.is_empty():
			continue
		for face in cell.faces:
			var poly : PackedVector3Array = face.vertices
			for i in poly.size():
				var a : Vector3 = poly[i]
				var b : Vector3 = poly[(i + 1) % poly.size()]
				# Deduplicate (rough: use string key of rounded positions)
				var key := str(a.snapped(Vector3.ONE * 0.0001)) + str(b.snapped(Vector3.ONE * 0.0001))
				var key2 := str(b.snapped(Vector3.ONE * 0.0001)) + str(a.snapped(Vector3.ONE * 0.0001))
				if seen.has(key) or seen.has(key2):
					continue
				seen[key] = true
				im.surface_set_color(colour)
				im.surface_add_vertex(a)
				im.surface_set_color(colour)
				im.surface_add_vertex(b)
	
	im.surface_end()
	
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
