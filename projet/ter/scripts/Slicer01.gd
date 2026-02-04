extends Node3D

func slice_object(target: RigidBody3D):
	#On récupère le mesh
	var mesh_instance = target.get_node("MeshInstance3D")
	var old_mesh = mesh_instance.mesh
	#on mets ses infos (triangles) dans un Array
	var array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, old_mesh.get_mesh_arrays())
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
	var plane = Plane(Vector3.UP, 0)
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
	
	create_piece(mesh_left, target.global_transform, target.linear_velocity, Vector3(0, 0.2, 0))
	create_piece(mesh_right, target.global_transform, target.linear_velocity, Vector3(0, -0.2, 0))
	
	target.queue_free()

func add_poly_to_st(st: SurfaceTool, poly: PackedVector3Array):
	for i in range(1, poly.size() - 1):
		st.add_vertex(poly[0])
		st.add_vertex(poly[i])
		st.add_vertex(poly[i+1])

func create_piece(m: Mesh, t: Transform3D, v: Vector3, offset: Vector3):
	if m.get_surface_count() == 0:
		return

	var new_body = RigidBody3D.new()	#crée un rigidbody vide
	var new_mesh_inst = MeshInstance3D.new()
	var new_shape = CollisionShape3D.new()
	
	new_mesh_inst.mesh = m #on lui donne le mesh qu'on vient de créer
	new_shape.shape = m.create_convex_shape()	#on créé la boite de collision qui match la forme
	
	new_body.add_child(new_mesh_inst)
	new_body.add_child(new_shape)
	
	add_child(new_body)
	new_body.global_transform = t	#on place le nouveau mesh la ou etait l'ancien
	#new_body.global_translate(offset)	#on y applique un leger decalage
	new_body.linear_velocity = v #on lui donne la vitesse initiale du cube
	
func _ready():
	await get_tree().create_timer(1.0).timeout
	var target = get_node_or_null("RigidBody3D")
	if target:
		slice_object(target)
