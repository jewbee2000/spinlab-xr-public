extends SceneTree
## Work-instruction evidence, automatic dwell, persistence and actual science.
const Tutorial = preload("res://scripts/lab_tutorial.gd")
const Science = preload("res://scripts/rotor_lab.gd")
var checks: int = 0
var failures: int = 0
var saved_report: bool = false

func _initialize() -> void:
	_test_content_and_navigation()
	_test_ordered_buffer_and_review()
	_test_capture_freshness()
	_test_action_boundaries()
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
		"latest": lab.latest.duplicate(true), "saved_report": saved_report, "grab_owners_empty": true}

func _go(tutorial, id: String) -> void:
	for unused in range(tutorial.steps.size()):
		if tutorial.steps[tutorial.index].id == id: return
		tutorial.skip_step()
	_check(false, "Instruction exists: " + id)

func _dwell(tutorial, snapshot: Dictionary) -> void:
	for unused in range(16):
		var result: Dictionary = tutorial.tick(0.1, snapshot)
		if result.advanced: return
	_check(false, "Ready instruction advances after readable dwell")

func _accepted(tutorial, lab, command: String, result: Dictionary) -> void:
	tutorial.observe(_context(lab), {"command": command, "ok": result.ok})

func _finish(tutorial, lab, id: String) -> void:
	var view: Dictionary = tutorial.view(_context(lab))
	_check(view.id == id, "Expected instruction " + id)
	_check(view.ready, "Completed physical work satisfies " + id)
	_dwell(tutorial, _context(lab))

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
	_check(tutorial.steps.size() == 15, "Fifteen practical stages replace UI orientation lessons")
	var ids: Dictionary = {}
	for step in tutorial.steps:
		_check(not ids.has(step.id), "Unique stage " + step.id)
		ids[step.id] = true
		_check(step.body.length() <= 200, "%s instruction remains digestible (%d chars)" % [step.id, step.body.length()])
		_check(step.theory.length() <= 200, "%s inline science remains digestible (%d chars)" % [step.id, step.theory.length()])
		_check(not step.gatehint.is_empty() and not step.target.is_empty(), "Stage has concrete fixture target " + step.id)
	_check(not ids.has("welcome") and not ids.has("touch") and not ids.has("comfort"), "No menu orientation is a required lesson")
	tutorial.start(ctx)
	var initial: Dictionary = tutorial.view(ctx)
	_check(initial.id == "load" and initial.active and initial.automatic and initial.total == 15, "First launch begins rotor seating work")
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
	_check(tutorial.view(ctx).ready and tutorial.index == 0, "Rotor seating begins visible success dwell")
	ctx.homed = true
	tutorial.observe(ctx, {"command": "home", "ok": true, "event_id": 1})
	ctx.guard_closed = true
	tutorial.observe(ctx, {"command": "guard", "ok": true, "event_id": 2})
	tutorial.tick(100, ctx)
	_check(tutorial.index == 0, "A huge frame delta cannot skip success dwell")
	_dwell(tutorial, ctx)
	_check(tutorial.view(ctx).id == "home" and tutorial.view(ctx).ready, "Buffered fresh HOME counts after seating")
	_check(tutorial.back().ok and tutorial.view(ctx).review, "X enters explicit review mode")
	var remaining: float = tutorial.view(ctx).success_remaining_s
	for unused in range(30): tutorial.tick(0.1, ctx)
	_check(tutorial.index == 0 and is_equal_approx(tutorial.view(ctx).success_remaining_s, remaining), "Review freezes unfinished work dwell")
	_check(tutorial.next(ctx).ok and tutorial.index == 1 and not tutorial.view(ctx).review, "A returns to unfinished work checkpoint")
	_dwell(tutorial, ctx)
	_check(tutorial.view(ctx).id == "guard" and tutorial.view(ctx).ready, "Buffered guard closure reaches its own instruction")
	_dwell(tutorial, ctx)
	_check(tutorial.view(ctx).id == "baseline" and not tutorial.view(ctx).ready, "Mechanical checks cannot chain into an old baseline")
	for unused in range(60): tutorial.tick(0.1, ctx)
	_check(tutorial.view(ctx).id == "baseline", "Waiting cannot pass a missing baseline")
	var mounted = Tutorial.new("")
	mounted.start(ctx)
	_check(mounted.view(ctx).ready, "Restart confirms already seated rotor")
	_dwell(mounted, ctx)
	_check(mounted.view(ctx).id == "home" and not mounted.view(ctx).ready, "Preexisting homing cannot satisfy fresh HOME")
	mounted.observe(ctx, {"command": "home", "ok": false})
	_check(not mounted.view(ctx).ready, "Rejected HOME cannot reuse an old reference")
	mounted.observe(ctx, {"command": "home", "ok": "true"})
	_check(not mounted.view(ctx).ready, "String success is not accepted boolean evidence")
	mounted.observe(ctx, {"command": "home", "ok": true})
	_check(mounted.view(ctx).ready, "New accepted HOME works with referenced fixture")
	# Regression: a successful reset while reviewing must clear even zero-record
	# HOME evidence; a record-ID reset detector alone cannot find this case.
	mounted.back()
	ctx.mounted = false
	ctx.homed = false
	ctx.guard_closed = false
	mounted.observe(ctx, {"command": "new", "ok": true})
	_check(mounted.view(ctx).id == "load" and not mounted.view(ctx).ready and not mounted.view(ctx).review, "New Session during review clears buffered HOME and review checkpoint")
	for unused in range(30): mounted.tick(0.1, ctx)
	_check(mounted.index == 0, "Unloaded reset cannot coast through stale mechanical success")

func _test_capture_freshness() -> void:
	for pair in [["baseline", "baseline"], ["trial_measure", "trial_a"], ["verify", "verify"], ["repeat", "repeat"]]:
		var ctx: Dictionary = _context(Science.new())
		ctx.mounted = true
		ctx.homed = true
		ctx.guard_closed = true
		ctx.solution = {"condition_number": 1.0, "masses_g": [0.0, 0.0], "angles_deg": [0.0, 0.0]}
		var record: Dictionary = {"id": 10, "kind": pair[1], "accepted": true, "repeatability": {"n": 3}}
		ctx.latest = record.duplicate(true)
		ctx.records = [record.duplicate(true)]
		if pair[1] in ["baseline", "trial_a"]: ctx[pair[1]] = record.duplicate(true)
		var tutorial = Tutorial.new("")
		tutorial.start(ctx)
		_go(tutorial, pair[0])
		tutorial.observe(ctx, {"command": pair[1], "ok": true})
		_check(not tutorial.view(ctx).ready, "%s rejects preexisting record despite new Start press" % pair[0])
		record.id = 11
		record.accepted = false
		ctx.latest = record.duplicate(true)
		if pair[1] in ["baseline", "trial_a"]: ctx[pair[1]] = record.duplicate(true)
		tutorial.observe(ctx)
		_check(not tutorial.view(ctx).ready, "%s rejects aborted record" % pair[0])
		record.accepted = true
		ctx.latest = record.duplicate(true)
		if pair[1] in ["baseline", "trial_a"]: ctx[pair[1]] = record.duplicate(true)
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
	ctx.solution = {"condition_number": 1.0, "masses_g": [0.4, 0.0], "angles_deg": [90.0, 0.0]}
	ctx.masses = [0.4, 0.0]
	ctx.angles = [90.0, 0.0]
	var tutorial = Tutorial.new("")
	tutorial.start(ctx)
	_go(tutorial, "verify")
	ctx.latest = {"id": 1, "kind": "verify", "accepted": true, "verified": false, "configuration_changed": true}
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

func _test_reset_and_preferences() -> void:
	var ctx: Dictionary = _context(Science.new())
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
	_dwell(reload, ctx)
	_check(reload.completed and not reload.active and not reload.startup_enabled, "Actual final save/dwell records completion and startup OFF")
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
	saved_report = false
	var lab = Science.new()
	var tutorial = Tutorial.new("")
	tutorial.start(_context(lab))
	_accepted(tutorial, lab, "mount", lab.mount_rotor())
	_finish(tutorial, lab, "load")
	_accepted(tutorial, lab, "home", lab.home_probe())
	_finish(tutorial, lab, "home")
	_accepted(tutorial, lab, "guard", lab.toggle_guard())
	_finish(tutorial, lab, "guard")
	_capture(lab, tutorial, "baseline")
	_finish(tutorial, lab, "baseline")
	_accepted(tutorial, lab, "guard", lab.toggle_guard())
	_finish(tutorial, lab, "open_trial")
	_accepted(tutorial, lab, "fit_trial", lab.fit_trial(0))
	_finish(tutorial, lab, "trial_fit")
	_accepted(tutorial, lab, "guard", lab.toggle_guard())
	_finish(tutorial, lab, "close_trial")
	_capture(lab, tutorial, "trial_a")
	_finish(tutorial, lab, "trial_measure")
	_accepted(tutorial, lab, "solve", lab.solve_balance())
	_finish(tutorial, lab, "solve")
	_accepted(tutorial, lab, "guard", lab.toggle_guard())
	_finish(tutorial, lab, "open_apply")
	_accepted(tutorial, lab, "apply", lab.apply_solution())
	_finish(tutorial, lab, "apply")
	_accepted(tutorial, lab, "guard", lab.toggle_guard())
	_finish(tutorial, lab, "close_verify")
	_capture(lab, tutorial, "verify")
	_finish(tutorial, lab, "verify")
	_check(float(lab.latest.get("reduction_percent", [0.0])[0]) > 95.0, "Real measured correction reduces sensor A vibration over95%")
	_capture(lab, tutorial, "repeat")
	_finish(tutorial, lab, "repeat")
	saved_report = true
	tutorial.observe(_context(lab), {"command": "save", "ok": true})
	var before: Dictionary = lab.report().duplicate(true)
	_finish(tutorial, lab, "report")
	_check(not tutorial.active and tutorial.completed and not tutorial.startup_enabled, "Actual measured procedure advances automatically through completion")
	_check(lab.records.size() == 4 and lab.report() == before, "Guide preserves four measured records and all fixture data")
