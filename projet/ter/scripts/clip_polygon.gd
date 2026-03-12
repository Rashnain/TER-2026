extends Node
class_name ClipPolygon

static func determinant(v1: Vector2, v2: Vector2) -> float:
	return v1.x * v2.y - v1.y * v2.x


static func clip_polygon_2d(polygon: PackedVector2Array, clipping_polygon: PackedVector2Array) -> Array[PackedVector2Array]:
	var inside : PackedVector2Array = []
	var outside : PackedVector2Array = []
	var results : Array[PackedVector2Array] = [inside, outside]
	for i in range(len(clipping_polygon)):
		print("Edge %d %d" % [i, (i+1) % len(clipping_polygon)])
		var p0 := clipping_polygon[i]
		var p1 := clipping_polygon[(i+1) % len(clipping_polygon)]
		var vector0 := p1 - p0
		for y in range(len(polygon)):
			var vector1 := polygon[y] - p0
			if determinant(vector0.normalized(), vector1.normalized()) > 0:
				print("%d: %f %f is inside" % [y, polygon[y].x, polygon[y].y])
				inside.append(polygon[y])
			else:
				print("%d: %f %f is outside" % [y, polygon[y].x, polygon[y].y])
				# TODO créer deux nouveaux points, en projetant le point sur chaqu'une de ses arrêtes
				outside.append(polygon[y])
				pass
		polygon = inside
		inside = []
	return results


static func clip_polygon_3d(polygon: PackedVector3Array, clipping_polygon: PackedVector3Array) -> Array[PackedVector3Array]:
	var results : Array[PackedVector3Array] = []
	return results
