class_name ImpactManager
extends RefCounted

var use_impact_distribution: bool = false
var impact_point: Vector3 = Vector3.ZERO
var impact_point_set: bool = false
var impact_falloff: float = 0.0

# Active/désactive la distribution avec impact et définit le point
func set_impact_distribution(enabled: bool, point: Vector3 = Vector3.ZERO, falloff: float = 0.5):
	use_impact_distribution = enabled
	impact_point = point
	impact_point_set = enabled
	impact_falloff = clamp(falloff, 0.0, 1.0)

# Définit le point d'impact au centre du mesh
func set_impact_at_center(aabb: AABB):
	var center = aabb.get_center()
	set_impact_distribution(true, center, impact_falloff)

# Définit le point d'impact à une position spécifique
func set_impact_at_position(position: Vector3, falloff: float = 0.5):
	set_impact_distribution(true, position, falloff)
