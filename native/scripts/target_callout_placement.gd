class_name TargetCalloutPlacement
extends RefCounted
## Conservative target-local placement. Physical bounds include the whole card;
## visibility tests the entire finite viewing pyramid, not a few sample rays.
## If conservative tests reject every nearby candidate, the visual stays hidden.

const DEFAULT_SIZE: Vector3 = Vector3(0.24, 0.10, 0.016)
const CLEARANCE_M: float = 0.012
const EPSILON: float = 0.000001
const DEFAULT_OFFSETS: Array[Vector3] = [
	Vector3(0.22, 0, 0.10), Vector3(-0.22, 0, 0.10),
	Vector3(0, 0.13, 0.12), Vector3(0, -0.13, 0.12),
	Vector3(0.30, 0.06, 0.12), Vector3(-0.30, 0.06, 0.12),
	Vector3(0.22, 0.13, 0.17), Vector3(-0.22, 0.13, 0.17),
	Vector3(0, 0.20, 0.20), Vector3(0.36, 0.10, 0.16),
	Vector3(-0.36, 0.10, 0.16), Vector3(0, 0.25, 0.27),
	# Larger targets (the tray rotor silhouette) need room outside the entire
	# projected disk. These remain within the same0.48m target-local limit.
	Vector3(0, 0.30, -0.12), Vector3(0, 0.38, -0.12),
	Vector3(-0.36, 0.23, 0), Vector3(0.36, 0.23, 0),
	Vector3(-0.43, 0.04, 0.16), Vector3(0.43, 0.04, 0.16),
	Vector3(-0.25, 0.33, -0.12), Vector3(0.25, 0.33, -0.12),
	# Clear foreground lift posts at oblique/desktop viewing angles without
	# masking the full rotor silhouette or moving beyond target adjacency.
	Vector3(0.36, 0.10, 0.28), Vector3(-0.36, 0.10, 0.28),
	Vector3(0.42, 0.05, 0.20), Vector3(-0.42, 0.05, 0.20),
	Vector3(0, 0.04, 0.46), Vector3(0, -0.08, 0.44),
	Vector3(-0.15, 0.43, -0.06), Vector3(-0.10, 0.44, 0),
	Vector3(-0.18, 0.42, -0.04), Vector3(0.15, 0.43, -0.06),
	Vector3(-0.20, 0.42, -0.04), Vector3(-0.22, 0.42, -0.02)
]

static func find_placement(target_transform: Transform3D, head_transform: Transform3D, obstacles: Array, options: Dictionary = {}) -> Dictionary:
	var hidden: Dictionary = {"visible": false, "transform": Transform3D.IDENTITY, "bounds": AABB(), "reason": "No clear target-adjacent position.", "target_world_position": target_transform.origin, "candidate_index": -1}
	if not _finite_transform(target_transform) or not _finite_transform(head_transform):
		hidden.reason = "Invalid target or head transform."
		return hidden
	var size: Vector3 = options.get("size", DEFAULT_SIZE)
	var clearance: float = float(options.get("clearance", CLEARANCE_M))
	var max_distance: float = float(options.get("max_target_distance", 0.48))
	if not size.is_finite() or size.x <= 0 or size.y <= 0 or size.z <= 0 or not is_finite(clearance) or clearance < 0 or not is_finite(max_distance) or max_distance <= 0:
		hidden.reason = "Invalid callout bounds."
		return hidden
	var occluders: Array = options.get("occluders", obstacles)
	for item in obstacles + occluders:
		if not item is AABB or not item.position.is_finite() or not item.size.is_finite() or item.size.x < 0 or item.size.y < 0 or item.size.z < 0:
			hidden.reason = "Incomplete geometry bounds."
			return hidden
	var local_bounds := AABB(-size * 0.5, size)
	var target_bounds: AABB = options.get("target_bounds", AABB(target_transform.origin - Vector3.ONE * 0.01, Vector3.ONE * 0.02))
	if not target_bounds.position.is_finite() or not target_bounds.size.is_finite() or target_bounds.size.x <= 0 or target_bounds.size.y <= 0 or target_bounds.size.z <= 0:
		hidden.reason = "Invalid target bounds."
		return hidden
	var offsets: Array = options.get("candidate_offsets", DEFAULT_OFFSETS)
	var order: Array[int] = []
	var preferred: int = int(options.get("preferred_candidate", -1))
	if preferred >= 0 and preferred < offsets.size(): order.append(preferred)
	for candidate_index in range(offsets.size()):
		if candidate_index != preferred: order.append(candidate_index)
	var target_axes: Basis = target_transform.basis.orthonormalized()
	var eye_half_separation: float = float(options.get("eye_half_separation", 0.04))
	if not is_finite(eye_half_separation) or eye_half_separation < 0:
		hidden.reason = "Invalid stereo view separation."
		return hidden
	var eyes: Array[Vector3] = [head_transform.origin - head_transform.basis.x.normalized() * eye_half_separation, head_transform.origin + head_transform.basis.x.normalized() * eye_half_separation]
	for candidate_index in order:
		if typeof(offsets[candidate_index]) != TYPE_VECTOR3: continue
		var offset: Vector3 = offsets[candidate_index]
		if not offset.is_finite() or offset.length() > max_distance: continue
		var position: Vector3 = target_transform.origin + target_axes * offset
		var toward_head: Vector3 = head_transform.origin - position
		if toward_head.length() < float(options.get("min_head_distance", 0.20)) or toward_head.length() > float(options.get("max_head_distance", 5.0)): continue
		var up: Vector3 = Vector3.UP if absf(toward_head.normalized().dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
		var transform := Transform3D(Basis.looking_at(toward_head, up, true), position)
		var bounds: AABB = transform * local_bounds
		if bounds.position.y < float(options.get("floor_y", 0.015)): continue
		var clear: bool = true
		for obstacle in obstacles:
			if bounds.grow(clearance + EPSILON).intersects(obstacle):
				clear = false
				break
		if not clear: continue
		var corners: Array[Vector3] = _face_corners(transform, size)
		for eye in eyes:
			# Keep the target itself visible: a nearby prompt may not cover the
			# target's projected bounds just because it misses physical contact.
			if _pyramid_intersects(eye, _projected_face(eye, target_bounds), bounds):
				clear = false
				break
			for obstacle in occluders:
				if _pyramid_intersects(eye, corners, obstacle.grow(0.001)):
					clear = false
					break
			if not clear: break
		if clear:
			return {"visible": true, "transform": transform, "bounds": bounds, "reason": "Clear target-local candidate.", "target_world_position": target_transform.origin, "candidate_index": candidate_index}
	return hidden

static func collect_world_aabbs(branch: Node3D, excluded: Array = [], opaque_only: bool = false) -> Dictionary:
	var result: Dictionary = {"bounds": [], "complete": true, "issues": []}
	_collect(branch, excluded, opaque_only, result)
	return result

static func capture_geometry(branch: Node3D, excluded: Array = []) -> Dictionary:
	# Capture every descriptor, including currently hidden rotor/plane meshes.
	# Only local construction data/material classification is cached. World
	# transforms and visibility MUST be read live for every placement update.
	var result: Dictionary = {"entries": [], "complete": true, "issues": []}
	_capture(branch, excluded, result)
	return result

static func world_aabbs_from_capture(capture: Dictionary) -> Dictionary:
	var result: Dictionary = {"bounds": [], "opaque_bounds": [], "complete": true, "issues": []}
	for descriptor in capture.get("entries", []):
		var node: Variant = descriptor.node
		if not is_instance_valid(node):
			result.complete = false
			result.issues.append("Captured geometry was removed: " + str(descriptor.name))
			continue
		if not node.is_visible_in_tree(): continue
		if not bool(descriptor.complete):
			result.complete = false
			result.issues.append(descriptor.issue)
			continue
		var world: Transform3D = node.global_transform
		var count: int = descriptor.transforms.size()
		if node is MultiMeshInstance3D:
			if node.multimesh != descriptor.resource or node.multimesh.instance_count != count:
				result.complete = false
				result.issues.append("MultiMesh construction changed; rebuild callout capture: " + str(descriptor.name))
				continue
			if node.multimesh.visible_instance_count >= 0: count = mini(count, node.multimesh.visible_instance_count)
		for instance_index in range(count):
			var bounds: AABB = (world * descriptor.transforms[instance_index]) * descriptor.mesh_bounds
			result.bounds.append(bounds)
			if descriptor.opaque: result.opaque_bounds.append(bounds)
	return result

static func _capture(node: Node, excluded: Array, result: Dictionary) -> void:
	if node in excluded: return
	if (node is MeshInstance3D and node.mesh) or (node is MultiMeshInstance3D and node.multimesh and node.multimesh.mesh):
		var mesh: Mesh = node.mesh if node is MeshInstance3D else node.multimesh.mesh
		var descriptor: Dictionary = {"node": node, "name": str(node.name), "mesh_bounds": mesh.get_aabb(), "opaque": _opaque(node, mesh), "transforms": [], "complete": true, "issue": ""}
		if node is MeshInstance3D:
			descriptor.transforms = [Transform3D.IDENTITY]
		else:
			var multi: MultiMesh = node.multimesh
			descriptor.resource = multi
			var cached: Array = node.get_meta("callout_instance_transforms", [])
			if cached.size() >= multi.instance_count:
				descriptor.transforms = cached.slice(0, multi.instance_count).duplicate()
			elif DisplayServer.get_name() != "headless":
				for instance_index in range(multi.instance_count): descriptor.transforms.append(multi.get_instance_transform(instance_index))
			elif multi.instance_count > 0:
				descriptor.complete = false
				descriptor.issue = "Missing CPU instance transforms: " + str(node.name)
				result.complete = false
				result.issues.append(descriptor.issue)
		result.entries.append(descriptor)
	for child in node.get_children(): _capture(child, excluded, result)

static func _collect(node: Node, excluded: Array, opaque_only: bool, result: Dictionary) -> void:
	if node in excluded: return
	if node is Node3D and not node.is_visible_in_tree(): return
	if node is MeshInstance3D and node.mesh:
		if not opaque_only or _opaque(node, node.mesh): result.bounds.append(node.global_transform * node.mesh.get_aabb())
	elif node is MultiMeshInstance3D and node.multimesh and node.multimesh.mesh:
		var multi: MultiMesh = node.multimesh
		if not opaque_only or _opaque(node, multi.mesh):
			var count: int = multi.instance_count if multi.visible_instance_count < 0 else mini(multi.instance_count, multi.visible_instance_count)
			var cached: Array = node.get_meta("callout_instance_transforms", [])
			if cached.size() >= count:
				for instance_index in range(count): result.bounds.append(node.global_transform * cached[instance_index] * multi.mesh.get_aabb())
			elif DisplayServer.get_name() != "headless":
				for instance_index in range(count): result.bounds.append(node.global_transform * multi.get_instance_transform(instance_index) * multi.mesh.get_aabb())
			elif count > 0:
				result.complete = false
				result.issues.append("Missing CPU instance transforms: " + str(node.name))
	for child in node.get_children(): _collect(child, excluded, opaque_only, result)

static func _opaque(instance: GeometryInstance3D, mesh: Mesh) -> bool:
	if instance.material_overlay and _opaque_material(instance.material_overlay): return true
	if instance.material_override:
		return _opaque_material(instance.material_override)
	if instance is MeshInstance3D:
		for surface in range(mesh.get_surface_count()):
			if _opaque_material(instance.get_active_material(surface)): return true
		return mesh.get_surface_count() == 0
	for surface in range(mesh.get_surface_count()):
		if _opaque_material(mesh.surface_get_material(surface)): return true
	return mesh.get_surface_count() == 0

static func _opaque_material(material: Material) -> bool:
	# Unknown/custom shaders are treated as opaque, a conservative choice.
	# Alpha render mode alone does not prove translucency: a1.0-alpha surface
	# may still be fully opaque. Only explicitly translucent color is excluded.
	return not material is BaseMaterial3D or material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_color.a >= 0.99

static func _face_corners(transform: Transform3D, size: Vector3) -> Array[Vector3]:
	return [transform * Vector3(-size.x * 0.5, -size.y * 0.5, size.z * 0.5),
		transform * Vector3(size.x * 0.5, -size.y * 0.5, size.z * 0.5),
		transform * Vector3(size.x * 0.5, size.y * 0.5, size.z * 0.5),
		transform * Vector3(-size.x * 0.5, size.y * 0.5, size.z * 0.5)]

static func _projected_face(eye: Vector3, box: AABB) -> Array[Vector3]:
	var forward: Vector3 = box.get_center() - eye
	if forward.length_squared() < 0.000001: return []
	forward = forward.normalized()
	var up: Vector3 = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	var right: Vector3 = forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	var depth: float = 0
	for corner_index in range(8):
		var delta: Vector3 = box.get_endpoint(corner_index) - eye
		var z: float = delta.dot(forward)
		if z <= EPSILON: return []
		depth = maxf(depth, z)
		min_x = minf(min_x, delta.dot(right) / z)
		max_x = maxf(max_x, delta.dot(right) / z)
		min_y = minf(min_y, delta.dot(up) / z)
		max_y = maxf(max_y, delta.dot(up) / z)
	var center: Vector3 = eye + forward * depth
	return [center + right * min_x * depth + up * min_y * depth, center + right * max_x * depth + up * min_y * depth,
		center + right * max_x * depth + up * max_y * depth, center + right * min_x * depth + up * max_y * depth]

static func _pyramid_intersects(eye: Vector3, face: Array[Vector3], box: AABB) -> bool:
	# Complete separating-axis test for a convex viewing pyramid and world
	# AABB. Face planes and world axes reject most boxes cheaply; cross-products
	# of pyramid/AABB edges resolve oblique near misses without sparse rays.
	if face.size() != 4: return true
	var broad := AABB(eye, Vector3.ZERO)
	var center: Vector3 = Vector3.ZERO
	for point in face:
		broad = broad.expand(point)
		center += point * 0.25
	if not broad.grow(EPSILON).intersects(box): return false
	var box_center: Vector3 = box.get_center()
	var half: Vector3 = box.size * 0.5
	for side in range(5):
		var plane: Plane = Plane(eye, face[side], face[(side + 1) % 4]) if side < 4 else Plane(face[0], face[1], face[2])
		var inside: Vector3 = center if side < 4 else eye
		if plane.distance_to(inside) > 0: plane = Plane(-plane.normal, -plane.d)
		var radius: float = plane.normal.abs().dot(half)
		if plane.distance_to(box_center) - radius > EPSILON: return false
	var edges: Array[Vector3] = [face[0]-eye,face[1]-eye,face[2]-eye,face[3]-eye,face[1]-face[0],face[2]-face[1]]
	for edge in edges:
		for box_axis in [Vector3.RIGHT,Vector3.UP,Vector3.BACK]:
			var axis: Vector3 = edge.cross(box_axis)
			if axis.length_squared() < 0.000000000001: continue
			var low: float = axis.dot(eye)
			var high: float = low
			for point in face:
				var value: float = axis.dot(point)
				low = minf(low,value)
				high = maxf(high,value)
			var middle: float = axis.dot(box_center)
			var radius: float = axis.abs().dot(half)
			var tolerance: float = EPSILON*axis.length()
			if high < middle-radius-tolerance or low > middle+radius+tolerance: return false
	return true

static func _finite_transform(transform: Transform3D) -> bool:
	return transform.origin.is_finite() and transform.basis.x.is_finite() and transform.basis.y.is_finite() and transform.basis.z.is_finite() and absf(transform.basis.determinant()) > EPSILON
