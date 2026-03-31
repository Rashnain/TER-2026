extends Node3D

var aabb: AABB
@onready var aabb_node: MeshInstance3D = %aabb
@onready var points_node: Node3D = %points
@onready var base_point: MeshInstance3D = %base_point
@onready var pieces_node: Node3D = %pieces
@onready var mesh_to_cut: RigidBody3D = %pieces/RigidBody3D

@onready var slice_button: Button = %SliceButton
@onready var reset_button: Button = %ResetButton
@onready var points_spin: SpinBox = %PointsSpinBox
@onready var depth_spin: SpinBox = %DepthSpinBox

var original_mesh_instance: MeshInstance3D
var voronoi_fracture: VoronoiFracture
var tetrahedralization_debug_mesh: Node3D
var voronoi_diagram_debug_mesh: Node3D

func slice_object(mesh_instance: MeshInstance3D, points: PackedVector3Array, depth: int):
	if depth <= 0 or mesh_instance == null:
		return

	# 1. Prepare the Initial Mesh Data
	var array_mesh: ArrayMesh
	if mesh_instance.mesh is PrimitiveMesh:
		array_mesh = ArrayMesh.new()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_instance.mesh.get_mesh_arrays())
	else:
		array_mesh = mesh_instance.mesh

	
	if points.size() < 2: return
	var p1 = points[0]
	var p2 = points[1]
	var plane_normal = (p1 - p2).normalized()	#on trouve la normale au plan
	plane_normal = (plane_normal + Vector3(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), randf_range(-0.1, 0.1))).normalized() #on rajoute un peu d'aléatoire
	var plane_point = (p1 + p2) / 2.0 #on trouve le centre du plan (sinon par defaut c'est l'origine du monde)
	var plane = Plane(plane_normal, plane_point)
	
	points.remove_at(0)
	points.remove_at(0)

	var st_left = SurfaceTool.new()
	var st_right = SurfaceTool.new()
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

		var poly_left := Geometry3D.clip_polygon(triangle, plane)
		var poly_right := Geometry3D.clip_polygon(triangle, -plane)

		if poly_left.size() >= 3:
			add_poly_to_st(st_left, poly_left)
			for p in poly_left:
				if abs(plane.distance_to(p)) < 0.001:
					intersection_points.append(p)
					
		if poly_right.size() >= 3:
			add_poly_to_st(st_right, poly_right)

	if intersection_points.size() >= 3:
		fill_cut_hole(st_left, intersection_points, plane)
		fill_cut_hole(st_right, intersection_points, -plane)

	var mesh_left = finalize_st(st_left)
	var mesh_right = finalize_st(st_right)

	var parent_body = mesh_instance.get_parent()
	var velocity = parent_body.linear_velocity if parent_body is RigidBody3D else Vector3.ZERO
	var trans = mesh_instance.global_transform

	var mi3d_left = create_piece(mesh_left, trans, velocity, plane.normal * 0.005, true, plane_point)
	var mi3d_right = create_piece(mesh_right, trans, velocity, -plane.normal * 0.005, false, plane_point)

	parent_body.queue_free()

	if points.size() >= 2:
		if mi3d_left: slice_object(mi3d_left, points.duplicate(), depth - 1)
		if mi3d_right: slice_object(mi3d_right, points.duplicate(), depth - 1)

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

func create_piece(m: Mesh, t: Transform3D, velocity: Vector3, offset: Vector3, is_left: bool,impact_point: Vector3 = Vector3.ZERO) -> MeshInstance3D:
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
	#mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	new_mesh_inst.material_override = mat
	new_body.add_child(new_mesh_inst)
	new_body.add_child(new_shape)

	pieces_node.add_child(new_body)
	new_body.global_transform = t
	new_body.global_translate(offset)
	new_body.linear_velocity = velocity
	if impact_point != Vector3.ZERO:
		var push_direction = offset.normalized()
		var force = 2000.0 
		new_body.apply_impulse(push_direction * force)
		
	new_body.global_transform = t
	new_body.global_translate(offset)
	new_body.linear_velocity = velocity

	return new_mesh_inst

# sample random points into the aabb
func sample_aabb(points: PackedVector3Array, amount: int):
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
		new_point.visible = true
		points_node.add_child(new_point)

func show_points_2d(points: PackedVector2Array, color: Color):
	var points_3d : PackedVector3Array = []
	for point in points:
		points_3d.append(Vector3(point.x, 0, point.y))
	show_points_3d(points_3d, color)

func show_points_3d(points: PackedVector3Array, color: Color):
	for point in points:
		var new_point := MeshInstance3D.new()
		new_point.mesh = PointMesh.new()
		new_point.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		new_point.position = point
		new_point.mesh.material = base_point.mesh.material.duplicate()
		new_point.mesh.material.albedo_color = color
		points_node.add_child(new_point)

func show_tetrahedralization(points: PackedVector3Array):
	voronoi_fracture.bowyer_watson(points)
	voronoi_fracture.compute_voronoi_diagram()
	tetrahedralization_debug_mesh = voronoi_fracture.create_debug_mesh()
	add_child(tetrahedralization_debug_mesh)
	voronoi_diagram_debug_mesh = voronoi_fracture.create_debug_voronoi_mesh()
	add_child(voronoi_diagram_debug_mesh)

# pick two points and return a plane
func plane_from_points(points: PackedVector3Array) -> Plane:
	if points.size() >= 2:
		var plane_normal := points[0] - points[1]
		points.remove_at(0)
		points.remove_at(0)
		return Plane(plane_normal)
	return Plane.PLANE_XZ

func _ready():
	voronoi_fracture = VoronoiFracture.new()
	add_child(voronoi_fracture)
	original_mesh_instance = mesh_to_cut.get_node("MeshInstance3D")

	aabb_node.rotate(Vector3.UP, PI/2) # debug pour ce qu'il y a en dessous

	#var polygon_crescent := [Vector2(0.6, 1), Vector2(0.2, 1), Vector2(0.0, 0.6), Vector2(0.2, 0.2), Vector2(0.6, 0.2), Vector2(0.4, 0.6)]
	#var clip_polygon_triangle := [Vector2(0.4, 0.4), Vector2(0.4, 0.0), Vector2(0.8, 0.2)]
	#show_points_2d(polygon_crescent, Color.GREEN)
	#show_points_2d(clip_polygon_triangle, Color.YELLOW)
	#var res := ClipPolygon.clip_polygon_2d(polygon_crescent, clip_polygon_triangle)
	#show_points_2d(res, Color.BLACK)

	#var polygon_square := [Vector2(0, 0), Vector2(0.67, 0), Vector2(0.67, 0.67), Vector2(0, 0.67)]
	#var clip_square := [Vector2(0.33, 0.33), Vector2(1, 0.33), Vector2(1, 1), Vector2(0.33, 1)]
	#show_points_2d(polygon_square, Color.GREEN)
	#show_points_2d(clip_square, Color.YELLOW)
	#var res := ClipPolygon.clip_polygon_2d(polygon_square, clip_square)
	#show_points_2d(res, Color.BLACK)

	var triangle := [Vector3(0.75, 0.25, 0.75), Vector3(0, 0.67, 0), Vector3(0.33, 0.5, -0.5)]
	var clip_tetrahedron := [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(0.67, 1, 0.67)]
	var clip_indices : Array[int] = [0, 3, 1, 1, 3, 2, 2, 3, 0, 0, 1, 2]
	show_points_3d(triangle, Color.GREEN)
	show_points_3d(clip_tetrahedron, Color.YELLOW)
	var res := ClipPolygon.clip_polygon_3d(triangle, clip_tetrahedron, clip_indices)
	show_points_3d(res[0], Color.BLACK)

func _on_slice_button_pressed():
	clean_pieces()
	var nb_points = int(points_spin.value)
	var depth = int(depth_spin.value)
	aabb = original_mesh_instance.get_aabb()
	aabb.abs()
	aabb_node.mesh.size = aabb.size
	var voronoi_points: PackedVector3Array = []
	sample_aabb(voronoi_points, nb_points)
	#show_points(voronoi_points)
	#show_tetrahedralization(voronoi_points)
	slice_object(original_mesh_instance, voronoi_points, depth)
	slice_button.disabled = true

func _on_reset_button_pressed():
	get_tree().reload_current_scene()

func _on_check_button_toggled(toggled_on: bool) -> void:
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if toggled_on else Viewport.DEBUG_DRAW_DISABLED

func clean_pieces():
	for point in points_node.get_children():
		point.queue_free()
	for piece in pieces_node.get_children():
		piece.queue_free()
