extends SceneTree
## Pure head-relative motion and swept fixture/room collision contracts.
const Navigation = preload("res://scripts/operator_navigation.gd")
const CENTER := Vector3(0.0, 0.85, -1.4)
const HALF := Vector2(0.85, 0.475)
const MARGIN: float = 0.18
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_test_movement()
	_test_room_bounds()
	_test_swept_bench_collision()
	_test_sliding_and_corners()
	_test_invalid_start_recovery()
	_test_walk_around()
	_test_adversarial_paths()
	print("NAVIGATION TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("NAVIGATION: " + description)

func _near(actual: Vector3, expected: Vector3, description: String) -> void:
	_check(actual.distance_to(expected) < 0.00001, description + " actual=" + str(actual) + " expected=" + str(expected))

func _move(position: Vector3, step: Vector3) -> Vector3:
	return Navigation.constrain_motion(position, step, CENTER, HALF, MARGIN)

func _in_bench(point: Vector3) -> bool:
	return absf(point.x - CENTER.x) < HALF.x + MARGIN - 0.00001 and absf(point.z - CENTER.z) < HALF.y + MARGIN - 0.00001

func _test_movement() -> void:
	for stick in [Vector2.ZERO, Vector2(0.18, 0), Vector2(0, -0.18), Vector2(0.1, 0.1)]:
		_near(Navigation.movement(stick, Vector3.FORWARD, 0.02), Vector3.ZERO, "Radial deadzone suppresses drift")
	_near(Navigation.movement(Vector2(0, 1), Vector3.FORWARD, 0.02), Vector3(0, 0, -0.013), "Forward stick follows negative-Z head forward")
	_near(Navigation.movement(Vector2(0, -1), Vector3.FORWARD, 0.02), Vector3(0, 0, 0.013), "Backward stick reverses head-relative movement")
	_near(Navigation.movement(Vector2(1, 0), Vector3.FORWARD, 0.02), Vector3(0.013, 0, 0), "Right stick X strafes right")
	_near(Navigation.movement(Vector2(0, 1), Vector3.RIGHT, 0.02), Vector3(0.013, 0, 0), "Head yaw rotates forward movement")
	_near(Navigation.movement(Vector2(1, 0), Vector3.RIGHT, 0.02), Vector3(0, 0, 0.013), "Head-relative right is orthogonal at quarter turn")
	var diagonal: Vector3 = Navigation.movement(Vector2(1, 1), Vector3.FORWARD, 0.02)
	_check(absf(diagonal.length() - 0.013) < 0.000001, "Diagonal input cannot move faster than cardinal input")
	_check(absf(diagonal.x + diagonal.z) < 0.000001 and diagonal.x > 0, "Diagonal direction preserves equal components")
	_near(Navigation.movement(Vector2(4, 4), Vector3.FORWARD, 0.02), diagonal, "Over-range finite stick input has bounded speed")
	_near(Navigation.movement(Vector2(0, 1), Vector3(0, -0.95, -0.1), 0.02), Vector3(0, 0, -0.013), "Looking down changes neither speed nor elevation")
	_near(Navigation.movement(Vector2(0, 1), Vector3(0, 0.95, -0.1), 0.02), Vector3(0, 0, -0.013), "Looking up retains horizontal heading")
	_near(Navigation.movement(Vector2(0, 1), Vector3.UP, 0.02), Vector3.ZERO, "Exactly vertical heading does not invent a yaw")
	_near(Navigation.movement(Vector2(0, 1), Vector3.ZERO, 0.02), Vector3.ZERO, "Missing heading produces no movement")
	var half_strength: Vector3 = Navigation.movement(Vector2(0, 0.59), Vector3.FORWARD, 0.02)
	_check(absf(half_strength.length() - 0.0065) < 0.000001, "Analog strength remaps continuously above the deadzone")
	_near(Navigation.movement(Vector2.ONE, Vector3.FORWARD, 1.0), Navigation.movement(Vector2.ONE, Vector3.FORWARD, 0.05), "Stalled frame cannot exceed 50ms commanded movement")
	for delta in [0.0, -0.1, INF, NAN]:
		_near(Navigation.movement(Vector2.ONE, Vector3.FORWARD, delta), Vector3.ZERO, "Invalid time cannot create movement")
	_near(Navigation.movement(Vector2(NAN, 1), Vector3.FORWARD, 0.02), Vector3.ZERO, "Invalid stick data fails closed")
	_near(Navigation.movement(Vector2.ONE, Vector3(INF, 0, -1), 0.02), Vector3.ZERO, "Invalid head data fails closed")
	var short_frame: Vector3 = Navigation.movement(Vector2(0, 1), Vector3.FORWARD, 0.01)
	_near(short_frame * 2, Navigation.movement(Vector2(0, 1), Vector3.FORWARD, 0.02), "Normal frame partition preserves distance")

func _test_room_bounds() -> void:
	_near(_move(Vector3(3.19, 1.7, 1), Vector3(2, 4, 0.1)), Vector3(3.2, 1.7, 1.1), "Room X wall clamps movement and preserves Y/tangential Z")
	_near(_move(Vector3(-3.19, 0.7, 1), Vector3(-2, -7, 0)), Vector3(-3.2, 0.7, 1), "Negative X room wall is bounded")
	_near(_move(Vector3(2, 1.2, 2.79), Vector3(0.1, 0, 4)), Vector3(2.1, 1.2, 2.8), "Positive Z wall permits lateral sliding")
	_near(_move(Vector3(2, 1.2, -2.69), Vector3(0, 0, -4)), Vector3(2, 1.2, -2.70), "Negative Z room wall is bounded before the workshop back wall")
	_near(_move(Vector3(3.2, 1.2, 2.8), Vector3(1, 2, 1)), Vector3(3.2, 1.2, 2.8), "Room corner prevents escape on both axes")
	_near(_move(Vector3(5, 1.2, 1), Vector3.ZERO), Vector3(5, 1.2, 1), "Physical position outside room is not snapped when idle")
	_near(_move(Vector3(5, 1.2, 1), Vector3(0.2, 0, 0.1)), Vector3(5, 1.2, 1.1), "Outside-room input cannot move farther out")
	_near(_move(Vector3(5, 1.2, 1), Vector3(-0.2, 0, 0)), Vector3(4.8, 1.2, 1), "Outside-room input can recover gradually")
	_near(_move(Vector3(-5, 1.2, 4), Vector3(0.1, 0, -0.2)), Vector3(-4.9, 1.2, 3.8), "Outside corner recovery preserves actual small motion")

func _test_swept_bench_collision() -> void:
	var front: float = CENTER.z + HALF.y + MARGIN
	var back: float = CENTER.z - HALF.y - MARGIN
	var side: float = HALF.x + MARGIN
	_near(_move(Vector3(0, 1.7, 0), Vector3(0, 0, -3)), Vector3(0, 1.7, front), "Swept front collision stops a step whose endpoint passed through the table")
	_near(_move(Vector3(0, 1.7, -3), Vector3(0, 0, 3)), Vector3(0, 1.7, back), "Swept rear collision blocks reverse crossing")
	_near(_move(Vector3(-2, 1.7, -1.4), Vector3(4, 0, 0)), Vector3(-side, 1.7, -1.4), "Swept left side blocks cross-table shortcut")
	_near(_move(Vector3(2, 1.7, -1.4), Vector3(-4, 0, 0)), Vector3(side, 1.7, -1.4), "Swept right side blocks reverse shortcut")
	_near(_move(Vector3(0, 1.7, front), Vector3(0, 0, -0.03)), Vector3(0, 1.7, front), "At-face inward command is blocked")
	_near(_move(Vector3(0, 1.7, front), Vector3(0, 0, 0.03)), Vector3(0, 1.7, front + 0.03), "At-face outward command remains available")
	var shifted := Vector3(1.0, 99.0, 0.5)
	_near(Navigation.constrain_motion(Vector3(1, 1.2, 2), Vector3(0, 0, -3), shifted, HALF, MARGIN), Vector3(1, 1.2, 0.5 + HALF.y + MARGIN), "Bench position follows supplied world center; its height is irrelevant")
	_near(Navigation.constrain_motion(Vector3(0, 1.2, 0), Vector3(0, 0, -3), CENTER, HALF), Vector3(0, 1.2, CENTER.z + HALF.y + 0.25), "API default margin expands the fixture consistently")

func _test_sliding_and_corners() -> void:
	var front: float = CENTER.z + HALF.y + MARGIN
	var side: float = HALF.x + MARGIN
	_near(_move(Vector3(0, 1.7, 0), Vector3(0.5, 0, -1)), Vector3(0.5, 1.7, front), "Diagonal front impact keeps useful tangential travel")
	_near(_move(Vector3(0, 1.7, front), Vector3(2, 0, 0)), Vector3(2, 1.7, front), "Walking along the front edge can clear its corner")
	_near(_move(Vector3(side, 1.7, -1.4), Vector3(0, 0, -1)), Vector3(side, 1.7, -2.4), "Side-boundary travel is tangential rather than sticky")
	var corner := Vector3(-side, 1.7, front)
	_near(_move(corner + Vector3(-0.5, 0, 0.5), Vector3(1, 0, -1)), corner, "Simultaneous corner entry blocks both inward axes")
	_near(_move(corner + Vector3(-0.5, 0, 0.5), Vector3(1, 0, 1)), corner + Vector3(0.5, 0, 1.5), "Motion outside a corner is not blocked")
	_near(_move(Vector3(side + 0.01, 1.7, 0), Vector3(0, 0, -3)), Vector3(side + 0.01, 1.7, -2.70), "Near miss beyond the expanded side passes until the room wall")
	_near(_move(corner + Vector3(-0.5, 0, -0.5), Vector3(1, 0, 1)), corner + Vector3(0.5, 0, 0.5), "A path touching only the mathematical corner does not enter the bench")

func _test_invalid_start_recovery() -> void:
	var front: float = CENTER.z + HALF.y + MARGIN
	var embedded := Vector3(0.2, 1.7, front - 0.05)
	_near(_move(embedded, Vector3.ZERO), embedded, "Embedded room-scale head is not ejected while idle")
	_near(_move(embedded, Vector3(0, 0, -0.03)), embedded, "Embedded input cannot move deeper toward the far side")
	_near(_move(embedded, Vector3(0.02, 0, 0.02)), embedded + Vector3(0, 0, 0.02), "Embedded input only recovers toward the nearest exit")
	_near(_move(embedded, Vector3(0, 0, 0.1)), embedded + Vector3(0, 0, 0.1), "Recovery may cross the nearest face into valid space")
	_near(_move(Vector3(0, 1.7, CENTER.z), Vector3(0, 0, -0.01)), Vector3(0, 1.7, CENTER.z - 0.01), "Tied nearest exits honor the requested outward direction")
	var source := Vector3(2, 1.7, 1)
	_near(_move(source, Vector3(NAN, 0, 0)), source, "Invalid step fails closed")
	_near(Navigation.constrain_motion(source, Vector3.ONE, CENTER, Vector2.ZERO), source, "Invalid fixture extents do not disable collision")
	_near(Navigation.constrain_motion(source, Vector3.ONE, CENTER, HALF, -1), source, "Negative clearance fails closed")
	_near(Navigation.constrain_motion(source, Vector3.ONE, Vector3(INF, 0, 0), HALF), source, "Invalid bench location fails closed")

func _test_walk_around() -> void:
	var position := Vector3(0, 1.7, 0)
	for leg in [Vector3(1.4, 0, 0), Vector3(0, 0, -2.6), Vector3(-2.8, 0, 0), Vector3(0, 0, 2.6), Vector3(1.4, 0, 0)]:
		var increment: Vector3 = leg / 100.0
		for frame in range(100):
			position = _move(position, increment)
			_check(not _in_bench(position), "A complete route around the bench remains outside its clearance")
	_near(position, Vector3(0, 1.7, 0), "Walking round all four sides can return to the starting position")

func _test_adversarial_paths() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 741839
	for sample in range(200):
		var start := Vector3(rng.randf_range(-3.1, 3.1), rng.randf_range(0.5, 2.0), rng.randf_range(-2.6, 2.7))
		if _in_bench(start):
			continue
		var step := Vector3(rng.randf_range(-8, 8), rng.randf_range(-10, 10), rng.randf_range(-8, 8))
		var result: Vector3 = _move(start, step)
		_check(result.is_finite() and is_equal_approx(result.y, start.y), "Adversarial commanded path remains finite and horizontal")
		_check(not _in_bench(result), "Adversarial large step cannot end inside fixture clearance")
		_check(result.x >= Navigation.ROOM_MIN.x - 0.00001 and result.x <= Navigation.ROOM_MAX.x + 0.00001 and result.z >= Navigation.ROOM_MIN.y - 0.00001 and result.z <= Navigation.ROOM_MAX.y + 0.00001, "Adversarial path remains in room bounds")
		_check(Vector2(result.x - start.x, result.z - start.z).length() <= Vector2(step.x, step.z).length() + 0.00001, "Collision cannot add commanded displacement")
