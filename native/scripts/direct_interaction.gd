class_name DirectInteraction
extends RefCounted
## Pure contact logic. The caller translates the button's RESTING front face
## to z=0 before passing fingertip positions. Positive local Z is in front;
## a physical push travels toward negative Z. All distances are metres.

class PushContact extends RefCounted:
	## Keep one instance per fingertip/button pair. Button ownership across hands
	## belongs to the caller; `pressed` is a one-update event, never a held state.
	var press_depth_m: float = 0.006
	var stroke_m: float = 0.008
	var arm_distance_m: float = 0.035
	var withdraw_distance_m: float = 0.025
	var hover_distance_m: float = 0.045
	var rear_hover_limit_m: float = 0.030
	var debounce_s: float = 0.120
	var max_sample_gap_s: float = 0.250

	var _has_previous: bool = false
	var _previous: Vector3 = Vector3.ZERO
	var _armed: bool = false
	var _entered_front: bool = false
	var _latched: bool = false
	var _since_press_s: float = 1000.0

	func reset() -> void:
		## Call on app focus loss, tracking-origin recenter, or target relocation.
		## No old position/contact can become a press after resuming.
		_has_previous = false
		_previous = Vector3.ZERO
		_armed = false
		_entered_front = false
		_latched = false
		_since_press_s = 1000.0

	func process(local_point: Vector3, half_extents: Vector2, delta: float, tracked: bool = true) -> Dictionary:
		if not tracked or not local_point.is_finite() or not half_extents.is_finite() or half_extents.x <= 0.0 or half_extents.y <= 0.0 or not is_finite(delta) or delta <= 0.0 or delta > max_sample_gap_s:
			reset()
			return _empty_result()
		_since_press_s += delta
		var inside: bool = _inside_face(local_point, half_extents)
		if not _has_previous:
			# Seeing a fingertip already inside the cap, or behind it, cannot
			# activate anything. A fresh sample in front may arm a later stroke.
			_has_previous = true
			_previous = local_point
			_armed = inside and local_point.z >= arm_distance_m
			return _feedback(local_point, half_extents, false, false)

		if _latched:
			if local_point.z >= withdraw_distance_m:
				_latched = false
				_entered_front = false
				_armed = inside and local_point.z >= arm_distance_m
			_previous = local_point
			return _feedback(local_point, half_extents, false, false)

		# Segment-plane intersections preserve valid fast pushes even if the
		# sample before the stroke was too far away to register as hovering.
		if inside and local_point.z >= arm_distance_m:
			_armed = true
		if _crosses_forward(_previous, local_point, arm_distance_m):
			_armed = _inside_face(_at_plane(_previous, local_point, arm_distance_m), half_extents)

		if _armed and _crosses_forward(_previous, local_point, 0.0):
			_entered_front = _inside_face(_at_plane(_previous, local_point, 0.0), half_extents)
			if not _entered_front:
				_armed = false

		var pressed: bool = false
		var debounced: bool = false
		if _armed and _entered_front and _crosses_forward(_previous, local_point, -press_depth_m):
			var stroke_crossing: Vector3 = _at_plane(_previous, local_point, -press_depth_m)
			if _inside_face(stroke_crossing, half_extents):
				_latched = true
				_armed = false
				_entered_front = false
				pressed = _since_press_s >= debounce_s
				debounced = not pressed
				if pressed:
					_since_press_s = 0.0

		if not _latched:
			if local_point.z > 0.0:
				_entered_front = false
			if not inside and local_point.z < arm_distance_m:
				# A lateral exit consumes the approach. Coming back through a
				# side wall while already behind the face must never activate it.
				_armed = false
				_entered_front = false
		_previous = local_point
		return _feedback(local_point, half_extents, pressed, debounced)

	func _inside_face(point: Vector3, half_extents: Vector2) -> bool:
		return absf(point.x) <= half_extents.x and absf(point.y) <= half_extents.y

	func _crosses_forward(a: Vector3, b: Vector3, plane_z: float) -> bool:
		return a.z >= plane_z and b.z <= plane_z and b.z < a.z

	func _at_plane(a: Vector3, b: Vector3, plane_z: float) -> Vector3:
		var fraction: float = clampf((plane_z - a.z) / (b.z - a.z), 0.0, 1.0)
		return a.lerp(b, fraction)

	func _empty_result() -> Dictionary:
		return {"hover": false, "depth": 0.0, "pressed": false, "latched": false, "armed": false, "debounced": false}

	func _feedback(point: Vector3, half_extents: Vector2, pressed: bool, debounced: bool) -> Dictionary:
		var hover: bool = _inside_face(point, half_extents) and point.z <= hover_distance_m and point.z >= -rear_hover_limit_m and (_armed or _entered_front or _latched)
		var depth: float = clampf(-point.z, 0.0, stroke_m) if hover and (_entered_front or _latched) else 0.0
		return {"hover": hover, "depth": depth, "pressed": pressed, "latched": _latched, "armed": _armed, "debounced": debounced}
