class_name PointSampler
extends RefCounted

var aabb: AABB

func _init(bounds: AABB):
	aabb = bounds

# sample random points into the aabb
func sample_aabb(points: PackedVector3Array, amount: int):
	var start := aabb.position
	var size := aabb.size
	for i in amount:
		var x := randf()
		var y := randf()
		var z := randf()
		points.append(Vector3(start.x + size.x * x, start.y + size.y * y, start.z + size.z * z))

# sample points avec la densité basé sur le point d'impact
func sample_aabb_with_impact(points: PackedVector3Array, amount: int, impact: Vector3, falloff: float):
	var start: Vector3 = aabb.position
	var size: Vector3 = aabb.size
	var min_bound: Vector3 = start
	var max_bound: Vector3 = start + size
	var effective_impact: Vector3 = _clamp_point_to_aabb(impact, AABB(start, size))
	# Le rayon caractéristique : moitié de la plus petite dimension de l'AABB
	var characteristic_radius: float = min(size.x, size.y, size.z) * 0.5
	var near_ratio: float = lerp(0.2, 0.9, falloff)  # More extreme: 20% to 90% near impact
	var mid_ratio: float = lerp(0.3, 0.05, falloff)  # Reduced mid at high falloff
	var near_radius: float = characteristic_radius * lerp(0.4, 0.3, falloff)  # Tighter near radius at high falloff
	var mid_radius: float = characteristic_radius * lerp(0.9, 1.2, falloff)  # Larger mid radius
		
	for i in amount:
		var point: Vector3
		var pick: float = randf()
		if pick < near_ratio:
			point = _random_point_near_impact(effective_impact, near_radius, min_bound, max_bound)
		elif pick < near_ratio + mid_ratio:
			point = _random_point_near_impact(effective_impact, mid_radius, min_bound, max_bound)
		else:
			point = Vector3(start.x + randf() * size.x, start.y + randf() * size.y, start.z + randf() * size.z)
		points.append(point)
	

func _random_point_near_impact(impact: Vector3, radius: float, min_bound: Vector3, max_bound: Vector3) -> Vector3:
	var dir: Vector3 = Vector3.ZERO
	for attempt in range(10):
		dir = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		if dir == Vector3.ZERO:
			dir = Vector3(1, 0, 0)
		dir = dir.normalized() * randf() * radius
		var point: Vector3 = impact + dir
		if point.x >= min_bound.x and point.x <= max_bound.x and point.y >= min_bound.y and point.y <= max_bound.y and point.z >= min_bound.z and point.z <= max_bound.z:
			return point
	# fallback si trop de tentatives, utilise un point proche limitant la longueur du vecteur
	var fallback_dir: Vector3 = dir.limit_length(radius * 0.6)
	var fallback: Vector3 = impact + fallback_dir
	return Vector3(clamp(fallback.x, min_bound.x, max_bound.x), clamp(fallback.y, min_bound.y, max_bound.y), clamp(fallback.z, min_bound.z, max_bound.z))

func _clamp_point_to_aabb(point: Vector3, bounds: AABB) -> Vector3:
	return Vector3(
		clamp(point.x, bounds.position.x, bounds.position.x + bounds.size.x),
		clamp(point.y, bounds.position.y, bounds.position.y + bounds.size.y),
		clamp(point.z, bounds.position.z, bounds.position.z + bounds.size.z)
	)
