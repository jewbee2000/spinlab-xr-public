class_name OperatorNavigation
extends RefCounted
## Pure commanded-motion math. The application gates input/focus/held tools and
## applies (allowed_head_position - actual_head_position) to XROrigin3D.

const DEADZONE: float = 0.18
const SPEED_M_S: float = 0.65
const MAX_DELTA_S: float = 0.05
const ROOM_MIN: Vector2 = Vector2(-3.2, -2.70)
const ROOM_MAX: Vector2 = Vector2(3.2, 2.8)
const EPS: float = 0.000001

## Positive stick Y moves along headforward; positive X moves to its right.
## Head pitch is removed. No motion is invented for a vertical/invalid heading.
static func movement(stick: Vector2, headforward: Vector3, delta: float) -> Vector3:
	if not stick.is_finite() or not headforward.is_finite() or not is_finite(delta) or delta <= 0.0:
		return Vector3.ZERO
	var magnitude: float = stick.length()
	if not is_finite(magnitude) or magnitude <= DEADZONE:
		return Vector3.ZERO
	var forward := Vector3(headforward.x, 0.0, headforward.z)
	var forward_length: float = forward.length()
	if not is_finite(forward_length) or forward_length <= EPS:
		return Vector3.ZERO
	forward /= forward_length
	var right: Vector3 = forward.cross(Vector3.UP)
	var direction: Vector2 = stick / magnitude
	var strength: float = clampf((magnitude - DEADZONE) / (1.0 - DEADZONE), 0.0, 1.0)
	return (right * direction.x + forward * direction.y) * SPEED_M_S * strength * minf(delta, MAX_DELTA_S)

## Returns an absolute allowed position, preserving position.y. Only commanded
## motion is constrained: an already invalid physical head position is never
## snapped to an edge. Room recovery is gradual; bench recovery permits motion
## towards a nearest exit face, not deeper traversal through the tabletop.
static func constrain_motion(position: Vector3, step: Vector3, bench_center: Vector3, bench_half_extents: Vector2, margin: float = 0.25) -> Vector3:
	if not position.is_finite() or not step.is_finite() or not bench_center.is_finite() or not bench_half_extents.is_finite() or not is_finite(margin):
		return position
	if bench_half_extents.x <= 0.0 or bench_half_extents.y <= 0.0 or margin < 0.0:
		return position
	var start := Vector2(position.x, position.z)
	var requested := Vector2(step.x, step.z)
	var destination := Vector2(_room_axis(start.x, requested.x, ROOM_MIN.x, ROOM_MAX.x), _room_axis(start.y, requested.y, ROOM_MIN.y, ROOM_MAX.y))
	if not destination.is_finite():
		return position
	var center := Vector2(bench_center.x, bench_center.z)
	var half: Vector2 = bench_half_extents + Vector2.ONE * margin
	var lower: Vector2 = center - half
	var upper: Vector2 = center + half
	if not lower.is_finite() or not upper.is_finite():
		return position
	var remaining: Vector2 = destination - start
	if _inside(start, lower, upper):
		var recovery: Vector2 = _recover(start, remaining, lower, upper)
		return Vector3(recovery.x, position.y, recovery.y)
	var current: Vector2 = start
	# A single rectangle has at most two blocking axes. Re-sweep after sliding so
	# even very large input steps cannot tunnel across a face or corner.
	for iteration in range(3):
		if remaining.length_squared() <= EPS * EPS:
			break
		var hit: Dictionary = _sweep(current, remaining, lower, upper)
		if not hit.hit:
			current += remaining
			break
		var fraction: float = clampf(hit.time, 0.0, 1.0)
		current += remaining * fraction
		remaining *= 1.0 - fraction
		var normal: Vector2 = hit.normal
		if normal.x != 0.0:
			remaining.x = 0.0
		if normal.y != 0.0:
			remaining.y = 0.0
	return Vector3(current.x, position.y, current.y)

static func _room_axis(value: float, step: float, lower: float, upper: float) -> float:
	if value < lower:
		return clampf(value + step, value, upper)
	if value > upper:
		return clampf(value + step, lower, value)
	return clampf(value + step, lower, upper)

static func _inside(point: Vector2, lower: Vector2, upper: Vector2) -> bool:
	return point.x > lower.x + EPS and point.x < upper.x - EPS and point.y > lower.y + EPS and point.y < upper.y - EPS

static func _recover(point: Vector2, step: Vector2, lower: Vector2, upper: Vector2) -> Vector2:
	var distances := [point.x - lower.x, upper.x - point.x, point.y - lower.y, upper.y - point.y]
	var normals := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
	var nearest: float = minf(minf(distances[0], distances[1]), minf(distances[2], distances[3]))
	var best_motion := Vector2.ZERO
	var best_distance: float = 0.0
	for face in range(4):
		if distances[face] > nearest + EPS:
			continue
		var outward: float = step.dot(normals[face])
		if outward > best_distance:
			best_distance = outward
			best_motion = normals[face] * outward
	return point + best_motion

static func _sweep(start: Vector2, step: Vector2, lower: Vector2, upper: Vector2) -> Dictionary:
	var enter: float = -INF
	var leave: float = INF
	var normal := Vector2.ZERO
	for axis in range(2):
		if absf(step[axis]) <= EPS:
			# A path on the boundary is tangential, not inside the obstacle.
			if start[axis] <= lower[axis] + EPS or start[axis] >= upper[axis] - EPS:
				return {"hit": false}
			continue
		var near: float = (lower[axis] - start[axis]) / step[axis]
		var far: float = (upper[axis] - start[axis]) / step[axis]
		if near > far:
			var swap: float = near
			near = far
			far = swap
		var axis_normal := Vector2.ZERO
		axis_normal[axis] = -signf(step[axis])
		if near > enter + EPS:
			enter = near
			normal = axis_normal
		elif absf(near - enter) <= EPS:
			normal += axis_normal
		leave = minf(leave, far)
		if enter > leave:
			return {"hit": false}
	# Touching just one corner, or arriving exactly at a face, does not enter it.
	if enter < -EPS or enter > 1.0 or leave <= maxf(enter, 0.0) + EPS:
		return {"hit": false}
	return {"hit": true, "time": maxf(enter, 0.0), "normal": normal}
