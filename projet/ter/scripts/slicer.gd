extends Node3D

var aabb: AABB
@onready var aabb_node: MeshInstance3D = %aabb
@onready var points_node: Node3D = %points
@onready var points_node2: Node3D = %pieces/points
@onready var base_point: MeshInstance3D = %base_point
@onready var pieces_node: Node3D = %pieces
@onready var mesh_to_cut: RigidBody3D = %pieces/RigidBody3D

@onready var slice_button: Button = %SliceButton
@onready var reset_button: Button = %ResetButton
@onready var points_spin: SpinBox = %PointsSpinBox
@onready var depth_spin: SpinBox = %DepthSpinBox
@onready var use_planes_button: CheckButton = %UsePlanesButton
@onready var use_voronoi_button: CheckButton = %UseVoronoi

var original_mesh_instance: MeshInstance3D
var voronoi_fracture: VoronoiFracture
var dt: DelaunayTetrahedralization3D
var vd: VoronoiDiagram3D
var tetrahedralization_debug_mesh: Node3D
var voronoi_diagram_debug_mesh: Node3D
var use_planes: bool
var use_voronoi: bool
var clip_tetrahedron: PackedVector3Array
var clip_indices: Array[int]

var point_sampler: PointSampler
var mesh_slicer: MeshSlicer
var piece_creator: PieceCreator
var visualizer: Visualizer
var impact_manager: ImpactManager

func _ready():
	voronoi_fracture = VoronoiFracture.new()
	dt = DelaunayTetrahedralization3D.new()
	vd = VoronoiDiagram3D.new()
	add_child(voronoi_fracture)
	original_mesh_instance = mesh_to_cut.get_node("MeshInstance3D")

	aabb = original_mesh_instance.get_aabb()
	aabb.abs()
	aabb_node.mesh.size = aabb.size

	aabb_node.rotate(Vector3.UP, PI/2)
	use_planes = use_planes_button.button_pressed
	use_voronoi = use_voronoi_button.button_pressed
	#clip_tetrahedron = [Vector3(0, 0, -2), Vector3(-2, 0, 0), Vector3(0, 0, 2), Vector3(0, 2, 0)] # full ext, aligné axes
	#clip_tetrahedron = [Vector3(0.5, 0, -2), Vector3(-2, 0, 0), Vector3(0, 0, 2), Vector3(0, 2, 0)] # full ext, !aligné
	#clip_tetrahedron = [Vector3(1, -0.35, -2), Vector3(-2, 0.5, 0), Vector3(0, 0, 2), Vector3(0, 2, 0)] # obj flottant
	#clip_tetrahedron = [Vector3(0, 0, -2), Vector3(-2, 0, 0), Vector3(0, 0, 2), Vector3(0, 0.4, 0)] # 1p int
	#clip_tetrahedron = [Vector3(0, 0, -2), Vector3(-0.4, 0, 0), Vector3(0, 0, 2), Vector3(0, 1, 0)] # 1p int
	#clip_tetrahedron = [Vector3(0, 0, -2), Vector3(-0.4, 0, 0), Vector3(0, 0, 2), Vector3(0, 0.4, 0)] # 2p int
	clip_tetrahedron = [Vector3(0, 0, -0.4), Vector3(-0.4, 0, 0), Vector3(0, 0, 2), Vector3(0, 0.4, 0)] # 3p int
	#clip_tetrahedron = [Vector3(0, 0, -0.4), Vector3(-0.4, 0, 0), Vector3(0, 0, 0.4), Vector3(0, 0.4, 0)] # 4p int
	clip_indices = [0, 3, 1, 1, 3, 2, 2, 3, 0, 0, 1, 2]

	var triangle := [Vector3(0, 0, 2), Vector3(-2, 0, 0), Vector3(0, 0, -2)]

	var dist = ClipPolygon.distance_to_triangle(Vector3(0, 0, 0), triangle)
	print("dist(0, 0, 0) = ", dist) # 0

	dist = ClipPolygon.distance_to_triangle(Vector3(0.5, 0, 2), triangle)
	print("dist(0.5, 0, 2) = ", dist) # 0.5

	dist = ClipPolygon.distance_to_triangle(Vector3(0.5, 0, 1), triangle)
	print("dist(0.5, 0, 1) = ", dist) # 0.5

	dist = ClipPolygon.distance_to_triangle(Vector3(-1, 0, 1.5), triangle)
	print("dist(-1, 0, 1.5) = ", dist) # <0.5

	dist = ClipPolygon.distance_to_triangle(Vector3(-0.5, 0, 0.5), triangle)
	print("dist(-0.5, 0, 0.5) = ", dist) # 0

	dist = ClipPolygon.distance_to_triangle(Vector3(-0.5, 0.6, 0.5), triangle)
	print("dist(-0.5, 0.6, 0.5) = ", dist) # ~0.6

	dist = ClipPolygon.distance_to_triangle(Vector3(0, 1, 0), triangle)
	print("dist(0, 1, 0) = ", dist) # 1

	# Initialize new classes
	point_sampler = PointSampler.new(aabb)
	visualizer = Visualizer.new(points_node, points_node2, base_point)
	piece_creator = PieceCreator.new(pieces_node, use_planes)
	mesh_slicer = MeshSlicer.new(use_planes, clip_tetrahedron, clip_indices, visualizer)
	impact_manager = ImpactManager.new()

	impact_manager.set_impact_at_position(Vector3(0, 0.5, 0.35), impact_manager.impact_falloff)  # on défini point d'impact et falloff

func _on_use_planes_toggled(toggled_on: bool) -> void:
	use_planes = toggled_on
	mesh_slicer.use_planes = use_planes
	piece_creator.use_planes = use_planes
	if toggled_on and use_voronoi_button.button_pressed:
		use_voronoi_button.button_pressed = false

func _on_slice_button_pressed():
	var start := Time.get_ticks_msec()
	clean_pieces()
	var nb_points = int(points_spin.value)
	var depth = int(depth_spin.value)
	var voronoi_points: PackedVector3Array = []
	
	if impact_manager.use_impact_distribution and not impact_manager.impact_point_set:
		impact_manager.impact_point = aabb.get_center()
		impact_manager.impact_point_set = true
	if impact_manager.use_impact_distribution and impact_manager.impact_point_set:
		point_sampler.sample_aabb_with_impact(voronoi_points, nb_points, impact_manager.impact_point, impact_manager.impact_falloff)
		visualizer.show_points_3d_with_impact(voronoi_points, impact_manager.impact_point, points_node)
	else:
		point_sampler.sample_aabb(voronoi_points, nb_points)
		visualizer.show_points(voronoi_points)
	
	dt.insert_points(voronoi_points)
	var nb_violations = dt.verify()
	if nb_violations > 0:
		print("violations = ", nb_violations)
	visualizer.show_tetrahedralization2(dt, points_node)
	visualizer.show_points_3d(dt.get_circumcenters(), dt.color_cc, points_node)
	vd.build(dt, aabb)
	#var cell = vd.cells[0]
	#var offset := 0
	#var new_clip_vertices : Array[Vector3] = []
	#var new_clip_indices : Array[int] = []
	#for face in cell.faces:
		#var vertices_count := 0
		#for v in face.vertices:
			#new_clip_vertices.append(v)
			#if vertices_count > 1:
				#new_clip_indices.append(offset)
				#new_clip_indices.append(offset + vertices_count-1)
				#new_clip_indices.append(offset + vertices_count)
			#vertices_count += 1
		#offset += vertices_count
	#mesh_slicer.clip_tetrahedron = new_clip_vertices
	#mesh_slicer.clip_indices = new_clip_indices
	#visualizer.show_tetrahedralization(voronoi_points, voronoi_fracture, self)

	var delta := Time.get_ticks_msec() - start
	print("avant slice_object = ", delta, " ms")
	start = Time.get_ticks_msec()
	if use_voronoi:
		mesh_slicer.voronoi_slicing(original_mesh_instance, vd, piece_creator)
	else:
		mesh_slicer.slice_object(original_mesh_instance, voronoi_points, depth, piece_creator)
	delta = Time.get_ticks_msec() - start
	print("slice_object = ", delta, " ms")
	visualizer.show_voronoi_dual(vd, points_node)
	visualizer.show_aabb_points(aabb, points_node)
	slice_button.disabled = true

func _on_reset_button_pressed():
	get_tree().reload_current_scene()

func _on_wireframe_toggled(toggled_on: bool) -> void:
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if toggled_on else Viewport.DEBUG_DRAW_DISABLED

func _on_back_face_culling_toggled(toggled_on: bool) -> void:
	var rigid_bodies: Array[Node] = pieces_node.get_children()
	for rb in rigid_bodies:
		if (rb.get_child_count() == 0): continue
		var mi := rb.get_child(0)
		if mi.material_override:
			mi.material_override.cull_mode = BaseMaterial3D.CULL_BACK if toggled_on else BaseMaterial3D.CULL_DISABLED

func clean_pieces():
	for point in points_node.get_children():
		point.queue_free()
	for piece in pieces_node.get_children():
		if piece.name != "points":
			piece.queue_free()

func _on_points_toggled(toggled_on: bool) -> void:
	visualizer.points_node.visible = toggled_on
	visualizer.points_node2.visible = toggled_on

func _on_use_voronoi_button_toggled(toggled_on: bool) -> void:
	use_voronoi = toggled_on
	if toggled_on and use_planes_button.button_pressed:
		use_planes_button.button_pressed = false
