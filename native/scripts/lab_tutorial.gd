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
	if accepted:
		var command: String = str(event.get("command", event.get("target", "")))
		if command=="new":_flags.erase("report_saved")
		var input_kind: String = str(event.get("input_kind", event.get("kind", "")))
		if command == "tutorial:touch" or (input_kind == "fingertip" and not command.begins_with("tutorial:")):
			_flags["touch_practiced"] = true
		if ["lower", "raise", "distance", "recenter", "assist"].has(command):
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
	if bool(snapshot.get("reach_assist", false)):
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
		"ready": ready, "hint": "Ready when you are. Next continues; Practice opens the lab controls." if ready else step.gatehint,
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
		return {"ok": true, "message": "Tutorial complete. Reopen Learn at any time." if saved.ok else saved.message,
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
		"touch": return bool(_flags.get("touch_practiced", false))
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
		_step("welcome", "ORIENT", "Welcome to SpinLab", "Learn to measure rotor vibration, find a correction, and verify it. Release the index trigger, touch Next with the extended fingertip, then withdraw. Practice opens real controls; Back and Skip let you review or leave.", "Rotor mass errors create vibration that grows with speed and is amplified by the supports. This simulated station uses measured vibration amplitude and tach phase to estimate the mass and angle of a balancing correction.", "read", "Read, then choose Next. Skip a lesson or close the tour whenever useful.", "operate", ""),
		_step("comfort", "ORIENT", "Make the bench comfortable", "Use Session to adjust bench height and distance, or recenter. Try a comfortable reach. B/Y cycles menus; holding B/Y toggles optional reach assist for menu buttons.", "Keep physical movement within your clear play area. After tracking or focus returns, release grip and withdraw the fingertip before interacting again. App or XR focus loss stops acquisition.", "comfort", "Use a height, distance, recenter, or reach-assist control in Session.", "session", "distance"),
		_step("touch", "ORIENT", "Practice a deliberate fingertip press", "Approach a button from its front with an extended index finger, then push through its short stroke and withdraw. Try the tutorial's touch-practice button. On desktop, click that button.", "A fresh front approach arms contact. Stroke, debounce, and withdrawal prevent repeated presses while held. Grip selects nearby mechanical handles; distant trigger selection needs optional reach assist.", "touch", "Press the touch-practice button, or complete an accepted physical fingertip action.", "operate", "tutorial:touch"),
		_step("load", "PREPARE", "Carry the rotor onto the spindle", "Reach the tray rotor and squeeze grip nearby. Carry it upright over the spindle, then release. A distant or upside-down release returns it to the tray.", "The virtual rotor follows the grip pose with an offset and has one owner at a time. Seating checks position and upright orientation. This is constrained assembly training, not contact-force physics.", "mounted", "Grip the tray rotor nearby; release it upright and centered above the spindle.", "operate", "rotor"),
		_step("home", "PREPARE", "Home the vibration probe", "At zero speed, press the physical HOME cap or Home control. Confirm the probe reads 6.00 mm. Keep the rotor loaded and clear faults first.", "Homing establishes the probe reference. Homing, probe motion, speed or mode changes, and a new baseline discard current influence-coefficient calibration. Perform these before calibration runs.", "home", "Load the rotor, clear faults, then Home the probe at zero speed.", "operate", "home"),
		_step("dials", "PREPARE", "Turn a dial, then restore Home", "Grip a nearby probe dial and turn your wrist about its shaft; translation alone does not adjust it. Try a small probe change, release, then Home again. Mass and angle dials edit the selected plane.", "The synthetic probe permits 4–8 mm standoff; 6 mm is the reference. Corrections require zero speed and an open guard. Probe changes invalidate calibration, so restore Home before measuring.", "dial_restore", "Change the probe setting, release its dial, then Home it back to 6.00 mm.", "operate", "dial:probe"),
		_step("guard", "PREPARE", "Lower and latch the guard", "Grip the orange guard handle nearby. Lower it fully and release to latch. The interlock opens when the handle is lifted. Release every mechanical handle before starting the spindle.", "Guard state inhibits the simulated drive. A held handle cannot authorize a run even at the bottom of its travel. Guard motion and containment are training representations, not certified machinery safety.", "guard", "Lower the orange handle fully, release grip, and confirm the guard is closed.", "operate", "guard"),
		_step("baseline", "MEASURE", "Record the unchanged baseline", "Record Baseline with the rotor loaded, probe homed, and guard closed. Wait for capture and coast. Stop / Controlled Coast aborts capture; wait for zero speed before adjustments. Partial runs are not accepted.", "Baseline stores both tach phasors and the installed masses. Trials must preserve speed, radius, probe setup, and baseline configuration. A new baseline replaces calibration captures.", "baseline", "Record a completed baseline and wait for zero speed.", "operate", "baseline"),
		_step("phasor", "MEASURE", "Read amplitude and tach phase", "Read sensor A and B amplitudes in micrometres peak. Phase is measured against the tachometer. Near the noise floor, phase is shown as unavailable rather than a meaningful direction.", "For a sinusoid, RMS = peak/√2. Unbalance force is F = Uω², where U = mass × eccentric radius. Support dynamics rotate and amplify vibration, so measured phase is not simply the rotor's heavy-spot angle.", "read", "Compare both amplitudes, phase observability, and units.", "diagnostic", "chart"),
		_step("analyzer", "MEASURE", "Compare waveform, spectrum, and order", "Cycle Chart with A/X or the Chart control to Time and Order. The waveform includes DC, 1×, 2×, and noise. The spectrum displays a 0–100 Hz DFT; a 1× tone follows shaft frequency, rpm/60.", "Each capture fits DC plus sine/cosine at 1× and 2× from 1,024 samples at 1,024 Hz. The solver uses the tach least-squares phasor. Off-bin DFT leakage means its largest bin can differ from that amplitude.", "analyzer", "Open both Time and Order chart views in Analyze.", "diagnostic", "chart"),
		_step("trial_fit", "BALANCE", "Fit a known plane A trial", "At zero speed, open the guard and select plane A. Fit Known Trial adds 0.250 g at a known angle relative to baseline and restores the other plane to its baseline mass configuration.", "A trial supplies a known complex mass-radius vector Ut. Its measured change identifies sensitivity. Independent trials change only one correction plane relative to the same baseline.", "trial_fit", "Open the guard and Fit Known Trial on plane A using a valid baseline.", "balance", "fit_trial"),
		_step("trial_measure", "BALANCE", "Measure the plane A response", "Release handles, close the guard, and Measure Trial A at the baseline speed. Wait for capture and coast. The model rejects missing trials, setup mismatches, and changes to both planes together.", "The trial measurement Vt and baseline V0 are complex vibration vectors. Subtracting them isolates the response caused by the known trial, including its phase through the support and sensors.", "trial_a", "Close the guard, Measure Trial A, and wait for zero speed.", "balance", "trial_a"),
		_step("solve", "BALANCE", "Solve from measured influence", "Choose Solve Influence Matrix. Inspect the calculated mass, angle, and conditioning diagnostic. The solver uses captured baseline and trial phasors; it does not read the hidden rotor imbalance.", "For one plane: α = (Vt − V0)/Ut, then C = −V0/α. C is the correction added to baseline. The complex division accounts for sensor and support phase; rotating mass opposite the raw measured phase is insufficient.", "solve", "Capture valid baseline and Trial A measurements, then Solve.", "balance", "solve"),
		_step("verify", "BALANCE", "Apply, then take a fresh verification", "At zero speed, open the guard and Fit Calculated Correction. This replaces trial masses with total installed masses. Close the guard and Verify. Read the measured reduction; a failed result is a reason to inspect and retry.", "A prediction is not a verification. Only a fresh accepted measurement tests the installed correction. Editing configuration clears the current pass. Single-plane balancing minimizes sensor A at one speed; B can retain motion.", "verify", "Fit the calculated correction, then complete a fresh Verify run and coast to zero.", "balance", "apply"),
		_step("repeat", "DIAGNOSE", "Measure repeatability", "With unchanged setup, run Repeatability. Read n = 3, the mean amplitude, sample standard deviation s, and Type A standard error of the mean. Keep the guard closed until zero speed.", "s describes repeat scatter; SEM = s/√n describes uncertainty of the mean under independent repeats. These three synthetic windows do not include calibration bias or establish total or expanded uncertainty.", "repeat", "Complete Repeatability with three accepted windows, then wait for zero speed.", "balance", "repeat"),
		_step("sweep", "DIAGNOSE", "Explore the support resonance", "Run Resonance Speed Sweep and inspect amplitude versus rpm. The illustrative support mode is near 22 Hz, or 1,320 rpm. A balanced rotor may produce only a small synchronous response.", "This sweep evaluates separate quasi-steady windows in a damped model; it is not a transient integration. Forcing changes with speed squared. An unnormalized peak width is not a valid direct damping estimate.", "sweep", "Complete a speed sweep and wait for zero speed; inspect its recorded trace.", "diagnostic", "sweep"),
		_step("two_plane", "ADVANCED", "Two planes and cross response", "Select Two Plane mode for the advanced method. Capture a fresh baseline, then independent A and B trials. Before each trial, restore the other plane to baseline. Solve, apply totals, and verify both sensors.", "Both sensors respond to both planes, giving direct and off-diagonal complex coefficients in A·C = −V0. Singular or poorly conditioned A amplifies measurement error; the app rejects condition numbers above 30.", "two_plane", "Select Two Plane mode at zero speed, or skip this optional advanced reference.", "operate", "mode"),
		_step("estop", "RECOVER", "Practice E-stop recovery at zero speed", "At zero speed, press Emergency Stop, then Release/Reset. Rehome the probe. The drive must remain stopped throughout this practice. Releasing E-stop never starts a run.", "E-stop clears calibration and probe referencing in this training model. This exercise checks deliberate recovery state; it does not validate a real safety circuit or require an emergency during a run.", "estop_recovery", "At zero speed: E-stop, Release/Reset, then Home. Calibration will be discarded.", "operate", "estop"),
		_step("faults", "RECOVER", "Recover sensor and tach faults", "At zero speed, inject a sensor disconnect, reset, and Home. Repeat with tachometer loss. Read each fault message. Restore referencing after the final reset before continuing.", "Missing sensor or tach data makes calibration untrustworthy. These faults discard captures and require rehoming; no reset restarts the spindle. Future measurements need a fresh baseline and trials.", "fault_recovery", "Practice both sensor and tach faults, resetting and homing after each.", "diagnostic", "fault_sensor"),
		_step("references", "REFERENCE", "Inspect tools and test speed", "Try Explode/Assemble, motor sonification, and Guided Coach. Reassemble before practice. Test Speed cycles 900/1,200/1,500 rpm at zero speed; changing it discards calibration. Use one speed for baseline and trials.", "Exploded geometry clarifies assemblies without changing the numerical model. Audio represents motor speed, not a calibrated vibration measurement. Text carries critical states even when audio or haptics are unavailable.", "read", "These reference tools are optional; Next continues without changing the fixture.", "diagnostic", "explode"),
		_step("report", "SESSION", "Save a traceable JSON report", "Choose Save Report in Session. Confirm the saved-file message. The report contains configuration, accepted captures, solver diagnostics, events, scientific references, and limits. Keep the file with your test notes.", "Traceability connects a result to its setup, method, and history. A command press is not proof of a saved file. Application-loop timing in the report is not compositor/GPU frame time or comfort acceptance.", "save", "Save Report successfully and confirm its output path.", "session", "save"),
		_step("session", "SESSION", "Start again or leave deliberately", "New Session clears the fixture and recorded data; save anything needed first. Exit closes the app. Learn can be restarted manually at any time, including after disabling its startup prompt.", "Practice only opens a control page. It never resets the fixture or runs a command. Tutorial navigation and startup preferences are separate from laboratory state, calibration, and reports.", "read", "Read the reset and exit behavior; no reset is required to finish this tour.", "session", "new"),
		_step("finish", "FINISH", "Continue practicing independently", "You have reviewed preparation, measurement, correction, diagnostics, recovery, and traceability. Choose Finish to complete the tour. Reopen Learn for a refresher, or enable Show at Startup again in its settings.", "Completion records this tour, including any skipped lessons. It does not certify laboratory competence, scientific accuracy, real equipment safety, or headset performance. Physical acceptance remains a separate test.", "read", "Choose Finish; no laboratory state will change.", "session", "")
	]

func _step(id: String, chapter: String, title: String, body: String, theory: String, gate: String, gatehint: String, practice_tab: String, target: String) -> Dictionary:
	return {"id": id, "chapter": chapter, "title": title, "body": body, "theory": theory, "gate": gate, "gatehint": gatehint, "practice_tab": practice_tab, "target": target}
