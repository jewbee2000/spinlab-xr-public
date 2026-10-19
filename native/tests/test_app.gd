extends SceneTree
## Exercise the actual world-menu commands without an OpenXR runtime.
## godot --headless --xr-mode off --path native --script res://tests/test_app.gd
## Omit --headless and append -- --capture=<absolute.png> for a verified-state image.

var checks: int = 0
var failures: int = 0
var app: Node3D
var _started_at: int
var _capture_path := ""


func _initialize() -> void:
	_started_at = Time.get_ticks_msec()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			_capture_path = argument.trim_prefix("--capture=")
	call_deferred("_run_tests")


func _run_tests() -> void:
	var scene = load("res://main.tscn") as PackedScene
	_check(scene != null, "Main scene loads")
	if scene == null:
		_finish()
		return
	app = scene.instantiate()
	app.tutorial_settings_path = ""
	app.tutorial_autostart = false
	root.add_child(app)
	app.set_process(false)
	app.set_process_unhandled_input(false)
	# Tests advance deterministic simulated time; worker-thread coverage lives in
	# the science suite and physical headset analysis remains asynchronous.
	app.model.async_processing = false
	_check(not app.xr_active, "Integration test uses desktop fallback without XR")
	_test_world_controls()
	_test_action_map()
	_test_balance_workflow(false)
	_test_balance_workflow(true)
	_check(Time.get_ticks_msec() - _started_at < 15000, "Integration suite completes within 15 seconds")
	if not _capture_path.is_empty():
		await _capture_verified_state()
	_finish()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("APP TEST: " + description)


func _finish() -> void:
	print("APP INTEGRATION TESTS: %d checks, %d failures (%d ms)" % [checks, failures, Time.get_ticks_msec() - _started_at])
	quit(0 if failures == 0 else 1)


func _click(command: String) -> bool:
	# Resolve the command through the same metadata selected by a controller ray.
	for button in app.buttons:
		if is_instance_valid(button) and str(button.get_meta("action", "")) == command:
			app._action(str(button.get_meta("action")))
			return true
	_check(false, "World button exposes command " + command)
	return false


func _tab(value: String) -> void:
	_click("tab:" + value)
	_check(app.tab == value, "Menu tab selected: " + value)


func _sync_ui() -> void:
	app._update_ui()
	app.geometry.update_state(app.model.telemetry())


func _test_world_controls() -> void:
	for menu in ["operate", "balance", "diagnostic", "session"]:
		_tab(menu)
		var menu_count := 0
		for button in app.buttons:
			_check(button is StaticBody3D, "World button is ray-collidable")
			_check(not str(button.get_meta("action", "")).is_empty(), "World button has an action")
			_check((button.collision_layer & 1) == (1 if button.enabled and button.is_visible_in_tree() else 0), "Only visible enabled buttons use controller collision layer")
			var shapes: Array = button.find_children("*", "CollisionShape3D", false, false)
			_check(not shapes.is_empty() and shapes[0].shape != null, "World button has a collision shape")
			_check(is_instance_valid(button.face) and is_instance_valid(button.text_label), "World button has a visible face and caption")
			if button.get_meta("menu", false):
				menu_count += 1
		_check(menu_count == 8, "Eight visible commands in " + menu)
	var physical_actions: Dictionary = {}
	var grabbable := false
	for body in app.geometry.find_children("*", "StaticBody3D", true, false):
		var action := str(body.get_meta("action", ""))
		physical_actions[action] = true
		if body.get_meta("grab_kind", "") == "rotor":
			grabbable = true
		_check(not body.find_children("*", "CollisionShape3D", false, false).is_empty(), "Physical fixture target has a collider")
	for action in ["mount", "guard", "home"]:
		_check(physical_actions.has(action), "Fixture supports physical action " + action)
	_check(grabbable, "Rotor cassette exposes grip interaction")
	_check(is_instance_valid(app.geometry.rotor) and is_instance_valid(app.geometry.kit_rotor), "Mounted and pickup rotor geometry exists")


func _test_action_map() -> void:
	var action_map = load("res://openxr_action_map.tres")
	_check(action_map != null, "Packaged OpenXR action map loads")
	if action_map == null:
		return
	var actions: Dictionary = {}
	for action_set in action_map.get("action_sets"):
		for action in action_set.get("actions"):
			actions[str(action.resource_name)] = action
	var required := ["trigger_click", "grip_click", "primary", "aim_pose", "haptic"]
	for action in required:
		_check(actions.has(action), "OpenXR action declared: " + action)
	var touch_profile
	for profile in action_map.get("interaction_profiles"):
		if str(profile.get("interaction_profile_path")) == "/interaction_profiles/oculus/touch_controller":
			touch_profile = profile
	_check(touch_profile != null, "Quest Touch interaction profile is packaged")
	if touch_profile == null:
		return
	var bindings: Dictionary = {}
	for binding in touch_profile.get("bindings"):
		var action_name := str(binding.get("action").resource_name)
		var path := str(binding.get("binding_path"))
		bindings[action_name + (":left" if path.begins_with("/user/hand/left/") else ":right")] = true
	for action in required:
		for hand in ["left", "right"]:
			_check(bindings.has(action + ":" + hand), "Quest Touch %s binds %s" % [hand, action])


func _acquire(command: String) -> bool:
	var count_before: int = app.model.records.size()
	_click(command)
	_check(app.model.running and app.model.run_kind == command, "Menu starts acquisition " + command)
	if not app.model.running:
		return false
	for step in range(850):
		app.model.tick(0.02)
		if not app.model.running and not app.model.processing and app.model.rpm < 1.0:
			break
	_sync_ui()
	var complete: bool = not app.model.running and not app.model.processing and app.model.rpm < 1.0
	_check(complete, command + " completes and coasts to zero")
	_check(app.model.records.size() == count_before + 1, command + " commits one traceable record")
	_check(str(app.model.latest.get("kind", "")) == command, command + " reaches instrument readout")
	return complete


func _guard(closed: bool) -> void:
	if app.model.guard_closed != closed:
		_tab("operate")
		_click("guard")
	_check(app.model.guard_closed == closed, "Guard is " + ("closed" if closed else "open"))


func _check_chart(kind: String) -> void:
	_check(app.chart_kind == kind, "Chart menu selects " + kind)
	_sync_ui()
	_check(app.chart.line_mesh.mesh != null and app.chart.line_mesh.mesh.get_surface_count() > 0, kind + " chart contains a rendered trace")
	_check(not app.readouts.chart.text.is_empty() and not app.readouts.axis.text.is_empty(), kind + " chart labels its data and units")


func _test_balance_workflow(two_plane: bool) -> void:
	_tab("session")
	_click("new")
	app.model.async_processing = false
	_check(not app.model.mounted and app.model.records.is_empty(), "Session reset clears fixture and records")
	if two_plane:
		_tab("operate")
		_click("mode")
	_check(app.model.mode == ("two_plane" if two_plane else "single"), "Requested balancing method selected")
	_tab("operate")
	_click("mount")
	_click("home")
	_check(app.model.mounted and app.model.homed, "Load and home commands prepare fixture")
	_guard(true)
	_tab("operate")
	if not _acquire("baseline"):
		return
	_check(not app.model.baseline.is_empty(), "Baseline is available to calibration")
	_check(app.model.waveform.size() == 256 and app.model.spectrum.size() == 101, "Native acquisition supplies waveform and spectrum")
	_check(app.geometry.rotor.visible and not app.geometry.kit_rotor.visible, "Mounted rotor replaces tray cassette")
	_tab("diagnostic")
	# Exercise all chart commands through their cyclic UI, regardless of the
	# view inherited from a preceding test scenario.
	for i in range(3):
		if app.chart_kind == "time":
			break
		_click("chart")
	_check_chart("time")
	_click("chart")
	_check_chart("order")
	if not _acquire("sweep"):
		return
	_check(app.model.sweep_points.size() >= 15, "Resonance sweep has multiple acquired speed points")
	_click("chart")
	_check_chart("sweep")
	_guard(false)
	_tab("balance")
	_click("fit_trial")
	_check(is_equal_approx(float(app.model.masses[0]), 0.25), "Known plane A trial installed from menu")
	_guard(true)
	_tab("balance")
	if not _acquire("trial_a"):
		return
	if two_plane:
		_guard(false)
		_tab("balance")
		_click("plane")
		_check(app.active_plane == 1, "Plane selector chooses B")
		_click("fit_trial")
		_check(is_zero_approx(float(app.model.masses[0])) and is_equal_approx(float(app.model.masses[1]), 0.25), "Plane B helper restores independent trial configuration")
		_guard(true)
		_tab("balance")
		if not _acquire("trial_b"):
			return
	_click("solve")
	_check(not app.model.solution.is_empty(), "Influence-coefficient solution reaches instrument")
	_check(app.readouts.solution.text.contains("condition"), "Solution readout reports matrix condition")
	_guard(false)
	_tab("balance")
	_click("apply")
	_check(float(app.model.masses[0]) > 0.0, "Calculated total correction is installed")
	_guard(true)
	_tab("balance")
	if not _acquire("verify"):
		return
	_check(app.model.latest.get("verified", false), "Corrected rotor passes numerical verification")
	_check(app.readouts.result is Label3D and app.readouts.result.text.begins_with("VERIFIED"), "Visible instrument announces VERIFIED")
	if two_plane:
		_check(app.model.latest.reduction_percent[1] > 90.0, "Two-plane verification includes sensor B")
	# A mass edit must invalidate a green result even though it does not erase
	# the historical verification record in the session report.
	_guard(false)
	_click("nudge:mass:1")
	_sync_ui()
	_check(not app.model.latest.get("verified", false), "Correction edit invalidates verified model status")
	_check(not app.readouts.result.text.begins_with("VERIFIED"), "Correction edit clears visible VERIFIED status")
	_tab("balance")
	_click("apply")
	_guard(true)
	_tab("balance")
	if not _acquire("repeat"):
		return
	var stats: Dictionary = app.model.latest.get("repeatability", {})
	_check(int(stats.get("n", 0)) == 3 and stats.get("windows", []).size() == 3, "Repeatability retains three independent windows")
	_check(app.readouts.quality.text.contains("n=3") and app.readouts.quality.text.contains("SEM"), "Repeatability instrument reports n and Type A SEM")
	if not _acquire("verify"):
		return
	_check(app.readouts.result.text.begins_with("VERIFIED"), "Reverification returns visible VERIFIED status")
	_test_report(two_plane)
	print("APP WORKFLOW OK mode=", app.model.mode, " records=", app.model.records.size(), " result=", app.readouts.result.text)


func _test_report(two_plane: bool) -> void:
	_tab("session")
	_click("save")
	_check(not app.saved_path.is_empty() and FileAccess.file_exists(app.saved_path), "Session menu exports JSON report")
	if app.saved_path.is_empty() or not FileAccess.file_exists(app.saved_path):
		return
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(app.saved_path))
	_check(report is Dictionary, "Export parses as JSON object")
	if not report is Dictionary:
		return
	_check(report.get("schema", "") == "spinlab-native-report-v1", "Report declares native schema")
	_check(report.get("application", "") == "SpinLab XR" and not report.get("version", "").is_empty(), "Report identifies application version")
	_check(report.configuration.mode == ("two_plane" if two_plane else "single"), "Report preserves balancing method")
	_check(report.records.size() == app.model.records.size() and report.records[-1].verified, "Report preserves measured records and final verification")
	_check(not report.baseline.is_empty() and not report.trial_a.is_empty() and not report.solution.is_empty(), "Report preserves calibration and solution")
	_check(report.sweep.size() >= 15 and report.references.size() >= 3, "Report preserves sweep and scientific references")
	_check(not report.events.is_empty() and not report.limitations.is_empty(), "Report includes event history and limitations")
	if two_plane:
		_check(not report.trial_b.is_empty(), "Two-plane report includes independent plane B trial")


func _capture_verified_state() -> void:
	if DisplayServer.get_name() == "headless":
		print("APP_CAPTURE_SKIPPED: headless rendering has no viewport pixels")
		return
	_tab("balance")
	app.chart_kind = "time"
	_sync_ui()
	for frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(_capture_path)
	_check(error == OK, "Verified-state screenshot saves")
	print("APP_CAPTURE ", _capture_path)
