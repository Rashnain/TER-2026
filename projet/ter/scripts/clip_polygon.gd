extends Node
class_name ClipPolygon


static func determinant(v1: Vector2, v2: Vector2) -> float:
	return v1.x * v2.y - v1.y * v2.x


static func intersection(v1: Vector2, v2: Vector2, clip_v1: Vector2, clip_v2: Vector2) -> Vector2:
	var denominator := (v1.x - v2.x) * (clip_v1.y - clip_v2.y) - (v1.y - v2.y) * (clip_v1.x - clip_v2.x)
	if abs(denominator) < 1e-07: # edges are parallels
		return Vector2.ZERO
	var start := v1.x * v2.y - v1.y * v2.x
	var end := clip_v1.x * clip_v2.y - clip_v1.y * clip_v2.x
	var x := (start * (clip_v1.x - clip_v2.x) - (v1.x - v2.x) * end) / denominator
	var y := (start * (clip_v1.y - clip_v2.y) - (v1.y - v2.y) * end) / denominator
	return Vector2(x, y)


static func intersection_stupid(v1: Vector2, v2: Vector2, clip_v1: Vector2, clip_v2: Vector2) -> Vector2:
	var edge := v2 - v1
	var length := edge.length()
	var dir := edge.normalized()
	var clip_edge := (clip_v2 - clip_v1).normalized()
	var clip_edge_v3 := Vector3(clip_edge.x, 0, clip_edge.y)
	var clip_edge_normal_v3 := clip_edge_v3.cross(Vector3(0, 1, 0)).normalized()
	var clip_edge_normal := Vector2(clip_edge_normal_v3.x, clip_edge_normal_v3.z)
	var t = (clip_v1 - v1).dot(clip_edge_normal) / dir.dot(clip_edge_normal)
	if t > 0 && t < length:
		return v1 + dir * t
	return Vector2.ZERO


# Sutherland–Hodgman algorithm
static func clip_polygon_2d(polygon: PackedVector2Array, clipping_polygon: PackedVector2Array) -> PackedVector2Array:
	var output := polygon.duplicate()
	for i in range(len(clipping_polygon)):
		var input := output.duplicate()
		output.clear()

		print("Edge %d-%d" % [i, (i + 1) % len(clipping_polygon)])
		var c0 := clipping_polygon[i]
		var c1 := clipping_polygon[(i + 1) % len(clipping_polygon)]
		var clip_edge := (c1 - c0).normalized()

		for y in range(len(input)):
			var current_point := input[y]
			var prev_point := input[(y - 1) % len(input)]

			var intersection_point := intersection(prev_point, current_point, c0, c1)

			var clip_to_current := (current_point - c0).normalized()
			var clip_to_prev := (prev_point - c0).normalized()
			var current_inside := determinant(clip_edge, clip_to_current)
			var prev_inside := determinant(clip_edge, clip_to_prev)

			if current_inside > 0:
				print("%d: %f %f is inside" % [y, current_point.x, current_point.y])
				if not prev_inside > 0:
					print("prev not inside")
					print(intersection_point)
					output.append(intersection_point)
				output.append(current_point)
			else:
				print("%d: %f %f is outside" % [y, current_point.x, current_point.y])
				if prev_inside > 0:
					print("prev inside")
					print(intersection_point)
					output.append(intersection_point)
	return output


static func clip_polygon_3d(polygon: PackedVector3Array, clipping_polygon: PackedVector3Array) -> Array[PackedVector3Array]:
	var results : Array[PackedVector3Array] = []
	return results
