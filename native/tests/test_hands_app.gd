extends SceneTree
## Exercise actual main.gd direct interaction using fake tracked grip transforms.
## This verifies application behavior without claiming headset tracking accuracy.

const DT: float = 1.0 / 72.0
class SimPose extends RefCounted:
	var tracking_confidence: int = XRPose.XR_TRACKING_CONFIDENCE_HIGH

class SimGrip extends Node3D:
	var simulated_tracking: bool = true
	var simulated_pose: RefCounted = SimPose.new()
	func get_pose() -> RefCounted:
		return simulated_pose
	func get_has_tracking_data() -> bool:
		return simulated_tracking

class SimController extends Node3D:
	var tracker: StringName = &"right_hand"
	var simulated_grip: float = 0.0
	func get_float(input_name: String) -> float:
		return simulated_grip if input_name == "grip" else 0.0
	func get_vector2(_input_name: String) -> Vector2:
		return Vector2.ZERO
	func is_button_pressed(_input_name: String) -> bool:
		return false

var checks: int = 0
var failures: int = 0
var app: Node3D
var left: Dictionary
var right: Dictionary
var started_at: int = 0

func _initialize() -> void:
	started_at = Time.get_ticks_msec()
	call_deferred("_run_tests")

func _run_tests() -> void:
	var scene = load("res://main.tscn") as PackedScene
	_check(scene != null, "Main scene loads for direct-hand integration")
	if scene == null:
		_finish()
		return
	app = scene.instantiate()
	app.narration_enabled=false;app.narration_settings_path=""
	app.tutorial_settings_path = ""
	app.tutorial_autostart = false
	root.add_child(app)
	app.set_process(false)
	app.set_process_unhandled_input(false)
	app.model.async_processing = false
	left = _make_fake_hand("LeftTest")
	right = _make_fake_hand("RightTest")
	_check(not app.xr_active and not app.reach_assist, "Desktop test starts with direct interactions and no reach assist")
	_test_world_fingertip_commands()
	_test_two_hand_button_latching()
	_test_near_grab_and_carry()
	_test_guard_motion_and_interlocks()
	_test_wrist_dials()
	_test_tracking_and_focus_cancel()
	_test_polled_grip_rearm()
	_test_focus_source_conjunction()
	_test_interaction_report()
	_finish()

func _finish() -> void:
	print("HANDS APP INTEGRATION TESTS: %d checks, %d failures (%d ms)" % [checks, failures, Time.get_ticks_msec() - started_at])
	quit(0 if failures == 0 else 1)

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("HANDS APP TEST: " + description)

func _make_fake_hand(hand_name: String) -> Dictionary:
	var controller = SimController.new()
	controller.name = hand_name + "Aim"
	app.rig.add_child(controller)
	var grip = SimGrip.new()
	grip.name = hand_name + "Grip"
	app.rig.add_child(grip)
	grip.position = Vector3(3.0, 2.0, 3.0)
	var entry: Dictionary = app._make_hand_entry(controller, grip)
	var beam = Node3D.new()
	controller.add_child(beam)
	entry.beam = beam
	var ray = RayCast3D.new()
	controller.add_child(ray)
	entry.ray = ray
	entry.tracked = true
	app.controllers.append(entry)
	return entry

func _fresh_session() -> void:
	app._cancel_hand_interactions()
	app.model.reset()
	app.model.async_processing = false
	app.geometry.guard_preview = -1.0
	app.geometry.kit_rotor.transform = app.kit_home
	app.geometry.update_state(app.model.telemetry())
	app.active_plane = 0
	app.app_has_focus = true
	app._set_xr_focus(true)
	app.tab = "operate"
	app._rebuild_menu()
	for entry in [left, right]:
		entry.grip_node.global_transform = Transform3D(Basis.IDENTITY, Vector3(3.0, 2.0, 3.0))
		entry.grip_down = false
		entry.tracked = true
		entry.node.simulated_grip = 0.0
		entry.grip_node.simulated_tracking = true
	app._update_ui()

func _button(command: String):
	for button in app.buttons:
		if is_instance_valid(button) and not button.is_queued_for_deletion() and button.action == command:
			return button
	_check(false, "World button exists for " + command)
	return null

func _point(button, normalized_z: float) -> Vector3:
	return button.to_global(Vector3(0.0, 0.0, button.front_z_m + normalized_z))

func _poke_frame(calls: Array) -> void:
	app.frame_latches.clear()
	app.frame_depths.clear()
	for button in app.buttons:
		if is_instance_valid(button):
			button.hover(false)
	for call in calls:
		app._process_pokes(call.entry, call.tip, DT, call.get("tracked", true))
	app._finish_pokes()

func _poke(entry: Dictionary, button, z: float, tracked: bool = true) -> void:
	_poke_frame([{"entry": entry, "tip": _point(button, z), "tracked": tracked}])

func _press(entry: Dictionary, button) -> void:
	_poke(entry, button, 0.060)
	_poke(entry, button, -0.008)

func _count_event(kind: String, target: String) -> int:
	var count: int = 0
	for event in app.interaction_events:
		if event.kind == kind and event.target == target:
			count += 1
	return count

func _test_world_fingertip_commands() -> void:
	_fresh_session()
	var event_count: int = app.interaction_events.size()
	app._controller_pressed("trigger_click", left)
	_check(app.interaction_events.size() == event_count and not app.model.mounted, "Far trigger has no default selection behavior")
	app._physical_action("mount")
	_check(not app.model.mounted, "Touching Load gives carry instructions instead of remotely mounting rotor")
	app.model.mount_rotor()
	app.geometry.update_state(app.model.telemetry())
	var home = app.geometry.probe_home_button
	_poke(left, home, -0.008)
	_check(not app.model.homed, "Spawning a fingertip inside the physical Home cap cannot home")
	_press(left, home)
	_check(app.model.homed, "Front physical fingertip stroke activates actual Home command")
	_check(home.depression_m > 0.005, "Physical Home cap shows measured press travel")
	var homes_before: int = _count_event("fingertip", "home")
	for frame in range(20):
		_poke(left, home, -0.008)
	_check(_count_event("fingertip", "home") == homes_before, "Held physical cap cannot repeatedly actuate Home")
	app._reset_pokes()
	var baseline = _button("baseline")
	_press(left, baseline)
	_check(not app.model.running, "Direct baseline button preserves open-guard interlock")
	app.model.toggle_guard()
	app.geometry.guard_preview = -1.0
	app.geometry.update_state(app.model.telemetry())
	app._reset_pokes()
	_press(left, baseline)
	_check(app.model.running and app.model.run_kind == "baseline", "Prepared direct baseline stroke starts actual acquisition")
	app.model.stop()
	app.model.tick(2.0)
	# A new menu must not treat a finger already occupying its new button as
	# a fresh front approach, even when its position overlaps an old command.
	app._action("tab:balance")
	var fit = _button("fit_trial")
	event_count = app.interaction_events.size()
	_poke(left, fit, -0.008)
	_check(app.interaction_events.size() == event_count, "Menu replacement under a finger cannot actuate a new command")

func _test_two_hand_button_latching() -> void:
	_fresh_session()
	app.model.mount_rotor()
	var home = app.geometry.probe_home_button
	var count_before: int = _count_event("fingertip", "home")
	_poke_frame([{"entry": left, "tip": _point(home, 0.060)}, {"entry": right, "tip": _point(home, 0.060)}])
	_poke_frame([{"entry": left, "tip": _point(home, -0.008)}, {"entry": right, "tip": _point(home, -0.008)}])
	_check(_count_event("fingertip", "home") == count_before + 1, "Simultaneous left/right press actuates shared cap exactly once")
	for frame in range(12):
		_poke_frame([{"entry": left, "tip": _point(home, 0.060)}, {"entry": right, "tip": _point(home, -0.008)}])
	_poke_frame([{"entry": left, "tip": _point(home, -0.008)}, {"entry": right, "tip": _point(home, -0.008)}])
	_check(_count_event("fingertip", "home") == count_before + 1, "One hand cannot retrigger a cap still latched by the other")

func _place_grip(entry: Dictionary, position: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	entry.grip_node.global_transform = Transform3D(basis, position)

func _grab_rotor(entry: Dictionary) -> bool:
	var point: Vector3 = app.geometry.rotor_grab.global_position
	_place_grip(entry, point)
	return app._begin_near_grab(entry, point)

func _carry_rotor_to(entry: Dictionary, position: Vector3, upright: bool = true) -> void:
	var basis: Basis = Basis.IDENTITY.scaled(Vector3.ONE * 0.82)
	if not upright:
		basis = Basis(Vector3.RIGHT, PI) * basis
	var desired: Transform3D = Transform3D(basis, position)
	entry.grip_node.global_transform = desired * entry.grab_offset.affine_inverse()
	app._update_held(entry, entry.grip_node.global_position)

func _test_near_grab_and_carry() -> void:
	_fresh_session()
	_check(app._find_near_grabbable(Vector3(4.0, 4.0, 4.0)) == null, "Far palm has no grabbable target")
	_check(not app._begin_near_grab(left, Vector3(4.0, 4.0, 4.0)), "Grip cannot remotely select hardware")
	var rotor_target: Node3D = app.geometry.rotor_grab
	_check(app._find_near_grabbable(rotor_target.to_global(Vector3(-0.35, 0.0, 0.0))) == null, "Palm beyond collider contact margin cannot acquire rotor")
	_check(app._find_near_grabbable(rotor_target.to_global(Vector3(-0.25, 0.0, 0.0))) == rotor_target, "Palm near actual scaled collider surface can acquire rotor")
	_check(app._find_near_grabbable(rotor_target.global_position) == rotor_target, "Rotor collider surface resolves nearby grip target")
	_check(_grab_rotor(left) and left.held == "rotor", "Nearby grip acquires tray rotor")
	_check(not app._begin_near_grab(right, rotor_target.global_position), "Second hand cannot take an already owned rotor")
	var original: Transform3D = app.geometry.kit_rotor.global_transform
	left.grip_node.global_position += Vector3(0.12, 0.10, -0.06)
	app._update_held(left, left.grip_node.global_position)
	_check(app.geometry.kit_rotor.global_position.distance_to(original.origin + Vector3(0.12, 0.10, -0.06)) < 0.0001, "Carried rotor follows full grip translation")
	app._release_near_grab(left)
	_check(not app.model.mounted and app.geometry.kit_rotor.transform.is_equal_approx(app.kit_home), "Far release returns rotor to tray without mounting")
	_check(app.grab_owners.is_empty(), "Releasing rotor clears exclusive owner")
	_check(_grab_rotor(left), "Returned rotor can be acquired again")
	var spindle: Vector3 = app.station.to_global(app.Geometry.CENTER)
	_carry_rotor_to(left, spindle, false)
	app._release_near_grab(left)
	_check(not app.model.mounted, "Upside-down rotor is rejected at spindle")
	_check(_grab_rotor(left), "Rejected rotor is available in tray")
	_carry_rotor_to(left, spindle, true)
	_check(app.geometry.kit_rotor.global_position.distance_to(spindle) < 0.0001, "Grip offset maps rotor center precisely to spindle")
	app._release_near_grab(left)
	app.geometry.update_state(app.model.telemetry())
	_check(app.model.mounted and app.geometry.rotor.visible and not app.geometry.kit_rotor.visible, "Upright centered release snaps rotor into mounted fixture")
	_check(_count_event("rotor_seated", "spindle") >= 1, "Successful physical seating is traceable")

func _test_guard_motion_and_interlocks() -> void:
	_fresh_session()
	app.model.mount_rotor()
	app.model.home_probe()
	app.geometry.update_state(app.model.telemetry())
	var handle: Node3D = app.geometry.guard_handle
	var open_point: Vector3 = handle.global_position
	_place_grip(left, open_point)
	_check(app._begin_near_grab(left, open_point) and left.held == "guard", "Grip acquires nearby guard handle")
	var half_point: Vector3 = open_point - Vector3.UP * app.geometry.guard_travel_m * 0.5
	_place_grip(left, half_point)
	app._update_held(left, half_point)
	_check(absf(app.geometry.guard_fraction() - 0.5) < 0.0001 and not app.model.guard_closed, "Guard follows continuous half travel and interlock stays open")
	var closed_point: Vector3 = open_point - Vector3.UP * app.geometry.guard_travel_m
	_place_grip(left, closed_point)
	app._update_held(left, closed_point)
	_check(app.geometry.guard_fraction() < 0.001 and not app.model.guard_closed, "Fully lowered held guard waits for explicit release to latch")
	app._action("baseline")
	_check(not app.model.running, "Acquisition cannot start while a mechanical handle is held")
	app._release_near_grab(left)
	_check(app.model.guard_closed and app.geometry.guard_fraction() < 0.001, "Handle release at bottom latches model guard")
	var closed_handle: Vector3 = handle.global_position
	_place_grip(left, closed_handle)
	_check(app._begin_near_grab(left, closed_handle), "Closed guard can be gripped for lifting")
	app._action("baseline")
	_check(app.model.guard_closed and not app.model.running, "Even a closed valid guard cannot start drive while its handle is held")
	_place_grip(left, closed_handle + Vector3.UP * 0.08)
	app._update_held(left, closed_handle + Vector3.UP * 0.08)
	_check(not app.model.guard_closed and app.geometry.guard_fraction() > 0.1, "Lifting guard opens interlock before significant travel")
	app._release_near_grab(left, true)
	_check(not app.model.guard_closed, "Cancelled partial guard motion cannot silently relatch interlock")

func _test_wrist_dials() -> void:
	_fresh_session()
	app.model.mount_rotor()
	app.model.home_probe()
	app.geometry.update_state(app.model.telemetry())
	var dial: Node3D = app.dial_nodes.probe
	var point: Vector3 = dial.global_position
	_place_grip(left, point)
	_check(app._begin_near_grab(left, point) and left.held == "dial", "Nearby grip acquires probe dial")
	var before: float = app.model.sensor_position_mm
	var other_probe: Vector3 = app.geometry.probe_grab.global_position
	_place_grip(right, other_probe)
	_check(not app._begin_near_grab(right, other_probe), "Front dial and physical micrometer share exclusive probe ownership")
	app._action("nudge:probe:1")
	_check(is_equal_approx(app.model.sensor_position_mm, before), "Second-hand increment cannot overwrite a held dial's reference")
	app._action("mode")
	_check(app.model.mode == "single", "Scenario cannot change underneath a held fixture adjustment")
	app._update_held(left, point)
	_check(is_equal_approx(app.model.sensor_position_mm, before), "Holding a stationary wrist does not drift dial")
	_place_grip(left, point + Vector3(0.04, 0.0, 0.0))
	app._update_held(left, left.grip_node.global_position)
	_check(is_equal_approx(app.model.sensor_position_mm, before), "Translating wrist without rotation does not turn dial")
	_place_grip(left, point, Basis(Vector3.RIGHT, 0.25))
	app._update_held(left, point)
	_check(is_equal_approx(app.model.sensor_position_mm, before), "Panel dial ignores wrist rotation perpendicular to its Z axis")
	_place_grip(left, point)
	app._update_held(left, point)
	_place_grip(left, point, Basis(Vector3.BACK, 0.25))
	app._update_held(left, point)
	_check(app.model.sensor_position_mm > before, "Wrist twist around dial axis increases probe setting")
	var after_turn: float = app.model.sensor_position_mm
	_place_grip(left, point, Basis(Vector3.BACK, 0.25))
	app._update_held(left, point)
	_check(is_equal_approx(app.model.sensor_position_mm, after_turn), "Holding rotated wrist does not continuously integrate adjustment")
	_place_grip(left, point + Vector3(0.5, 0.0, 0.0), Basis(Vector3.BACK, 0.25))
	app._update_held(left, left.grip_node.global_position)
	_check(left.held == "" and app.grab_owners.is_empty(), "Moving away from dial releases ownership safely")
	# The physical micrometer thimble axis is X; panel dials use local Z.
	var micrometer: Node3D = app.geometry.probe_grab
	point = micrometer.global_position
	_place_grip(left, point)
	_check(app._begin_near_grab(left, point), "Physical micrometer can be gripped nearby")
	before = app.model.sensor_position_mm
	_place_grip(left, point, Basis(Vector3.BACK, 0.25))
	app._update_held(left, point)
	_check(is_equal_approx(app.model.sensor_position_mm, before), "Physical micrometer ignores wrist twist perpendicular to its X axis")
	_place_grip(left, point)
	app._update_held(left, point)
	_place_grip(left, point, Basis(Vector3.RIGHT, 0.25))
	app._update_held(left, point)
	_check(app.model.sensor_position_mm > before, "Physical micrometer responds to twist around actual X axis")
	app._release_near_grab(left)
	# Fixture interlocks remain in the science model even when a dial is held.
	app.model.toggle_guard()
	point = app.dial_nodes.mass.global_position
	_place_grip(left, point)
	app._begin_near_grab(left, point)
	var mass_before: float = app.model.masses[0]
	_place_grip(left, point, Basis(Vector3.BACK, 0.3))
	app._update_held(left, point)
	_check(is_equal_approx(app.model.masses[0], mass_before), "Wrist mass adjustment preserves closed-guard interlock")
	app._release_near_grab(left)

func _test_tracking_and_focus_cancel() -> void:
	_fresh_session()
	_check(_grab_rotor(left), "Rotor grabbed before focus loss")
	var spindle: Vector3 = app.station.to_global(app.Geometry.CENTER)
	_carry_rotor_to(left, spindle)
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not app.input_focused and left.held == "" and app.grab_owners.is_empty(), "Focus loss cancels hand ownership")
	_check(not left.grip_down and not left.grip_armed and left.contacts.is_empty(), "Focus loss resets button and grip rearm latches")
	_check(not app.model.mounted and app.geometry.kit_rotor.transform.is_equal_approx(app.kit_home), "Focus cancellation at spindle cannot seat rotor")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	app.model.mount_rotor()
	var home = app.geometry.probe_home_button
	_poke(left, home, 0.060)
	_poke(left, home, -0.008, false)
	_poke(left, home, -0.008, true)
	_check(not app.model.homed, "Tracking loss and reacquisition inside button cannot activate Home")
	_press(left, home)
	_check(app.model.homed, "Fresh tracked front approach resumes button interaction")
	app.model.toggle_guard()
	app.model.begin_run("baseline")
	app.model.tick(0.1)
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not app.model.running and app.model.rpm > 0.0, "Focus loss stops acquisition and leaves controlled coast")
	app.model.tick(2.0)
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(not app.model.running, "Focus return cannot restart drive automatically")

func _place_palm(entry: Dictionary, position: Vector3) -> void:
	var offset: Vector3 = entry.hand.palm_global() - entry.grip_node.global_position
	entry.grip_node.global_position = position - offset

func _test_polled_grip_rearm() -> void:
	_fresh_session()
	_place_palm(left, app.geometry.rotor_grab.global_position)
	left.node.simulated_grip = 1.0
	app._update_controllers(DT)
	_check(left.held == "", "Initial tracking with grip already held cannot acquire hardware")
	left.node.simulated_grip = 0.0
	app._update_controllers(DT)
	left.node.simulated_grip = 1.0
	app._update_controllers(DT)
	_check(left.held == "rotor", "Polled release followed by deliberate nearby squeeze acquires rotor")
	left.grip_node.simulated_tracking = false
	app._update_controllers(DT)
	_check(left.held == "" and app.grab_owners.is_empty() and not left.grip_armed and not left.grip_down, "Polled tracking loss cancels grab and resets squeeze latches")
	left.grip_node.simulated_tracking = true
	app._update_controllers(DT)
	_check(left.held == "", "Tracking reacquisition with squeeze held cannot automatically regrab")
	left.node.simulated_grip = 0.0
	app._update_controllers(DT)
	left.node.simulated_grip = 1.0
	app._update_controllers(DT)
	_check(left.held == "rotor", "Fresh release/squeeze after tracking return deliberately regrabs")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	app._update_controllers(DT)
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	app._update_controllers(DT)
	_check(left.held == "", "Focus return with held squeeze cannot automatically regrab")

func _test_interaction_report() -> void:
	app._save_report()
	_check(FileAccess.file_exists(app.saved_path), "Interaction report saves on desktop")
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(app.saved_path))
	_check(report is Dictionary, "Interaction report is valid JSON")
	if not report is Dictionary:
		return
	_check(report.interaction_mode.contains("virtual hands"), "Report identifies virtual controller-hand input mode")
	_check(report.interaction_events.size() == app.interaction_events.size(), "Report retains actual interaction history")
	var kinds: Dictionary = {}
	for event in report.interaction_events:
		kinds[event.kind] = true
	_check(kinds.has("fingertip") and kinds.has("grip_begin") and kinds.has("grip_cancel") and kinds.has("rotor_seated") and kinds.has("guard_latched"), "Report distinguishes press, grab, cancellation, seating, and guard latch events")
	_check(report.has("runtime_samples") and report.runtime_note.contains("not compositor"), "Report labels application-loop timing without hardware comfort claims")

func _test_focus_source_conjunction() -> void:
	_fresh_session()
	app._set_xr_focus(false)
	_check(not app.input_focused and app.app_has_focus and not app.xr_has_focus, "OpenXR session focus loss disables input even while Android app stays focused")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(app.app_has_focus and not app.input_focused, "Android focus-in cannot override an unfocused OpenXR system-menu session")
	_place_palm(left, app.geometry.rotor_grab.global_position)
	left.node.simulated_grip = 1.0
	app._update_controllers(DT)
	_check(not left.tracked and not left.hand.visible and left.held == "", "Unfocused XR session suppresses hand visibility and nearby grip polling")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	app._set_xr_focus(true)
	_check(app.xr_has_focus and not app.app_has_focus and not app.input_focused, "OpenXR focus return cannot override Android application focus loss")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(app.app_has_focus and app.xr_has_focus and app.input_focused, "Input resumes only when both independent focus sources agree")
	app._update_controllers(DT)
	_check(left.tracked and left.hand.visible and left.held == "", "Focus recovery restores tracked hands without regrabbing a held squeeze")
	left.node.simulated_grip = 0.0
	app._update_controllers(DT)
	left.node.simulated_grip = 1.0
	app._update_controllers(DT)
	_check(left.held == "rotor", "Fresh deliberate grip works after both focus sources recover")
	app._cancel_hand_interactions()
	app.model.mount_rotor()
	app.model.home_probe()
	app.model.toggle_guard()
	_check(app.model.begin_run("baseline").ok, "Prepared acquisition starts before OpenXR session-focus test")
	app.model.tick(0.2)
	var records_before: int = app.model.records.size()
	app._set_xr_focus(false)
	_check(not app.model.running and app.model.rpm > 0.0 and not app.input_focused, "OpenXR focus loss immediately disables drive and preserves controlled coast")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(not app.input_focused and not app.model.running, "Android focus event during XR system menu cannot restart stopped acquisition")
	app._set_xr_focus(true)
	_check(app.input_focused and not app.model.running, "OpenXR focus return enables input without restarting drive")
	app.model.tick(2.0)
	_check(app.model.rpm < 0.1 and app.model.records.size() == records_before, "Focus-stopped acquisition coasts to zero without publishing a partial record")
	app._action("baseline")
	_check(app.model.running, "A new explicit command can restart after complete focus recovery")
	app.model.stop()
	app.model.tick(2.0)
