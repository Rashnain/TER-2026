extends Node3D

var aabb: AABB
@onready var aabb_node: MeshInstance3D = $aabb
@onready var points_node: Node3D = $aabb/points
@onready var base_point: MeshInstance3D = $aabb/base_point
@onready var node_3d: Node3D = $Node3D
@onready var mesh_to_cut: RigidBody3D = $Node3D/RigidBody3D

func slice_object(mesh_instance: MeshInstance3D, points: PackedVector3Array, depth: int):
	#await get_tree().create_timer(0.25).timeout
	if depth == 0:
		return
	var array_mesh: ArrayMesh
	if mesh_instance.mesh is PrimitiveMesh:
		var old_mesh: PrimitiveMesh = mesh_instance.mesh
		array_mesh = ArrayMesh.new()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, old_mesh.get_mesh_arrays())
	elif mesh_instance.mesh is ArrayMesh:
		array_mesh = mesh_instance.mesh

	var st_left = SurfaceTool.new()
	var st_right = SurfaceTool.new()

	st_left.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_right.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mdt = MeshDataTool.new()
	mdt.create_from_surface(array_mesh, 0)

	#var plane_normal = Vector3(1, 1, 1)
	#var plane = Plane(plane_normal)
	var plane = plane_from_points(points)
	plane.normalized()

	for i in range(mdt.get_face_count()):
		var v1 := mdt.get_vertex(mdt.get_face_vertex(i, 0))
		var v2 := mdt.get_vertex(mdt.get_face_vertex(i, 1))
		var v3 := mdt.get_vertex(mdt.get_face_vertex(i, 2))
		var triangle := PackedVector3Array([v1, v2, v3])
		var poly_left := Geometry3D.clip_polygon(triangle, plane)
		var poly_right := Geometry3D.clip_polygon(triangle, -plane)

		if poly_left.size() >= 3:
			add_poly_to_st(st_left, poly_left)
		if poly_right.size() >= 3:
			add_poly_to_st(st_right, poly_right)

	st_left.index()
	st_right.index()
	var mesh_left := st_left.commit()
	var mesh_right = st_right.commit()

	var offset := Vector3(0, 0, 0)
	var mi3d_left := create_piece(mesh_left, mesh_instance.global_transform, mesh_instance.get_parent().linear_velocity, offset, true)
	var mi3d_right := create_piece(mesh_right, mesh_instance.global_transform, mesh_instance.get_parent().linear_velocity, -offset, false)

	var points_left := Geometry3D.clip_polygon(points, plane)
	var points_right := Geometry3D.clip_polygon(points, -plane)

	mesh_instance.get_parent().queue_free()

	slice_object(mi3d_left, points_left, depth - 1)
	slice_object(mi3d_right, points_right, depth - 1)

func add_poly_to_st(st: SurfaceTool, poly: PackedVector3Array):
	# fan triangulation
	for i in range(1, poly.size() - 1):
		st.add_vertex(poly[0])
		st.add_vertex(poly[i])
		st.add_vertex(poly[i+1])

func create_piece(m: Mesh, t: Transform3D, velocity: Vector3, offset: Vector3, is_left: bool) -> MeshInstance3D:
	if m.get_surface_count() == 0:
		return

	var new_body = RigidBody3D.new()
	var new_mesh_inst = MeshInstance3D.new()
	var new_shape = CollisionShape3D.new()
	
	new_mesh_inst.mesh = m
	new_shape.shape = m.create_convex_shape()
	#var array_mesh := ArrayMesh.new()
	#var arrays := []
	#arrays.resize(ArrayMesh.ARRAY_MAX)
	#arrays[ArrayMesh.ARRAY_VERTEX] = new_shape.shape.points
	#array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	#new_mesh_inst.mesh = m
	var mat := StandardMaterial3D.new()
	new_mesh_inst.material_override = mat
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if (is_left):
		new_mesh_inst.material_override.albedo_color = Color.PURPLE
	else:
		new_mesh_inst.material_override.albedo_color = Color.PINK
	new_body.add_child(new_mesh_inst)
	new_body.add_child(new_shape)
	#new_body.gravity_scale = 0

	node_3d.add_child(new_body)
	new_body.global_transform = t
	new_body.global_translate(offset)
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

func plane_from_points(points: PackedVector3Array) -> Plane:
	# pick two points and return a plane
	if points.size() >= 2:
		var plane_normal := points[0] - points[1]
		points.remove_at(0)
		points.remove_at(0)
		return Plane(plane_normal)
	return Plane.PLANE_XZ

func _ready():
	var mesh: MeshInstance3D = mesh_to_cut.get_node("MeshInstance3D")
	var voronoi_points: PackedVector3Array
	aabb = mesh.get_aabb()
	aabb.abs()
	aabb_node.mesh.size = aabb.size
	sample_aabb(voronoi_points, 50)
	show_points(voronoi_points)
	aabb_node.position = Vector3(-1.5, 1, 0)
	slice_object(mesh, voronoi_points, 4)
