class_name LabTutorial
extends RefCounted
## Read-only rotor-balancing work instructions. Actions operate the lab; this
## controller observes their real outcomes and advances one instruction at a time.

const SUCCESS_DWELL_S: float = 1.5
const MAX_BUFFERED_OUTCOMES: int = 128
var active: bool = false
var index: int = 0
var startup_enabled: bool = true
var completed: bool = false
var preferences_path: String = "user://tutorial.cfg"
var settings_error: String = ""
var steps: Array = []
var _work_index: int = 0
var _serial: int = 0
var _entry: Dictionary = {}
var _previous: Dictionary = {}
var _cached_snapshot: Dictionary = {}
var _completion_snapshot: Dictionary = {}
var _completion_serial: int = 0
var _events: Dictionary = {}
var _proof: Dictionary = {}
var _ready: bool = false
var _remaining: float = 0.0
var _pending: Array = []
var _seen_event_ids: Dictionary = {}
var _observed_max_record: int = 0
var _last_signature: String = ""

func _init(settings_path: String = "user://tutorial.cfg") -> void:
	steps = _make_steps()
	load_settings(settings_path)

func start(snapshot: Dictionary) -> void:
	active = true
	index = 0
	_work_index = 0
	_serial = 0
	_pending.clear()
	_seen_event_ids.clear()
	_cached_snapshot = snapshot
	_observed_max_record = _max_record_id(snapshot)
	_last_signature = _signature(snapshot)
	_enter_step(0, snapshot, 0)

func should_autostart() -> bool:
	return startup_enabled

func set_startup(enabled: bool) -> Dictionary:
	if enabled == startup_enabled:
		return {"ok": true, "message": "Startup guide setting unchanged."}
	startup_enabled = enabled
	return save_settings(preferences_path)

func load_settings(path: String) -> Dictionary:
	preferences_path = path
	startup_enabled = true
	completed = false
	settings_error = ""
	if path.is_empty():
		return {"ok": true, "message": "Guide preferences use memory only."}
	var config := ConfigFile.new()
	var result: Error = config.load(path)
	if result == ERR_FILE_NOT_FOUND:
		return {"ok": true, "message": "Default guide preferences loaded."}
	if result != OK:
		settings_error = "Could not load tutorial settings: %s" % error_string(result)
		return {"ok": false, "message": settings_error}
	var startup_value: Variant = config.get_value("tutorial", "startup_enabled", true)
	var completed_value: Variant = config.get_value("tutorial", "completed", false)
	startup_enabled = startup_value if typeof(startup_value) == TYPE_BOOL else true
	completed = completed_value if typeof(completed_value) == TYPE_BOOL else false
	return {"ok": true, "message": "Guide preferences loaded."}

func save_settings(path: String) -> Dictionary:
	preferences_path = path
	settings_error = ""
	if path.is_empty():
		return {"ok": true, "message": "Guide preferences updated in memory."}
	var config := ConfigFile.new()
	config.set_value("tutorial", "schema", 2)
	config.set_value("tutorial", "startup_enabled", startup_enabled)
	config.set_value("tutorial", "completed", completed)
	var result: Error = config.save(path)
	if result != OK:
		settings_error = "Could not save tutorial settings: %s" % error_string(result)
		return {"ok": false, "message": settings_error}
	return {"ok": true, "message": "Guide preferences saved."}

func observe(snapshot: Dictionary, event: Dictionary = {}) -> void:
	_cached_snapshot = snapshot
	if not active:
		return
	_serial += 1
	var accepted: bool = _accepted_event(event)
	var command: String = str(event.get("command", event.get("target", "")))
	var current_max: int = _max_record_id(snapshot)
	if (accepted and command == "new") or current_max < _observed_max_record:
		# New Session changes guide position only after the lab actually reset.
		# Rejected resets and previous-session record IDs cannot supply evidence.
		_pending.clear()
		_seen_event_ids.clear()
		_observed_max_record = current_max
		_last_signature = _signature(snapshot)
		_enter_step(0, snapshot, _serial)
		return
	_observed_max_record = current_max
	if index != _work_index:
		return
	var actual_event: Dictionary = event
	if event.has("event_id"):
		var event_id: String = str(event.event_id)
		if _seen_event_ids.has(event_id):
			actual_event = {}
		else:
			_seen_event_ids[event_id] = true
	var signature: String = _signature(snapshot)
	if actual_event.is_empty() and signature == _last_signature:
		return
	_last_signature = signature
	var row: Dictionary = {"snapshot": snapshot.duplicate(true), "event": actual_event.duplicate(true), "serial": _serial}
	if _ready:
		# Buffer only material changes or actual action events AFTER completion.
		# Replaying their original order preserves fast legitimate next actions.
		_pending.append(row)
		if _pending.size() > MAX_BUFFERED_OUTCOMES:
			_pending.pop_front()
	else:
		_consume(row)

func tick(delta: float, snapshot: Dictionary) -> Dictionary:
	observe(snapshot)
	var result: Dictionary = {"advanced": false, "finished": false, "message": ""}
	if not active or index != _work_index or not _ready:
		return result
	if not _proof_still_valid(snapshot):
		_ready = false
		_remaining = 0.0
		_proof.clear()
		_pending.clear()
		return result
	if delta > 0.0 and is_finite(delta):
		_remaining = maxf(0.0, _remaining - minf(delta, 0.1))
	if _remaining <= 0.0:
		return _advance(snapshot, true)
	return result

func view(snapshot: Dictionary) -> Dictionary:
	# Pure presentation: rendering must never consume actions or move the guide.
	var step: Dictionary = steps[clampi(index, 0, steps.size() - 1)]
	var reviewing: bool = index < _work_index
	var ready: bool = reviewing or (_ready and _proof_still_valid(snapshot))
	var hint: String = str(step.gatehint)
	if reviewing:
		hint = "Review only. A returns forward; automatic work guidance resumes afterward."
	elif ready:
		hint = "Complete. Next instruction appears automatically in %.1f s." % _remaining
	elif not _healthy(snapshot):
		hint = "Clear the fault or E-stop and rehome before continuing. No run restarts automatically."
	elif str(snapshot.get("mode", "single")) != "single":
		hint = "This procedure uses SINGLE mode. At zero speed, press physical MODE to select it."
	elif step.id == "load" and bool(snapshot.get("mounted", false)):
		hint = "Rotor already seated; confirming configuration before a fresh HOME action."
	var result: Dictionary = step.duplicate(true)
	result.merge({"active": active, "index": index, "total": steps.size(), "step_index": index + 1, "step_count": steps.size(),
		"progress": "Instruction %d / %d" % [index + 1, steps.size()], "progress_fraction": float(index) / float(steps.size()),
		"ready": ready, "success": ready and not reviewing, "success_remaining_s": _remaining,
		"automatic": not reviewing, "reviewing": reviewing, "review": reviewing, "hint": hint, "what": step.body, "why": step.theory,
		"startup_enabled": startup_enabled, "completed": completed, "complete": completed,
		"can_back": active and index > 0, "can_skip": active, "is_last": index == steps.size() - 1,
		"can_finish": active and ready and index == steps.size() - 1, "settings_error": settings_error})
	return result

func next(snapshot: Dictionary) -> Dictionary:
	if not active:
		return {"ok": false, "message": "Start the work guide first.", "finished": false}
	if index < _work_index:
		index += 1
		return {"ok": true, "message": "Forward through review.", "finished": false}
	observe(snapshot)
	if not _ready or not _proof_still_valid(snapshot):
		return {"ok": false, "message": view(snapshot).hint, "finished": false}
	var result: Dictionary = _advance(snapshot, false)
	result["ok"] = true
	return result

func back() -> Dictionary:
	if not active or index <= 0:
		return {"ok": false, "message": "This is the first work instruction.", "finished": false}
	index -= 1
	return {"ok": true, "message": "Reviewing an earlier instruction; A returns forward.", "finished": false}

func skip_step() -> Dictionary:
	if not active:
		return {"ok": false, "message": "Start the work guide first.", "finished": false}
	if index < _work_index:
		return next(_cached_snapshot)
	if _work_index == steps.size() - 1:
		skip()
		return {"ok": true, "message": "Guide closed without claiming a saved report.", "finished": true, "skipped": true}
	_pending.clear()
	_enter_step(_work_index + 1, _cached_snapshot, _serial)
	return {"ok": true, "message": "Instruction explicitly skipped.", "finished": false, "skipped": true}

func skip() -> void:
	active = false

func _advance(snapshot: Dictionary, automatic: bool) -> Dictionary:
	if _work_index == steps.size() - 1:
		active = false
		completed = true
		startup_enabled = false
		var saved: Dictionary = save_settings(preferences_path)
		return {"advanced": true, "finished": true, "message": "Balancing work guide complete; measurements remain saved." if saved.ok else saved.message}
	var reference: Dictionary = _completion_snapshot
	var reference_serial: int = _completion_serial
	var buffered: Array = _pending
	_pending = []
	_enter_step(_work_index + 1, reference, reference_serial)
	for row in buffered:
		if _ready:
			_pending.append(row)
		else:
			_consume(row)
	# Catch no actions from the live snapshot here. Only the ordered buffer or
	# future observations may satisfy the new stage, never old compatible data.
	return {"advanced": true, "finished": false, "message": "Next work instruction." if automatic else "Continuing now."}

func _enter_step(new_index: int, snapshot: Dictionary, serial: int) -> void:
	index = new_index
	_work_index = new_index
	_entry = {"snapshot": snapshot.duplicate(true), "record_id": _max_record_id(snapshot), "serial": serial}
	_previous = snapshot.duplicate(true)
	_events.clear()
	_proof.clear()
	_ready = false
	_remaining = 0.0
	# Load and guard stages confirm present mechanical prerequisites. They do
	# not claim that preexisting captures or a previous HOME were performed now.
	if str(steps[_work_index].gate) in ["load", "closed_guard", "open_guard"]:
		_consume({"snapshot": snapshot.duplicate(true), "event": {}, "serial": serial})

func _consume(row: Dictionary) -> void:
	var snapshot: Dictionary = row.snapshot
	var event: Dictionary = row.event
	if _accepted_event(event):
		var command: String = str(event.get("command", event.get("target", "")))
		_events[command] = int(row.serial)
	var gate: String = str(steps[_work_index].gate)
	var correct: bool = false
	if _healthy(snapshot) and str(snapshot.get("mode", "single")) == "single":
		match gate:
			"load": correct = bool(snapshot.get("mounted", false)) and _at_zero(snapshot)
			"home": correct = bool(snapshot.get("mounted", false)) and bool(snapshot.get("homed", false)) and _at_zero(snapshot) and (_events.has("home") or (not bool(_previous.get("homed", false)) and bool(snapshot.get("homed", false))))
			"closed_guard": correct = bool(snapshot.get("guard_closed", false)) and bool(snapshot.get("homed", false)) and bool(snapshot.get("grab_owners_empty", true)) and _at_zero(snapshot)
			"open_guard": correct = not bool(snapshot.get("guard_closed", true)) and _at_zero(snapshot)
			"baseline": correct = _new_capture(snapshot.get("baseline", {}), "baseline") and _at_zero(snapshot)
			"trial_fit": correct = _events.has("fit_trial") and _trial_installed(snapshot) and not bool(snapshot.get("guard_closed", true)) and _at_zero(snapshot)
			"trial_a": correct = _new_capture(snapshot.get("trial_a", {}), "trial_a") and _at_zero(snapshot)
			"solve": correct = _events.has("solve") and _solution_valid(snapshot) and _at_zero(snapshot)
			"apply": correct = _events.has("apply") and _solution_installed(snapshot) and not bool(snapshot.get("guard_closed", true)) and _at_zero(snapshot)
			"verify": correct = _new_capture(snapshot.get("latest", {}), "verify") and _solution_installed(snapshot) and not bool(snapshot.get("latest", {}).get("configuration_changed", false)) and _at_zero(snapshot)
			"repeat": correct = _new_capture(snapshot.get("latest", {}), "repeat") and int(snapshot.get("latest", {}).get("repeatability", {}).get("n", 0)) >= 3 and _solution_installed(snapshot) and not bool(snapshot.get("latest", {}).get("configuration_changed", false)) and _at_zero(snapshot)
			"save": correct = _events.has("save") and bool(snapshot.get("saved_report", false)) and _at_zero(snapshot)
	_previous = snapshot.duplicate(true)
	if correct:
		_ready = true
		_remaining = SUCCESS_DWELL_S
		_completion_snapshot = snapshot.duplicate(true)
		_completion_serial = int(row.serial)
		_proof = {"gate": gate, "record_id": _max_record_id(snapshot), "baseline_id": int(snapshot.get("baseline", {}).get("id", 0))}

func _proof_still_valid(snapshot: Dictionary) -> bool:
	if not _ready or not _healthy(snapshot) or str(snapshot.get("mode", "single")) != "single":
		return false
	var gate: String = str(_proof.get("gate", ""))
	match gate:
		"load": return bool(snapshot.get("mounted", false))
		"home": return bool(snapshot.get("mounted", false)) and bool(snapshot.get("homed", false))
		"baseline": return _new_capture(snapshot.get("baseline", {}), "baseline")
		"trial_fit": return _trial_installed(snapshot)
		"trial_a": return _new_capture(snapshot.get("trial_a", {}), "trial_a")
		"solve": return _solution_valid(snapshot)
		"apply": return _solution_installed(snapshot)
		"verify": return _solution_installed(snapshot) and not bool(snapshot.get("latest", {}).get("configuration_changed", false))
		"repeat": return _solution_installed(snapshot) and not bool(snapshot.get("latest", {}).get("configuration_changed", false))
		"save": return bool(snapshot.get("saved_report", false))
	return true

func _accepted_event(event: Dictionary) -> bool:
	return typeof(event.get("ok", false)) == TYPE_BOOL and event.get("ok", false)

func _at_zero(snapshot: Dictionary) -> bool:
	return not bool(snapshot.get("running", false)) and not bool(snapshot.get("processing", false)) and float(snapshot.get("rpm", 0.0)) < 0.1

func _healthy(snapshot: Dictionary) -> bool:
	return not bool(snapshot.get("estop", false)) and str(snapshot.get("fault", "")).is_empty()

func _new_capture(record: Variant, kind: String) -> bool:
	return record is Dictionary and not record.is_empty() and typeof(record.get("accepted", false)) == TYPE_BOOL and record.get("accepted", false) and str(record.get("kind", "")) == kind and int(record.get("id", 0)) > int(_entry.get("record_id", 0))

func _max_record_id(snapshot: Dictionary) -> int:
	var highest: int = int(snapshot.get("latest", {}).get("id", 0))
	for record in snapshot.get("records", []):
		highest = maxi(highest, int(record.get("id", 0)))
	return highest

func _mass_vector(config: Dictionary, plane: int) -> Vector2:
	var masses: Array = config.get("masses", config.get("masses_g", [0.0, 0.0]))
	var angles: Array = config.get("angles", config.get("angles_deg", [0.0, 0.0]))
	if masses.size() <= plane or angles.size() <= plane:
		return Vector2.ZERO
	return Vector2(cos(deg_to_rad(float(angles[plane]))), sin(deg_to_rad(float(angles[plane])))) * float(masses[plane]) * float(config.get("radius_mm", 30.0))

func _trial_installed(snapshot: Dictionary) -> bool:
	var baseline: Dictionary = snapshot.get("baseline", {})
	if baseline.is_empty() or not bool(baseline.get("accepted", false)):
		return false
	return (_mass_vector(snapshot, 0) - _mass_vector(baseline, 0)).length() >= 0.15 and (_mass_vector(snapshot, 1) - _mass_vector(baseline, 1)).length() < 0.001

func _solution_valid(snapshot: Dictionary) -> bool:
	var solution: Dictionary = snapshot.get("solution", {})
	var condition: float = float(solution.get("condition_number", INF))
	return not solution.is_empty() and is_finite(condition) and condition >= 1.0 and condition <= 30.0

func _solution_installed(snapshot: Dictionary) -> bool:
	if not _solution_valid(snapshot):
		return false
	var solution: Dictionary = snapshot.solution
	return solution.has("masses_g") and solution.has("angles_deg") and (_mass_vector(snapshot, 0) - _mass_vector(solution, 0)).length() < 0.01 and (_mass_vector(snapshot, 1) - _mass_vector(solution, 1)).length() < 0.01

func _signature(snapshot: Dictionary) -> String:
	var solution: Dictionary = snapshot.get("solution", {})
	return JSON.stringify([snapshot.get("mounted", false), snapshot.get("homed", false), snapshot.get("guard_closed", false), snapshot.get("estop", false), snapshot.get("fault", ""), snapshot.get("mode", "single"), snapshot.get("running", false), snapshot.get("processing", false), _at_zero(snapshot), snapshot.get("grab_owners_empty", true), snapshot.get("sensor_position_mm", 6.0), snapshot.get("test_rpm", 1200), snapshot.get("masses", []), snapshot.get("angles", []), _max_record_id(snapshot), snapshot.get("baseline", {}).get("id", 0), snapshot.get("trial_a", {}).get("id", 0), solution.get("masses_g", []), solution.get("angles_deg", []), solution.get("condition_number", 0), snapshot.get("latest", {}).get("configuration_changed", false), snapshot.get("saved_report", false)])

func _make_steps() -> Array:
	return [
		_step("load", "PREPARE", "Seat the rotor upright", "Begin a single-plane balance. Grip the tray rotor, carry it upright over the spindle, and release to seat it. An already seated rotor is confirmed without removing it.", "Unbalance U = mass × radius creates rotating force F = Uω². This procedure measures its response, identifies sensitivity, installs a correction, and tests it with new data.", "load", "Seat the rotor upright and centered on the spindle.", "rotor"),
		_step("home", "PREPARE", "Press HOME on the station", "At zero speed, press the physical HOME cap with the rotor loaded. Confirm the probe reads 6.00 mm. Perform a fresh HOME action even if an old reference is displayed.", "Referencing fixes probe geometry before calibration. Home, probe motion, speed/mode changes, and a new baseline discard calibration. The synthetic operating standoff is 4–8 mm.", "home", "Press physical HOME now; an earlier reference does not count.", "home"),
		_step("guard", "PREPARE", "Latch the enclosure", "Grip the orange guard handle, lower it fully, and release. Confirm CLOSED and release every fixture handle. An already closed guard is checked in its present position.", "A closed interlock and released handles are separate start conditions. Lifting opens the interlock. This simulated enclosure does not certify real machinery containment.", "closed_guard", "Lower and release the orange guard handle; confirm CLOSED.", "guard"),
		_step("baseline", "MEASURE", "Press BASELINE and wait for zero", "Press the station BASELINE cap. Keep the guard closed through capture and coast. STOP aborts capture; interrupted data do not count. Wait until the spindle reads zero.", "Baseline V0 stores both tach phasors and the installed masses. Amplitude is micrometres peak; sinusoidal RMS = peak/√2. Support phase is not simply the heavy-spot angle.", "baseline", "Complete a NEW BASELINE capture, analysis, and coast to zero.", "baseline"),
		_step("open_trial", "TRIAL", "Open the guard for the known trial", "At zero speed, grip the orange handle and lift the guard. Leave the baseline configuration unchanged until the known trial is installed.", "Trial and baseline must share speed, radius, sensor setup, and support dynamics. Changing those would make their response difference an invalid sensitivity measurement.", "open_guard", "Lift the orange guard handle at zero speed.", "guard"),
		_step("trial_fit", "TRIAL", "Press FIT TRIAL for plane A", "With guard open, select plane A and press FIT TRIAL on the station. The helper adds a known 0.250 g vector relative to baseline and restores the other plane to baseline.", "The known trial Ut measures how mass-radius unbalance affects vibration. Independent calibration changes only one plane; changing both would mix their effects.", "trial_fit", "Press physical FIT TRIAL on plane A with the guard open.", "fit_trial"),
		_step("close_trial", "TRIAL", "Latch the guard for Trial A", "Lower the orange handle fully, release grip, and confirm CLOSED. Keep the trial mass installed for its measurement.", "A guard is a prerequisite, not a measurement. The next capture must observe the known trial at exactly the baseline setup and speed.", "closed_guard", "Lower and release the guard; keep the trial installed.", "guard"),
		_step("trial_measure", "MEASURE", "Press MEASURE TRIAL A", "Press MEASURE TRIAL A on the station. Wait for capture, analysis, and coast to zero. A previous trial result cannot replace this new measurement.", "Vt − V0 isolates the known trial's complex response. The tach least-squares fit separates DC, 1×, and 2× from 1,024 samples at 1,024 Hz; DFT leakage can change spectrum-bin height.", "trial_a", "Complete a NEW MEASURE TRIAL A capture and coast to zero.", "trial_a"),
		_step("solve", "IDENTIFY", "Press SOLVE and inspect the correction", "At zero speed, press SOLVE on the station. Read the calculated correction mass, angle, and matrix condition. Rejected or insensitive trial data must be measured again.", "α = (Vt − V0)/Ut and C = −V0/α. Complex division accounts for sensor/support phase. The solver uses measured data, not a hidden heavy spot; poor conditioning amplifies error.", "solve", "Press physical SOLVE after the new baseline and Trial A.", "solve"),
		_step("open_apply", "CORRECT", "Open the guard for correction", "At zero speed, lift the orange guard handle. Leave the calculated solution available; do not change probe geometry or speed.", "Correction must use the same calibrated setup. A changed support or sensor response can invalidate the influence coefficient even when a displayed mass still looks plausible.", "open_guard", "Lift the guard at zero speed before fitting the correction.", "guard"),
		_step("apply", "CORRECT", "Press APPLY CORRECTION", "Press APPLY CORRECTION on the station with guard open. This removes the trial configuration and installs the calculated TOTAL masses, including any baseline masses.", "C is added to the baseline mass vector. It is not added again to a temporary trial mass. An installed prediction still needs a fresh verification measurement.", "apply", "Press physical APPLY CORRECTION with guard open.", "apply"),
		_step("close_verify", "VERIFY", "Latch the guard for verification", "Lower the guard fully and release the handle. Keep the calculated correction installed and confirm CLOSED before measuring.", "Single-plane correction targets sensor A at one speed. Sensor B can retain vibration. Only a new measurement can test the installed prediction.", "closed_guard", "Latch and release the guard with the correction installed.", "guard"),
		_step("verify", "VERIFY", "Press VERIFY and inspect reduction", "Press VERIFY on the station. Wait through analysis and coast to zero, then inspect measured reduction. A low reduction is a result to diagnose and retry, not an invented pass.", "Fresh verification tests the actual installed correction. Old results or edited configurations do not count. Near zero amplitude, tach phase becomes unobservable rather than a useful direction.", "verify", "Complete NEW VERIFY with the calculated masses installed; wait for zero.", "verify"),
		_step("repeat", "CONFIRM", "Press REPEAT with unchanged setup", "Press REPEAT on the station. Wait for all three windows and coast. Read n = 3, mean amplitude, sample standard deviation s, and Type A standard error of the mean.", "s describes repeat scatter; SEM = s/√n describes the mean under independent repeats. These synthetic windows omit calibration bias and do not establish total uncertainty.", "repeat", "Complete a NEW three-window REPEAT result and coast to zero.", "repeat"),
		_step("report", "RECORD", "Press SAVE REPORT to preserve evidence", "Press SAVE REPORT on the station and confirm its saved path. This ends the guided procedure automatically after the success message; laboratory data remain available.", "Traceability links setup, captures, solutions, events, and limits. Guide completion can include skipped instructions; it does not certify competence or equipment safety.", "save", "Press physical SAVE REPORT now and confirm successful file output.", "save")
	]

func _step(id: String, chapter: String, title: String, body: String, theory: String, gate: String, gatehint: String, target: String) -> Dictionary:
	return {"id": id, "chapter": chapter, "title": title, "body": body, "theory": theory, "gate": gate, "gatehint": gatehint, "target": target, "practice_tab": "balance"}
