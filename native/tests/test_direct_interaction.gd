extends SceneTree

const Interaction = preload("res://scripts/direct_interaction.gd")
const HALF: Vector2 = Vector2(0.050, 0.025)
const DT: float = 1.0 / 72.0
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_test_front_push_and_latch()
	_test_no_accidental_spawn()
	_test_fast_strokes()
	_test_side_and_back_rejection()
	_test_tracking_focus_and_sample_gaps()
	_test_debounce()
	_test_independent_contacts()
	print("DIRECT INTERACTION TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func _sample(contact, x: float, y: float, z: float, tracked: bool = true) -> Dictionary:
	return contact.process(Vector3(x, y, z), HALF, DT, tracked)

func _test_front_push_and_latch() -> void:
	var contact = Interaction.PushContact.new()
	_check(_sample(contact, 0.0, 0.0, 0.06).armed, "Front clearance arms a future stroke")
	_check(_sample(contact, 0.0, 0.0, 0.025).hover, "Front approach highlights cap")
	_check(not _sample(contact, 0.0, 0.0, -0.003).pressed, "Partial travel does not activate")
	var press: Dictionary = _sample(contact, 0.0, 0.0, -0.007)
	_check(press.pressed and press.latched, "Six millimetre stroke activates once")
	_check(absf(press.depth - 0.007) < 0.000001, "Visual depth is metres of travel")
	var press_count: int = 0
	for frame in range(100):
		if _sample(contact, 0.0, 0.0, -0.009).pressed:
			press_count += 1
	_check(press_count == 0, "Held button never repeats")
	_check(absf(_sample(contact, 0.0, 0.0, -0.020).depth - 0.008) < 0.000001, "Visual travel clamps at eight millimetres")
	_check(_sample(contact, 0.0, 0.0, 0.010).latched, "Small withdrawal retains hysteresis latch")
	_check(not _sample(contact, 0.0, 0.0, -0.008).pressed, "Cap-plane jitter cannot retrigger")
	_check(not _sample(contact, 0.0, 0.0, 0.040).latched, "Full front withdrawal releases latch")
	_check(_sample(contact, 0.0, 0.0, -0.008).pressed, "Fresh stroke after withdrawal activates again")

func _test_no_accidental_spawn() -> void:
	for initial_z in [-0.020, -0.007, 0.0, 0.012]:
		var contact = Interaction.PushContact.new()
		_check(not _sample(contact, 0.0, 0.0, initial_z).pressed, "Spawn in/near cap never presses")
		_check(not _sample(contact, 0.0, 0.0, -0.020).pressed, "Continued penetration without front approach stays inactive")
		_sample(contact, 0.0, 0.0, 0.060)
		_check(_sample(contact, 0.0, 0.0, -0.008).pressed, "Withdrawing and approaching enables normal activation")

func _test_fast_strokes() -> void:
	var contact = Interaction.PushContact.new()
	var before: Dictionary = _sample(contact, 0.0, 0.0, 0.150)
	_check(not before.hover, "Fast stroke starts outside hover zone")
	_check(_sample(contact, 0.0, 0.0, -0.080).pressed, "Swept segment catches front-to-back tunnelling in one frame")
	_check(not _sample(contact, 0.0, 0.0, -0.100).pressed, "A tunnel crossing still only triggers once")
	var diagonal = Interaction.PushContact.new()
	_sample(diagonal, -0.090, 0.0, 0.150)
	_check(_sample(diagonal, 0.010, 0.0, -0.020).pressed, "Fast diagonal stroke enters arm, front, and press planes inside face")
	var exit_after_press = Interaction.PushContact.new()
	_sample(exit_after_press, 0.0, 0.0, 0.060)
	_check(_sample(exit_after_press, 0.080, 0.0, -0.100).pressed, "Swept press is preserved if segment exits cap later")

func _test_side_and_back_rejection() -> void:
	var side = Interaction.PushContact.new()
	_sample(side, 0.0, 0.0, 0.060)
	_sample(side, 0.090, 0.0, 0.015)
	_sample(side, 0.090, 0.0, -0.008)
	_check(not _sample(side, 0.0, 0.0, -0.008).pressed, "Lateral entry behind face cannot press")
	var back = Interaction.PushContact.new()
	_sample(back, 0.0, 0.0, -0.080)
	_check(not _sample(back, 0.0, 0.0, 0.010).pressed, "Back-to-front crossing cannot activate")
	_check(not _sample(back, 0.0, 0.0, -0.010).pressed, "Insufficient front withdrawal does not arm")
	var corner = Interaction.PushContact.new()
	_sample(corner, 0.080, 0.040, 0.060)
	_check(not _sample(corner, 0.080, 0.040, -0.020).pressed, "Outside corner stroke rejected")
	var wrong_entry = Interaction.PushContact.new()
	_sample(wrong_entry, 0.0, 0.0, 0.060)
	_check(not _sample(wrong_entry, 0.090, 0.0, -0.008).pressed, "Crossing front plane beyond edge is rejected")
	_check(not _sample(wrong_entry, 0.0, 0.0, -0.010).pressed, "Reentering from side cannot resurrect invalid approach")

func _test_tracking_focus_and_sample_gaps() -> void:
	var contact = Interaction.PushContact.new()
	_sample(contact, 0.0, 0.0, 0.060)
	_check(not _sample(contact, 0.0, 0.0, -0.008, false).pressed, "Tracking loss consumes pending stroke")
	_check(not _sample(contact, 0.0, 0.0, -0.012).pressed, "Tracking reacquired inside cap cannot press")
	_sample(contact, 0.0, 0.0, 0.060)
	_check(_sample(contact, 0.0, 0.0, -0.008).pressed, "Fresh approach after tracking loss works")
	contact.reset()
	_check(not _sample(contact, 0.0, 0.0, -0.010).pressed, "Explicit focus/origin reset prevents a stale press")
	_sample(contact, 0.0, 0.0, 0.060)
	_check(not contact.process(Vector3(0.0, 0.0, -0.008), HALF, 0.5).pressed, "Long frame gap resets trajectory instead of sweeping stale position")
	_check(not _sample(contact, 0.0, 0.0, -0.010).pressed, "After long gap a fresh front approach is required")
	_check(not contact.process(Vector3(NAN, 0.0, 0.0), HALF, DT).pressed, "Invalid tracking coordinate resets safely")
	_check(not contact.process(Vector3.ZERO, Vector2.ZERO, DT).hover, "Invalid target extents do not create contact")

func _test_debounce() -> void:
	var contact = Interaction.PushContact.new()
	_sample(contact, 0.0, 0.0, 0.060)
	_check(_sample(contact, 0.0, 0.0, -0.008).pressed, "Initial debounced contact presses")
	_sample(contact, 0.0, 0.0, 0.040)
	var bounce: Dictionary = _sample(contact, 0.0, 0.0, -0.008)
	_check(not bounce.pressed and bounce.debounced and bounce.latched, "Rapid reentry is consumed as a debounce event")
	for frame in range(20):
		_check(not _sample(contact, 0.0, 0.0, -0.008).pressed, "Rejected bounce never becomes a delayed held press")
	_sample(contact, 0.0, 0.0, 0.060)
	_check(_sample(contact, 0.0, 0.0, -0.008).pressed, "Later fresh stroke works after debounce interval")

func _test_independent_contacts() -> void:
	var left = Interaction.PushContact.new()
	var right = Interaction.PushContact.new()
	_sample(left, 0.0, 0.0, 0.060)
	_sample(right, 0.0, 0.0, 0.060)
	_check(_sample(left, 0.0, 0.0, -0.008).pressed, "Left contact activates independently")
	_check(_sample(right, 0.0, 0.0, -0.008).pressed, "Right contact retains independent state for caller arbitration")
	left.reset()
	_check(not _sample(right, 0.0, 0.0, -0.010).pressed, "Resetting another contact does not release a held hand")
