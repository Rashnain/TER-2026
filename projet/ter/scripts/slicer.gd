extends Node3D

var aabb: AABB
@onready var aabb_node: MeshInstance3D = $aabb
@onready var points_node: Node3D = $aabb/points
@onready var base_point: MeshInstance3D = $aabb/base_point
@onready var node_3d: Node3D = $Node3D
@onready var mesh_to_cut: RigidBody3D = $Node3D/RigidBody3D

@onready var slice_button: Button = %SliceButton
@onready var reset_button: Button = %ResetButton
@onready var points_spin: SpinBox = %PointsSpinBox
@onready var depth_spin: SpinBox = %DepthSpinBox

var original_mesh_instance: MeshInstance3D
var bowyer_watson: BowyerWatson3D
var tetrahedralization_debug_mesh: Node3D
var voronoi_diagram_debug_mesh: Node3D

func slice_object(mesh_instance: MeshInstance3D, points: PackedVector3Array, depth: int):
	if depth <= 0 or mesh_instance == null:
		return
		
	var array_mesh: ArrayMesh
	if mesh_instance.mesh is PrimitiveMesh:
		array_mesh = ArrayMesh.new()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_instance.mesh.get_mesh_arrays())
	else:
		array_mesh = mesh_instance.mesh

	var st_left = SurfaceTool.new()
	var st_right = SurfaceTool.new()
	st_left.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_right.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mdt = MeshDataTool.new()
	mdt.create_from_surface(array_mesh, 0)

	var plane = plane_from_points(points)
	var intersection_points : PackedVector3Array = []

	for i in range(mdt.get_face_count()):
		var v1 := mdt.get_vertex(mdt.get_face_vertex(i, 0))
		var v2 := mdt.get_vertex(mdt.get_face_vertex(i, 1))
		var v3 := mdt.get_vertex(mdt.get_face_vertex(i, 2))
		var triangle := PackedVector3Array([v1, v2, v3])
		
		var poly_left := Geometry3D.clip_polygon(triangle, plane)
		var poly_right := Geometry3D.clip_polygon(triangle, -plane)

		if poly_left.size() >= 3:
			add_poly_to_st(st_left, poly_left)
			# On récupère les points d'intersection qu'ici pour limiter les doublons
			for p in poly_left:
				if abs(plane.distance_to(p)) < 0.0005:
					intersection_points.append(p)
		if poly_right.size() >= 3:
			add_poly_to_st(st_right, poly_right)

	if intersection_points.size() >= 3:
		fill_cut_hole(st_left, intersection_points, plane)
		fill_cut_hole(st_right, intersection_points, -plane)

	st_left.generate_normals()
	st_left.index()
	st_right.generate_normals()
	st_right.index()
	
	var mesh_left = st_left.commit()
	var mesh_right = st_right.commit()

	var velocity = mesh_instance.get_parent().linear_velocity if mesh_instance.get_parent() is RigidBody3D else Vector3.ZERO
	var mi3d_left = create_piece(mesh_left, mesh_instance.global_transform, velocity, plane.normal * 0.001, true) #offset pour eviter souci de collision
	var mi3d_right = create_piece(mesh_right, mesh_instance.global_transform, velocity, -plane.normal * 0.001, false)

	mesh_instance.get_parent().queue_free()

	if points.size() >= 2:
		slice_object(mi3d_left, points, depth - 1)
		slice_object(mi3d_right, points, depth - 1)

# ça utilise le fan clipping (c'est pas fou ça fait des artefacts) 
#func fill_cut_hole(st: SurfaceTool, points: PackedVector3Array, plane: Plane):
	#if points.size() < 3: return
	#
	## calcul centre
	#var center = Vector3.ZERO
	#for p in points: center += p
	#center /= points.size()
	#
	#var v_up = plane.normal.cross(Vector3.RIGHT if abs(plane.normal.x) < 0.9 else Vector3.FORWARD).normalized()
	#var v_right = plane.normal.cross(v_up).normalized()
	#
	#var sorted_points = Array(points)
	#sorted_points.sort_custom(func(a, b):
		#var da = a - center
		#var db = b - center
		#return atan2(da.dot(v_up), da.dot(v_right)) < atan2(db.dot(v_up), db.dot(v_right))
	#)
#
	#for i in range(sorted_points.size()):
		#var p1 = sorted_points[i]
		#var p2 = sorted_points[(i + 1) % sorted_points.size()]
		#if p1.distance_squared_to(p2) < 0.00001: continue
		#st.add_vertex(center)
		#st.add_vertex(p1)
		#st.add_vertex(p2)

#La c'est le ear clipping comme on avait dit en réu
func fill_cut_hole(st: SurfaceTool, points: PackedVector3Array, plane: Plane):
	if points.size() < 3: return
	#calcul centre du trou
	var center = Vector3.ZERO
	for p in points: center += p
	center /= points.size()
	#creation du plan pour projeter les points	
	var v_up = plane.normal.cross(Vector3.RIGHT if abs(plane.normal.x) < 0.9 else Vector3.FORWARD).normalized()
	var v_right = plane.normal.cross(v_up).normalized()
	#on tri les points pour faire le contour correctement
	var sorted_points = Array(points)
	sorted_points.sort_custom(func(a, b):
		var da = a - center
		var db = b - center
		return atan2(da.dot(v_up), da.dot(v_right)) < atan2(db.dot(v_up), db.dot(v_right))
	)
	#on passe les point3D en 2D pour faciliter
	var points_2d = PackedVector2Array()
	for p in sorted_points:
		points_2d.append(Vector2(p.dot(v_right), p.dot(v_up)))
	# ear clipping -> renvoie une liste d'indice par trois pour lestriangles
	var indices = Geometry2D.triangulate_polygon(points_2d)
	if indices.is_empty():
		return
	#on assemble
	for i in range(0, indices.size(), 3):
		var p1 = sorted_points[indices[i]]
		var p2 = sorted_points[indices[i+1]]
		var p3 = sorted_points[indices[i+2]]
		st.add_vertex(p1)
		st.add_vertex(p2)
		st.add_vertex(p3)
		
func add_poly_to_st(st: SurfaceTool, poly: PackedVector3Array):
	# fan triangulation
	for i in range(1, poly.size() - 1):
		st.add_vertex(poly[0])
		st.add_vertex(poly[i])
		st.add_vertex(poly[i+1])


func create_piece(m: Mesh, t: Transform3D, velocity: Vector3, offset: Vector3, is_left: bool) -> MeshInstance3D:
	if m.get_surface_count() == 0 or m.get_aabb().size.length() < 0.01:
		return null

	var new_body = RigidBody3D.new()
	var new_mesh_inst = MeshInstance3D.new()
	var new_shape = CollisionShape3D.new()
	
	new_mesh_inst.mesh = m
	# Convex shape est plus stable pour les RigidBodies
	new_shape.shape = m.create_convex_shape()
	
	var mat := StandardMaterial3D.new()
	# Correction Aliasing : textures et ombres
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = Color.PURPLE if is_left else Color.PINK
	
	new_mesh_inst.material_override = mat
	new_body.add_child(new_mesh_inst)
	new_body.add_child(new_shape)

	node_3d.add_child(new_body)
	new_body.global_transform = t
	new_body.global_translate(offset) # Écarte légèrement les morceaux
	new_body.linear_velocity = velocity

	return new_mesh_inst

func sample_aabb(points: PackedVector3Array, amount: int):
	# sample random points into the aabb
	var start := aabb.position
	var size := aabb.size
	for i in amount:
		var x := randf()
		var y := randf()
		var z := randf()
		points.append(Vector3(start.x + size.x * x, start.y + size.y * y, start.z + size.z * z))

func show_points(points: PackedVector3Array):
	for point in points:
		var new_point := base_point.duplicate()
		new_point.position = point
		points_node.add_child(new_point)
	base_point.visible = false

func show_tetrahedralization(points: PackedVector3Array):
	bowyer_watson.bowyer_watson(points)
	bowyer_watson.compute_voronoi_diagram()
	tetrahedralization_debug_mesh = bowyer_watson.create_debug_mesh()
	add_child(tetrahedralization_debug_mesh)
	voronoi_diagram_debug_mesh = bowyer_watson.create_debug_voronoi_mesh()
	add_child(voronoi_diagram_debug_mesh)

func plane_from_points(points: PackedVector3Array) -> Plane:
	# pick two points and return a plane
	if points.size() >= 2:
		var plane_normal := points[0] - points[1]
		points.remove_at(0)
		points.remove_at(0)
		return Plane(plane_normal)
	return Plane.PLANE_XZ

#func _ready():
	#var mesh: MeshInstance3D = mesh_to_cut.get_node("MeshInstance3D")
	#var voronoi_points: PackedVector3Array
	#aabb = mesh.get_aabb()
	#aabb.abs()
	#aabb_node.mesh.size = aabb.size
	#sample_aabb(voronoi_points, 50)
	#show_points(voronoi_points)
	#aabb_node.position = Vector3(-1.5, 1, 0)
	#slice_object(mesh, voronoi_points, 2)
	
	
func _ready():
	bowyer_watson = BowyerWatson3D.new()
	add_child(bowyer_watson)
	original_mesh_instance = mesh_to_cut.get_node("MeshInstance3D")
	points_spin.value = 50 #valeurs par defaut
	depth_spin.value = 2
	slice_button.pressed.connect(_on_slice_pressed)
	reset_button.pressed.connect(reset_scene)

func _on_slice_pressed():
	clean_pieces()
	var nb_points = int(points_spin.value)
	var depth = int(depth_spin.value)
	aabb = original_mesh_instance.get_aabb()
	aabb.abs()
	aabb_node.mesh.size = aabb.size
	aabb_node.position = Vector3(-1.5, 1, 0)
	var voronoi_points: PackedVector3Array = []
	sample_aabb(voronoi_points, nb_points)
	show_points(voronoi_points)
	show_tetrahedralization(voronoi_points)
	slice_object(original_mesh_instance, voronoi_points, depth)

func reset_scene():
	get_tree().reload_current_scene()

func clean_pieces():
	for p in points_node.get_children():
		p.queue_free()
	base_point.visible = false
	for child in node_3d.get_children():
		child.queue_free()
