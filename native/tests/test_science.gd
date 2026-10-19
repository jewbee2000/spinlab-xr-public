extends SceneTree

const LabScript = preload("res://scripts/rotor_lab.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_test_interlocks()
	_test_single_plane()
	_test_two_plane()
	_test_trial_validity()
	_test_bad_calibration()
	_test_repeat_sweep_and_determinism()
	_test_workflow_helpers_and_noninteger_speed()
	_test_async_acquisition()
	print("SCIENCE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func _ready_lab(two_plane: bool = false):
	var lab = LabScript.new()
	_check(lab.mount_rotor().ok, "Rotor loads")
	_check(lab.home_probe().ok, "Probe homes")
	if two_plane:
		_check(lab.set_mode("two_plane").ok, "Select two-plane method")
	return lab

func _run(lab, kind: String) -> void:
	if not lab.guard_closed:
		lab.toggle_guard()
	_check(lab.begin_run(kind).ok, "Start %s" % kind)
	for step in range(20000):
		lab.tick(0.02)
		if lab.processing:
			OS.delay_msec(1)
		if not lab.running and not lab.processing and lab.rpm < 1.0:
			return
	_check(false, "Acquisition and worker completed within the bounded test loop")

func _open(lab) -> void:
	if lab.guard_closed:
		_check(lab.toggle_guard().ok, "Open guard at zero speed")

func _test_interlocks() -> void:
	var lab = LabScript.new()
	_check(not lab.begin_run().ok, "Empty fixture cannot spin")
	lab.mount_rotor()
	lab.home_probe()
	_check(not lab.begin_run().ok, "Open guard inhibits spindle")
	lab.toggle_guard()
	_check(lab.begin_run().ok, "Prepared fixture starts")
	lab.tick(0.1)
	_check(not lab.toggle_guard().ok, "Guard stays latched during spin")
	_check(not lab.set_correction(0, 0.2, 0.0).ok, "Mass change rejected while running")
	lab.emergency_stop()
	_check(lab.estop and not lab.running, "E-stop disables drive")
	_check(not lab.release_estop().ok, "E-stop cannot reset before coast ends")
	lab.tick(2.0)
	_check(lab.release_estop().ok and not lab.homed, "E-stop release requires rehome")

func _test_single_plane() -> void:
	var lab = _ready_lab()
	_run(lab, "baseline")
	var initial: float = lab.baseline.amplitude_um
	_open(lab)
	lab.set_correction(0, 0.2, 90.0)
	_run(lab, "trial_a")
	_check(lab.solve_balance().ok, "Single-plane influence solve")
	_open(lab)
	_check(lab.apply_solution().ok, "Install single-plane correction")
	_run(lab, "verify")
	_check(lab.latest.amplitude_um < initial * 0.05, "Single-plane correction removes >95% sensor A 1x")
	_check(lab.latest.verified, "Single-plane verification accepted")
	_check(not lab.latest.phase_observable[0], "Near-zero 1x phase flagged unobservable")
	_check(lab.waveform.size() == 256 and lab.spectrum.size() == 101, "Captured waveform and spectrum sizes")
	_check(absf(lab.baseline.dc_offsets_um[0] - 1.1) < 0.01, "LS separates DC bias")
	_check(lab.baseline.second_harmonic_um[0] > 0.15, "LS recovers injected 2x harmonic")
	_check(lab.latest.noise_rms_um > 0.03 and lab.latest.noise_rms_um < 0.05, "Noise residual is realistic")
	print("Single-plane residual: %.5f / %.5f µm" % [lab.latest.amplitude_um, initial])

func _test_two_plane() -> void:
	var lab = _ready_lab(true)
	# Nonzero baseline proves that solution is relative to baseline configuration,
	# and application replaces trial masses with TOTAL required installed masses.
	lab.set_correction(0, 0.08, 40.0)
	lab.set_correction(1, 0.04, 120.0)
	_run(lab, "baseline")
	var initial: Array = lab.baseline.amplitudes_um.duplicate()
	_open(lab)
	lab.set_correction(0, 0.24, 90.0)
	_run(lab, "trial_a")
	_open(lab)
	lab.set_correction(0, 0.08, 40.0)
	lab.set_correction(1, 0.22, 0.0)
	_run(lab, "trial_b")
	_check(lab.solve_balance().ok, "Two-plane complex matrix solve")
	_check(lab.solution.condition_number < 5.0, "Independent trial matrix is well conditioned")
	_open(lab)
	_check(lab.apply_solution().ok, "Install total two-plane correction")
	_run(lab, "verify")
	_check(lab.latest.amplitudes_um[0] < initial[0] * 0.1, "Two-plane sensor A reduction >90%")
	_check(lab.latest.amplitudes_um[1] < initial[1] * 0.1, "Two-plane sensor B reduction >90%")
	_check(lab.latest.verified, "Two-plane verification accepted")
	print("Two-plane residuals: %s µm; condition %.3f" % [str(lab.latest.amplitudes_um), lab.solution.condition_number])

func _test_trial_validity() -> void:
	var lab = _ready_lab(true)
	lab.toggle_guard()
	_check(not lab.begin_run("trial_a").ok, "No trial without baseline")
	_run(lab, "baseline")
	_check(not lab.begin_run("trial_a").ok, "Zero trial rejected")
	_open(lab)
	lab.set_correction(0, 0.2, 0.0)
	lab.set_correction(1, 0.2, 90.0)
	lab.toggle_guard()
	_check(not lab.begin_run("trial_b").ok, "Trial B rejects retained plane A trial")
	_open(lab)
	lab.set_correction(1, 0.0, 0.0)
	lab.test_rpm = 1450.0
	lab.toggle_guard()
	_check(not lab.begin_run("trial_a").ok, "Trial rejects speed mismatch")
	lab.test_rpm = 1200.0
	_open(lab)
	lab.set_probe(12.0)
	_check(lab.baseline.is_empty(), "Probe change invalidates calibration")
	lab.toggle_guard()
	_check(not lab.begin_run().ok, "Bad probe standoff rejected")
	lab.set_probe(6.0)
	_run(lab, "baseline")
	lab.inject_fault("sensor")
	_check(lab.baseline.is_empty() and not lab.fault.is_empty(), "Sensor fault discards stale calibration")
	_check(not lab.begin_run().ok, "Fault blocks acquisition")
	_check(lab.reset_fault().ok and not lab.homed, "Fault reset requires probe rehome")
	lab.home_probe()
	lab.inject_fault("tach")
	_check(lab.fault == "Tachometer signal lost" and not lab.homed and lab.baseline.is_empty(), "Tach fault has correct label and invalidates setup")

func _test_bad_calibration() -> void:
	var lab = _ready_lab(true)
	_run(lab, "baseline")
	_open(lab)
	lab.set_correction(0, 0.2, 90.0)
	_run(lab, "trial_a")
	_open(lab)
	lab.set_correction(0, 0.0, 0.0)
	lab.set_correction(1, 0.2, 0.0)
	_run(lab, "trial_b")
	# Deliberately corrupted measured trials exercise the validation path. They
	# make both sensor responses identical, so the matrix loses rank.
	var base: Array = lab.baseline.phasors
	for record in [lab.trial_a, lab.trial_b]:
		var difference_re: float = record.phasors[0][0] - base[0][0]
		var difference_im: float = record.phasors[0][1] - base[0][1]
		record.phasors[1] = [base[1][0] + difference_re, base[1][1] + difference_im]
	_check(not lab.solve_balance().ok, "Nearly singular influence matrix rejected")
	_check(lab.solution.is_empty(), "No correction retained after singular solve")
	# A separate corrupted record with no measurable trial response.
	lab.trial_a.phasors = lab.baseline.phasors.duplicate(true)
	_check(not lab.solve_balance().ok, "Insufficient trial sensitivity rejected")

func _test_repeat_sweep_and_determinism() -> void:
	var lab = _ready_lab()
	_run(lab, "repeat")
	_check(lab.latest.repeatability.n == 3, "Three independent repeatability windows")
	_check(lab.latest.repeatability.sensor_a.sample_std_um > 0.0, "Sample standard deviation computed")
	_run(lab, "sweep")
	_check(lab.sweep_points.size() >= 18, "Sweep samples at least 18 speeds")
	_check(absf(lab.latest.peak.rpm - 1320.0) < 160.0, "Measured sweep resolves 22 Hz resonance")
	var first = _ready_lab()
	var second = _ready_lab()
	_run(first, "baseline")
	_run(second, "baseline")
	_check(first.baseline.phasors == second.baseline.phasors, "Fresh sessions are deterministic")
	var report: Dictionary = lab.report()
	_check(JSON.stringify(report).length() > 2000, "Report is JSON serializable with methodology and traces")

func _test_workflow_helpers_and_noninteger_speed() -> void:
	var lab = _ready_lab(true)
	_check(not lab.fit_trial(0).ok, "Trial helper needs a baseline")
	_check(lab.set_test_speed(1234.0).ok, "Noninteger revolution acquisition speed selected")
	lab.set_correction(0, 0.09, 24.0)
	lab.set_correction(1, 0.06, 175.0)
	_run(lab, "baseline")
	var initial: Array = lab.baseline.amplitudes_um.duplicate()
	_open(lab)
	_check(lab.fit_trial(0, 0.25, 90.0).ok, "Fit known A trial relative to nonzero baseline")
	_check(absf(lab.masses[1] - 0.06) < 0.00001, "Trial helper restores opposite baseline mass")
	_run(lab, "trial_a")
	_open(lab)
	_check(lab.fit_trial(1, 0.25, 0.0).ok, "Fit independent B trial")
	_check(absf(lab.masses[0] - 0.09) < 0.00001, "B trial removes prior A trial")
	_run(lab, "trial_b")
	_check(lab.solve_balance().ok, "Noninteger tach LS captures solve correctly")
	_open(lab)
	lab.apply_solution()
	_run(lab, "verify")
	_check(lab.latest.amplitudes_um[0] < initial[0] * 0.05 and lab.latest.amplitudes_um[1] < initial[1] * 0.05, "No DC/2x leakage at noninteger speed; both reductions >95%")
	_open(lab)
	lab.set_correction(0, 0.4, 10.0)
	_check(not lab.latest.verified, "Mass edit invalidates previous verification")
	_check(not lab.baseline.is_empty(), "Mass editing preserves trial calibration")
	_check(lab.set_test_speed(1500.0).ok and lab.baseline.is_empty() and lab.solution.is_empty(), "Speed setter clears stale calibration")
	_check(not lab.set_test_speed(1900.0).ok, "Out-of-range speed rejected")

func _drain_worker(lab) -> void:
	for step in range(10000):
		lab.tick(0.02)
		if not lab.processing:
			return
		OS.delay_msec(1)
	_check(false, "Worker joined within ten seconds")

func _test_async_acquisition() -> void:
	var sync_lab = _ready_lab()
	var threaded_lab = _ready_lab()
	threaded_lab.async_processing = true
	_run(sync_lab, "baseline")
	_run(threaded_lab, "baseline")
	_check(threaded_lab.baseline.phasors == sync_lab.baseline.phasors, "Worker capture matches synchronous phasors exactly")
	_check(threaded_lab.waveform == sync_lab.waveform and threaded_lab.spectrum == sync_lab.spectrum, "Worker waveform/DFT equal synchronous output")
	_run(sync_lab, "repeat")
	_run(threaded_lab, "repeat")
	_check(threaded_lab.latest.repeatability == sync_lab.latest.repeatability, "Worker repeatability windows match synchronous statistics exactly")
	_run(sync_lab, "sweep")
	_run(threaded_lab, "sweep")
	_check(threaded_lab.sweep_points == sync_lab.sweep_points, "Worker sweep points preserve acquisition speeds and RNG sequence")
	_check(threaded_lab.spectrum == sync_lab.spectrum, "Worker final sweep DFT matches synchronous result")
	# Stop/E-stop stays responsive while worker results remain private. A joined
	# cancelled worker must never publish a late baseline or verification pass.
	threaded_lab.begin_run("baseline")
	for step in range(200):
		threaded_lab.tick(0.02)
		if threaded_lab.processing:
			break
	_check(threaded_lab.processing, "Due acquisition starts a worker")
	_check(not threaded_lab.set_test_speed(900.0).ok, "Configuration edits inhibited during processing")
	_check(not threaded_lab.reset().ok, "Session reset waits for worker shutdown")
	threaded_lab.emergency_stop()
	_check(threaded_lab.estop and not threaded_lab.running, "E-stop remains immediate during processing")
	_drain_worker(threaded_lab)
	_check(threaded_lab.baseline.is_empty(), "Cancelled worker cannot republish stale calibration")
	threaded_lab.tick(2.0)
	_check(threaded_lab.reset().ok, "Session can reset after worker is joined")
