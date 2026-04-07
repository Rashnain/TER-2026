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


static func ray_plane_intersection(plan_point: Vector3, plan_normal: Vector3, ray_origin: Vector3, ray_dest: Vector3) -> Vector3:
	var destination := (ray_dest - ray_origin).normalized()
	var t := (plan_point - ray_origin).dot(plan_normal) / destination.dot(plan_normal)
	return ray_origin + t * destination


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


static func clip_polygon_3d(triangle: PackedVector3Array, clipping_points: PackedVector3Array, clipping_indices: Array[int]) -> Array:
	var results : Array = [[], []] # [inside, [outsides...]]

	var triangle_count := clipping_indices.size() / 3;

	var input := triangle.duplicate()
	var output: PackedVector3Array = []
	var outside: PackedVector3Array = []

	for i in triangle_count:
		var a := clipping_indices[i * 3]
		var b := clipping_indices[i * 3 + 1]
		var c := clipping_indices[i * 3 + 2]
		print(a, " ", b, " ", c)
		var ab := clipping_points[b] - clipping_points[a]
		var ac := clipping_points[c] - clipping_points[a]
		var normal := ac.cross(ab).normalized()
		print(normal)

		for y in range(len(input)):
			var current_point := input[y]
			var prev_point := input[(y - 1) % len(input)]

			var current_inside := (clipping_points[a] - current_point).dot(normal)
			var prev_inside := (clipping_points[a] - prev_point).dot(normal)

			if current_inside >= 0:
				print("%d: %f %f %f is inside" % [y, current_point.x, current_point.y, current_point.z])
				if not prev_inside >= 0:
					print("prev outside")
					var intersection_point := ray_plane_intersection(clipping_points[a], normal, current_point, prev_point)
					print(intersection_point)
					output.append(intersection_point)
					outside.append(intersection_point)
				output.append(current_point)
			else:
				print("%d: %f %f %f is outside" % [y, current_point.x, current_point.y, current_point.z])
				if prev_inside >= 0:
					print("prev inside")
					var intersection_point := ray_plane_intersection(clipping_points[a], normal, prev_point, current_point)
					print(intersection_point)
					output.append(intersection_point)
					outside.append(intersection_point)
				outside.append(current_point)

		input = output.duplicate()
		output.clear()

		if len(outside) > 0:
			results[1].append(outside.duplicate())
		outside.clear()

	results[0] = input

	return results
