class_name LabTutorial
extends RefCounted
## Self-paced instruction only. This class reads snapshots and accepted action
## outcomes; it never operates, resets, or starts the laboratory model.

var active: bool = false
var index: int = 0
var startup_enabled: bool = true
var completed: bool = false
var preferences_path: String = "user://tutorial.cfg"
var settings_error: String = ""
var steps: Array = []
var _flags: Dictionary = {}

func _init(settings_path: String = "user://tutorial.cfg") -> void:
	steps = _make_steps()
	load_settings(settings_path)

func start(snapshot: Dictionary) -> void:
	active = true
	index = 0
	_flags.clear()
	observe(snapshot)

func should_autostart() -> bool:
	# Completion turns this preference off. Explicitly enabling it afterward
	# must honor the visible ON setting, even when completion history exists.
	return startup_enabled

func set_startup(enabled: bool) -> Dictionary:
	if enabled == startup_enabled:
		return {"ok": true, "message": "Startup tutorial setting unchanged."}
	startup_enabled = enabled
	return save_settings(preferences_path)

func load_settings(path: String) -> Dictionary:
	preferences_path = path
	startup_enabled = true
	completed = false
	settings_error = ""
	if path.is_empty():
		return {"ok": true, "message": "Tutorial preferences use memory only."}
	var config := ConfigFile.new()
	var result: Error = config.load(path)
	if result == ERR_FILE_NOT_FOUND:
		return {"ok": true, "message": "Default tutorial preferences loaded."}
	if result != OK:
		settings_error = "Could not load tutorial settings: %s" % error_string(result)
		return {"ok": false, "message": settings_error}
	var startup_value: Variant = config.get_value("tutorial", "startup_enabled", true)
	var completed_value: Variant = config.get_value("tutorial", "completed", false)
	startup_enabled = startup_value if typeof(startup_value) == TYPE_BOOL else true
	completed = completed_value if typeof(completed_value) == TYPE_BOOL else false
	return {"ok": true, "message": "Tutorial preferences loaded."}

func save_settings(path: String) -> Dictionary:
	preferences_path = path
	settings_error = ""
	if path.is_empty():
		return {"ok": true, "message": "Tutorial preferences updated in memory."}
	var config := ConfigFile.new()
	config.set_value("tutorial", "schema", 1)
	config.set_value("tutorial", "startup_enabled", startup_enabled)
	config.set_value("tutorial", "completed", completed)
	var result: Error = config.save(path)
	if result != OK:
		settings_error = "Could not save tutorial settings: %s" % error_string(result)
		return {"ok": false, "message": settings_error}
	return {"ok": true, "message": "Tutorial preferences saved."}

func observe(snapshot: Dictionary, event: Dictionary = {}) -> void:
	if not active:
		return
	var accepted: bool = typeof(event.get("ok", false)) == TYPE_BOOL and event.get("ok", false)
	var record_id: int = _last_record_id(snapshot)
	var previous_id: int = int(_flags.get("observed_record_id", record_id))
	if record_id < previous_id or (accepted and str(event.get("command", "")) == "new"):
		# A new session reuses small record IDs. Never compare its verification
		# against the Apply checkpoint from a discarded laboratory session.
		_flags.erase("apply_seen")
		_flags.erase("apply_record_id")
		_flags.erase("pending_fault")
	_flags["observed_record_id"] = record_id
	if str(event.get("input_kind", event.get("kind", ""))) == "fingertip" and event.get("contact_accepted", false) == true:
		# Physical contact may be valid while the fixture rejects the requested
		# operation (for example Home before loading). Credit contact practice
		# only; measurement and preparation gates still require actual lab state.
		_flags["touch_practiced"] = true
	if accepted:
		var command: String = str(event.get("command", event.get("target", "")))
		if command=="new":_flags.erase("report_saved")
		var input_kind: String = str(event.get("input_kind", event.get("kind", "")))
		if input_kind == "pointer":
			_flags["pointer_practiced"] = true
		if command == "tutorial:touch" or (input_kind == "fingertip" and not command.begins_with("tutorial:")):
			_flags["touch_practiced"] = true
		if ["walk", "height", "distance", "recenter"].has(command):
			_flags["comfort_used"] = true
		if command == "dial:probe" and event.get("changed", false) == true:
			_flags["probe_moved"] = true
		if command == "apply":
			_flags["apply_seen"] = true
			_flags["apply_record_id"] = _last_record_id(snapshot)
		if command == "save":
			_flags["report_saved"] = true
		if command == "fault_sensor":
			_flags["sensor_fault_seen"] = true
		if command == "fault_tach":
			_flags["tach_fault_seen"] = true
	if float(snapshot.get("walk_distance_m", 0.0)) >= 0.05 or bool(snapshot.get("height_changed", false)):
		_flags["comfort_used"] = true
	if absf(float(snapshot.get("sensor_position_mm", 6.0)) - 6.0) > 0.015:
		_flags["probe_moved"] = true
	var chart_kind: String = str(snapshot.get("chart_kind", ""))
	if chart_kind == "time":
		_flags["chart_time"] = true
	elif chart_kind == "order":
		_flags["chart_order"] = true
	if bool(snapshot.get("estop", false)) and _at_zero(snapshot):
		_flags["estop_at_zero"] = true
	var fault_text: String = str(snapshot.get("fault", "")).to_lower()
	if fault_text.contains("sensor"):
		_flags["sensor_fault_seen"] = true
		_flags["pending_fault"] = "sensor"
	if fault_text.contains("tach"):
		_flags["tach_fault_seen"] = true
		_flags["pending_fault"] = "tach"
	if _healthy(snapshot) and bool(snapshot.get("homed", false)) and _at_zero(snapshot):
		var pending: String = str(_flags.get("pending_fault", ""))
		if not pending.is_empty():
			_flags[pending + "_recovered"] = true
			_flags["pending_fault"] = ""

func view(snapshot: Dictionary) -> Dictionary:
	observe(snapshot)
	var step: Dictionary = steps[clampi(index, 0, steps.size() - 1)]
	var ready: bool = _gate_ready(str(step.gate), snapshot)
	var result: Dictionary = step.duplicate(true)
	result.merge({"active": active, "index": index, "total": steps.size(), "step_index": index + 1, "step_count": steps.size(),
		"progress": "Step %d / %d" % [index + 1, steps.size()], "progress_fraction": float(index) / float(steps.size()),
		"ready": ready, "hint": "A continues. X goes back. B/Y opens the menu." if ready else step.gatehint,
		"what": step.body, "why": step.theory, "startup_enabled": startup_enabled, "completed": completed, "complete": completed,
		"can_back": active and index > 0, "can_skip": active, "is_last": index == steps.size() - 1,
		"can_finish": active and ready and index == steps.size() - 1, "settings_error": settings_error})
	return result

func next(snapshot: Dictionary) -> Dictionary:
	if not active:
		return {"ok": false, "message": "Start the tutorial first.", "finished": false}
	var current: Dictionary = view(snapshot)
	if not current.ready:
		return {"ok": false, "message": current.gatehint, "finished": false}
	if index == steps.size() - 1:
		active = false
		completed = true
		startup_enabled = false
		var saved: Dictionary = save_settings(preferences_path)
		return {"ok": true, "message": "Guide complete. Restart it from the Session menu at any time." if saved.ok else saved.message,
			"finished": true, "settings_saved": saved.ok}
	index += 1
	return {"ok": true, "message": "Next lesson.", "finished": false}

func back() -> Dictionary:
	if not active or index <= 0:
		return {"ok": false, "message": "This is the first lesson.", "finished": false}
	index -= 1
	return {"ok": true, "message": "Previous lesson.", "finished": false}

func skip_step() -> Dictionary:
	if not active:
		return {"ok": false, "message": "Start the tutorial first.", "finished": false}
	if index == steps.size() - 1:
		skip()
		return {"ok": true, "message": "Tutorial closed. Startup preference unchanged.", "finished": true, "skipped": true}
	index += 1
	return {"ok": true, "message": "Lesson skipped; return with Back when useful.", "finished": false, "skipped": true}

func skip() -> void:
	active = false

func _at_zero(snapshot: Dictionary) -> bool:
	return not bool(snapshot.get("running", false)) and not bool(snapshot.get("processing", false)) and float(snapshot.get("rpm", 0.0)) < 0.1

func _healthy(snapshot: Dictionary) -> bool:
	return not bool(snapshot.get("estop", false)) and str(snapshot.get("fault", "")).is_empty()

func _accepted_capture(record: Variant, kind: String) -> bool:
	return record is Dictionary and not record.is_empty() and record.get("accepted", false) == true and str(record.get("kind", "")) == kind

func _has_capture(snapshot: Dictionary, kind: String) -> bool:
	for record in snapshot.get("records", []):
		if _accepted_capture(record, kind):
			return true
	return false

func _last_record_id(snapshot: Dictionary) -> int:
	var latest: Dictionary = snapshot.get("latest", {})
	return int(latest.get("id", snapshot.get("records", []).size()))

func _mass_vector(config: Dictionary, plane: int) -> Vector2:
	var mass_values: Array = config.get("masses", config.get("masses_g", [0.0, 0.0]))
	var angle_values: Array = config.get("angles", config.get("angles_deg", [0.0, 0.0]))
	if mass_values.size() <= plane or angle_values.size() <= plane:
		return Vector2.ZERO
	var radians: float = deg_to_rad(float(angle_values[plane]))
	return Vector2(cos(radians), sin(radians)) * float(mass_values[plane]) * float(config.get("radius_mm", 30.0))

func _trial_installed(snapshot: Dictionary) -> bool:
	var baseline: Dictionary = snapshot.get("baseline", {})
	if not _accepted_capture(baseline, "baseline"):
		return false
	return (_mass_vector(snapshot, 0) - _mass_vector(baseline, 0)).length() >= 0.15 and (_mass_vector(snapshot, 1) - _mass_vector(baseline, 1)).length() < 0.001

func _solution_valid(snapshot: Dictionary) -> bool:
	var solution: Dictionary = snapshot.get("solution", {})
	if solution.is_empty():
		return false
	var condition: float = float(solution.get("condition_number", INF))
	return is_finite(condition) and condition >= 1.0 and condition <= 30.0

func _solution_installed(snapshot: Dictionary) -> bool:
	if not _solution_valid(snapshot):
		return false
	var solution: Dictionary = snapshot.solution
	if not solution.has("masses_g") or not solution.has("angles_deg"):
		return false
	return (_mass_vector(snapshot, 0) - _mass_vector(solution, 0)).length() < 0.01 and (_mass_vector(snapshot, 1) - _mass_vector(solution, 1)).length() < 0.01

func _fresh_verification(snapshot: Dictionary) -> bool:
	var latest: Dictionary = snapshot.get("latest", {})
	if not _at_zero(snapshot) or not _healthy(snapshot) or not _accepted_capture(latest, "verify") or bool(latest.get("configuration_changed", false)) or not _solution_installed(snapshot):
		return false
	if _flags.get("apply_seen", false):
		return int(latest.get("id", 0)) > int(_flags.get("apply_record_id", 0))
	return true

func _repeat_done(snapshot: Dictionary) -> bool:
	for record in snapshot.get("records", []):
		if _accepted_capture(record, "repeat") and int(record.get("repeatability", {}).get("n", 0)) >= 3:
			return true
	return false

func _sweep_done(snapshot: Dictionary) -> bool:
	for record in snapshot.get("records", []):
		if _accepted_capture(record, "sweep") and record.get("points", []).size() >= 10:
			return true
	return false

func _gate_ready(gate: String, snapshot: Dictionary) -> bool:
	match gate:
		"read": return true
		"comfort": return bool(_flags.get("comfort_used", false))
		"touch", "pointer_menu": return (bool(_flags.get("pointer_practiced", false)) or bool(_flags.get("touch_practiced", false))) and not bool(snapshot.get("menu_open", false))
		"mounted": return bool(snapshot.get("mounted", false))
		"home": return bool(snapshot.get("homed", false)) and _healthy(snapshot)
		"dial_restore": return bool(_flags.get("probe_moved", false)) and bool(snapshot.get("homed", false)) and absf(float(snapshot.get("sensor_position_mm", 6.0)) - 6.0) < 0.015 and _at_zero(snapshot)
		"guard": return bool(snapshot.get("guard_closed", false)) and bool(snapshot.get("grab_owners_empty", true)) and _at_zero(snapshot)
		"baseline": return _accepted_capture(snapshot.get("baseline", {}), "baseline") and _at_zero(snapshot)
		"analyzer": return bool(_flags.get("chart_time", false)) and bool(_flags.get("chart_order", false))
		"trial_fit": return _trial_installed(snapshot) and _at_zero(snapshot)
		"trial_a": return _accepted_capture(snapshot.get("trial_a", {}), "trial_a") and _at_zero(snapshot)
		"solve": return _solution_valid(snapshot) and _at_zero(snapshot)
		"verify": return _fresh_verification(snapshot)
		"repeat": return _repeat_done(snapshot) and _at_zero(snapshot)
		"sweep": return _sweep_done(snapshot) and _at_zero(snapshot)
		"two_plane": return str(snapshot.get("mode", "single")) == "two_plane" and _at_zero(snapshot)
		"estop_recovery": return bool(_flags.get("estop_at_zero", false)) and _healthy(snapshot) and bool(snapshot.get("homed", false)) and _at_zero(snapshot)
		"fault_recovery": return bool(_flags.get("sensor_recovered", false)) and bool(_flags.get("tach_recovered", false)) and _healthy(snapshot) and bool(snapshot.get("homed", false)) and _at_zero(snapshot)
		"save": return bool(snapshot.get("saved_report", false)) or bool(_flags.get("report_saved", false))
	return false

func _make_steps() -> Array:
	return [
		_step("welcome", "ORIENT", "Welcome to SpinLab", "A (right) continues; X (left) goes back. Use B/Y to open the menu, then point and trigger to issue commands. B/Y closes it and restores hands for the rotor, guard, and dials.", "This floating guide is separate from the four-tab menu. The highlighted tab shows your location. Session offers pause/resume, restart, and startup settings. Guide navigation never starts the drive.", "read", "Press A to continue. B/Y opens the preferred pointer menu for commands.", "operate", ""),
		_step("comfort", "ORIENT", "Find a comfortable position", "Use the right stick to walk relative to your view. Use the left stick to adjust bench height. Try a small movement or height change until the fixture is comfortably within reach.", "Stay inside your clear play area. Focus loss stops acquisition. After focus or tracking returns, release grip and withdraw the fingertip before interacting again.", "comfort", "Move with the right stick, or adjust height with the left stick.", "session", ""),
		_step("touch", "ORIENT", "Point and trigger a menu command", "Press B/Y, aim a controller ray at the Operate tab, and squeeze index trigger. Then press B/Y to close the menu. Use this pointer method for station commands.", "Use pointer buttons for commands and hands for rotor, guard, and dials. Physical console caps are optional. A valid selection can still be rejected until the fixture is ready.", "pointer_menu", "Select the Operate tab with ray and trigger, then close the menu with B/Y.", "operate", "tab:operate"),
		_step("load", "PREPARE", "Carry the rotor onto the spindle", "Reach the tray rotor and squeeze grip nearby. Carry it upright over the spindle, then release. A distant or upside-down release returns it to the tray.", "The rotor follows the grip pose and has one owner. Seating checks position and upright orientation. These assembly constraints do not simulate contact forces.", "mounted", "Grip the tray rotor; release it upright and centered above the spindle.", "operate", "rotor"),
		_step("home", "PREPARE", "Home the vibration probe", "With rotor loaded and speed at zero, open B/Y menu > Operate > Home. Select it with ray and trigger. Confirm 6.00 mm, then close the menu. Clear faults first if needed.", "Homing establishes the probe reference. Homing, probe motion, speed or mode changes, and a new baseline discard calibration. Complete preparation before measuring trials.", "home", "Use Operate > Home with rotor loaded, faults cleared, and speed at zero.", "operate", "home"),
		_step("dials", "PREPARE", "Turn a dial, then restore Home", "Grip a nearby probe dial and twist your wrist about its shaft. Try a small change, release, then use menu > Operate > Home. Mass and angle dials edit the selected correction plane.", "Wrist translation alone does not turn a dial. The operating standoff is 4–8 mm; 6 mm is the reference. Corrections need zero speed and an open guard. Probe motion invalidates calibration.", "dial_restore", "Change the probe dial, release grip, then use menu Home to restore 6.00 mm.", "operate", "dial:probe"),
		_step("guard", "PREPARE", "Lower and latch the guard", "Grip the orange guard handle. Lower it fully and release to latch. Release every mechanical handle before starting the spindle.", "Lifting opens the interlock. A held handle cannot authorize a run even at the bottom of its travel. This enclosure is a training representation, not certified machinery containment.", "guard", "Lower the orange handle fully, release grip, and confirm CLOSED.", "operate", "guard"),
		_step("baseline", "MEASURE", "Record the unchanged baseline", "Use menu > Operate > Record Baseline with the fixture ready. Wait for capture and coast. Stop / Controlled Coast aborts capture; wait for zero before adjustments. Partial runs are rejected.", "Baseline stores both tach phasors and installed masses. Trials preserve speed, radius, probe setup, and baseline configuration. A new baseline replaces calibration captures.", "baseline", "Select Operate > Record Baseline with pointer/trigger, then wait for zero.", "operate", "baseline"),
		_step("phasor", "MEASURE", "Read amplitude and tach phase", "Read sensor A and B amplitudes in micrometres peak. Phase is relative to the tachometer. Near the noise floor, an unavailable phase has no useful direction.", "For a sinusoid, RMS = peak/√2. Unbalance force F = Uω², where U = mass × radius. Supports rotate and amplify vibration, so measured phase is not simply the heavy-spot angle.", "read", "Read both amplitudes, phase observability, and units; A continues.", "diagnostic", "chart"),
		_step("analyzer", "MEASURE", "Compare waveform and spectrum", "Open B/Y menu, then Analyze > Chart. Cycle to Time and Order views. Close the menu to restore hands. A 1× tone follows shaft frequency, rpm/60; the spectrum covers 0–100 Hz.", "A capture fits DC and 1×/2× from 1,024 samples at 1,024 Hz. Balancing uses its tach least-squares phasor. Off-bin DFT leakage can make the largest spectrum bin differ from that amplitude.", "analyzer", "Use Analyze > Chart to view both Time and Order, then close the menu.", "diagnostic", "chart"),
		_step("trial_fit", "BALANCE", "Fit a known plane A trial", "At zero, open the guard and use menu > Balance > Fit Known Trial on plane A. It adds 0.250 g relative to baseline and restores the other plane to its baseline configuration.", "A trial supplies known mass-radius vector Ut. Its measured effect identifies sensitivity. An independent trial changes only one plane against the same baseline.", "trial_fit", "Open the guard, then use Balance > Fit Known Trial on plane A.", "balance", "fit_trial"),
		_step("trial_measure", "BALANCE", "Measure the plane A response", "Release handles and close the guard. Use menu > Balance > Measure Trial A at baseline speed. Wait for capture and coast to zero.", "Subtracting baseline vibration V0 from trial vibration Vt isolates the known trial's response, including phase through the support and sensors. Both planes must not change together.", "trial_a", "Use Balance > Measure Trial A with guard closed, then wait for zero.", "balance", "trial_a"),
		_step("solve", "BALANCE", "Solve from measured influence", "In menu > Balance, point and trigger Solve Influence Matrix. Inspect calculated mass, angle, and matrix condition. The solver uses captured measurements, not hidden rotor imbalance.", "For one plane: α = (Vt − V0)/Ut and C = −V0/α. C is added to baseline. Complex division accounts for support phase; placing mass opposite the raw measured phase is insufficient.", "solve", "After baseline and Trial A, select Balance > Solve Influence Matrix.", "balance", "solve"),
		_step("verify", "BALANCE", "Apply and measure again", "At zero, open the guard and select Balance > Fit Calculated Correction in the menu. It installs total masses. Close the guard, select Verify, and read reduction. Inspect and retry a failed result.", "Only a fresh measurement tests the installed correction. Editing setup clears the current pass. Single-plane balancing minimizes sensor A at one speed; sensor B can retain motion.", "verify", "Use Balance > Apply, close the guard, then Verify and coast to zero.", "balance", "apply"),
		_step("repeat", "DIAGNOSE", "Measure repeatability", "With unchanged setup, select menu > Balance > Repeatability. Read n = 3, mean amplitude, sample standard deviation s, and Type A standard error of the mean.", "s describes repeat scatter; SEM = s/√n describes the mean under independent repeats. These synthetic windows omit calibration bias and do not establish total or expanded uncertainty.", "repeat", "Select Balance > Repeatability and wait for zero speed.", "balance", "repeat"),
		_step("sweep", "DIAGNOSE", "Explore the support resonance", "Select menu > Analyze > Resonance Speed Sweep. Inspect amplitude versus rpm. The support mode is near 22 Hz, or 1,320 rpm. A balanced rotor may have only a small synchronous response.", "The sweep uses separate quasi-steady windows, not transient integration. Forcing grows with speed squared, so an unnormalized peak width is not a direct damping estimate.", "sweep", "Select Analyze > Sweep, coast to zero, and inspect its trace.", "diagnostic", "sweep"),
		_step("two_plane", "ADVANCED", "Two planes and cross response", "Use menu > Operate > Mode to select Two Plane. Advanced practice uses a fresh baseline and independent A/B trials, restoring the other plane each time. Solve, apply totals, and verify both sensors.", "Both sensors respond to both planes: direct and off-diagonal coefficients form A·C = −V0. Poor conditioning amplifies measurement error; the app rejects condition numbers above 30.", "two_plane", "Use Operate > Mode at zero, or Session > Skip Lesson to retain calibration.", "operate", "mode"),
		_step("estop", "RECOVER", "Practice deliberate E-stop recovery", "At zero speed, use menu > Operate > Emergency Stop, then Release/Reset and Home. Keep the drive stopped throughout this exercise.", "E-stop discards calibration; release requires probe referencing again. Releasing it never starts a run. This practice demonstrates recovery states, not a certified safety circuit.", "estop_recovery", "Use Operate > E-stop, Release/Reset, then Home. Calibration is discarded.", "operate", "estop"),
		_step("faults", "RECOVER", "Recover sensor and tach faults", "At zero, inject sensor disconnect from the Analyze menu. Use Operate > Reset, then Home. Repeat with Analyze > Tachometer Loss. Read both messages and restore referencing after each.", "Missing sensor or tach data invalidates calibration. Reset never restarts the spindle. Further measurements require a fresh baseline and trials.", "fault_recovery", "Use Analyze faults and Operate recovery/Home for both sensor and tach.", "diagnostic", "fault_sensor"),
		_step("references", "REFERENCE", "Inspect tools and test speed", "Try Explode/Assemble, sound, and Guided Coach. Reassemble afterward. Test Speed cycles 900/1,200/1,500 rpm at zero and discards calibration; baseline and trials must share a speed.", "Exploded geometry leaves the numerical model unchanged. Audio represents motor speed, not calibrated vibration. Text communicates critical states without sound or haptics.", "read", "Explore these optional controls from Analyze; A continues.", "diagnostic", "explode"),
		_step("report", "SESSION", "Save a traceable JSON report", "Use B/Y menu > Session > Save Report. Confirm the saved path. The JSON retains configuration, captures, solver diagnostics, events, scientific references, and limits.", "Traceability links results to setup and history. A button press does not prove a file was saved. App-loop timing is not GPU/compositor frame time or a comfort measurement.", "save", "Save Report successfully from Session and confirm its output path.", "session", "save"),
		_step("session", "SESSION", "Pause, restart, or start again", "Session offers guide pause/resume, restart, skip lesson, and startup OFF. Operate > New Session clears lab data; save first. Exit closes the app. B/Y closes the menu and restores hands.", "The read-only guide never resets or operates the lab. Its navigation and startup preference are separate from fixture state, calibration, and saved reports.", "read", "A continues. No reset or exit is required to finish the guide.", "session", "new"),
		_step("finish", "FINISH", "Continue practicing independently", "Press A to finish. Restart this guide from Session whenever useful. Enabling Show at Startup again makes it appear on the next launch.", "Completion records this guide, including skipped lessons. It does not certify laboratory competence, machinery safety, scientific accuracy, or headset performance.", "read", "Press A to finish; laboratory state stays unchanged.", "session", "")
	]

func _step(id: String, chapter: String, title: String, body: String, theory: String, gate: String, gatehint: String, practice_tab: String, target: String) -> Dictionary:
	return {"id": id, "chapter": chapter, "title": title, "body": body, "theory": theory, "gate": gate, "gatehint": gatehint, "practice_tab": practice_tab, "target": target}
