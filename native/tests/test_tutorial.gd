extends SceneTree
## Novice-course evidence, immediate progression, persistence and actual science.
const Tutorial = preload("res://scripts/lab_tutorial.gd")
const Science = preload("res://scripts/rotor_lab.gd")
var checks: int = 0
var failures: int = 0
var saved_report: bool = false
var chart_kind: String = "time"

func _initialize() -> void:
	_test_content_and_navigation()
	_test_ordered_buffer_and_review()
	_test_capture_freshness()
	_test_action_boundaries()
	_test_mass_restoration_prerequisites()
	_test_recalibration_recovery()
	_test_reset_and_preferences()
	_test_complete_measured_workflow()
	print("TUTORIAL TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TUTORIAL TEST: " + description)

func _context(lab) -> Dictionary:
	return {"mounted": lab.mounted, "homed": lab.homed, "guard_closed": lab.guard_closed, "estop": lab.estop, "fault": lab.fault,
		"rpm": lab.rpm, "running": lab.running, "processing": lab.processing, "sensor_position_mm": lab.sensor_position_mm,
		"masses": lab.masses.duplicate(), "angles": lab.angles.duplicate(), "radius_mm": lab.radius_mm, "mode": lab.mode, "active_plane": lab.active_plane,
		"test_rpm": lab.test_rpm, "records": lab.records.duplicate(true), "baseline": lab.baseline.duplicate(true), "trial_a": lab.trial_a.duplicate(true), "solution": lab.solution.duplicate(true),
		"latest": lab.latest.duplicate(true), "trial_b": lab.trial_b.duplicate(true), "chart_kind": chart_kind, "waveform_count": lab.waveform.size(), "spectrum_count": lab.spectrum.size(), "sweep_count": lab.sweep_points.size(), "saved_report": saved_report, "grab_owners_empty": true}

func _go(tutorial, id: String) -> void:
	for unused in range(tutorial.steps.size()):
		if tutorial.steps[tutorial.index].id == id: return
		tutorial.skip_step()
	_check(false, "Instruction exists: " + id)

func _advance_ready(tutorial, snapshot: Dictionary) -> void:
	var before: int = tutorial.index
	var result: Dictionary = tutorial.tick(0.0, snapshot)
	_check(result.advanced, "Correct physical work advances immediately without a timer or speech event")
	_check(tutorial.index <= before + 1, "One process tick advances at most one instruction")

func _accepted(tutorial, lab, command: String, result: Dictionary) -> void:
	tutorial.observe(_context(lab), {"command": command, "ok": result.ok})

func _finish(tutorial, lab, id: String) -> void:
	var view: Dictionary = tutorial.view(_context(lab))
	_check(view.id == id, "Expected instruction " + id)
	_check(view.ready, "Completed physical work satisfies " + id)
	_advance_ready(tutorial, _context(lab))

func _capture(lab, tutorial, kind: String) -> void:
	_check(lab.begin_run(kind).ok, "Actual science starts " + kind)
	for unused in range(1000):
		lab.tick(0.02)
		tutorial.observe(_context(lab))
		if not lab.running and not lab.processing and lab.rpm < 0.1: break
	_check(not lab.running and not lab.processing and lab.rpm < 0.1 and lab.latest.get("kind", "") == kind, "Actual science completes capture and coast " + kind)

func _test_content_and_navigation() -> void:
	var lab = Science.new()
	var ctx: Dictionary = _context(lab)
	var original: Dictionary = ctx.duplicate(true)
	var tutorial = Tutorial.new("")
	_check(tutorial.steps.size() == 38, "Thirty-eight short experiments teach the complete two-plane activity")
	var ids: Dictionary = {}
	for step in tutorial.steps:
		_check(not ids.has(step.id), "Unique stage " + step.id)
		ids[step.id] = true
		_check(step.body.length() <= 250, "%s instruction remains digestible (%d chars)" % [step.id, step.body.length()])
		_check(step.theory.length() <= 250, "%s inline science remains digestible (%d chars)" % [step.id, step.theory.length()])
		_check(not step.gatehint.is_empty() and not step.target.is_empty(), "Stage has concrete fixture target " + step.id)
	_check(not ids.has("welcome") and not ids.has("touch") and not ids.has("comfort"), "No menu orientation is a required lesson")
	tutorial.start(ctx)
	var initial: Dictionary = tutorial.view(ctx)
	_check(initial.id == "load" and initial.active and initial.automatic and initial.total == 38, "First launch begins rotor seating work")
	_check(not initial.ready and not tutorial.next(ctx).ok and tutorial.index == 0, "Unloaded first step cannot be bypassed with A")
	_check(not tutorial.back().ok, "Review cannot underflow")
	for unused in range(100): tutorial.view(ctx)
	_check(tutorial.index == 0 and not tutorial.view(ctx).ready, "Rendering never advances or manufactures evidence")
	tutorial.tick(100.0, ctx)
	_check(tutorial.index == 0, "Elapsed time cannot satisfy missing work")
	tutorial.skip_step()
	_check(tutorial.index == 1 and tutorial.view(ctx).id == "home", "Explicit Skip advances only the requested instruction")
	tutorial.skip()
	tutorial.observe(ctx, {"command": "home", "ok": true})
	_check(not tutorial.active and tutorial.should_autostart() and not tutorial.completed, "Pause preserves preference without claiming completion")
	tutorial.start(ctx)
	_check(tutorial.index == 0 and not tutorial.view(ctx).ready, "Restart clears transient work evidence only")
	_check(ctx == original and not lab.mounted and lab.records.is_empty(), "Guide actions never modify fixture or source snapshot")
	_check(initial.body == initial.what and initial.theory == initial.why, "View aliases carry identical instruction and science")

func _test_ordered_buffer_and_review() -> void:
	var ctx: Dictionary = _context(Science.new())
	var tutorial = Tutorial.new("")
	tutorial.start(ctx)
	ctx.mounted = true
	tutorial.observe(ctx, {"command": "mount", "ok": true})
	_check(tutorial.view(ctx).ready and tutorial.index == 0, "Observation records the load without advancing presentation")
	ctx.homed = true
	tutorial.observe(ctx, {"command": "home", "ok": true, "event_id": 1})
	tutorial.tick(100, ctx)
	_check(tutorial.index == 1 and tutorial.view(ctx).id == "home" and tutorial.view(ctx).ready, "A long frame advances once and preserves the ordered fresh HOME")
	_check(tutorial.back().ok and tutorial.view(ctx).review, "X enters explicit review mode")
	for unused in range(30): tutorial.tick(0.1, ctx)
	_check(tutorial.index == 0, "Review freezes the unfinished work checkpoint")
	_check(tutorial.next(ctx).ok and tutorial.index == 1 and not tutorial.view(ctx).review, "A returns to the actual work checkpoint")
	_advance_ready(tutorial, ctx)
	_check(tutorial.view(ctx).id == "probe_adjust" and not tutorial.view(ctx).ready, "Buffered HOME cannot manufacture a micrometer movement")
	for unused in range(60): tutorial.tick(0.1, ctx)
	_check(tutorial.view(ctx).id == "probe_adjust", "Time alone cannot move the micrometer")
	var mounted = Tutorial.new("")
	mounted.start(ctx)
	_check(mounted.view(ctx).ready, "Restart confirms an already seated rotor")
	_advance_ready(mounted, ctx)
	_check(mounted.view(ctx).id == "home" and not mounted.view(ctx).ready, "Preexisting homing cannot satisfy fresh HOME")
	mounted.observe(ctx, {"command": "home", "ok": false})
	_check(not mounted.view(ctx).ready, "Rejected HOME cannot reuse an old reference")
	mounted.observe(ctx, {"command": "home", "ok": "true"})
	_check(not mounted.view(ctx).ready, "String success is not accepted boolean evidence")
	mounted.observe(ctx, {"command": "home", "ok": true})
	_check(mounted.view(ctx).ready, "A fresh accepted HOME works with a referenced fixture")
	mounted.back();ctx.mounted = false;ctx.homed = false;ctx.guard_closed = false
	mounted.observe(ctx, {"command": "new", "ok": true})
	_check(mounted.view(ctx).id == "load" and not mounted.view(ctx).ready and not mounted.view(ctx).review, "New Session during review clears buffered HOME and the review checkpoint")
	for unused in range(30): mounted.tick(0.1, ctx)
	_check(mounted.index == 0, "Unloaded reset cannot advance through stale mechanical evidence")
	_test_exploration_evidence()

func _test_exploration_evidence() -> void:
	var ctx: Dictionary = _context(Science.new())
	ctx.mounted = true;ctx.homed = true
	var tutorial = Tutorial.new("");tutorial.start(ctx);_go(tutorial, "probe_adjust")
	ctx.sensor_position_mm = 6.05
	tutorial.observe(ctx, {"command": "dial:probe", "ok": true})
	_check(not tutorial.view(ctx).ready, "Micrometer exercise requires a noticeable actual movement")
	ctx.sensor_position_mm = 6.10;ctx.grab_owners_empty = false
	tutorial.observe(ctx, {"command": "dial:probe", "ok": true})
	_check(not tutorial.view(ctx).ready, "Held micrometer does not advance before release")
	ctx.grab_owners_empty = true;tutorial.observe(ctx)
	_check(tutorial.view(ctx).ready, "Actual valid 0.10mm micrometer travel and release satisfy the experiment")
	var order = Tutorial.new("");ctx.mode = "two_plane";ctx.baseline = {"id": 1};order.start(ctx);_go(order, "chart_order")
	ctx.chart_kind = "order";order.observe(ctx, {"command": "chart", "ok": true})
	_check(not order.view(ctx).ready, "Empty spectrum never counts as a graph lesson")
	ctx.spectrum_count = 101;order.observe(ctx)
	_check(order.view(ctx).ready, "Selected order view needs actual captured spectrum data")
	var safety = Tutorial.new("");safety.start(ctx);_go(safety, "estop")
	safety.observe(ctx, {"command": "estop", "ok": true})
	_check(not safety.view(ctx).ready, "E-stop exercise requires the real latched state")
	ctx.estop = true;safety.observe(ctx)
	_check(safety.view(ctx).ready, "Deliberate E-stop lesson recognizes the latched state")
	_advance_ready(safety, ctx)
	ctx.estop = false;ctx.fault = "Sensor dropout"
	safety.observe(ctx, {"command": "recover", "ok": true})
	_check(not safety.view(ctx).ready, "Releasing E-stop cannot hide a separate sensor fault")
	ctx.fault = "";safety.observe(ctx, {"command": "recover", "ok": true})
	_check(safety.view(ctx).ready, "Recovery waits for both latch and fault to clear")

func _test_capture_freshness() -> void:
	for pair in [["baseline", "baseline"], ["trial_measure", "trial_a"], ["trial_measure_b", "trial_b"], ["sweep", "sweep"], ["verify", "verify"], ["repeat", "repeat"]]:
		var ctx: Dictionary = _context(Science.new())
		ctx.mode = "two_plane"
		ctx.mounted = true
		ctx.homed = true
		ctx.guard_closed = true
		ctx.solution = {"condition_number": 1.0, "masses_g": [0.0, 0.0], "angles_deg": [0.0, 0.0]}
		var record: Dictionary = {"id": 10, "kind": pair[1], "accepted": true, "repeatability": {"n": 3}, "points": [{}, {}, {}]}
		ctx.sweep_count = 3
		if pair[1] in ["trial_a", "trial_b"]:
			ctx.baseline = {"id": 9, "accepted": true, "masses": [0.0, 0.0], "angles": [0.0, 0.0]}
			ctx.masses = [0.25, 0.0] if pair[1] == "trial_a" else [0.0, 0.25]
			record.masses = ctx.masses.duplicate();record.angles = [0.0, 0.0]
		ctx.latest = record.duplicate(true)
		ctx.records = [record.duplicate(true)]
		if pair[1] in ["baseline", "trial_a", "trial_b"]: ctx[pair[1]] = record.duplicate(true)
		var tutorial = Tutorial.new("")
		tutorial.start(ctx)
		_go(tutorial, pair[0])
		tutorial.observe(ctx, {"command": pair[1], "ok": true})
		_check(not tutorial.view(ctx).ready, "%s rejects preexisting record despite new Start press" % pair[0])
		record.id = 11
		record.accepted = false
		ctx.latest = record.duplicate(true)
		if pair[1] in ["baseline", "trial_a", "trial_b"]: ctx[pair[1]] = record.duplicate(true)
		tutorial.observe(ctx)
		_check(not tutorial.view(ctx).ready, "%s rejects aborted record" % pair[0])
		record.accepted = true
		ctx.latest = record.duplicate(true)
		if pair[1] in ["baseline", "trial_a", "trial_b"]: ctx[pair[1]] = record.duplicate(true)
		ctx.rpm = 0.2
		tutorial.observe(ctx)
		_check(not tutorial.view(ctx).ready, "%s waits for visible zero" % pair[0])
		ctx.rpm = 0.0
		ctx.processing = true
		tutorial.observe(ctx)
		_check(not tutorial.view(ctx).ready, "%s waits for analysis" % pair[0])
		ctx.processing = false
		tutorial.observe(ctx)
		_check(tutorial.view(ctx).ready, "%s accepts new complete data at zero" % pair[0])
		ctx.fault = "Sensor dropout"
		_check(not tutorial.view(ctx).ready, "%s cannot complete during fault" % pair[0])
		tutorial.tick(0.1, ctx)
		_check(not tutorial._ready, "%s cancels pending success on fault" % pair[0])
	var ctx: Dictionary = _context(Science.new())
	ctx.mode = "two_plane"
	ctx.solution = {"condition_number": 1.0, "masses_g": [0.4, 0.0], "angles_deg": [90.0, 0.0]}
	ctx.masses = [0.4, 0.0]
	ctx.angles = [90.0, 0.0]
	var tutorial = Tutorial.new("")
	tutorial.start(ctx)
	_go(tutorial, "verify")
	ctx.latest = {"id": 1, "kind": "verify", "accepted": true, "verified": false, "configuration_changed": true, "masses": [0.4, 0.0], "angles": [90.0, 0.0]}
	tutorial.observe(ctx)
	_check(not tutorial.view(ctx).ready, "Changed-configuration verification never satisfies work")
	ctx.latest.configuration_changed = false
	ctx.masses[0] = 0.5
	tutorial.observe(ctx)
	_check(not tutorial.view(ctx).ready, "Manual mass edit cannot verify calculated correction")
	ctx.masses[0] = 0.4
	tutorial.observe(ctx)
	_check(tutorial.view(ctx).ready, "Fresh failed reduction is honest measured result with solution installed")

func _test_action_boundaries() -> void:
	var ctx: Dictionary = _context(Science.new())
	ctx.mode = "two_plane"
	ctx.baseline = {"id": 1, "accepted": true, "masses": [0.0, 0.0], "angles": [0.0, 0.0]}
	ctx.latest = ctx.baseline.duplicate(true)
	ctx.records = [ctx.baseline.duplicate(true)]
	var tutorial = Tutorial.new("")
	tutorial.start(ctx)
	_go(tutorial, "trial_fit")
	ctx.masses = [0.25, 0.25]
	tutorial.observe(ctx, {"command": "fit_trial", "ok": true})
	_check(not tutorial.view(ctx).ready, "Known trial cannot change both planes")
	ctx.masses = [0.25, 0.0]
	tutorial.observe(ctx)
	_check(tutorial.view(ctx).ready, "Independent A trial preserves other baseline plane")
	var solve = Tutorial.new("")
	solve.start(ctx)
	_go(solve, "solve")
	ctx.solution = {"condition_number": 31.0, "masses_g": [0.4, 0.0], "angles_deg": [90.0, 0.0]}
	solve.observe(ctx, {"command": "solve", "ok": true})
	_check(not solve.view(ctx).ready, "Ill-conditioned solution is rejected")
	ctx.solution.condition_number = 1.0
	solve.observe(ctx)
	_check(solve.view(ctx).ready, "Accepted solve plus usable measured solution satisfy identification")
	var apply = Tutorial.new("")
	apply.start(ctx)
	_go(apply, "apply")
	ctx.masses = [0.4, 0.0]
	ctx.angles = [90.0, 0.0]
	ctx.latest.configuration_changed = true
	apply.observe(ctx, {"target": "apply", "kind": "pointer", "ok": false})
	_check(not apply.view(ctx).ready, "Raw prevalidation contact cannot claim Apply")
	apply.observe(ctx, {"command": "apply", "ok": false})
	_check(not apply.view(ctx).ready, "Rejected Apply cannot claim installed solution")
	apply.observe(ctx, {"command": "apply", "ok": true})
	_check(apply.view(ctx).ready, "Actual Apply ignores an old stale Verify display")
	var report = Tutorial.new("")
	ctx.saved_report = true
	report.start(ctx)
	_go(report, "report")
	report.observe(ctx, {"target": "save", "kind": "pointer", "ok": false})
	_check(not report.view(ctx).ready, "Raw contact and old file cannot claim a new save")
	report.observe(ctx, {"command": "save", "ok": false})
	_check(not report.view(ctx).ready, "Failed file output does not complete guide")
	ctx.saved_report = false
	report.observe(ctx, {"command": "save", "ok": true})
	_check(not report.view(ctx).ready, "Accepted command requires actual file output")
	ctx.saved_report = true
	report.observe(ctx)
	_check(report.view(ctx).ready, "Successful save plus file state complete reporting")

func _test_mass_restoration_prerequisites() -> void:
	for plane in range(2):
		var ctx: Dictionary = _context(Science.new())
		ctx.mode = "two_plane";ctx.mounted = true;ctx.homed = true;ctx.guard_closed = true
		ctx.baseline = {"id": 1, "kind": "baseline", "accepted": true, "masses": [0.0, 0.0], "angles": [0.0, 0.0]}
		ctx.latest = ctx.baseline.duplicate(true);ctx.records = [ctx.baseline.duplicate(true)]
		var tutorial = Tutorial.new("");tutorial.start(ctx);_go(tutorial, "trial_measure" if plane == 0 else "trial_measure_b")
		var before: Dictionary = ctx.duplicate(true)
		_check(tutorial.view(ctx).prompt_id == "open_setup" and ctx == before, "Missing trial targets guard opening without installing anything")
		ctx.guard_closed = false;ctx.active_plane = 1 - plane
		_check(tutorial.view(ctx).target == "plane", "A wrong editor plane is corrected before fitting the requested trial")
		ctx.active_plane = plane
		_check(tutorial.view(ctx).prompt_id == ("trial_fit" if plane == 0 else "trial_fit_b"), "Correct editor selects the appropriate known-trial helper")
		ctx.masses = [0.5, 0.0] if plane == 0 else [0.0, 0.5]
		var wrong: Dictionary = {"id": 2, "kind": "trial_a" if plane == 0 else "trial_b", "accepted": true, "masses": ctx.masses.duplicate(), "angles": [0.0, 0.0]}
		ctx["trial_a" if plane == 0 else "trial_b"] = wrong;ctx.latest = wrong
		tutorial.observe(ctx)
		_check(not tutorial.view(ctx).ready, "A different accepted trial mass does not silently replace this lesson's known0.250g experiment")
		ctx.masses = [0.25, 0.0] if plane == 0 else [0.0, 0.25];ctx.guard_closed = true
		tutorial.observe(ctx, {"command": "fit_trial", "ok": true})
		_check(not tutorial.view(ctx).ready, "Restoring the installed trial cannot relabel the previous wrong-configuration capture")
		var fresh: Dictionary = wrong.duplicate(true);fresh.id = 3;fresh.masses = ctx.masses.duplicate()
		ctx["trial_a" if plane == 0 else "trial_b"] = fresh;ctx.latest = fresh
		tutorial.observe(ctx)
		_check(tutorial.view(ctx).ready, "Only a fresh capture of the restored known trial completes its measurement lesson")
	for stage in ["sweep", "verify", "repeat"]:
		var ctx: Dictionary = _context(Science.new())
		ctx.mode = "two_plane";ctx.mounted = true;ctx.homed = true;ctx.guard_closed = true
		ctx.solution = {"condition_number": 1.0, "masses_g": [0.4, 0.0], "angles_deg": [90.0, 0.0]}
		ctx.masses = [0.5, 0.0];ctx.angles = [90.0, 0.0];ctx.sweep_count = 3
		var tutorial = Tutorial.new("");tutorial.start(ctx);_go(tutorial, stage)
		_check(tutorial.view(ctx).prompt_id == "open_setup", stage + " directs guard opening for an accidentally edited correction")
		ctx.guard_closed = false
		_check(tutorial.view(ctx).prompt_id == "apply", stage + " directs the actual Apply helper after access is open")
		ctx.latest = {"id": 1, "kind": stage, "accepted": true, "masses": [0.5, 0.0], "angles": [90.0, 0.0], "points": [{}, {}, {}], "repeatability": {"n": 3}}
		tutorial.observe(ctx)
		_check(not tutorial.view(ctx).ready, stage + " cannot qualify an uncorrected installed state")
		ctx.masses = [0.4, 0.0];ctx.guard_closed = true
		tutorial.observe(ctx, {"command": "apply", "ok": true})
		_check(not tutorial.view(ctx).ready, stage + " requires fresh corrected data after Apply rather than relabeling an old capture")
		ctx.latest.id = 2;ctx.latest.masses = [0.4, 0.0]
		tutorial.observe(ctx)
		_check(tutorial.view(ctx).ready, stage + " accepts the new capture of the restored solution")

func _test_recalibration_recovery() -> void:
	var ctx: Dictionary = _context(Science.new())
	ctx.mode = "two_plane";ctx.mounted = true;ctx.homed = true;ctx.guard_closed = true
	ctx.baseline = {"id": 5, "kind": "baseline", "accepted": true, "rpm": 1200.0, "sensor_position_mm": 6.0, "radius_mm": 30.0, "mode": "two_plane"}
	ctx.latest = ctx.baseline.duplicate(true);ctx.records = [ctx.baseline.duplicate(true)]
	var tutorial = Tutorial.new("");tutorial.start(ctx);_go(tutorial, "trial_fit")
	var historical: Array = ctx.records.duplicate(true)
	tutorial.observe(ctx, {"command": "dial:probe", "ok": false})
	_check(tutorial.view(ctx).id == "trial_fit", "Rejected probe command cannot rewind the course")
	tutorial.observe(ctx, {"command": "dial:probe", "ok": true, "changed": false})
	_check(tutorial.view(ctx).id == "trial_fit", "Accepted unchanged probe command keeps valid calibration")
	ctx.sensor_position_mm = 6.10;ctx.baseline = {}
	tutorial.observe(ctx, {"command": "dial:probe", "ok": true, "changed": true})
	_check(tutorial.view(ctx).id == "baseline" and not tutorial.view(ctx).ready, "Actual calibration invalidation returns to a fresh-baseline checkpoint")
	_check(ctx.records == historical, "Read-only recovery preserves all historical captures")
	ctx.baseline = historical[0].duplicate(true);ctx.sensor_position_mm = 6.0
	tutorial.observe(ctx)
	_check(not tutorial.view(ctx).ready, "An old compatible baseline cannot satisfy the new entry record checkpoint")
	ctx.baseline.id = 6;ctx.latest = ctx.baseline.duplicate(true);ctx.records.append(ctx.baseline.duplicate(true))
	tutorial.observe(ctx);_check(tutorial.view(ctx).ready, "Recovery requires a new accepted baseline ID")
	_advance_ready(tutorial, ctx);_go(tutorial, "trial_measure")
	ctx.mode = "single" # Existing object now conflicts with actual setup.
	tutorial.observe(ctx)
	_check(tutorial.view(ctx).id == "baseline" and tutorial.view(ctx).prompt_id == "mode_two", "An observed incompatible baseline directs method restoration and recalibration")
	ctx.mode = "two_plane";ctx.baseline = {};ctx.homed = false;ctx.estop = true
	tutorial.observe(ctx, {"command": "estop", "ok": true})
	_check(tutorial.view(ctx).id == "baseline" and tutorial.view(ctx).prompt_id == "recover", "Recovery prerequisite targets RECOVER while keeping fresh-baseline work")
	ctx.estop = false;tutorial.observe(ctx, {"command": "recover", "ok": true})
	_check(tutorial.view(ctx).prompt_id == "rehome", "No automatic rehome is claimed after E-stop release")
	ctx.homed = true;tutorial.observe(ctx, {"command": "home", "ok": true})
	_check(tutorial.view(ctx).prompt_id == "baseline" and not tutorial.view(ctx).ready, "Fresh HOME exposes the actual new measurement task")

func _test_reset_and_preferences() -> void:
	var ctx: Dictionary = _context(Science.new())
	ctx.mode = "two_plane"
	ctx.latest = {"id": 50, "kind": "baseline", "accepted": true}
	ctx.records = [ctx.latest.duplicate(true)]
	var tutorial = Tutorial.new("")
	tutorial.start(ctx)
	_go(tutorial, "verify")
	tutorial.observe(ctx, {"command": "new", "ok": false})
	_check(tutorial.view(ctx).id == "verify", "Rejected New Session preserves position")
	ctx.latest = {}
	ctx.records = []
	tutorial.observe(ctx, {"command": "new", "ok": true})
	_check(tutorial.view(ctx).id == "load" and not tutorial.view(ctx).ready, "Successful reset clears old evidence")
	_go(tutorial, "baseline")
	ctx.baseline = {"id": 1, "kind": "baseline", "accepted": true}
	ctx.latest = ctx.baseline.duplicate(true)
	tutorial.observe(ctx)
	_check(tutorial.view(ctx).ready, "New session records restart at one without stale-ID deadlock")
	var path: String = "user://work-guide-test-%d.cfg" % Time.get_ticks_usec()
	var prefs = Tutorial.new(path)
	prefs.start(ctx)
	prefs.skip()
	_check(not FileAccess.file_exists(path), "Default/start/pause do not write preferences")
	_check(prefs.set_startup(false).ok and FileAccess.file_exists(path), "Explicit startup choice persists")
	var reload = Tutorial.new(path)
	_check(not reload.should_autostart() and not reload.completed, "Startup OFF reloads accurately")
	reload.start(ctx)
	_go(reload, "report")
	ctx.saved_report = true
	reload.observe(ctx, {"command": "save", "ok": true})
	_advance_ready(reload, ctx)
	_check(reload.completed and not reload.active and not reload.startup_enabled, "Actual final save records completion and startup OFF")
	var completed_copy = Tutorial.new(path)
	_check(completed_copy.completed and not completed_copy.should_autostart(), "Completion preferences survive reload")
	completed_copy.start(ctx)
	_check(completed_copy.completed and completed_copy.view(ctx).id == "load" and not completed_copy.view(ctx).is_last, "Replay preserves history but begins first instruction")
	completed_copy.set_startup(true)
	var opted_in = Tutorial.new(path)
	_check(opted_in.completed and opted_in.should_autostart(), "Explicit startup ON is honored after completion")
	var before_pause: String = FileAccess.get_file_as_string(path)
	opted_in.start(ctx)
	opted_in.skip()
	_check(FileAccess.get_file_as_string(path) == before_pause, "Pause does not rewrite history or preferences")
	var skipped = Tutorial.new("")
	skipped.start(ctx)
	_go(skipped, "report")
	skipped.skip_step()
	_check(not skipped.active and not skipped.completed and skipped.startup_enabled, "Final Skip cannot manufacture completed reporting")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Isolated preference is removed")

func _test_complete_measured_workflow() -> void:
	saved_report = false;chart_kind = "time"
	var lab = Science.new()
	var tutorial = Tutorial.new("");tutorial.start(_context(lab))
	_accepted(tutorial, lab, "mount", lab.mount_rotor());_finish(tutorial, lab, "load")
	_accepted(tutorial, lab, "home", lab.home_probe());_finish(tutorial, lab, "home")
	_accepted(tutorial, lab, "dial:probe", lab.set_probe(6.10));_finish(tutorial, lab, "probe_adjust")
	_accepted(tutorial, lab, "home", lab.home_probe());_finish(tutorial, lab, "probe_restore")
	_finish(tutorial, lab, "open_setup")
	_accepted(tutorial, lab, "dial:mass", lab.set_correction(0, 0.08, 0.0));_finish(tutorial, lab, "mass_practice")
	_accepted(tutorial, lab, "dial:angle", lab.set_correction(0, 0.08, 30.0));_finish(tutorial, lab, "angle_practice")
	_accepted(tutorial, lab, "dial:mass", lab.set_correction(0, 0.0, 30.0));_finish(tutorial, lab, "clear_mass")
	_accepted(tutorial, lab, "mode", lab.set_mode("two_plane"));_finish(tutorial, lab, "mode_two")
	lab.active_plane = 1;_accepted(tutorial, lab, "plane", {"ok": true});_finish(tutorial, lab, "plane_b")
	lab.active_plane = 0;_accepted(tutorial, lab, "plane", {"ok": true});_finish(tutorial, lab, "plane_a")
	_accepted(tutorial, lab, "speed", lab.set_test_speed(1500));_finish(tutorial, lab, "speed_explore")
	_accepted(tutorial, lab, "speed", lab.set_test_speed(900))
	_check(not tutorial.view(_context(lab)).ready, "900RPM is not the selected 1200RPM reference")
	_accepted(tutorial, lab, "speed", lab.set_test_speed(1200));_finish(tutorial, lab, "speed_restore")
	_accepted(tutorial, lab, "guard", lab.toggle_guard());_finish(tutorial, lab, "guard")
	_accepted(tutorial, lab, "sweep", lab.begin_run("sweep"));_finish(tutorial, lab, "preview_start")
	lab.tick(0.1);_accepted(tutorial, lab, "stop", lab.stop())
	for unused in range(100):lab.tick(0.02);tutorial.observe(_context(lab))
	_finish(tutorial, lab, "stop")
	_check(lab.records.is_empty(), "STOP exercise does not fabricate a complete capture")
	_accepted(tutorial, lab, "estop", lab.emergency_stop());_finish(tutorial, lab, "estop")
	_accepted(tutorial, lab, "recover", lab.release_estop());_finish(tutorial, lab, "recover")
	_accepted(tutorial, lab, "home", lab.home_probe());_finish(tutorial, lab, "rehome")
	_capture(lab, tutorial, "baseline");_finish(tutorial, lab, "baseline")
	chart_kind = "order";_accepted(tutorial, lab, "chart", {"ok": true});_finish(tutorial, lab, "chart_order")
	_accepted(tutorial, lab, "guard", lab.toggle_guard());_finish(tutorial, lab, "open_trial")
	_accepted(tutorial, lab, "fit_trial", lab.fit_trial(0));_finish(tutorial, lab, "trial_fit")
	_accepted(tutorial, lab, "guard", lab.toggle_guard());_finish(tutorial, lab, "close_trial")
	_capture(lab, tutorial, "trial_a");_finish(tutorial, lab, "trial_measure")
	_accepted(tutorial, lab, "guard", lab.toggle_guard());_finish(tutorial, lab, "open_trial_b")
	lab.active_plane = 1;_accepted(tutorial, lab, "plane", {"ok": true});_finish(tutorial, lab, "plane_b_trial")
	_accepted(tutorial, lab, "fit_trial", lab.fit_trial(1));_finish(tutorial, lab, "trial_fit_b")
	_accepted(tutorial, lab, "guard", lab.toggle_guard());_finish(tutorial, lab, "close_trial_b")
	_capture(lab, tutorial, "trial_b");_finish(tutorial, lab, "trial_measure_b")
	_accepted(tutorial, lab, "solve", lab.solve_balance());_finish(tutorial, lab, "solve")
	_accepted(tutorial, lab, "guard", lab.toggle_guard());_finish(tutorial, lab, "open_apply")
	_accepted(tutorial, lab, "apply", lab.apply_solution());_finish(tutorial, lab, "apply")
	_accepted(tutorial, lab, "guard", lab.toggle_guard());_finish(tutorial, lab, "close_verify")
	_capture(lab, tutorial, "sweep");_finish(tutorial, lab, "sweep")
	_capture(lab, tutorial, "verify");_finish(tutorial, lab, "verify")
	_check(float(lab.latest.get("reduction_percent", [0.0, 0.0])[0]) > 95.0 and float(lab.latest.get("reduction_percent", [0.0, 0.0])[1]) > 95.0, "Two measured trial columns reduce BOTH support vibrations over95%")
	_capture(lab, tutorial, "repeat");_finish(tutorial, lab, "repeat")
	saved_report = true;tutorial.observe(_context(lab), {"command": "save", "ok": true})
	var before: Dictionary = lab.report().duplicate(true);_finish(tutorial, lab, "report")
	_check(not tutorial.active and tutorial.completed and not tutorial.startup_enabled, "Actual complete two-plane experiment advances automatically through reporting")
	_check(lab.records.size() == 6 and lab.report() == before, "Guide preserves all six accepted records, valid calibration and installed correction")
