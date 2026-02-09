extends Node3D

var bounding_box: AABB
var voronoi_points: PackedVector3Array
@onready var points_3d: Node3D = $points
@onready var base_point: MeshInstance3D = $points/MeshInstance3D
@onready var aabb: MeshInstance3D = $points/aabb

func slice_object(mesh_instance: MeshInstance3D, rec: int):
	#await get_tree().create_timer(0.25).timeout
	if rec == 0:
		return
	var array_mesh: ArrayMesh
	if mesh_instance.mesh is PrimitiveMesh:
		var old_mesh: PrimitiveMesh = mesh_instance.mesh
		#on mets ses infos (triangles) dans un Array
		array_mesh = ArrayMesh.new()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, old_mesh.get_mesh_arrays())
	elif mesh_instance.mesh is ArrayMesh:
		array_mesh = mesh_instance.mesh
	#Initialisation des outils qui tracent les triangles
	var st_left = SurfaceTool.new()
	var st_right = SurfaceTool.new()
	#Préparation a tracer des triangles
	st_left.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_right.begin(Mesh.PRIMITIVE_TRIANGLES)
	#lit les informations du triangles
	var mdt = MeshDataTool.new()
	mdt.create_from_surface(array_mesh, 0)
	#le plan de coupe
	#var plane_normal = Vector3(1, 1, 1)
	var plane_normal = plane_from_points()
	var plane = Plane(plane_normal.normalized())
	#on parcourt les triangles du mesh
	for i in range(mdt.get_face_count()):
		#on récupère les sommets du triangles actuel
		var v1 = mdt.get_vertex(mdt.get_face_vertex(i, 0))
		var v2 = mdt.get_vertex(mdt.get_face_vertex(i, 1))
		var v3 = mdt.get_vertex(mdt.get_face_vertex(i, 2))
		#On regroupe en une liste
		var triangle = PackedVector3Array([v1, v2, v3])
		#compare le triangle et le plan, ne garde que la partie du triangle qui est "au-dessus" du plan, il crée de nouveaux points d'intersection.
		var poly_left = Geometry3D.clip_polygon(triangle, plane)
		#même cose pour l'autre coté
		var poly_right = Geometry3D.clip_polygon(triangle, -plane)

		if poly_left.size() >= 3: #Si la découpe a laissé au moins 3 points, on a de quoi faire un triangle
			add_poly_to_st(st_left, poly_left)	#on dessine le triangle
		if poly_right.size() >= 3:
			add_poly_to_st(st_right, poly_right)

	#ça fusionne les sommets qui ont la meme position
	st_left.index()
	st_right.index()
	#on transforme en vrai mesh utilisable
	var mesh_left = st_left.commit()
	var mesh_right = st_right.commit()
	
	var mi3d_left := create_piece(mesh_left, mesh_instance.global_transform, mesh_instance.get_parent().linear_velocity, Vector3(-0.5, 0, 0), true)
	var mi3d_right := create_piece(mesh_right, mesh_instance.global_transform, mesh_instance.get_parent().linear_velocity, Vector3(0.5, 0, 0), false)
	
	mesh_instance.get_parent().queue_free()

	slice_object(mi3d_left, rec - 1)
	slice_object(mi3d_right, rec - 1)

func add_poly_to_st(st: SurfaceTool, poly: PackedVector3Array):
	for i in range(1, poly.size() - 1):
		st.add_vertex(poly[0])
		st.add_vertex(poly[i])
		st.add_vertex(poly[i+1])

func create_piece(m: Mesh, t: Transform3D, v: Vector3, offset: Vector3, is_left: bool) -> MeshInstance3D:
	if m.get_surface_count() == 0:
		return

	var new_body = RigidBody3D.new()	#crée un rigidbody vide
	var new_mesh_inst = MeshInstance3D.new()
	var new_shape = CollisionShape3D.new()
	
	new_mesh_inst.mesh = m #on lui donne le mesh qu'on vient de créer
	new_shape.shape = m.create_convex_shape()	#on créé la boite de collision qui match la forme
	new_mesh_inst.material_override = StandardMaterial3D.new()
	new_mesh_inst.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	if (is_left):
		new_mesh_inst.material_override.albedo_color = Color.PURPLE
	else:
		new_mesh_inst.material_override.albedo_color = Color.PINK
	new_body.add_child(new_mesh_inst)
	new_body.add_child(new_shape)
	#new_body.gravity_scale = 0
	
	add_child(new_body)
	new_body.global_transform = t	#on place le nouveau mesh la ou etait l'ancien
	#new_body.global_translate(offset)	#on y applique un leger decalage
	new_body.linear_velocity = v #on lui donne la vitesse initiale du cube
	
	return new_mesh_inst

func sample_aabb(amount: int):
	# sample random points into the aabb and remove the ones that are not in the mesh
	var start := bounding_box.position
	var size := bounding_box.size
	for i in amount:
		var x := randf()
		var y := randf()
		var z := randf()
		voronoi_points.append(Vector3(start.x + size.x * x, start.y + size.y * y, start.z + size.z * z))

func show_points():
	for point in voronoi_points:
		var new_point := base_point.duplicate()
		new_point.position = point
		points_3d.add_child(new_point)
	base_point.visible = false

func plane_from_points() -> Plane:
	# pick two points and return a plane
	print(voronoi_points)
	var plane_normal := voronoi_points[0] - voronoi_points[1]
	voronoi_points.remove_at(0)
	voronoi_points.remove_at(0)
	return Plane(plane_normal.normalized())

func _ready():
	var mesh: MeshInstance3D = get_node("RigidBody3D").get_node("MeshInstance3D")
	bounding_box = mesh.custom_aabb
	bounding_box.abs()
	aabb.mesh.size = bounding_box.size
	print(bounding_box.position)
	print(bounding_box.size)
	aabb.position = bounding_box.position + bounding_box.size/2
	sample_aabb(50)
	show_points()
	slice_object(mesh, 4)
