class_name RotorLab
extends RefCounted
## A deterministic teaching instrument. The solver only sees measured phasors;
## the synthetic rotor model is confined to the signal generator.
## Amplitudes are displacement PEAK micrometres, phase is relative to the tach.

const SAMPLE_RATE: float = 1024.0
const SAMPLE_COUNT: int = 1024
const RESONANCE_HZ: float = 22.0
const DAMPING_RATIO: float = 0.11
const MAX_CONDITION: float = 30.0
const MIN_SENSITIVITY: float = 0.025

var mounted: bool = false
var guard_closed: bool = false
var homed: bool = false
var estop: bool = false
var fault: String = ""
var rpm: float = 0.0
var running: bool = false
var time: float = 0.0
var sensor_position_mm: float = 6.0
var masses: Array = [0.0, 0.0]
var angles: Array = [0.0, 0.0]
var radius_mm: float = 30.0
var active_plane: int = 0
var mode: String = "single"
var test_rpm: float = 1200.0
var run_kind: String = ""
var records: Array = []
var baseline: Dictionary = {}
var trial_a: Dictionary = {}
var trial_b: Dictionary = {}
var solution: Dictionary = {}
var latest: Dictionary = {}
var sweep_points: Array = []
var waveform: Array = []
var spectrum: Array = []
var events: Array = []
## Enable on the headset. Pure science tests retain synchronous execution.
var async_processing: bool = false
var processing: bool = false

var _run_elapsed: float = 0.0
var _settled_time: float = 0.0
var _next_sweep: float = 0.45
var _seed: int = 424242
var _run_config: Dictionary = {}
var _last_progress: float = 0.0
var _target_rpm: float = 0.0
var _raw_a: Array = []
var _raw_b: Array = []
var _processing_thread: Thread
var _processing_worker: RefCounted
var _processing_job: String = ""
var _discard_processing: bool = false

func mount_rotor() -> Dictionary:
	if not _stationary() or guard_closed or estop:
		return _reject("Stop the spindle, release E-stop, and open the guard to load the rotor.")
	mounted = true
	homed = false
	_clear_calibration()
	return _success("Rotor seated and latched. Home the probe before running.")

func toggle_guard() -> Dictionary:
	if not _stationary():
		return _reject("Wait for zero speed before opening the guard.")
	guard_closed = not guard_closed
	return _success("Guard closed." if guard_closed else "Guard open; spindle interlock active.")

func home_probe() -> Dictionary:
	if not _stationary() or not mounted or estop or not fault.is_empty():
		return _reject("Load the rotor and clear faults at zero speed before homing.")
	sensor_position_mm = 6.0
	homed = true
	_clear_calibration()
	return _success("Probe homed at 6.00 mm standoff.")

func set_probe(mm: float) -> Dictionary:
	if not _stationary():
		return _reject("Probe adjustments require zero speed.")
	if not is_finite(mm) or mm < 0.0 or mm > 15.0:
		return _reject("Probe travel is 0–15 mm.")
	if absf(mm - sensor_position_mm) > 0.001:
		_clear_calibration()
	sensor_position_mm = mm
	return _success("Probe standoff: %.2f mm." % mm)

func set_correction(plane: int, grams: float, angle: float) -> Dictionary:
	if not _stationary() or guard_closed or not mounted:
		return _reject("Load the rotor and open the guard at zero speed to change masses.")
	if plane < 0 or plane > 1 or not is_finite(grams) or not is_finite(angle) or grams < 0.0 or grams > 2.0:
		return _reject("Select plane A or B and a mass between 0 and 2 g.")
	if mode == "single" and plane != 0:
		return _reject("Plane B is available in two-plane mode.")
	masses[plane] = grams
	angles[plane] = fposmod(angle, 360.0)
	active_plane = plane
	_invalidate_verification()
	return _success("Plane %s: %.3f g at %.1f°." % ["A" if plane == 0 else "B", grams, angles[plane]])

func set_test_speed(speed: float) -> Dictionary:
	if not _stationary():
		return _reject("Stop the spindle before changing acquisition speed.")
	if not is_finite(speed) or speed < 300.0 or speed > 1800.0:
		return _reject("Measurement speed must be 300–1800 rpm.")
	if absf(speed - test_rpm) > 0.001:
		_clear_calibration()
		_invalidate_verification()
	test_rpm = speed
	return _success("Test speed %.0f rpm. Acquire a fresh baseline after a speed change." % speed)

func fit_trial(plane: int, grams: float = 0.25, angle: float = 0.0) -> Dictionary:
	if not _stationary() or guard_closed or not mounted:
		return _reject("Open the guard at zero speed to install a known trial mass.")
	if baseline.is_empty() or not _same_measurement_setup(baseline):
		return _reject("Acquire a matching baseline before fitting a trial mass.")
	if plane < 0 or plane > 1 or (mode == "single" and plane != 0):
		return _reject("Select an available trial plane.")
	if not is_finite(grams) or not is_finite(angle) or grams < 0.005 or grams > 1.0:
		return _reject("Known trial mass must be 0.005–1.0 g.")
	var total: Vector2 = _record_mass(baseline, plane) + _polar(grams * radius_mm, angle)
	if total.length() / radius_mm > 2.0:
		return _reject("Combined baseline and trial mass exceeds fixture capacity.")
	# Restore the opposite plane to baseline for independent columns of A.
	for plane_index in range(2):
		var installed: Vector2 = total if plane_index == plane else _record_mass(baseline, plane_index)
		masses[plane_index] = installed.length() / radius_mm
		angles[plane_index] = _phase(installed)
	active_plane = plane
	_invalidate_verification()
	return _success("Known trial %.3f g at %.1f° added to baseline on plane %s; other plane restored." % [grams, fposmod(angle, 360.0), "A" if plane == 0 else "B"])

func set_mode(value: String) -> Dictionary:
	if not _stationary():
		return _reject("Stop the spindle before changing the balance method.")
	if value != "single" and value != "two_plane":
		return _reject("Choose single or two_plane mode.")
	if value != mode:
		mode = value
		active_plane = 0
		_clear_calibration()
	return _success("%s method selected; acquire a fresh baseline." % ("Two-plane" if mode == "two_plane" else "Single-plane"))

func begin_run(kind: String = "baseline") -> Dictionary:
	if not _stationary():
		return _reject("Wait for zero speed before starting another acquisition.")
	if not mounted or not guard_closed or not homed:
		return _reject("Load the rotor, home the probe, and close the guard first.")
	if estop or not fault.is_empty():
		return _reject("Release E-stop and reset the fault before running.")
	if sensor_position_mm < 4.0 or sensor_position_mm > 8.0:
		return _reject("Probe signal invalid: set standoff within 4–8 mm and rehome as needed.")
	if not is_finite(test_rpm) or test_rpm < 300.0 or test_rpm > 1800.0:
		return _reject("Measurement speed must be 300–1800 rpm.")
	if not ["baseline", "trial_a", "trial_b", "verify", "sweep", "repeat"].has(kind):
		return _reject("Unknown acquisition kind.")
	if kind == "trial_a" or kind == "trial_b":
		var validity: Dictionary = _validate_trial(kind)
		if not validity.ok:
			return _reject(validity.message)
	if kind == "baseline":
		_clear_calibration()
	if kind == "sweep":
		sweep_points.clear()
	running = true
	run_kind = kind
	_run_elapsed = 0.0
	_settled_time = 0.0
	_last_progress = 0.0
	_next_sweep = 0.45
	_run_config = _configuration()
	_target_rpm = test_rpm if kind != "sweep" else 0.0
	return _success("%s acquisition started." % kind.capitalize())

func stop() -> Dictionary:
	running = false
	_target_rpm = 0.0
	_discard_processing = processing
	return _success("Acquisition stopped. Spindle coasting to zero.")

func emergency_stop() -> Dictionary:
	estop = true
	running = false
	_target_rpm = 0.0
	_discard_processing = processing
	_clear_calibration()
	return _success("Emergency stop latched. Calibration discarded; wait for zero speed.")

func release_estop() -> Dictionary:
	if not _stationary():
		return _reject("Wait for zero speed before releasing E-stop.")
	estop = false
	homed = false
	return _success("E-stop released. Rehome the probe before restarting.")

func reset_fault() -> Dictionary:
	if not _stationary() or estop:
		return _reject("Stop the spindle and release E-stop before fault reset.")
	fault = ""
	homed = false
	return _success("Fault cleared. Rehome and reacquire calibration.")

func inject_fault(kind: String = "sensor") -> Dictionary:
	if kind == "sensor":
		fault = "Sensor dropout"
	elif kind == "tach":
		fault = "Tachometer signal lost"
	elif kind == "speed":
		fault = "Tachometer disagreement"
	else:
		fault = "Interlock fault"
	running = false
	_target_rpm = 0.0
	_discard_processing = processing
	homed = false
	_clear_calibration()
	return _success("Injected fault: %s. Drive disabled." % fault)

func solve_balance() -> Dictionary:
	if not _stationary() or estop or not fault.is_empty():
		return _reject("Solve requires zero speed with all faults cleared.")
	if baseline.is_empty() or trial_a.is_empty():
		return _reject("Capture a baseline and a known plane A trial first.")
	if not _same_measurement_setup(baseline):
		return _reject("Speed or probe setup changed; reacquire the baseline and trials.")
	var trial_vector_a: Vector2 = _record_mass(trial_a, 0) - _record_mass(baseline, 0)
	if trial_vector_a.length() < 0.15:
		return _reject("Plane A trial mass is too small for a reliable coefficient.")
	var alpha_a: Vector2 = _cdiv(_record_phasor(trial_a, 0) - _record_phasor(baseline, 0), trial_vector_a)
	if alpha_a.length() < MIN_SENSITIVITY:
		return _reject("Plane A trial has insufficient measured sensitivity.")
	var correction_a: Vector2
	var correction_b: Vector2 = Vector2.ZERO
	var condition_number: float = 1.0
	var influence: Array = [[_pair(alpha_a)]]
	if mode == "two_plane":
		if trial_b.is_empty():
			return _reject("Two-plane balancing requires an independent plane B trial from baseline.")
		var trial_vector_b: Vector2 = _record_mass(trial_b, 1) - _record_mass(baseline, 1)
		if trial_vector_b.length() < 0.15:
			return _reject("Plane B trial mass is too small for a reliable coefficient.")
		var alpha_b: Vector2 = _cdiv(_record_phasor(trial_b, 0) - _record_phasor(baseline, 0), trial_vector_b)
		var beta_a: Vector2 = _cdiv(_record_phasor(trial_a, 1) - _record_phasor(baseline, 1), trial_vector_a)
		var beta_b: Vector2 = _cdiv(_record_phasor(trial_b, 1) - _record_phasor(baseline, 1), trial_vector_b)
		if beta_b.length() < MIN_SENSITIVITY:
			return _reject("Plane B trial has insufficient measured sensitivity.")
		var determinant: Vector2 = _cmul(alpha_a, beta_b) - _cmul(alpha_b, beta_a)
		var norm_squared: float = alpha_a.length_squared() + alpha_b.length_squared() + beta_a.length_squared() + beta_b.length_squared()
		var discriminant: float = sqrt(maxf(0.0, norm_squared * norm_squared - 4.0 * determinant.length_squared()))
		var lambda_min: float = maxf(0.0, (norm_squared - discriminant) / 2.0)
		var lambda_max: float = (norm_squared + discriminant) / 2.0
		condition_number = sqrt(lambda_max / maxf(lambda_min, 0.000000000001))
		if determinant.length() < 0.00001 or condition_number > MAX_CONDITION:
			solution = {}
			return _reject("Influence matrix is nearly singular (condition %.1f); change trial setup and reacquire." % condition_number)
		var negative_a: Vector2 = -_record_phasor(baseline, 0)
		var negative_b: Vector2 = -_record_phasor(baseline, 1)
		correction_a = _cdiv(_cmul(negative_a, beta_b) - _cmul(alpha_b, negative_b), determinant)
		correction_b = _cdiv(_cmul(alpha_a, negative_b) - _cmul(negative_a, beta_a), determinant)
		influence = [[_pair(alpha_a), _pair(alpha_b)], [_pair(beta_a), _pair(beta_b)]]
	else:
		correction_a = _cdiv(-_record_phasor(baseline, 0), alpha_a)
	var total_a: Vector2 = _record_mass(baseline, 0) + correction_a
	var total_b: Vector2 = _record_mass(baseline, 1) + correction_b
	if total_a.length() / radius_mm > 2.0 or total_b.length() / radius_mm > 2.0:
		return _reject("Computed correction exceeds the 2 g fixture capacity; inspect trial data.")
	solution = {
		"mode": mode, "mass_a_g": total_a.length() / radius_mm, "angle_a_deg": _phase(total_a),
		"mass_b_g": total_b.length() / radius_mm, "angle_b_deg": _phase(total_b),
		"masses_g": [total_a.length() / radius_mm, total_b.length() / radius_mm],
		"angles_deg": [_phase(total_a), _phase(total_b)],
		"added_to_baseline_gmm": [_pair(correction_a), _pair(correction_b)],
		"condition_number": condition_number, "influence_um_per_gmm": influence,
		"baseline_record_id": baseline.id, "rpm": baseline.rpm,
		"method": "Measured complex influence coefficients; total installed masses include baseline masses."
	}
	return _success("Correction solved from measured trials; matrix condition %.2f. Open guard to apply." % condition_number)

func apply_solution() -> Dictionary:
	if not _stationary() or guard_closed or estop or not fault.is_empty():
		return _reject("Stop, clear faults, and open the guard to apply corrections.")
	if solution.is_empty():
		return _reject("Solve a valid calibration first.")
	if not _same_measurement_setup(baseline):
		return _reject("Calibration no longer matches the measurement setup.")
	masses = solution.masses_g.duplicate()
	angles = solution.angles_deg.duplicate()
	return _success("Trial masses replaced with the total calculated correction. Close guard and verify.")

func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	time += delta
	if processing:
		# Worker signals are isolated: never inspect its arrays while it is alive.
		# Pause the acquisition clock while analysis runs, keeping sweep samples
		# deterministic regardless of rendering framerate or worker scheduling.
		if not running:
			rpm = move_toward(rpm, 0.0, delta * 1500.0)
		_poll_processing()
		return
	if not running:
		rpm = move_toward(rpm, 0.0, delta * 1500.0)
		return
	_run_elapsed += delta
	if not guard_closed or not mounted or estop or not fault.is_empty():
		inject_fault("guard")
		return
	if run_kind == "sweep":
		_target_rpm = minf(1800.0, _run_elapsed / 9.0 * 1800.0)
		rpm = move_toward(rpm, _target_rpm, delta * 1100.0)
		_last_progress = minf(1.0, _run_elapsed / 9.5)
		if _run_elapsed >= _next_sweep and rpm >= 80.0:
			_next_sweep += 0.45
			if async_processing:
				_start_processing("sweep_point", rpm)
				return
			_append_sweep_point(_measure(rpm, false))
		if _run_elapsed >= 9.5:
			_finish_sweep()
		return
	_target_rpm = test_rpm
	rpm = move_toward(rpm, _target_rpm, delta * 1100.0)
	_settled_time = _settled_time + delta if absf(rpm - test_rpm) < 2.0 else 0.0
	var acquisition_duration: float = 5.2 if run_kind == "repeat" else 3.2
	var settled_duration: float = 3.0 if run_kind == "repeat" else 1.0
	_last_progress = minf(0.98, _run_elapsed / acquisition_duration)
	if _run_elapsed >= acquisition_duration and _settled_time >= settled_duration:
		_finish_measurement()
	elif _run_elapsed > 6.0:
		inject_fault("speed")

func telemetry() -> Dictionary:
	var result: Dictionary = _configuration()
	result.merge({"mounted": mounted, "guard_closed": guard_closed, "homed": homed, "estop": estop, "fault": fault,
		"rpm": rpm, "target_rpm": _target_rpm if running else 0.0, "running": running, "time": time,
		"processing": processing, "async_processing": async_processing,
		"run_kind": run_kind, "run_progress": _last_progress, "amplitude_um": float(latest.get("amplitude_um", 0.0)),
		"phase_deg": float(latest.get("phase_deg", 0.0)), "amplitudes_um": latest.get("amplitudes_um", [0.0, 0.0]),
		"phases_deg": latest.get("phases_deg", [0.0, 0.0]), "latest": latest.duplicate(true),
		"phase_observable": latest.get("phase_observable", [false, false]),
		"has_baseline": not baseline.is_empty(), "has_trial_a": not trial_a.is_empty(), "has_trial_b": not trial_b.is_empty(),
		"has_solution": not solution.is_empty(), "solution": solution.duplicate(true), "record_count": records.size(),
		"waveform": waveform.duplicate(true), "spectrum": spectrum.duplicate(true), "sweep_points": sweep_points.duplicate(true)})
	return result

func report() -> Dictionary:
	return {
		"schema": "spinlab-native-report-v1", "units": {"displacement": "micrometres peak", "mass": "grams", "radius": "millimetres", "phase": "degrees relative to tach"},
		"configuration": _configuration(), "records": records.duplicate(true), "events": events.duplicate(true),
		"baseline": baseline.duplicate(true), "trial_a": trial_a.duplicate(true), "trial_b": trial_b.duplicate(true),
		"solution": solution.duplicate(true), "sweep": sweep_points.duplicate(true),
		"methodology": [
			"Single-plane correction Uc = -V0/alpha; alpha = (Vtrial - V0)/Utrial, with known complex mass-radius trial vector.",
			"Two-plane correction solves the measured 2x2 complex influence matrix; singular-value condition estimate must be <=30.",
			"Quasi-steady synthetic acquisition: 1024 samples at 1024 Hz, with tach phase; least-squares DC, cos/sin 1x and cos/sin 2x basis separates synchronous motion from DC and 2x.",
			"The displayed waveform contains the last 256 samples; spectrum is a peak-amplitude one-sided DFT, 0–100 Hz, computed only when a run finishes.",
			"The sweep uses a linear damped second-order response with a 22 Hz natural frequency and damping ratio 0.11; each sweep point is a quasi-steady simulated window, not a transient integration.",
			"Repeatability uses three independent deterministic-noise windows and sample standard deviation (n-1); this is Type A repeatability, not a complete uncertainty budget."
		],
		"references": [
			{"title": "Yu and Péton, Texas A&M: Two-plane influence coefficient balancing", "url": "https://oaktrust.library.tamu.edu/items/e9117928-4326-48e0-8302-335013f69251"},
			{"title": "Liu, Maghami and Blaurock: Reaction Wheel Disturbance Modeling, Jitter Analysis, and Validation Tests for Solar Dynamics Observatory", "url": "https://ntrs.nasa.gov/api/citations/20080039248/downloads/20080039248.pdf"},
			{"title": "NI: Performing Order Analysis", "url": "https://www.ni.com/en/shop/labview/performing-order-analysis-in-labview-with-sound-and-vibration-so.html"}
		],
		"limitations": ["Fictional educational rotor and sensors; all data are synthetic.", "Rigid-rotor influence-coefficient exercise with one illustrative structural mode; not a validated spacecraft or flexible-rotor model.", "No claim of ISO balance grade, instrument calibration traceability, flight qualification, or safety certification.", "Single-plane balancing minimizes sensor A at one speed; residual sensor B motion can remain.", "Phase below 0.02 micrometres is flagged unobservable at the simulated instrument noise floor.", "No headset microphone or tracking measurements are used as vibration sensors."]
	}

func reset() -> Dictionary:
	if processing:
		return _reject("Wait for signal analysis to finish before resetting the session.")
	mounted = false
	guard_closed = false
	homed = false
	estop = false
	fault = ""
	rpm = 0.0
	running = false
	time = 0.0
	sensor_position_mm = 6.0
	masses = [0.0, 0.0]
	angles = [0.0, 0.0]
	radius_mm = 30.0
	active_plane = 0
	mode = "single"
	test_rpm = 1200.0
	run_kind = ""
	_target_rpm = 0.0
	_run_elapsed = 0.0
	_last_progress = 0.0
	_seed = 424242
	records.clear()
	events.clear()
	latest.clear()
	sweep_points.clear()
	waveform.clear()
	spectrum.clear()
	_clear_calibration()
	return _success("New commissioning session ready.")

func _finish_measurement() -> void:
	if async_processing:
		_start_processing("capture", test_rpm)
	else:
		_commit_measurement(_build_measurement(test_rpm, run_kind))

func _build_measurement(speed: float, kind: String) -> Dictionary:
	var record: Dictionary = _measure(speed, true)
	if kind == "repeat":
		var samples_a: Array = [record.amplitude_um]
		var samples_b: Array = [record.amplitudes_um[1]]
		var repeat_windows: Array = [record.duplicate(true)]
		for repeat_index in range(2):
			var extra: Dictionary = _measure(speed, repeat_index == 1)
			samples_a.append(extra.amplitudes_um[0])
			samples_b.append(extra.amplitudes_um[1])
			repeat_windows.append(extra)
		record["repeatability"] = {"n": 3, "sensor_a": _statistics(samples_a), "sensor_b": _statistics(samples_b), "windows": repeat_windows}
	return record

func _commit_measurement(record: Dictionary) -> void:
	record["id"] = records.size() + 1
	record["kind"] = run_kind
	record["mode"] = mode
	record["simulation_time_s"] = time
	record["accepted"] = true
	if run_kind == "baseline":
		baseline = record.duplicate(true)
	elif run_kind == "trial_a":
		trial_a = record.duplicate(true)
		solution = {}
	elif run_kind == "trial_b":
		trial_b = record.duplicate(true)
		solution = {}
	elif run_kind == "verify" and not baseline.is_empty():
		var reductions: Array = []
		for sensor in range(2):
			reductions.append(100.0 * (1.0 - float(record.amplitudes_um[sensor]) / maxf(float(baseline.amplitudes_um[sensor]), 0.000001)))
		record["reduction_percent"] = reductions
		record["verified"] = reductions[0] > 90.0 and (mode == "single" or reductions[1] > 90.0)
	latest = record.duplicate(true)
	records.append(record)
	running = false
	_target_rpm = 0.0
	_last_progress = 1.0
	_event("capture", "%s captured: A %.3f µm at %.1f°, B %.3f µm." % [run_kind, record.amplitude_um, record.phase_deg, record.amplitudes_um[1]])

func _finish_sweep() -> void:
	if async_processing:
		_start_processing("sweep_final", 1800.0)
	else:
		_commit_sweep(_measure(1800.0, true))

func _append_sweep_point(point: Dictionary) -> void:
	sweep_points.append({"rpm": point.rpm, "frequency_hz": point.rpm / 60.0, "amplitude_um": point.amplitude_um, "amplitudes_um": point.amplitudes_um, "phase_deg": point.phase_deg})
	latest = point

func _commit_sweep(record: Dictionary) -> void:
	var peak: Dictionary = {}
	for point in sweep_points:
		if peak.is_empty() or point.amplitude_um > peak.amplitude_um:
			peak = point.duplicate(true)
	record.merge({"id": records.size() + 1, "kind": "sweep", "mode": mode, "simulation_time_s": time, "accepted": true, "peak": peak, "points": sweep_points.duplicate(true)})
	records.append(record)
	latest = record.duplicate(true)
	running = false
	_target_rpm = 0.0
	_last_progress = 1.0
	_event("capture", "Sweep complete: %d quasi-steady points; peak %.0f rpm." % [sweep_points.size(), float(peak.get("rpm", 0.0))])

func _start_processing(job: String, speed: float) -> void:
	# Each worker gets independent arrays and RNG state from the run snapshot.
	# It neither reads nor mutates the live lab while running on another thread.
	var worker = get_script().new()
	worker.mode = _run_config.mode
	worker.active_plane = _run_config.active_plane
	worker.sensor_position_mm = _run_config.sensor_position_mm
	worker.masses = _run_config.masses.duplicate()
	worker.angles = _run_config.angles.duplicate()
	worker.radius_mm = _run_config.radius_mm
	worker.test_rpm = _run_config.test_rpm
	worker._seed = _seed
	_processing_worker = worker
	_processing_job = job
	_discard_processing = false
	processing = true
	_processing_thread = Thread.new()
	var start_error: Error = _processing_thread.start(Callable(worker, "_compute_job").bind(job, speed, run_kind))
	if start_error != OK:
		# Thread creation failure is recoverable; preserve this measurement with
		# an explicit synchronous fallback instead of dropping or faking data.
		_event("analysis", "Worker unavailable; this capture uses synchronous analysis.")
		var outcome: Dictionary = worker._compute_job(job, speed, run_kind)
		_processing_thread = null
		processing = false
		_accept_worker_result(job, outcome)
		_processing_worker = null

func _compute_job(job: String, speed: float, kind: String) -> Dictionary:
	var record: Dictionary = _build_measurement(speed, kind) if job == "capture" else _measure(speed, job == "sweep_final")
	return {"record": record, "waveform": waveform, "spectrum": spectrum, "seed": _seed}

func _poll_processing() -> void:
	if _processing_thread == null or _processing_thread.is_alive():
		return
	var outcome: Dictionary = _processing_thread.wait_to_finish()
	_processing_thread = null
	processing = false
	if _discard_processing:
		_event("analysis", "Cancelled analysis discarded after worker shutdown.")
	else:
		_accept_worker_result(_processing_job, outcome)
	_processing_worker = null
	_processing_job = ""
	_discard_processing = false

func _accept_worker_result(job: String, outcome: Dictionary) -> void:
	# Copies occur only after the thread has completed; no live arrays are shared.
	_seed = outcome.seed
	if not outcome.waveform.is_empty():
		waveform = outcome.waveform.duplicate(true)
	if not outcome.spectrum.is_empty():
		spectrum = outcome.spectrum.duplicate(true)
	var record: Dictionary = outcome.record.duplicate(true)
	if job == "capture":
		_commit_measurement(record)
	elif job == "sweep_point":
		_append_sweep_point(record)
	elif job == "sweep_final":
		_commit_sweep(record)

func _notification(what: int) -> void:
	# Godot requires every started Thread to be joined before destruction.
	if what == NOTIFICATION_PREDELETE and _processing_thread != null and _processing_thread.is_started():
		_processing_thread.wait_to_finish()

func _measure(speed: float, include_display: bool) -> Dictionary:
	var physical_a: Vector2 = _synthetic_response(speed, 0)
	var physical_b: Vector2 = _synthetic_response(speed, 1)
	var frequency: float = speed / 60.0
	var gram: Array = []
	var rhs_a: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
	var rhs_b: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
	for row_index in range(5):
		gram.append([0.0, 0.0, 0.0, 0.0, 0.0])
	_raw_a = []
	_raw_b = []
	var samples_display: Array = []
	var basis_rows: Array = []
	for sample_index in range(SAMPLE_COUNT):
		var sample_time: float = float(sample_index) / SAMPLE_RATE
		var theta: float = TAU * frequency * sample_time + 0.37
		var basis: Array = [1.0, cos(theta), sin(theta), cos(2.0 * theta), sin(2.0 * theta)]
		var second_a: float = 0.16 + 0.028 * physical_a.length()
		var second_b: float = 0.12 + 0.022 * physical_b.length()
		var signal_a: float = 1.1 + physical_a.x * basis[1] - physical_a.y * basis[2] + second_a * cos(2.0 * theta + 0.4) + _noise() * 0.07
		var signal_b: float = -0.65 + physical_b.x * basis[1] - physical_b.y * basis[2] + second_b * cos(2.0 * theta - 0.3) + _noise() * 0.07
		_raw_a.append(signal_a)
		_raw_b.append(signal_b)
		basis_rows.append(basis)
		for row_index in range(5):
			rhs_a[row_index] += basis[row_index] * signal_a
			rhs_b[row_index] += basis[row_index] * signal_b
			for column_index in range(5):
				gram[row_index][column_index] += basis[row_index] * basis[column_index]
		if include_display and sample_index >= SAMPLE_COUNT - 256:
			samples_display.append({"t": sample_time, "y": signal_a, "a": signal_a, "b": signal_b, "tach": cos(theta)})
	var fit_a: Array = _linear_solve(gram, rhs_a)
	var fit_b: Array = _linear_solve(gram, rhs_b)
	var measured_a: Vector2 = Vector2(fit_a[1], -fit_a[2])
	var measured_b: Vector2 = Vector2(fit_b[1], -fit_b[2])
	var residual_energy: float = 0.0
	for sample_index in range(SAMPLE_COUNT):
		var prediction: float = 0.0
		for basis_index in range(5):
			prediction += fit_a[basis_index] * basis_rows[sample_index][basis_index]
		residual_energy += pow(float(_raw_a[sample_index]) - prediction, 2.0)
	if include_display:
		waveform = samples_display
		spectrum = _dft(_raw_a)
	var config: Dictionary = _configuration()
	config.merge({"rpm": speed, "frequency_hz": frequency, "phasors": [_pair(measured_a), _pair(measured_b)],
		"amplitude_um": measured_a.length(), "phase_deg": _phase(measured_a),
		"amplitudes_um": [measured_a.length(), measured_b.length()], "phases_deg": [_phase(measured_a), _phase(measured_b)],
		"phase_observable": [measured_a.length() >= 0.02, measured_b.length() >= 0.02],
		"noise_rms_um": sqrt(residual_energy / float(SAMPLE_COUNT - 5)),
		"dc_offsets_um": [fit_a[0], fit_b[0]], "second_harmonic_um": [Vector2(fit_a[3], fit_a[4]).length(), Vector2(fit_b[3], fit_b[4]).length()],
		"measurement": {"sample_rate_hz": SAMPLE_RATE, "samples": SAMPLE_COUNT, "duration_s": float(SAMPLE_COUNT) / SAMPLE_RATE, "method": "tach-referenced least squares: DC + cos/sin 1x + cos/sin 2x", "synthetic": true}})
	return config

func _synthetic_response(speed: float, sensor: int) -> Vector2:
	# This model is deliberately absent from solve_balance(). Hidden unbalance is
	# converted to displacement, then noisy time samples are demodulated above.
	var imbalance_a: Vector2 = _polar(12.6, 34.0) + _mass_vector(0)
	var imbalance_b: Vector2 = _polar(9.3, 208.0) + _mass_vector(1)
	var normalized_frequency: float = speed / 60.0 / RESONANCE_HZ
	var dynamics: Vector2 = _cdiv(Vector2(normalized_frequency * normalized_frequency, 0.0), Vector2(1.0 - normalized_frequency * normalized_frequency, 2.0 * DAMPING_RATIO * normalized_frequency))
	var output: Vector2
	if sensor == 0:
		output = _cmul(_polar(0.34, 0.0), imbalance_a) + _cmul(_polar(0.19, 23.0), imbalance_b)
	else:
		output = _cmul(_polar(0.17, -17.0), imbalance_a) + _cmul(_polar(0.38, 13.0), imbalance_b)
	var standoff_gain: float = exp(-pow((sensor_position_mm - 6.0) / 4.0, 2.0))
	return _cmul(dynamics, output) * standoff_gain

func _validate_trial(kind: String) -> Dictionary:
	if baseline.is_empty():
		return {"ok": false, "message": "Acquire a baseline before adding a trial mass."}
	if not _same_measurement_setup(baseline):
		return {"ok": false, "message": "Trial speed and probe position must match the baseline."}
	var plane: int = 0 if kind == "trial_a" else 1
	if plane == 1 and mode != "two_plane":
		return {"ok": false, "message": "Plane B trials require two-plane mode."}
	if (_mass_vector(plane) - _record_mass(baseline, plane)).length() < 0.15:
		return {"ok": false, "message": "Install a known trial mass on plane %s relative to baseline." % ("A" if plane == 0 else "B")}
	if (_mass_vector(1 - plane) - _record_mass(baseline, 1 - plane)).length() > 0.001:
		return {"ok": false, "message": "Restore the other plane to its baseline mass before an independent trial."}
	return {"ok": true, "message": "Valid independent trial."}

func _same_measurement_setup(record: Dictionary) -> bool:
	return not record.is_empty() and absf(float(record.rpm) - test_rpm) <= maxf(2.0, test_rpm * 0.01) and absf(float(record.sensor_position_mm) - sensor_position_mm) < 0.01 and absf(float(record.radius_mm) - radius_mm) < 0.01 and record.mode == mode

func _configuration() -> Dictionary:
	return {"mode": mode, "active_plane": active_plane, "sensor_position_mm": sensor_position_mm,
		"masses": masses.duplicate(), "angles": angles.duplicate(), "masses_g": masses.duplicate(), "angles_deg": angles.duplicate(),
		"mass_vectors_gmm": [_pair(_mass_vector(0)), _pair(_mass_vector(1))], "radius_mm": radius_mm, "test_rpm": test_rpm}

func _clear_calibration() -> void:
	baseline = {}
	trial_a = {}
	trial_b = {}
	solution = {}
	_invalidate_verification()

func _invalidate_verification() -> void:
	if latest.has("verified"):
		latest["verified"] = false
	latest.erase("reduction_percent")
	if not latest.is_empty():
		latest["configuration_changed"] = true

func _stationary() -> bool:
	return not running and not processing and rpm < 1.0

func _mass_vector(plane: int) -> Vector2:
	return _polar(float(masses[plane]) * radius_mm, float(angles[plane]))

func _record_mass(record: Dictionary, plane: int) -> Vector2:
	return Vector2(float(record.mass_vectors_gmm[plane][0]), float(record.mass_vectors_gmm[plane][1]))

func _record_phasor(record: Dictionary, sensor: int) -> Vector2:
	return Vector2(float(record.phasors[sensor][0]), float(record.phasors[sensor][1]))

func _pair(value: Vector2) -> Array:
	return [value.x, value.y]

func _polar(magnitude: float, degrees: float) -> Vector2:
	return Vector2(cos(deg_to_rad(degrees)), sin(deg_to_rad(degrees))) * magnitude

func _phase(value: Vector2) -> float:
	return fposmod(rad_to_deg(atan2(value.y, value.x)), 360.0)

func _cmul(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x)

func _cdiv(a: Vector2, b: Vector2) -> Vector2:
	var denominator: float = maxf(b.length_squared(), 0.000000000000001)
	return Vector2(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / denominator

func _noise() -> float:
	_seed = (1664525 * _seed + 1013904223) % 4294967296
	return float(_seed) / 2147483648.0 - 1.0

func _linear_solve(matrix: Array, rhs: Array) -> Array:
	# Pivoted Gauss-Jordan elimination; the five tach basis functions are fitted
	# together so non-integer revolutions do not leak DC/2x into the 1x phasor.
	var work: Array = matrix.duplicate(true)
	var result: Array = rhs.duplicate()
	for pivot in range(5):
		var best: int = pivot
		for row_index in range(pivot + 1, 5):
			if absf(work[row_index][pivot]) > absf(work[best][pivot]):
				best = row_index
		var swap_row: Array = work[pivot]
		work[pivot] = work[best]
		work[best] = swap_row
		var swap_value: float = result[pivot]
		result[pivot] = result[best]
		result[best] = swap_value
		var divisor: float = float(work[pivot][pivot])
		if absf(divisor) < 0.00000001:
			return [0.0, 0.0, 0.0, 0.0, 0.0]
		for column_index in range(5):
			work[pivot][column_index] /= divisor
		result[pivot] /= divisor
		for row_index in range(5):
			if row_index == pivot:
				continue
			var factor: float = float(work[row_index][pivot])
			for column_index in range(5):
				work[row_index][column_index] -= factor * work[pivot][column_index]
			result[row_index] -= factor * result[pivot]
	return result

func _dft(signal_samples: Array) -> Array:
	var output: Array = []
	for frequency_bin in range(101):
		var re: float = 0.0
		var im: float = 0.0
		for sample_index in range(SAMPLE_COUNT):
			var phase: float = TAU * float(frequency_bin * sample_index) / float(SAMPLE_COUNT)
			re += signal_samples[sample_index] * cos(phase)
			im -= signal_samples[sample_index] * sin(phase)
		var amplitude: float = Vector2(re, im).length() / float(SAMPLE_COUNT)
		if frequency_bin > 0:
			amplitude *= 2.0
		output.append({"hz": float(frequency_bin), "frequency_hz": float(frequency_bin), "amplitude": amplitude, "amplitude_um": amplitude})
	return output

func _statistics(values: Array) -> Dictionary:
	var average: float = 0.0
	for value in values:
		average += value
	average /= float(values.size())
	var variance: float = 0.0
	for value in values:
		variance += pow(value - average, 2.0)
	var deviation: float = sqrt(variance / float(values.size() - 1))
	return {"mean_um": average, "sample_std_um": deviation, "standard_error_um": deviation / sqrt(float(values.size())), "cv_percent": 100.0 * deviation / maxf(average, 0.000001), "samples_um": values.duplicate()}

func _event(kind: String, message: String) -> void:
	events.append({"time_s": time, "kind": kind, "message": message})

func _success(message: String) -> Dictionary:
	_event("action", message)
	return {"ok": true, "message": message}

func _reject(message: String) -> Dictionary:
	_event("rejected", message)
	return {"ok": false, "message": message}
