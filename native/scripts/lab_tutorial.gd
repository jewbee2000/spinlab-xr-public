class_name LabTutorial
extends RefCounted
## Read-only rotor-balancing work instructions. Actions operate the lab; this
## controller observes their real outcomes and advances one instruction at a time.

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
	if _needs_recalibration(snapshot, event):
		# Revisit the experiment at its first invalidated dependency. Scientific
		# records remain in the instrument; only transient guide proof is reset.
		_pending.clear()
		_seen_event_ids.clear()
		_last_signature = _signature(snapshot)
		_enter_step(_step_index("baseline"), snapshot, _serial)
		return
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

func _step_index(step_id: String) -> int:
	for step_index in range(steps.size()):
		if str(steps[step_index].id) == step_id: return step_index
	return -1

func _calibration_matches(snapshot: Dictionary) -> bool:
	var baseline: Dictionary = snapshot.get("baseline", {})
	if baseline.is_empty() or not bool(baseline.get("accepted", false)): return false
	return str(baseline.get("mode", snapshot.get("mode", "single"))) == str(snapshot.get("mode", "single")) and absf(float(baseline.get("sensor_position_mm", snapshot.get("sensor_position_mm", 6.0))) - float(snapshot.get("sensor_position_mm", 6.0))) < 0.01 and absf(float(baseline.get("radius_mm", snapshot.get("radius_mm", 30.0))) - float(snapshot.get("radius_mm", 30.0))) < 0.01 and absf(float(baseline.get("rpm", snapshot.get("test_rpm", 1200.0))) - float(snapshot.get("test_rpm", 1200.0))) <= maxf(2.0, float(snapshot.get("test_rpm", 1200.0)) * 0.01)

func _needs_recalibration(snapshot: Dictionary, event: Dictionary) -> bool:
	if _work_index <= _step_index("baseline") or _calibration_matches(snapshot): return false
	var had_calibration: bool = _calibration_matches(_previous) or _calibration_matches(_entry.get("snapshot", {}))
	if not had_calibration: return false
	if not event.is_empty():
		if not _accepted_event(event): return false
		return str(event.get("command", event.get("target", ""))) in ["baseline", "home", "mode", "speed", "dial:probe", "estop", "recover", "fault_sensor", "fault_tach"]
	# Internal interlocks can invalidate calibration without a user command.
	# Observe the actual changed instrument state, never elapsed time or UI.
	return str(snapshot.get("fault", "")) != str(_previous.get("fault", "")) or bool(snapshot.get("estop", false)) != bool(_previous.get("estop", false)) or str(snapshot.get("mode", "single")) != str(_previous.get("mode", "single")) or not is_equal_approx(float(snapshot.get("sensor_position_mm", 6.0)), float(_previous.get("sensor_position_mm", 6.0))) or not is_equal_approx(float(snapshot.get("test_rpm", 1200.0)), float(_previous.get("test_rpm", 1200.0))) or (not _previous.get("baseline", {}).is_empty() and snapshot.get("baseline", {}).is_empty())

func tick(_delta: float, snapshot: Dictionary) -> Dictionary:
	observe(snapshot)
	var result: Dictionary = {"advanced": false, "finished": false, "message": ""}
	if not active or index != _work_index or not _ready:
		return result
	if not _proof_still_valid(snapshot):
		_ready = false
		_proof.clear()
		_pending.clear()
		return result
	# Task completion, not speech or a timer, controls the transition.
	return _advance(snapshot, true)

func view(snapshot: Dictionary) -> Dictionary:
	# Pure presentation: rendering must never consume actions or move the guide.
	var step: Dictionary = steps[clampi(index, 0, steps.size() - 1)]
	var reviewing: bool = index < _work_index
	var ready: bool = reviewing or (_ready and _proof_still_valid(snapshot))
	var hint: String = str(step.gatehint)
	if reviewing:
		hint = "Review only. A returns forward; automatic work guidance resumes afterward."
	elif ready:
		hint = "Complete. The next task appears immediately."
	elif not _step_healthy(snapshot):
		hint = "Clear the fault or E-stop and rehome before continuing. No run restarts automatically."
	elif not _mode_matches(snapshot):
		hint = "At zero speed, use physical MODE to select TWO-PLANE for this experiment."
	elif step.id == "load" and bool(snapshot.get("mounted", false)):
		hint = "Rotor already seated; confirming configuration before a fresh HOME action."
	var result: Dictionary = step.duplicate(true)
	result.merge({"active": active, "index": index, "total": steps.size(), "step_index": index + 1, "step_count": steps.size(),
		"progress": "Instruction %d / %d" % [index + 1, steps.size()], "progress_fraction": float(index) / float(steps.size()),
		"ready": ready, "success": ready and not reviewing, "success_remaining_s": 0.0,
		"automatic": not reviewing, "reviewing": reviewing, "review": reviewing, "hint": hint, "what": step.body, "why": step.theory,
		"startup_enabled": startup_enabled, "completed": completed, "complete": completed,
		"can_back": active and index > 0, "can_skip": active, "is_last": index == steps.size() - 1,
		"can_finish": active and ready and index == steps.size() - 1, "settings_error": settings_error})
	# Recovery prompts explain the real prerequisite without moving the work
	# checkpoint or manufacturing the original task's accepted evidence.
	var prerequisite: Dictionary = _prerequisite(snapshot, ready, reviewing)
	result["prompt_id"] = str(prerequisite.get("id", step.id))
	result["voice_id"] = result.prompt_id
	result["prerequisite"] = not prerequisite.is_empty()
	if not prerequisite.is_empty(): result["target"] = prerequisite.target
	return result

func _prerequisite(snapshot: Dictionary, ready: bool, reviewing: bool) -> Dictionary:
	if not active or ready or reviewing: return {}
	var gate: String = str(steps[_work_index].gate)
	if not str(snapshot.get("fault", "")).is_empty() or (bool(snapshot.get("estop", false)) and gate != "estop"):
		return {"id": "recover", "target": "recover"}
	if gate != "load" and not bool(snapshot.get("mounted", false)):
		return {"id": "load", "target": "rotor"}
	if not _at_zero(snapshot) and gate not in ["baseline", "trial_a", "trial_b", "verify", "repeat", "sweep", "preview_start", "stop"]:
		return {"id": "stop", "target": "stop"}
	if gate not in ["load", "home", "recover", "estop", "preview_start", "stop"] and bool(snapshot.get("mounted", false)) and (not bool(snapshot.get("homed", false)) or float(snapshot.get("sensor_position_mm", 6.0)) < 4.0 or float(snapshot.get("sensor_position_mm", 6.0)) > 8.0):
		return {"id": "rehome", "target": "home"}
	if not _mode_matches(snapshot):
		return {"id": "mode_two", "target": "mode"}
	if gate in ["mass_change", "angle_change", "mass_clear", "trial_fit", "trial_fit_b", "apply"] and bool(snapshot.get("guard_closed", false)):
		return {"id": "open_setup", "target": "guard"}
	if gate in ["mass_change", "angle_change", "mass_clear", "trial_fit"] and int(snapshot.get("active_plane", 0)) != 0:
		return {"id": "plane_a", "target": "plane"}
	if gate == "trial_fit_b" and int(snapshot.get("active_plane", 0)) != 1:
		return {"id": "plane_b_trial", "target": "plane"}
	if gate == "angle_change" and _mass(snapshot, 0) < 0.049:
		return {"id": "mass_practice", "target": "dial:mass"}
	if gate in ["trial_a", "trial_b"]:
		var plane: int = 0 if gate == "trial_a" else 1
		if not _trial_installed(snapshot, plane):
			if not _at_zero(snapshot): return {"id": "stop", "target": "stop"}
			if bool(snapshot.get("guard_closed", false)): return {"id": "open_setup", "target": "guard"}
			if int(snapshot.get("active_plane", 0)) != plane: return {"id": "plane_a" if plane == 0 else "plane_b_trial", "target": "plane"}
			return {"id": "trial_fit" if plane == 0 else "trial_fit_b", "target": "fit_trial"}
	if gate in ["sweep", "verify", "repeat"] and _solution_valid(snapshot) and not _solution_installed(snapshot):
		if not _at_zero(snapshot): return {"id": "stop", "target": "stop"}
		if bool(snapshot.get("guard_closed", false)): return {"id": "open_setup", "target": "guard"}
		return {"id": "apply", "target": "apply"}
	if gate in ["baseline", "trial_a", "trial_b", "verify", "repeat", "sweep", "preview_start"] and not bool(snapshot.get("guard_closed", false)):
		return {"id": "guard", "target": "guard"}
	return {}

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
	if _step_healthy(snapshot) and _mode_matches(snapshot):
		match gate:
			"load": correct = bool(snapshot.get("mounted", false)) and _at_zero(snapshot)
			"probe_change": correct = _events.has("dial:probe") and absf(float(snapshot.get("sensor_position_mm", 6.0)) - float(_entry.snapshot.get("sensor_position_mm", 6.0))) >= 0.095 and float(snapshot.get("sensor_position_mm", 6.0)) >= 4.0 and float(snapshot.get("sensor_position_mm", 6.0)) <= 8.0 and bool(snapshot.get("grab_owners_empty", true)) and _at_zero(snapshot)
			"mass_change": correct = _events.has("dial:mass") and int(snapshot.get("active_plane", 0)) == 0 and absf(_mass(snapshot, 0) - _mass(_entry.snapshot, 0)) >= 0.049 and _mass(snapshot, 0) >= 0.049 and not bool(snapshot.get("guard_closed", true)) and bool(snapshot.get("grab_owners_empty", true)) and _at_zero(snapshot)
			"angle_change": correct = _events.has("dial:angle") and int(snapshot.get("active_plane", 0)) == 0 and absf(wrapf(_angle(snapshot, 0) - _angle(_entry.snapshot, 0), -180.0, 180.0)) >= 19.9 and _mass(snapshot, 0) >= 0.049 and not bool(snapshot.get("guard_closed", true)) and bool(snapshot.get("grab_owners_empty", true)) and _at_zero(snapshot)
			"mass_clear": correct = _events.has("dial:mass") and _mass(snapshot, 0) <= 0.005 and not bool(snapshot.get("guard_closed", true)) and bool(snapshot.get("grab_owners_empty", true)) and _at_zero(snapshot)
			"mode_two": correct = _events.has("mode") and str(snapshot.get("mode", "single")) == "two_plane" and _at_zero(snapshot)
			"plane_a": correct = _events.has("plane") and int(snapshot.get("active_plane", 0)) == 0 and _at_zero(snapshot)
			"plane_b": correct = _events.has("plane") and int(snapshot.get("active_plane", 0)) == 1 and _at_zero(snapshot)
			"speed_change": correct = _events.has("speed") and not is_equal_approx(float(snapshot.get("test_rpm", 1200.0)), float(_entry.snapshot.get("test_rpm", 1200.0))) and _at_zero(snapshot)
			"speed_restore": correct = _events.has("speed") and is_equal_approx(float(snapshot.get("test_rpm", 0.0)), 1200.0) and _at_zero(snapshot)
			"preview_start": correct = _events.has("sweep") and bool(snapshot.get("running", false))
			"stop": correct = _events.has("stop") and _at_zero(snapshot)
			"estop": correct = _events.has("estop") and bool(snapshot.get("estop", false)) and _at_zero(snapshot)
			"recover": correct = _events.has("recover") and _healthy(snapshot) and _at_zero(snapshot)
			"chart_order": correct = _events.has("chart") and str(snapshot.get("chart_kind", "")) == "order" and int(snapshot.get("spectrum_count", 0)) > 0 and not snapshot.get("baseline", {}).is_empty() and _at_zero(snapshot)
			"sweep": correct = _new_capture(snapshot.get("latest", {}), "sweep") and _solution_installed(snapshot) and _solution_config_installed(snapshot.get("latest", {}), snapshot.get("solution", {})) and int(snapshot.get("sweep_count", snapshot.get("latest", {}).get("points", []).size())) >= 3 and _at_zero(snapshot)
			"home": correct = bool(snapshot.get("mounted", false)) and bool(snapshot.get("homed", false)) and absf(float(snapshot.get("sensor_position_mm", 0.0)) - 6.0) <= 0.005 and _at_zero(snapshot) and (_events.has("home") or (not bool(_previous.get("homed", false)) and bool(snapshot.get("homed", false))))
			"closed_guard": correct = bool(snapshot.get("guard_closed", false)) and bool(snapshot.get("homed", false)) and bool(snapshot.get("grab_owners_empty", true)) and _at_zero(snapshot)
			"open_guard": correct = not bool(snapshot.get("guard_closed", true)) and bool(snapshot.get("grab_owners_empty", true)) and _at_zero(snapshot)
			"baseline": correct = _new_capture(snapshot.get("baseline", {}), "baseline") and _at_zero(snapshot)
			"trial_fit": correct = _events.has("fit_trial") and int(snapshot.get("active_plane", 0)) == 0 and _trial_installed(snapshot, 0) and not bool(snapshot.get("guard_closed", true)) and _at_zero(snapshot)
			"trial_fit_b": correct = _events.has("fit_trial") and int(snapshot.get("active_plane", 0)) == 1 and _trial_installed(snapshot, 1) and not bool(snapshot.get("guard_closed", true)) and _at_zero(snapshot)
			"trial_b": correct = _new_capture(snapshot.get("trial_b", {}), "trial_b") and _trial_installed(snapshot, 1) and _trial_capture_valid(snapshot, 1) and _at_zero(snapshot)
			"trial_a": correct = _new_capture(snapshot.get("trial_a", {}), "trial_a") and _trial_installed(snapshot, 0) and _trial_capture_valid(snapshot, 0) and _at_zero(snapshot)
			"solve": correct = _events.has("solve") and _solution_valid(snapshot) and _at_zero(snapshot)
			"apply": correct = _events.has("apply") and _solution_installed(snapshot) and not bool(snapshot.get("guard_closed", true)) and _at_zero(snapshot)
			"verify": correct = _new_capture(snapshot.get("latest", {}), "verify") and _solution_installed(snapshot) and _solution_config_installed(snapshot.get("latest", {}), snapshot.get("solution", {})) and not bool(snapshot.get("latest", {}).get("configuration_changed", false)) and _at_zero(snapshot)
			"repeat": correct = _new_capture(snapshot.get("latest", {}), "repeat") and int(snapshot.get("latest", {}).get("repeatability", {}).get("n", 0)) >= 3 and _solution_installed(snapshot) and _solution_config_installed(snapshot.get("latest", {}), snapshot.get("solution", {})) and not bool(snapshot.get("latest", {}).get("configuration_changed", false)) and _at_zero(snapshot)
			"save": correct = _events.has("save") and bool(snapshot.get("saved_report", false)) and _at_zero(snapshot)
	_previous = snapshot.duplicate(true)
	if correct:
		_ready = true
		_completion_snapshot = snapshot.duplicate(true)
		_completion_serial = int(row.serial)
		_proof = {"gate": gate, "record_id": _max_record_id(snapshot), "baseline_id": int(snapshot.get("baseline", {}).get("id", 0))}

func _proof_still_valid(snapshot: Dictionary) -> bool:
	if not _ready or not _step_healthy(snapshot) or not _mode_matches(snapshot):
		return false
	var gate: String = str(_proof.get("gate", ""))
	match gate:
		"load": return bool(snapshot.get("mounted", false))
		"home": return bool(snapshot.get("mounted", false)) and bool(snapshot.get("homed", false)) and absf(float(snapshot.get("sensor_position_mm", 0.0)) - 6.0) <= 0.005
		"probe_change": return absf(float(snapshot.get("sensor_position_mm", 6.0)) - float(_entry.snapshot.get("sensor_position_mm", 6.0))) >= 0.095 and float(snapshot.get("sensor_position_mm", 6.0)) >= 4.0 and float(snapshot.get("sensor_position_mm", 6.0)) <= 8.0 and bool(snapshot.get("grab_owners_empty", true))
		"mass_change": return int(snapshot.get("active_plane", 0)) == 0 and absf(_mass(snapshot, 0) - _mass(_entry.snapshot, 0)) >= 0.049 and _mass(snapshot, 0) >= 0.049 and not bool(snapshot.get("guard_closed", true)) and bool(snapshot.get("grab_owners_empty", true))
		"angle_change": return int(snapshot.get("active_plane", 0)) == 0 and absf(wrapf(_angle(snapshot, 0) - _angle(_entry.snapshot, 0), -180.0, 180.0)) >= 19.9 and _mass(snapshot, 0) >= 0.049 and not bool(snapshot.get("guard_closed", true)) and bool(snapshot.get("grab_owners_empty", true))
		"mass_clear": return _mass(snapshot, 0) <= 0.005 and not bool(snapshot.get("guard_closed", true)) and bool(snapshot.get("grab_owners_empty", true))
		"mode_two": return str(snapshot.get("mode", "single")) == "two_plane"
		"plane_a": return int(snapshot.get("active_plane", 0)) == 0
		"plane_b": return int(snapshot.get("active_plane", 0)) == 1
		"speed_change": return not is_equal_approx(float(snapshot.get("test_rpm", 1200.0)), float(_entry.snapshot.get("test_rpm", 1200.0)))
		"speed_restore": return is_equal_approx(float(snapshot.get("test_rpm", 0.0)), 1200.0)
		"chart_order": return str(snapshot.get("chart_kind", "")) == "order" and int(snapshot.get("spectrum_count", 0)) > 0
		"baseline": return _new_capture(snapshot.get("baseline", {}), "baseline")
		"trial_fit": return _trial_installed(snapshot, 0)
		"trial_fit_b": return _trial_installed(snapshot, 1)
		"trial_b": return _new_capture(snapshot.get("trial_b", {}), "trial_b") and _trial_installed(snapshot, 1) and _trial_capture_valid(snapshot, 1)
		"sweep": return _new_capture(snapshot.get("latest", {}), "sweep") and _solution_installed(snapshot) and _solution_config_installed(snapshot.get("latest", {}), snapshot.get("solution", {}))
		"closed_guard": return bool(snapshot.get("guard_closed", false)) and bool(snapshot.get("grab_owners_empty", true)) and _at_zero(snapshot)
		"open_guard": return not bool(snapshot.get("guard_closed", true)) and bool(snapshot.get("grab_owners_empty", true)) and _at_zero(snapshot)
		"estop": return bool(snapshot.get("estop", false)) and _at_zero(snapshot)
		"recover": return _healthy(snapshot) and _at_zero(snapshot)
		"trial_a": return _new_capture(snapshot.get("trial_a", {}), "trial_a") and _trial_installed(snapshot, 0) and _trial_capture_valid(snapshot, 0)
		"solve": return _solution_valid(snapshot)
		"apply": return _solution_installed(snapshot)
		"verify": return _solution_installed(snapshot) and _solution_config_installed(snapshot.get("latest", {}), snapshot.get("solution", {})) and not bool(snapshot.get("latest", {}).get("configuration_changed", false))
		"repeat": return _solution_installed(snapshot) and _solution_config_installed(snapshot.get("latest", {}), snapshot.get("solution", {})) and not bool(snapshot.get("latest", {}).get("configuration_changed", false))
		"save": return bool(snapshot.get("saved_report", false))
	return true

func _accepted_event(event: Dictionary) -> bool:
	return typeof(event.get("ok", false)) == TYPE_BOOL and event.get("ok", false)

func _at_zero(snapshot: Dictionary) -> bool:
	return not bool(snapshot.get("running", false)) and not bool(snapshot.get("processing", false)) and float(snapshot.get("rpm", 0.0)) < 0.1

func _healthy(snapshot: Dictionary) -> bool:
	return not bool(snapshot.get("estop", false)) and str(snapshot.get("fault", "")).is_empty()

func _step_healthy(snapshot: Dictionary) -> bool:
	# The deliberate E-stop exercise observes the latched state itself. Other
	# lessons never treat a fault or an E-stop as successful work.
	if str(steps[_work_index].gate) == "estop":
		return str(snapshot.get("fault", "")).is_empty()
	return _healthy(snapshot)

func _mode_matches(snapshot: Dictionary) -> bool:
	var expected: String = str(steps[_work_index].get("expected_mode", ""))
	return expected.is_empty() or str(snapshot.get("mode", "single")) == expected

func _mass(snapshot: Dictionary, plane: int) -> float:
	return float(snapshot.get("masses", [0.0, 0.0])[plane])

func _angle(snapshot: Dictionary, plane: int) -> float:
	return float(snapshot.get("angles", [0.0, 0.0])[plane])

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

func _trial_installed(snapshot: Dictionary, plane: int = 0) -> bool:
	var baseline: Dictionary = snapshot.get("baseline", {})
	if baseline.is_empty() or not bool(baseline.get("accepted", false)):
		return false
	return _known_trial_configuration(snapshot, baseline, plane)

func _known_trial_configuration(config: Dictionary, baseline: Dictionary, plane: int) -> bool:
	var expected_trial: Vector2 = Vector2(0.250 * float(config.get("radius_mm", 30.0)), 0.0)
	return (_mass_vector(config, plane) - _mass_vector(baseline, plane) - expected_trial).length() < 0.01 and (_mass_vector(config, 1 - plane) - _mass_vector(baseline, 1 - plane)).length() < 0.001

func _trial_capture_valid(snapshot: Dictionary, plane: int) -> bool:
	var record: Dictionary = snapshot.get("trial_a" if plane == 0 else "trial_b", {})
	return not record.is_empty() and _known_trial_configuration(record, snapshot.get("baseline", {}), plane)

func _solution_config_installed(config: Dictionary, solution: Dictionary) -> bool:
	return solution.has("masses_g") and solution.has("angles_deg") and (_mass_vector(config, 0) - _mass_vector(solution, 0)).length() < 0.01 and (_mass_vector(config, 1) - _mass_vector(solution, 1)).length() < 0.01

func _solution_valid(snapshot: Dictionary) -> bool:
	var solution: Dictionary = snapshot.get("solution", {})
	var condition: float = float(solution.get("condition_number", INF))
	return not solution.is_empty() and is_finite(condition) and condition >= 1.0 and condition <= 30.0

func _solution_installed(snapshot: Dictionary) -> bool:
	if not _solution_valid(snapshot):
		return false
	var solution: Dictionary = snapshot.solution
	return _solution_config_installed(snapshot, solution)

func _signature(snapshot: Dictionary) -> String:
	var solution: Dictionary = snapshot.get("solution", {})
	return JSON.stringify([snapshot.get("mounted", false), snapshot.get("homed", false), snapshot.get("guard_closed", false), snapshot.get("estop", false), snapshot.get("fault", ""), snapshot.get("mode", "single"), snapshot.get("running", false), snapshot.get("processing", false), _at_zero(snapshot), snapshot.get("grab_owners_empty", true), snapshot.get("sensor_position_mm", 6.0), snapshot.get("test_rpm", 1200), snapshot.get("masses", []), snapshot.get("angles", []), _max_record_id(snapshot), snapshot.get("baseline", {}).get("id", 0), snapshot.get("trial_a", {}).get("id", 0), snapshot.get("trial_b", {}).get("id", 0), snapshot.get("active_plane", 0), snapshot.get("chart_kind", ""), snapshot.get("spectrum_count", 0), snapshot.get("sweep_count", 0), solution.get("masses_g", []), solution.get("angles_deg", []), solution.get("condition_number", 0), snapshot.get("latest", {}).get("configuration_changed", false), snapshot.get("saved_report", false)])

func _make_steps() -> Array:
	var course: Array = [
		_step("load", "MEET THE ROTOR", "Seat the rotor on the spindle", "Grip the tray rotor, carry it upright over the spindle, and release. Our mission is to make this small spacecraft wheel run smoothly.", "A tiny off-center mass pulls outward once per revolution. That rotating force shakes the supports. We will measure it, add a known trial, calculate a cancelling mass, and verify the result.", "load", "Seat the rotor upright and centered on the spindle.", "rotor"),
		_step("home", "MEET THE ROTOR", "Reference the probe with HOME", "With the rotor seated and stopped, press HOME on the station. Watch the probe readout become 6.00 mm.", "The probe senses motion without touching the rotor. HOME establishes a repeatable reference so later measurements share the same sensor geometry.", "home", "Press HOME now; an old reference is not a new action.", "home"),
		_step("probe_adjust", "TRY THE MICROMETER", "Turn the actual probe micrometer", "Grip the micrometer drum beside the probe. Turn it to move the standoff at least 0.10 mm, staying between 4 and 8 mm, then release.", "The micrometer converts one full turn into 0.5 mm of linear travel. Sensor distance changes sensitivity, so moving it after calibration would require new measurements.", "probe_change", "Turn the micrometer at least 0.10 mm from its entry position, then release.", "dial:probe"),
		_step("probe_restore", "TRY THE MICROMETER", "Restore the probe reference", "Press HOME again to restore 6.00 mm. We have explored the adjustment; now return to a repeatable measurement setup.", "A known reference matters more than the appearance of a knob. Rehoming discards old calibration because measured sensitivity belongs to a particular probe position.", "home", "Press HOME to restore 6.00 mm before proceeding.", "home"),
		_step("open_setup", "BUILD A MASS VECTOR", "Open the guard for dial practice", "At zero speed, grip the orange handle and lift the guard. Release it before adjusting the mass controls. An already open guard is confirmed automatically.", "The mass controls change hardware inside the enclosure. The station requires zero speed and an open guard for those changes; a closed guard is required later to run the drive.", "open_guard", "Lift and release the guard at zero speed for mass adjustment.", "guard"),
		_step("mass_practice", "BUILD A MASS VECTOR", "Try the MASS dial", "With the guard open, grip the MASS dial for plane A. Turn it until the installed mass changes by at least 0.050 g, then release.", "A correction is a small mass at a known radius. More mass at the same radius produces more rotating force; its direction depends on where it sits around the rotor.", "mass_change", "Select plane A, change MASS by at least 0.050 g, and release.", "dial:mass"),
		_step("angle_practice", "BUILD A MASS VECTOR", "Rotate the ANGLE dial", "Grip ANGLE and move the mass by at least 20 degrees around plane A. Watch its marker move, then release.", "Mass and angle form a vector: an amount and a direction. The same mass on the opposite side pulls in the opposite direction. Vibration phase will help us find that direction.", "angle_change", "With nonzero mass on plane A, change ANGLE by at least 20 degrees, then release.", "dial:angle"),
		_step("clear_mass", "BUILD A MASS VECTOR", "Remove the practice mass", "Turn MASS back to 0.000 g and release. Leave the rotor bare for its first baseline; ANGLE has no physical effect when mass is zero.", "A baseline records the actual starting configuration. Returning this practice mass to zero keeps our first experiment easy to interpret; later the trial helper tracks masses relative to that baseline.", "mass_clear", "Turn plane A MASS down to 0.000 g and release.", "dial:mass"),
		_step("mode_two", "TWO RINGS, TWO SENSORS", "Select TWO-PLANE mode", "Press MODE until the monitor reads TWO-PLANE. This wheel has correction rings A and B and a vibration sensor at each support.", "A long rotor can wobble as well as shake sideways. Two correction planes and two measured responses let us account for both effects. Each plane needs its own known trial.", "mode_two", "Use physical MODE to select TWO-PLANE.", "mode"),
		_step("plane_b", "TWO RINGS, TWO SENSORS", "Select correction plane B", "Press PLANE to select B. The MASS and ANGLE dials now edit the second ring; notice their plane label change.", "One pair of dials edits whichever plane is selected. Selecting a plane changes only the editing destination, not the installed mass or the measurement method.", "plane_b", "Press PLANE until B is selected.", "plane"),
		_step("plane_a", "TWO RINGS, TWO SENSORS", "Return the editor to plane A", "Press PLANE to select A again. We will identify the response to a known trial on A first, then repeat independently on B.", "Independent trials isolate one input at a time. Changing both planes together would mix their contributions and make the sensitivity matrix impossible to identify from those two tests.", "plane_a", "Press PLANE until A is selected.", "plane"),
		_step("speed_explore", "CHOOSE THE EXPERIMENT", "Try another test speed", "Press SPEED to change the test-speed setting. The spindle stays stopped while you choose the next acquisition speed.", "Unbalance force increases with speed squared, while support resonance also changes vibration. A correction calibration belongs to its test speed; changing speed clears that calibration.", "speed_change", "Press physical SPEED to change the stopped test-speed setting.", "speed"),
		_step("speed_restore", "CHOOSE THE EXPERIMENT", "Set the experiment to 1200 RPM", "Press SPEED until the setting reads 1200 RPM. From 1500, the next settings are 900 and then 1200. Keep this setting through baseline, trials, and verification.", "Consistent speed lets us compare like with like. A speed sweep later explores resonance separately; it does not replace a matched-speed balancing calibration.", "speed_restore", "Use SPEED until 1200 RPM is selected.", "speed"),
		_step("guard", "PRACTICE A SAFE STOP", "Latch the enclosure", "Grip the orange guard handle, lower it fully, and release. Confirm CLOSED and let go of every fixture control.", "The drive requires a closed interlock and released handles. The simulated guard demonstrates this operating logic; it does not establish real machinery containment performance.", "closed_guard", "Lower and release the orange handle; confirm CLOSED.", "guard"),
		_step("preview_start", "PRACTICE A SAFE STOP", "Start a practice sweep", "Press SWEEP to start the drive. This first run is for practicing STOP; the next instruction will ask you to end it.", "Acquisition accelerates the rotor and samples its response. Starting a run is different from completing a valid measurement. We will deliberately interrupt this practice run.", "preview_start", "Press SWEEP to begin the stop exercise.", "sweep"),
		_step("stop", "PRACTICE A SAFE STOP", "Press STOP and watch coast-down", "Press STOP. Watch RPM fall to zero and keep the guard closed until it stops. An interrupted capture is discarded rather than treated as valid balancing data.", "Normal STOP cancels acquisition and allows coast-down. It does not latch an emergency condition or restart the spindle. A stopped drive can still be rotating.", "stop", "Press STOP and wait until speed is below 0.1 RPM.", "stop"),
		_step("estop", "PRACTICE A SAFE STOP", "Test the emergency latch", "At zero speed, press the red E-STOP. This is an intentional stopped-machine exercise; notice the latched status and disabled drive.", "E-STOP is for an emergency, while STOP ends normal work. Here E-STOP also discards calibration. Releasing a latch must never restart the rotor automatically.", "estop", "Press E-STOP at zero speed for the deliberate latch test.", "estop"),
		_step("recover", "PRACTICE A SAFE STOP", "Release the emergency latch", "Press RECOVER at zero speed to release E-STOP. If an actual simulated fault is also present, clear it with a separate RECOVER action before continuing.", "Recovery removes the stop or fault condition but leaves the drive stopped and the probe unreferenced. Operators must deliberately rehome and reacquire calibration after recovery.", "recover", "Press RECOVER until E-stop is released and no fault remains.", "recover"),
		_step("rehome", "PRACTICE A SAFE STOP", "Rehome before the real experiment", "Press HOME to establish 6.00 mm again. Keep the guard closed. The stop exercise is complete; now we will collect the real balancing data.", "A fresh reference after recovery makes the next calibration trustworthy. Neither recovery nor this guide starts a measurement for you.", "home", "Perform a fresh HOME after recovery.", "home"),
		_step("baseline", "LISTEN TO THE ROTOR", "Measure the starting vibration", "Press BASELINE. Wait through capture, analysis, and coast to zero. Watch the monitor draw the measured sensor waveforms.", "The baseline is our before picture: both support vibrations and the installed mass configuration. The vertical scale is displacement in micrometres; the horizontal scale is time in seconds.", "baseline", "Complete a NEW BASELINE capture and coast to zero.", "baseline"),
		_step("chart_order", "LISTEN TO THE ROTOR", "Find the once-per-turn peak", "Press CHART to show ORDER. Find 1x: one vibration cycle per rotor revolution. The two traces represent the two support sensors.", "The time waveform contains mixed motion. A spectrum separates frequency components; orders divide frequency by rotational frequency. The tachometer supplies the reference needed for amplitude and phase.", "chart_order", "Press CHART until ORDER is visible with measured spectrum data.", "chart"),
		_step("open_trial", "IDENTIFY PLANE A", "Open for the known A trial", "At zero speed, grip and lift the orange guard. Keep the probe, speed, and baseline configuration unchanged.", "We do not know the rotor's hidden heavy spots. Instead, we add a known change and measure its effect. That experiment identifies how the real station responds.", "open_guard", "Lift the guard at zero speed.", "guard"),
		_step("trial_fit", "IDENTIFY PLANE A", "Install the known A trial", "With plane A selected and the guard open, press FIT TRIAL. The helper adds a known 0.250 g vector to A relative to baseline.", "The other plane is restored to baseline. Only A changes, so the difference from baseline reveals A's effect on both sensors. The helper performs vector addition when baseline mass is nonzero.", "trial_fit", "Select A and press FIT TRIAL with the guard open.", "fit_trial"),
		_step("close_trial", "IDENTIFY PLANE A", "Latch for Trial A", "Lower and release the guard with the known A trial installed. Confirm CLOSED before pressing its measurement control.", "We retain the same probe position, radius, and speed. If those change, the response difference would combine multiple effects rather than isolate the known trial.", "closed_guard", "Lower and release the guard with the A trial installed.", "guard"),
		_step("trial_measure", "IDENTIFY PLANE A", "Measure the A trial response", "Press MEASURE TRIAL A and wait through analysis and coast. Compare its sensor response with the baseline.", "Subtracting the baseline complex vibration removes the original response. Dividing that difference by the known trial gives a measured influence coefficient: vibration per mass-radius input.", "trial_a", "Complete a NEW TRIAL A measurement and coast to zero.", "trial_a"),
		_step("open_trial_b", "IDENTIFY PLANE B", "Open for the independent B trial", "At zero speed, lift the guard. Next we will move the known perturbation to B, keeping A at its baseline configuration.", "Two-plane balancing needs two independent experiments. The response to A alone forms one matrix column; the response to B alone forms the other.", "open_guard", "Lift the guard at zero speed before changing the trial.", "guard"),
		_step("plane_b_trial", "IDENTIFY PLANE B", "Select B for its known trial", "Press PLANE to select B. FIT TRIAL will now act on the second correction ring.", "The selected editing plane and the trial measurement button have different jobs. Select B to install its trial, then use MEASURE TRIAL B to identify that trial's captured response.", "plane_b", "Press PLANE until B is selected for trial installation.", "plane"),
		_step("trial_fit_b", "IDENTIFY PLANE B", "Install the independent B trial", "Press FIT TRIAL with B selected and the guard open. Watch A return to baseline while the known 0.250 g trial is fitted to B.", "Leaving A's temporary trial installed would contaminate the B experiment. The helper restores the opposite plane so each measured matrix column has only one changed input.", "trial_fit_b", "Press FIT TRIAL on B and preserve A's baseline mass vector.", "fit_trial"),
		_step("close_trial_b", "IDENTIFY PLANE B", "Latch for Trial B", "Lower and release the guard with the independent B trial installed. Keep all measurement settings unchanged.", "Interlocks protect the acquisition sequence. They do not prove that a trial is correct; the station also validates which plane changed relative to baseline before accepting a trial measurement.", "closed_guard", "Lower and release the guard with the B trial installed.", "guard"),
		_step("trial_measure_b", "IDENTIFY PLANE B", "Measure the B trial response", "Press MEASURE TRIAL B and wait through analysis and coast to zero. We now have the baseline and both independent trial responses.", "Both sensors observe each plane. These cross-coupled responses explain why cancelling one support's vibration alone can leave the other support shaking.", "trial_b", "Complete a NEW TRIAL B measurement and coast to zero.", "trial_b"),
		_step("solve", "CANCEL THE VIBRATION", "Solve the measured two-plane system", "Press SOLVE. Read the calculated masses and angles for A and B and the condition number on the monitor.", "The solver combines the measured influence columns to predict cancelling vectors for both sensors. A large condition number warns that measurement errors can strongly distort the answer; an unusable solution is rejected.", "solve", "Press SOLVE after the fresh baseline and both independent trials.", "solve"),
		_step("open_apply", "CANCEL THE VIBRATION", "Open for the calculated correction", "At zero speed, lift the guard. Preserve the calibrated probe and speed while replacing the temporary trial configuration.", "A mathematical prediction is not an installed correction. We must put the calculated masses on the rotor and then test their actual measured effect.", "open_guard", "Lift the guard at zero speed before fitting the correction.", "guard"),
		_step("apply", "CANCEL THE VIBRATION", "Install the calculated masses", "Press APPLY CORRECTION with the guard open. Watch the mass markers move to the calculated amounts and angles on both rings.", "The result specifies total installed mass vectors, including any baseline masses. The trial is replaced; the correction is not added again on top of the temporary trial mass.", "apply", "Press APPLY CORRECTION with the guard open.", "apply"),
		_step("close_verify", "TEST THE PREDICTION", "Latch for independent verification", "Lower and release the guard with the calculated correction installed. The prediction is ready for an independent measurement.", "An unchanged setup lets a fresh capture test the prediction fairly. If the measured reduction is poor, the honest response is to diagnose the setup and repeat the experiment.", "closed_guard", "Lower and release the guard with the solution installed.", "guard"),
		_step("sweep", "EXPLORE THE SUPPORTS", "Measure the resonance curve", "Press SWEEP and let this run finish. Watch vibration versus speed, then inspect the curve after coast-down. Next we will verify at the original 1200 RPM.", "Unbalance forcing rises with speed, but support resonance also magnifies motion near a natural frequency. This is a quasi-steady synthetic speed sweep, not a flexible-rotor critical-speed certification.", "sweep", "Complete a NEW SWEEP with at least three measured speed points and coast to zero.", "sweep"),
		_step("verify", "TEST THE PREDICTION", "Measure how much vibration remains", "Press VERIFY. Wait through capture and coast, then compare both sensors with baseline and read the measured reduction.", "Verification uses new data rather than trusting the calculation. Close to zero amplitude, phase loses a reliable direction. A small residual is meaningful; a random phase at tiny amplitude is not.", "verify", "Complete NEW VERIFY with the calculated masses still installed.", "verify"),
		_step("repeat", "TEST THE PREDICTION", "Find the measurement's repeatability", "Press REPEAT without changing the corrected setup. Three windows estimate mean vibration, sample scatter, and the standard error of the mean.", "Repeatability shows how measurements vary under unchanged conditions. Scatter describes individual windows; standard error describes their estimated mean. These simulated repeats do not include calibration bias or total uncertainty.", "repeat", "Complete a NEW three-window REPEAT and coast to zero.", "repeat"),

		_step("report", "KEEP THE EVIDENCE", "Save the balancing experiment", "Press SAVE REPORT. You have measured an unknown rotor, identified two-plane sensitivity, installed a correction, verified it, and explored repeatability and resonance.", "The report preserves configuration, captures, solver evidence, events, and limitations. Explicitly skipped lessons do not certify that their work was performed. The station remains available for independent experiments.", "save", "Press SAVE REPORT now and confirm successful file output.", "save")
	]
	# Preparation can be replayed in either mode. From the plane-selection
	# chapter onward, the experiment requires the explicitly selected method.
	var require_two_plane: bool = false
	for step in course:
		step["expected_mode"] = "two_plane" if require_two_plane else ""
		if step.id == "mode_two": require_two_plane = true
	return course

func _step(id: String, chapter: String, title: String, body: String, theory: String, gate: String, gatehint: String, target: String) -> Dictionary:
	return {"id": id, "chapter": chapter, "title": title, "body": body, "theory": theory, "gate": gate, "gatehint": gatehint, "target": target, "practice_tab": "diagnostic"}
