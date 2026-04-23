## 3D Delaunay Tetrahedralization (DT) — flip-based incremental insertion.
##
## Based on:
##   Ledoux, H. (2007). "Computing the 3D Voronoi Diagram Robustly: An Easy Explanation."
##   Joe, B. (1991). "Construction of three-dimensional Delaunay triangulations
##                     using local transformations."
##
## Usage
##   var dt := DelaunayTetrahedralization3D.new()
##   dt.insert_points(your_array_of_vector3)
##   var voronoi := dt.extract_voronoi() # → VoronoiDiagram3D

class_name DelaunayTetrahedralization3D

## Stores one tetrahedron and its four face-adjacencies.
##
## Vertex winding convention (matches Orient left-hand rule):
##   vertices[0..3] are the four vertex indices into DT.points[].
##   For face f (0..3), the opposite vertex is vertices[f].
##   neighbours[f] is the adjacent Tetrahedron sharing face f.
##   neighbour_face[f] is the face index in that neighbour that points back.
class Tetrahedron:
	var vertices : PackedInt32Array       # size 4, indices into DT.points
	var neighbours : Array                # size 4, Tetrahedron | null
	var neighbour_face : PackedInt32Array # size 4, face index in neighbour
	
	# Cached circumsphere (set lazily, invalidated on flip)
	var _cc_valid : bool = false
	var _cc_centre : Vector3 = Vector3.ZERO
	var _cc_r2 : float = 0.0 # squared radius
	
	func _init(_vertices: PackedInt32Array) -> void:
		vertices = _vertices
		neighbours = [null, null, null, null]
		neighbour_face = PackedInt32Array([0, 0, 0, 0])
	
	## Return the three vertex indices of face f (the face opposite vertices[f]).
	func face_verts(f: int) -> PackedInt32Array:
		match f:
			0: return PackedInt32Array([vertices[1], vertices[2], vertices[3]])
			1: return PackedInt32Array([vertices[0], vertices[2], vertices[3]])
			2: return PackedInt32Array([vertices[0], vertices[1], vertices[3]])
			_: return PackedInt32Array([vertices[0], vertices[1], vertices[2]])
	
	## Return the local vertex index for a given global point index (-1 if absent).
	func local_index(point_index: int) -> int:
		for i in 4:
			if vertices[i] == point_index:
				return i
		return -1
	
	## Invalidate circumsphere cache (call after any structural change).
	func invalidate_cc() -> void:
		_cc_valid = false

class VoronoiDiagram3D:
	## One Voronoi vertex per Delaunay tetrahedron
	var vertices := PackedVector3Array()
	## cells[i] = Array of Voronoi vertex indices arrays forming cell of input point i
	var cells : Array = []
	## edges[i] = [v0_idx, v1_idx] Voronoi edge (dual to Delaunay triangle face)
	var edges : Array = []
	
	var input_points := PackedVector3Array()

# ==================================================================================================
# Constants
# ==================================================================================================

const BIG_SCALE := 1000.0 # Big-tetrahedron scale multiplier.
const EPSILON := 1e-10

# ==================================================================================================
# DT state
# ==================================================================================================

## All points: [0..3] are the big-tetrahedron points, rest are input points
var points := PackedVector3Array()

## All live tetrahedra (some slots may be null after flips/removals)
var tetrahedra : Array = [] # Array[Tetrahedron]

## How many user points have been inserted.
var _n_user_pts  : int = 0

# ==================================================================================================
# Public functions
# ==================================================================================================

## Insert an array of Vector3 points and build the DT.
func insert_points(pts: Array) -> void:
	_initialise(pts)
	for i in range(4, points.size()):
		_insert_one_point(i)

## Convenience: insert a single additional point after initial build.
## Returns the new point's index in self.points, or -1 if duplicate.
func insert_point(p: Vector3) -> int:
	var idx := points.size()
	points.append(p)
	_n_user_pts += 1
	_insert_one_point(idx)
	return idx

### Extract the Voronoi diagram dual to the current DT.
### Filters out all cells/vertices touching the big-tetrahedron sentinels.
#func extract_voronoi() -> VoronoiDiagram3D:
	#var vd := VoronoiDiagram3D.new()
	#vd.input_points = PackedVector3Array(points.slice(4))
	#
	## Map tetrahedron to Voronoi vertex index
	#var tetrahedron_to_voronoi_vertex : Dictionary = {}
	#var vv_list   : PackedVector3Array = PackedVector3Array()
	#
	#for ti in tetrahedra.size():
		#var tet : Tetrahedron = tetrahedra[ti]
		#if tet == null:
			#continue
		#if _tet_touches_big(tet):
			#tetrahedron_to_voronoi_vertex[ti] = -1
			#continue
		#var cc := _circumcentre(tet)
		#tetrahedron_to_voronoi_vertex[ti] = vv_list.size()
		#vv_list.append(cc)
	#
	#vd.vertices = vv_list
	#
	## Cells
	#var n_user := _n_user_pts
	#vd.cells.resize(n_user)
	#for i in n_user:
		#vd.cells[i] = []
	#
	#for ti in tetrahedra.size():
		#var tet : Tetrahedron = tetrahedra[ti]
		#if tet == null or tetrahedron_to_voronoi_vertex.get(ti, -1) == -1:
			#continue
		#var vv_idx : int = tetrahedron_to_voronoi_vertex[ti]
		#for lv in 4:
			#var gv := tet.vertices[lv]
			#if gv >= 4: # real user point
				#var cell_idx := gv - 4
				#if not vv_idx in vd.cells[cell_idx]:
					#vd.cells[cell_idx].append(vv_idx)
	
	# Edges (dual to Delaunay triangular faces) 
	#var seen_edges : Dictionary = {}
	#for ti in tetrahedra.size():
		#var tetrahedron : Tetrahedron = tetrahedra[ti]
		#if tetrahedron == null:
			#continue
		#var vv0 : int = tetrahedron_to_voronoi_vertex.get(ti, -1)
		#for f in 4:
			#var nbr : Tetrahedron = tetrahedron.neighbours[f]
			#if nbr == null:
				#continue
			#var nbr_idx := tetrahedra.find(nbr)
			#var vv1 : int = tetrahedron_to_voronoi_vertex.get(nbr_idx, -1)
			#if vv0 == -1 or vv1 == -1:
				#continue
			#var key := mini(vv0, vv1) * 1000000 + maxi(vv0, vv1)
			#if not seen_edges.has(key):
				#seen_edges[key] = true
				#vd.edges.append([vv0, vv1])
	#
	#return vd

# ==================================================================================================
# Initialisation
# ==================================================================================================

func _initialise(pts: Array) -> void:
	points.clear()
	tetrahedra.clear()
	_n_user_pts = pts.size()
	
	# Compute bounding box of input
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	
	var centre := (lo + hi) * 0.5
	var half := (hi - lo) * 0.5
	var radius := maxf(maxf(half.x, half.y), half.z) * BIG_SCALE + 1.0
	
	# Four sentinel vertices of the big tetrahedron
	points.append(centre + Vector3(0.0, radius, 0.0))
	points.append(centre + Vector3(-radius * 0.942, -radius * 0.333, -radius * 0.333))
	points.append(centre + Vector3(radius * 0.942, -radius * 0.333, -radius * 0.333))
	points.append(centre + Vector3(0.0, -radius * 0.333, radius * 1.0))
	
	for p in pts:
		points.append(p)
	
	# Build the initial big tetrahedron
	var t := _make_tetrahedron(0, 1, 2, 3)
	tetrahedra.append(t)

# ==================================================================================================
# Insertion code
# ==================================================================================================

## Based on the Algorithm InsertOnePoint from the paper
func _insert_one_point(pi: int) -> void:
	# 1. Obtain the tetrahedron containing p
	var tau : Tetrahedron = _walk(pi)
	if tau == null:
		push_warning("DelaunayDT: Walk failed for point %d — skipping." % pi)
		return
	
	# 2. Insert p into tau with a flip14
	var new_tets := _flip14(tau, pi)
	if new_tets.is_empty():
		return # degenerate: p coincides with an existing vertex
	
	# 3. Restore Delaunayness with a stack of tets to test
	var stack : Array = []
	for nt in new_tets:
		stack.append(nt)
	
	while not stack.is_empty():
		var t : Tetrahedron = stack.pop_back()
		var local_index := t.local_index(pi)
		if local_index == -1:
			continue
		var neighbour : Tetrahedron = t.neighbours[local_index]
		if neighbour == null:
			continue
		
		# Test if the neighbour's apex is inside t's circumsphere
		var neighbour_apex_local_index := -1
		for f in 4:
			if neighbour.neighbours[f] == t:
				neighbour_apex_local_index = f
				break
		if neighbour_apex_local_index == -1:
			continue
		var d := neighbour.vertices[neighbour_apex_local_index]
		
		if _in_sphere(t.vertices[0], t.vertices[1], t.vertices[2], t.vertices[3], d) > 0.0:
			var created := _flip(t, neighbour, pi)
			for ct in created:
				stack.append(ct)

## Returns the tetrahedron containing points[pi], the point to be inserted in the DT.
##
## Makes computation faster than comparing the new point to the circumsphere of every
## other tetrahedron.
## 
## Implementation of the Visibility walk based on the algorithm described in 
## "Walking in a triangulation" by Olivier et al. (2006)
func _walk(pi: int) -> Tetrahedron:
	# Start from the most recently added tetrahedron (chosen heuristic)
	var current : Tetrahedron = tetrahedra.back()
	
	var MAX_STEPS := tetrahedra.size()
	var steps := 0
	
	while steps < MAX_STEPS:
		steps += 1
		var moved := false
		for f in 4:
			var fv := current.face_verts(f)
			# Orient(face, apex) gives sign convention
			# p should be on the same side as apex; if not, cross to neighbour
			var side_apex := _orient(fv[0], fv[1], fv[2], current.vertices[f])
			var side_p := _orient(fv[0], fv[1], fv[2], pi)
			
			if absf(side_apex) < EPSILON:
				continue # degenerate face
			
			# Different signs means p is on the other side
			if (side_p * side_apex) < 0.0:
				var neighbour : Tetrahedron = current.neighbours[f]
				if neighbour != null:
					current = neighbour
					moved = true
					break
		if not moved:
			break
	
	return current

# ==================================================================================================
# Flip code
# ==================================================================================================

## Make internal adjacencies between the four tets produced by flip14.
## t0={p,b,c,d}, t1={a,p,c,d}, t2={a,b,p,d}, t3={a,b,c,p}
func _link_internal(t0, t1, t2, t3) -> void:
	# t0/t1: shared face {p,c,d}
	# In t0={p,b,c,d}: face opp b (local 1) = {p,c,d}
	# In t1={a,p,c,d}: face opp a (local 0) = {p,c,d}
	t0.neighbours[1] = t1
	t0.neighbour_face[1] = 0
	t1.neighbours[0] = t0
	t1.neighbour_face[0] = 1
	
	# t0/t2: shared face {p,b,d}
	# In t0={p,b,c,d}: face opp c (local 2) = {p,b,d}
	# In t2={a,b,p,d}: face opp a (local 0) = {b,p,d}
	t0.neighbours[2] = t2
	t0.neighbour_face[2] = 0
	t2.neighbours[0] = t0
	t2.neighbour_face[0] = 2
	
	# t0/t3: shared face {p,b,c}
	# In t0={p,b,c,d}: face opp d (local 3) = {p,b,c}
	# In t3={a,b,c,p}: face opp a (local 0) = {b,c,p}
	t0.neighbours[3] = t3
	t0.neighbour_face[3] = 0
	t3.neighbours[0] = t0
	t3.neighbour_face[0] = 3
	
	# t1/t2: shared face {a,p,d}
	# In t1={a,p,c,d}: face opp c (local 2) = {a,p,d}
	# In t2={a,b,p,d}: face opp b (local 1) = {a,p,d}
	t1.neighbours[2] = t2
	t1.neighbour_face[2] = 1
	t2.neighbours[1] = t1
	t2.neighbour_face[1] = 2
	
	# t1/t3: shared face {a,p,c}
	# In t1={p,b,c,d}: face opp d (local 3) = {a,p,c}
	# In t3={a,b,c,p}: face opp b (local 1) = {a,c,p}
	t1.neighbours[3] = t3
	t1.neighbour_face[3] = 1
	t3.neighbours[1] = t1
	t3.neighbour_face[1] = 3
	
	# t2/t3: shared face {a,b,p}
	# In t2={a,b,p,d}: face opp d (local 3) = {a,b,p}
	# In t3={a,b,c,p}: face opp c (local 2) = {a,b,p}
	t2.neighbours[3] = t3
	t2.neighbour_face[3] = 2
	t3.neighbours[2] = t2
	t3.neighbour_face[2] = 3

## Set external neighbour, updating the back-pointer in neighbour.
func _set_neighbour(tetrahedron: Tetrahedron, face: int, neighbour: Tetrahedron, neighbour_face: int) -> void:
	tetrahedron.neighbours[face] = neighbour
	tetrahedron.neighbour_face[face] = neighbour_face
	if neighbour != null:
		neighbour.neighbours[neighbour_face] = tetrahedron
		neighbour.neighbour_face[neighbour_face] = face

## Takes to adjacent Tetrahedra tetrahedron and neighbour and performs one of 4 possible flips
## to restore Delaunayness of the Tetrahedralisation depending on cases.
## 
## Returns an array of the new tetrahedra or an empty array if no flip was possible or if
## the adjacent tetrahedra are not neighbours. 
##
## Based on the Flip algorithm described in the paper.
func _flip(tetrahedron: Tetrahedron, neighbour: Tetrahedron, pi: int) -> Array:
	# Determine which face of t is shared with neighbour
	var fi_tetrahedron := -1
	for f in 4:
		if tetrahedron.neighbours[f] == neighbour:
			fi_tetrahedron = f
			break
	if fi_tetrahedron == -1:
		return []
	
	var fi_neighbour := tetrahedron.neighbour_face[fi_tetrahedron]
	var di := neighbour.vertices[fi_neighbour] # apex of neighbour (not in shared face)
	
	# The three shared face vertices
	var fv := tetrahedron.face_verts(fi_tetrahedron)   # {a, b, c}
	var a := fv[0]
	var b := fv[1]
	var c := fv[2]
	
	# Determine visibility from p to neighbour's faces by testing if pd crosses the
	# interior of the shared face abc
	var cross := _orient(a, b, c, pi) * _orient(a, b, c, di)
	
	# Case #4: flat tetrahedron (p lies on a face of neighbour, degenerate coplanar insert)
	if _tet_is_flat(tetrahedron):
		print("23_1")
		return _flip23(tetrahedron, neighbour, pi)
	
	# Case #1: convex union, perform flip23
	# TODO
	if cross < -EPSILON:
		print(cross)
		return _flip23(tetrahedron, neighbour, pi)
	
	# Case #3: pd and one edge of abc are coplanar, try flip44
	if absf(cross) <= EPSILON:
		print("44")
		return _try_flip44(tetrahedron, neighbour, pi, a, b, c)
	
	# Case #2: concave union — try flip32 (need third tetrahedron sharing edge pd)
	print("32")
	return _try_flip32(tetrahedron, neighbour, a, b, c, pi)

## Insert a point into the Tetrahedralisation by splitting a Tetrahedron tau into 4 new
## Tetrahedra linking the old faces of tau with the new point inserted point[pi] and linking new
## faces in the graph.
##
## Returns the 4 new Tetrahedra.
func _flip14(tau: Tetrahedron, pi: int) -> Array:
	# Check pi is not already a vertex of tau
	for vi in 4:
		if tau.vertices[vi] == pi:
			return []
	
	var a := tau.vertices[0]
	var b := tau.vertices[1]
	var c := tau.vertices[2]
	var d := tau.vertices[3]
	
	# Neighbours from tau's four faces (face i is opposite vertex i)
	var neighbour_a : Tetrahedron = tau.neighbours[0] # opposite a -> face bcd
	var neighbour_b : Tetrahedron = tau.neighbours[1] # opposite b -> face acd
	var neighbour_c : Tetrahedron = tau.neighbours[2] # opposite c -> face abd
	var neighbour_d : Tetrahedron = tau.neighbours[3] # opposite d -> face abc
	var neighbour_face_a := tau.neighbour_face[0]
	var neighbour_face_b := tau.neighbour_face[1]
	var neighbour_face_c := tau.neighbour_face[2]
	var neighbour_face_d := tau.neighbour_face[3]
	
	# Create 4 new tetrahedra: {p,b,c,d}, {a,p,c,d}, {a,b,p,d}, {a,b,c,p}
	var t0 := _make_tetrahedron(pi, b, c, d) # replaces face opposite a
	var t1 := _make_tetrahedron(a, pi, c, d) # replaces face opposite b
	var t2 := _make_tetrahedron(a, b, pi, d) # replaces face opposite c
	var t3 := _make_tetrahedron(a, b, c, pi) # replaces face opposite d
	
	# Internal adjacencies
	_link_internal(t0, t1, t2, t3)
	
	# External adjacencies (to original neighbours of tau)
	# In t0={pi,b,c,d}: opposite to pi (local 0) is {b,c,d} -> neighbour_a
	_set_neighbour(t0, 0, neighbour_a, neighbour_face_a)
	# In t1={a,pi,c,d}: opposite to pi (local 1) is {a,c,d} -> neighbour_b
	_set_neighbour(t1, 1, neighbour_b, neighbour_face_b)
	# In t2={a,b,pi,d}: opposite to pi (local 2) is {a,b,d} -> neighbour_c
	_set_neighbour(t2, 2, neighbour_c, neighbour_face_c)
	# In t3={a,b,c,pi}: opposite to pi (local 3) is {a,b,c} -> neighbour_d
	_set_neighbour(t3, 3, neighbour_d, neighbour_face_d)
	
	# Remove old tetrahedron from list (replace slot for memory efficiency)
	var slot := tetrahedra.find(tau)
	tetrahedra[slot] = t0
	tetrahedra.append(t1)
	tetrahedra.append(t2)
	tetrahedra.append(t3)
	
	return [t0, t1, t2, t3]

## Flip the tetrahedra topology to go from 2 to 3 tetrahedras
func _flip23(tau: Tetrahedron, tau_a: Tetrahedron, pi: int) -> Array:
	var fi_tau := _shared_face(tau, tau_a)
	var fi_tau_a := tau.neighbour_face[fi_tau]
	var d := tau_a.vertices[fi_tau_a]
	var p := pi
	var fv := tau.face_verts(fi_tau)
	var a := fv[0]
	var b := fv[1]
	var c := fv[2]
	
	# Neighbours external to tau / neighbour that we need to preserve
	var nPA : Tetrahedron
	var nPA_f: int  # tau's face opp a -> neighbour
	var nPB : Tetrahedron
	var nPB_f: int
	var nPC : Tetrahedron
	var nPC_f: int
	var nDA : Tetrahedron
	var nDA_f: int  # neighbour's face opp a
	var nDB : Tetrahedron
	var nDB_f: int
	var nDC : Tetrahedron
	var nDC_f: int
	
	# Local indices for each vertex in tau and tau_a
	var local_a := tau.local_index(a)
	var local_b := tau.local_index(b)
	var local_d := tau.local_index(c)
	var a_local_a := tau_a.local_index(a)
	var a_local_b := tau_a.local_index(b)
	var a_local_c := tau_a.local_index(c)
	
	nPA = tau.neighbours[local_a]
	nPA_f = tau.neighbour_face[local_a]
	nPB = tau.neighbours[local_b]
	nPB_f = tau.neighbour_face[local_b]
	nPC = tau.neighbours[local_d]
	nPC_f = tau.neighbour_face[local_d]
	nDA = tau_a.neighbours[a_local_a]
	nDA_f = tau_a.neighbour_face[a_local_a]
	nDB = tau_a.neighbours[a_local_b]
	nDB_f = tau_a.neighbour_face[a_local_b]
	nDC = tau_a.neighbours[a_local_c]
	nDC_f = tau_a.neighbour_face[a_local_c]
	
	# Three new tets: {p,d,b,c}, {p,a,d,c}, {p,a,b,d}
	var t0 := _make_tetrahedron(p, d, b, c)
	var t1 := _make_tetrahedron(p, a, d, c)
	var t2 := _make_tetrahedron(p, a, b, d)
	
	# Internal adjacencies:
	# t0 & t1 share face {p,d,c}: opp b in t0 (local 2), opp a in t1 (local 1)
	t0.neighbours[2] = t1
	t0.neighbour_face[2] = 1
	t1.neighbours[1] = t0
	t1.neighbour_face[1] = 2
	# t0 & t2 share face {p,d,b}: opp c in t0 (local 3), opp a in t2 (local 1)
	t0.neighbours[3] = t2
	t0.neighbour_face[3] = 1
	t2.neighbours[1] = t0
	t2.neighbour_face[1] = 3
	# t1 & t2 share face {p,a,d}: opp c in t1 (local 3), opp b in t2 (local 2)
	t1.neighbours[3] = t2
	t1.neighbour_face[3] = 2
	t2.neighbours[2] = t1
	t2.neighbour_face[2] = 3
	
	# External adjacencies:
	# t0={p,d,b,c}: face opp p(local 0)={d,b,c}=old tau_a face opp a, face opp d(local 1)={p,b,c}=old tet face opp a
	_set_neighbour(t0, 0, nDA, nDA_f)
	_set_neighbour(t0, 1, nPA, nPA_f)
	# t1={p,a,d,c}: face opp p={a,d,c}=nDB's side, face opp d={p,a,c}=nPB's side
	_set_neighbour(t1, 0, nDB, nDB_f)
	_set_neighbour(t1, 2, nPB, nPB_f)
	# t2={p,a,b,d}: face opp p={a,b,d}=nDC's side, face opp d={p,a,b}=nPC's side
	_set_neighbour(t2, 0, nDC, nDC_f)
	_set_neighbour(t2, 3, nPC, nPC_f)
	
	# Replace tau and tau_a slots
	_replace_tet(tau, t0)
	_replace_tet(tau_a, t1)
	
	return [t0, t1, t2]

func _try_flip32(tau: Tetrahedron, tau_a: Tetrahedron, a: int, b: int, c: int, pi: int) -> Array:
	var d := tau_a.vertices[tau.neighbour_face[_shared_face(tau, tau_a)]]
	var p := pi
	
	# Find a third tetrahedron sharing edges pd and ab, bc or ac
	var tau_b : Tetrahedron = _find_third_tet(tau, tau_a, p, d, a, b, c)
	if tau_b == null:
		return []  # no flip possible; non-Delaunay face will be fixed later
	
	# Determine which edge of abc is shared with tau_b
	# tau_b contains p and d plus exactly one of the edges of abc
	var shared_a := tau_b.local_index(a) != -1
	var shared_b := tau_b.local_index(b) != -1
	var shared_c := tau_b.local_index(c) != -1
	
	# In flip32 the three tets share one common edge (the one NOT in abc's face).
	# Collect external neighbours of all three faces on each side.
	var e0 : int
	var e1 : int
	var e2 : int  # three face vertices, e2 is the "hinge"
	if shared_a and shared_b:
		e0 = a
		e1 = b
		e2 = c
	elif shared_b and shared_c:
		e0 = b
		e1 = c
		e2 = a
	else:
		e0 = a
		e1 = c
		e2 = b
	
	# Gather external neighbours:
	# tau has faces opposite {p, a, b, c}: we want faces opp e0, e1, e2.
	var nPE2 : Tetrahedron = tau.neighbours[tau.local_index(e2)]
	var nPE2_f := tau.neighbour_face[tau.local_index(e2)]
	var nDE2 : Tetrahedron = tau_a.neighbours[tau_a.local_index(e2)]
	var nDE2_f := tau_a.neighbour_face[tau_a.local_index(e2)]
	# tau_b has face opp e0 and face opp e1 as externals.
	var nTE0 : Tetrahedron = tau_b.neighbours[tau_b.local_index(e0)]
	var nTE0_f := tau_b.neighbour_face[tau_b.local_index(e0)]
	var nTE1 : Tetrahedron = tau_b.neighbours[tau_b.local_index(e1)]
	var nTE1_f := tau_b.neighbour_face[tau_b.local_index(e1)]
	
	# Two new tets: {p, e2, e0, d} and {p, e2, e1, d} — wait, flip32 → 2 tets.
	# New tets share face {p, e2, d} outer faces pair with neighbours above.
	var t0 := _make_tetrahedron(p, e2, e0, d)   # {p,e2,e0,d}
	var t1 := _make_tetrahedron(p, e2, e1, d)   # {p,e2,e1,d}
	
	# Internal: face opp e0 in t0 ↔ face opp e1 in t1 (shared face = {p,e2,d})
	var li0 := t0.local_index(e0)
	var li1 := t1.local_index(e1)
	t0.neighbours[li0] = t1
	t0.neighbour_face[li0] = li1
	t1.neighbours[li1] = t0
	t1.neighbour_face[li1] = li0
	
	# External:
	_set_neighbour(t0, t0.local_index(d), nPE2, nPE2_f)
	_set_neighbour(t0, t0.local_index(p), nDE2, nDE2_f)
	_set_neighbour(t0, t0.local_index(e2), nTE0, nTE0_f)
	_set_neighbour(t1, t1.local_index(d), nPE2, nPE2_f)   # hmm — need careful assignment
	_set_neighbour(t1, t1.local_index(p), nDE2, nDE2_f)
	_set_neighbour(t1, t1.local_index(e2), nTE1, nTE1_f)
	
	_replace_tet(tau, t0)
	_replace_tet(tau_a, t1)
	_remove_tet(tau_b)
	
	return [t0, t1]

func _try_flip44(tau: Tetrahedron, tau_a: Tetrahedron, pi: int, a: int, b: int, c: int) -> Array:
	# Find which edge of the shared face abc is coplanar with p and d
	var d := tau_a.vertices[tau.neighbour_face[_shared_face(tau, tau_a)]]
	var p := pi
	# Determine the coplanar edge (the segment pd passes through it)
	# Try each edge of abc
	var coplanar_v0 := -1
	var coplanar_v1 := -1
	for pair in [[a,b],[b,c],[a,c]]:
		var v0 : int = pair[0]
		var v1 : int = pair[1]
		
		if absf(_orient(p, d, v0, v1)) < EPSILON:
			coplanar_v0 = v0
			coplanar_v1 = v1
			break
	if coplanar_v0 == -1:
		return []  # edge-case: can't do flip44
	
	# Find two more tetrahedra sharing the coplanar edge (config44 needs 4 tets total)
	var tau_b := _neighbour_sharing_edge_and_vertex(tau, coplanar_v0, coplanar_v1, p)
	var tau_c := _neighbour_sharing_edge_and_vertex(tau_a, coplanar_v0, coplanar_v1, d)
	if tau_b == null or tau_c == null:
		return []
	
	# Perform a flip23 on tau+tau_a first (creates flat tetrahedron), then flip32 on result
	# As per paper: flip44 = flip23 + immediate flip32 on the flat tetrahedron
	var after23 := _flip23(tau, tau_a, pi)
	if after23.is_empty():
		return []
	# The flat tetrahedron is the one containing all four coplanar vertices
	for t in after23:
		if _tet_is_flat(t):
			# Now flip32 this flat tetrahedron with tau_b or tau_c
			var neighbour : Tetrahedron = null
			for f in 4:
				var nb : Tetrahedron = t.neighbours[f]
				if nb == tau_b or nb == tau_c:
					neighbour = nb
					break
			if neighbour != null:
				return _flip23(t, neighbour, pi) # degenerately becomes a flip32-like op
	return after23

# ==================================================================================================
# Helper functions
# ==================================================================================================

func _make_tetrahedron(v0: int, v1: int, v2: int, v3: int) -> Tetrahedron:
	var t := Tetrahedron.new(PackedInt32Array([v0, v1, v2, v3]))
	return t

func _replace_tet(old_tet: Tetrahedron, new_tet: Tetrahedron) -> void:
	var idx := tetrahedra.find(old_tet)
	if idx != -1:
		tetrahedra[idx] = new_tet
	old_tet.invalidate_cc()

func _remove_tet(t: Tetrahedron) -> void:
	tetrahedra.erase(t)
	t.invalidate_cc()

func _shared_face(tet: Tetrahedron, neighbour: Tetrahedron) -> int:
	for f in 4:
		if tet.neighbours[f] == neighbour:
			return f
	return -1

func _tet_touches_big(tet: Tetrahedron) -> bool:
	for v in tet.vertices:
		if v < 4:
			return true
	return false

func _tet_is_flat(t: Tetrahedron) -> bool:
	var a := points[t.vertices[0]]
	var b := points[t.vertices[1]]
	var c := points[t.vertices[2]]
	var d := points[t.vertices[3]]
	var vol := absf((b-a).cross(c-a).dot(d-a))
	return vol < EPSILON * EPSILON

## Find a third tetrahedron sharing edges pd and ab, bc or ac.
func _find_third_tet(tau: Tetrahedron, tau_a: Tetrahedron, p: int, d: int, a: int, b: int, c: int) -> Tetrahedron:
	for f in 4:
		var neighbour : Tetrahedron = tau.neighbours[f]
		if neighbour == null or neighbour == tau_a:
			continue
		if (neighbour.local_index(p) != -1 and neighbour.local_index(d) != -1) and (neighbour.local_index(a) != -1 or neighbour.local_index(b) != -1 or neighbour.local_index(c) != -1):
			return neighbour
	return null

func _neighbour_sharing_edge_and_vertex(t: Tetrahedron, v0: int, v1: int, apex: int) -> Tetrahedron:
	for f in 4:
		var neighbour : Tetrahedron = t.neighbours[f]
		if neighbour == null:
			continue
		if neighbour.local_index(v0) != -1 and neighbour.local_index(v1) != -1 and neighbour.local_index(apex) == -1:
			return neighbour
	return null

# ==================================================================================================
# Geometric predicates
# ==================================================================================================

## Determines if a point p is over, under or lies on a plane defined by three points a, b and c.
## Returns a positive value when the point p is above the plane defined by a, b and c; a negative value
## if p is under the plane; and exactly 0 if p is directly on the plane. It is consistent with the left-hand rule
func _orient(ai: int, bi: int, ci: int, pi: int) -> float:
	var a := points[ai]
	var b := points[bi]
	var c := points[ci]
	var p := points[pi]
	return _orient_points(a, b, c, p)

func _orient_points(a: Vector3, b: Vector3, c: Vector3, p: Vector3) -> float:
	# Translate by -p (numerically stabler)
	var ax := a.x - p.x
	var ay := a.y - p.y
	var az := a.z - p.z
	var bx := b.x - p.x
	var by := b.y - p.y
	var bz := b.z - p.z
	var cx := c.x - p.x
	var cy := c.y - p.y
	var cz := c.z - p.z
	return (ax * (by * cz - bz * cy) - ay * (bx * cz - bz * cx) + az * (bx * cy - by * cx))

## Determines if a point p is inside, outside or lies on a sphere defined by four points a, b, c and d.
## A positive value is returned if p is inside the sphere; a negative if p is outside; and exactly 0
## if p is directly on the sphere
## The sign of the determinant is multiplied by sign(orient(a,b,c,d)) to give a result that
## is orientation-independent.
func _in_sphere(a: int, b: int, c: int, d: int, p: int) -> float:
	var pa := points[a] - points[p]
	var pa2 := pa.length_squared()
	var pb := points[b] - points[p]
	var pb2 := pb.length_squared()
	var pc := points[c] - points[p]
	var pc2 := pc.length_squared()
	var pd := points[d] - points[p]
	var pd2 := pd.length_squared()
	return _det4(pa.x, pa.y, pa.z, pa2, pb.x, pb.y, pb.z, pb2, pc.x, pc.y, pc.z, pc2, pd.x, pd.y, pd.z, pd2) * signf(_orient(a, b, c, d))

## Returns the determinent of a 3x3 matrix
func _det3(ax:float,ay:float,az:float,
		bx:float,by:float,bz:float,
		cx:float,cy:float,cz:float) -> float:
	return (ax*(by*cz - bz*cy) - ay*(bx*cz - bz*cx) + az*(bx*cy - by*cx))

## Returns the determinant of a 4x4 matrix
func _det4( a00: float, a01: float, a02: float, a03: float,
		a10: float, a11: float, a12: float, a13: float,
		a20: float, a21: float, a22: float, a23: float,
		a30: float, a31: float, a32: float, a33: float) -> float:
	var m0 := a11*(a22*a33-a23*a32) - a12*(a21*a33-a23*a31) + a13*(a21*a32-a22*a31)
	var m1 := a10*(a22*a33-a23*a32) - a12*(a20*a33-a23*a30) + a13*(a20*a32-a22*a30)
	var m2 := a10*(a21*a33-a23*a31) - a11*(a20*a33-a23*a30) + a13*(a20*a31-a21*a30)
	var m3 := a10*(a21*a32-a22*a31) - a11*(a20*a32-a22*a30) + a12*(a20*a31-a21*a30)
	return a00*m0 - a01*m1 + a02*m2 - a03*m3

# ==================================================================================================
# Circumcentre
# ==================================================================================================

func _circumcentre(tet: Tetrahedron) -> Vector3:
	if tet._cc_valid:
		return tet._cc_centre
	var a := points[tet.vertices[0]]
	var b := points[tet.vertices[1]]
	var c := points[tet.vertices[2]]
	var d := points[tet.vertices[3]]
	# Solve the linear system from the circumsphere equations.
	var ab := b - a
	var ac := c - a
	var ad := d - a
	var ab2 := ab.dot(ab)
	var ac2 := ac.dot(ac)
	var ad2 := ad.dot(ad)
	var denom := 2.0 * _det3(ab.x,ab.y,ab.z, ac.x,ac.y,ac.z, ad.x,ad.y,ad.z)
	if absf(denom) < EPSILON:
		tet._cc_valid  = true
		tet._cc_centre = (a + b + c + d) * 0.25   # fallback: centroid
		return tet._cc_centre
	var rx := _det3(ab2,ab.y,ab.z, ac2,ac.y,ac.z, ad2,ad.y,ad.z) / denom
	var ry := _det3(ab.x,ab2,ab.z, ac.x,ac2,ac.z, ad.x,ad2,ad.z) / denom
	var rz := _det3(ab.x,ab.y,ab2, ac.x,ac.y,ac2, ad.x,ad.y,ad2) / denom
	tet._cc_centre = a + Vector3(rx, ry, rz)
	tet._cc_valid  = true
	return tet._cc_centre

# ==================================================================================================
# Public helper functions for Voronoi fracture
# ==================================================================================================

## Return all tetrahedra incident to user-point index ui (0-based, not counting sentinels).
func get_star(ui: int) -> Array:
	var global_index := ui + 4
	var star : Array = []
	for t in tetrahedra:
		if t != null and t.local_index(global_index) != -1:
			star.append(t)
	return star

## Return neighbour user-point indices for user-point ui (Delaunay edges from ui).
func get_delaunay_neighbours(ui: int) -> PackedInt32Array:
	var global_index  := ui + 4
	var neighbours := PackedInt32Array()
	var seen : Dictionary = {}
	for t in tetrahedra:
		if t == null or t.local_index(global_index) == -1:
			continue
		for local_vertex in 4:
			var v_index : int = t.vertices[local_vertex]
			if v_index >= 4 and v_index != global_index and not seen.has(v_index):
				seen[v_index] = true
				neighbours.append(v_index - 4)
	return neighbours

## Return the Voronoi cell vertices for user-point ui as an Array[Vector3].
func get_voronoi_cell_vertices(ui: int) -> PackedVector3Array:
	var star := get_star(ui)
	var verts : PackedVector3Array = PackedVector3Array()
	for t in star:
		if not _tet_touches_big(t):
			verts.append(_circumcentre(t))
		else:
			#TODO
			continue
	return verts

## Verify the DT by checking the InSphere condition for all tetrahedron/neighbour pairs.
## Returns the number of violations found (0 = valid DT).
func verify() -> int:
	var violations := 0
	for ti in tetrahedra.size():
		var tet : Tetrahedron = tetrahedra[ti]
		if tet == null:
			continue
		for f in 4:
			var nbr : Tetrahedron = tet.neighbours[f]
			if nbr == null:
				continue
			var apex := nbr.vertices[tet.neighbour_face[f]]
			var s := _in_sphere(tet.vertices[0], tet.vertices[1], tet.vertices[2], tet.vertices[3], apex)
			if s > EPSILON:
				violations += 1
	@warning_ignore("integer_division")
	return violations / 2   # each pair counted twice

# ==================================================================================================
# DEBUG Functions
# ==================================================================================================

var color_dt := Color(0.0, 1.0, 0.0, 1.0)
var color_voronoi := Color(1.0, 0.0, 0.0, 1.0)
var voronoi_clip_radius : float = INF

## Draw all Delaunay tetrahedra edges in green.
## Pass the DelaunayTetrahedralization3D instance after insert_points().
func draw_dt(skip_sentinel_tets: bool = true) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var mat := _wire_material(color_dt)
	
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	
	var seen : Dictionary = {} # avoid duplicate edges
	
	print(tetrahedra.size())
	for t in tetrahedra:
		if t == null:
			continue
		if skip_sentinel_tets and _touches_sentinel(t):
			continue
		
		for i in 4:
			for j in range(i + 1, 4):
				var a : int = t.vertices[i]
				var b : int = t.vertices[j]
				var key := mini(a, b) * 100000 + maxi(a, b)
				if seen.has(key):
					continue
				seen[key] = true
				im.surface_set_color(color_dt)
				im.surface_add_vertex(points[a])
				im.surface_set_color(color_dt)
				im.surface_add_vertex(points[b])
	
	im.surface_end()
	
	return _make_mesh_instance(im, mat)
 
### Draw all Voronoi edges in red.
### Extracts the Voronoi diagram internally — no separate call needed.
#func draw_voronoi() -> MeshInstance3D:
	#var vd := extract_voronoi()
	#var im := ImmediateMesh.new()
	#var mat := _wire_material(color_voronoi)
	#
	#im.surface_begin(Mesh.PRIMITIVE_LINES)
	#
	#for edge in vd.edges:
		#var p0 : Vector3 = vd.vertices[edge[0]]
		#var p1 : Vector3 = vd.vertices[edge[1]]
		#
		## Optional clip: skip edges with endpoints far from origin
		#if voronoi_clip_radius < INF:
			#if p0.length() > voronoi_clip_radius or p1.length() > voronoi_clip_radius:
				#continue
		#
		#im.surface_set_color(color_voronoi)
		#im.surface_add_vertex(p0)
		#im.surface_set_color(color_voronoi)
		#im.surface_add_vertex(p1)
	#
	#im.surface_end()
	#
	#return _make_mesh_instance(im, mat)


func _make_mesh_instance(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
 
## Unshaded, vertex-colour wire material.
func _wire_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	mat.flags_use_point_size = false
	mat.no_depth_test = false
	mat.render_priority = 1
	return mat

func _touches_sentinel(tet: Tetrahedron) -> bool:
	for v in tet.vertices:
		if v < 4:
			return true
	return false
