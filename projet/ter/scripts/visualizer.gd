class_name Visualizer
extends RefCounted

var points_node: Node3D
var points_node2: Node3D
var base_point: MeshInstance3D

func _init(pn: Node3D, pn2: Node3D, bp: MeshInstance3D):
	points_node = pn
	points_node2 = pn2
	base_point = bp

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
	show_points_3d(points_3d, color, points_node)

func show_points_3d(points: PackedVector3Array, color: Color, node: Node):
	for point in points:
		var new_point := MeshInstance3D.new()
		new_point.mesh = PointMesh.new()
		new_point.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		new_point.position = point
		new_point.mesh.material = base_point.mesh.material.duplicate()
		new_point.mesh.material.albedo_color = color
		node.add_child(new_point)

# visualise les points avec gradient de couleur basé sur la distance à l'impact
func show_points_3d_with_impact(points: PackedVector3Array, impact: Vector3, node: Node):
	var max_distance: float = 0.0
	for point in points:
		var dist: float = point.distance_to(impact)
		if dist > max_distance:
			max_distance = dist
	
	if max_distance == 0.0:
		max_distance = 1.0
			
	for point in points:
		var new_point := MeshInstance3D.new()
		new_point.mesh = PointMesh.new()
		new_point.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		new_point.position = point
		new_point.mesh.material = base_point.mesh.material.duplicate()
		
		var distance: float = point.distance_to(impact)
		var ratio: float = distance / max_distance
		
		var point_color: Color
		if ratio < 0.33:
			# rouge à orange
			point_color = Color.RED.lerp(Color(1.0, 0.5, 0.0), ratio * 3.0)
		elif ratio < 0.66:
			# orange à jaune
			point_color = Color(1.0, 0.5, 0.0).lerp(Color.YELLOW, (ratio - 0.33) * 3.0)
		else:
			# jaune à vert
			point_color = Color.YELLOW.lerp(Color.GREEN, (ratio - 0.66) * 3.0)
		
		new_point.mesh.material.albedo_color = point_color
		node.add_child(new_point)
	
	var impact_mesh := MeshInstance3D.new()
	impact_mesh.mesh = PointMesh.new()
	impact_mesh.position = impact
	impact_mesh.mesh.material = base_point.mesh.material.duplicate()
	impact_mesh.mesh.material.albedo_color = Color.MAGENTA
	node.add_child(impact_mesh)

func show_tetrahedralization(points: PackedVector3Array, voronoi_fracture: VoronoiFracture, parent: Node):
	voronoi_fracture.bowyer_watson(points)
	voronoi_fracture.compute_voronoi_diagram()
	var tetrahedralization_debug_mesh = voronoi_fracture.create_debug_mesh()
	parent.add_child(tetrahedralization_debug_mesh)
	var voronoi_diagram_debug_mesh = voronoi_fracture.create_debug_voronoi_mesh()
	parent.add_child(voronoi_diagram_debug_mesh)