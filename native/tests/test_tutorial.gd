extends SceneTree
## Pure tutorial state, persistence, and real numerical-workflow integration.
const Tutorial = preload("res://scripts/lab_tutorial.gd")
const Science = preload("res://scripts/rotor_lab.gd")
var checks: int = 0
var failures: int = 0
var _chart_kind: String = "sweep"
var _saved_report: bool = false

func _initialize() -> void:
	_test_content_and_navigation()
	_test_preferences()
	_test_rejected_and_stale_gates()
	_test_new_session_record_ids()
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
		"masses": lab.masses, "angles": lab.angles, "radius_mm": lab.radius_mm, "mode": lab.mode, "active_plane": lab.active_plane,
		"records": lab.records, "baseline": lab.baseline, "trial_a": lab.trial_a, "trial_b": lab.trial_b, "solution": lab.solution,
		"latest": lab.latest, "chart_kind": _chart_kind, "saved_report": _saved_report, "grab_owners_empty": true,
		"reach_assist": false, "exploded": false, "sound_on": false, "coach": true, "tab": "operate"}

func _go(tutorial, id: String) -> void:
	for step_index in range(tutorial.steps.size()):
		if tutorial.steps[tutorial.index].id == id:
			return
		tutorial.skip_step()
	_check(false, "Lesson exists: " + id)

func _accepted(tutorial, lab, command: String, result: Dictionary, extra: Dictionary = {}) -> void:
	var event: Dictionary = {"command": command, "ok": result.ok}
	event.merge(extra, true)
	tutorial.observe(_context(lab), event)

func _advance(tutorial, lab, id: String) -> void:
	var current: Dictionary = tutorial.view(_context(lab))
	_check(current.id == id, "Expected lesson: " + id)
	_check(current.ready, "Completed practice unlocks " + id)
	_check(tutorial.next(_context(lab)).ok, "Next advances " + id)

func _capture(lab, kind: String, tutorial = null) -> void:
	_check(lab.begin_run(kind).ok, "Real lab starts " + kind)
	for sample_index in range(800):
		lab.tick(0.02)
		if tutorial != null:
			tutorial.observe(_context(lab))
		if not lab.running and lab.rpm < 1.0:
			break
	_check(not lab.running and lab.rpm < 1.0 and lab.latest.get("kind", "") == kind, "Real lab completes " + kind)

func _test_content_and_navigation() -> void:
	var tutorial = Tutorial.new("")
	var lab = Science.new()
	var snapshot: Dictionary = _context(lab)
	var preserved: Dictionary = snapshot.duplicate(true)
	_check(tutorial.steps.size() == 23, "Tour provides 23 focused lessons")
	var seen: Dictionary = {}
	for step in tutorial.steps:
		_check(not seen.has(step.id), "Lesson identifier is unique: " + step.id)
		seen[step.id] = true
		_check(step.body.length() <= 250, "%s body fits concise spatial panel (%d characters)" % [step.id, step.body.length()])
		_check(step.theory.length() <= 250, "%s theory fits concise spatial panel (%d characters)" % [step.id, step.theory.length()])
		_check(["operate", "balance", "diagnostic", "session"].has(step.practice_tab), "Lesson opens an existing practice tab")
		_check(step.has("target") and not step.gatehint.is_empty(), "Lesson has practice target and a gate hint")
	tutorial.start(snapshot)
	var first: Dictionary = tutorial.view(snapshot)
	_check(first.active and first.index == 0 and first.step_index == 1 and first.total == 23, "Start exposes a consistent first-step view")
	_check(first.body == first.what and first.theory == first.why, "Content aliases agree for presentation")
	_check(not first.can_back and not first.is_last and not first.can_finish, "First lesson has correct navigation affordances")
	_check(not tutorial.back().ok, "Back cannot underflow first lesson")
	_check(tutorial.next(snapshot).ok and tutorial.index == 1, "Read-only welcome advances without station preparation")
	_check(not tutorial.next(snapshot).ok and tutorial.index == 1, "Unfinished practice does not silently advance")
	_check(tutorial.skip_step().ok and tutorial.index == 2, "Explicit lesson skip advances independently of readiness")
	_check(tutorial.back().ok and tutorial.index == 1, "Back returns to a previous lesson")
	tutorial.observe(snapshot, {"command": "lower", "ok": true})
	_check(tutorial.view(snapshot).ready, "Accepted comfort action supplies practice evidence")
	tutorial.skip()
	_check(not tutorial.active and tutorial.should_autostart() and not tutorial.completed, "Skip for now preserves next-launch prompting")
	tutorial.observe(snapshot, {"command": "tutorial:touch", "ok": true})
	tutorial.start(snapshot)
	_go(tutorial, "touch")
	_check(not tutorial.view(snapshot).ready, "Manual restart clears transient practice evidence")
	_check(snapshot == preserved, "Tutorial navigation and observation do not mutate input snapshots")
	_check(not lab.mounted and not lab.running and lab.records.is_empty(), "Tour never mounts, starts, or resets real model state")

func _test_preferences() -> void:
	var path: String = "user://tutorial-test-%d.cfg" % Time.get_ticks_usec()
	_check(not FileAccess.file_exists(path), "Preferences test uses a fresh isolated destination")
	var tutorial = Tutorial.new(path)
	var ctx: Dictionary = _context(Science.new())
	_check(tutorial.startup_enabled and not tutorial.completed and tutorial.should_autostart(), "First launch defaults to tutorial enabled")
	tutorial.start(ctx)
	tutorial.skip()
	_check(not FileAccess.file_exists(path), "Reading defaults, starting, and skipping do not write settings")
	_check(tutorial.set_startup(false).ok and FileAccess.file_exists(path), "Explicit startup toggle persists preferences")
	var reloaded = Tutorial.new(path)
	_check(not reloaded.should_autostart() and not reloaded.completed, "Disabled startup reloads accurately")
	reloaded.start(ctx)
	_check(reloaded.active and not reloaded.startup_enabled, "Manual restart remains available while prompting is disabled")
	_go(reloaded, "finish")
	_check(reloaded.view(ctx).is_last and reloaded.view(ctx).can_finish, "Only final current lesson exposes Finish")
	_check(reloaded.next(ctx).finished and not reloaded.active, "Final Next closes completed tour")
	_check(reloaded.completed and not reloaded.startup_enabled, "Completion records history and disables startup prompt")
	var completed_copy = Tutorial.new(path)
	_check(completed_copy.completed and not completed_copy.should_autostart(), "Completion preferences survive reload")
	completed_copy.start(ctx)
	_check(completed_copy.completed and not completed_copy.view(ctx).is_last and not completed_copy.view(ctx).can_finish, "Historical completion cannot label replay's first step Finish")
	completed_copy.skip()
	_check(completed_copy.completed and not completed_copy.startup_enabled, "Skipping replay preserves completion history and prompt setting")
	completed_copy.set_startup(true)
	var opted_in = Tutorial.new(path)
	_check(opted_in.completed and opted_in.should_autostart(), "Explicit ON after completion honors next-launch replay")
	var before_skip: String = FileAccess.get_file_as_string(path)
	opted_in.start(ctx)
	opted_in.skip()
	_check(FileAccess.get_file_as_string(path) == before_skip, "Skip for now does not rewrite saved preferences")
	var memory = Tutorial.new("")
	memory.start(ctx)
	_go(memory, "finish")
	memory.skip_step()
	_check(not memory.active and not memory.completed and memory.startup_enabled, "Skipping final lesson does not manufacture completion")
	_check(memory.save_settings("").ok and memory.preferences_path.is_empty(), "Empty preference path guarantees memory-only updates")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Isolated preference test file is removed")

func _test_rejected_and_stale_gates() -> void:
	var lab = Science.new()
	var ctx: Dictionary = _context(lab)
	var tutorial = Tutorial.new("")
	tutorial.start(ctx)
	_go(tutorial, "touch")
	tutorial.observe(ctx, {"command": "home", "input_kind": "fingertip", "ok": false})
	_check(not tutorial.view(ctx).ready, "Rejected physical command cannot satisfy contact practice")
	tutorial.observe(ctx, {"command": "tutorial:touch", "ok": "true"})
	_check(not tutorial.view(ctx).ready, "Text claiming success is not an accepted boolean outcome")
	tutorial.observe(ctx, {"command": "tutorial:touch", "ok": true})
	_check(tutorial.view(ctx).ready, "Dedicated accepted touch practice works with desktop or fingertips")
	_go(tutorial, "baseline")
	ctx.baseline = {"kind": "baseline", "accepted": false}
	_check(not tutorial.view(ctx).ready, "Aborted baseline is not a completed measurement")
	ctx.baseline.accepted = true
	ctx.rpm = 1200.0
	_check(not tutorial.view(ctx).ready, "Capture must coast to zero before next preparation lesson")
	ctx.rpm = 0.0
	_check(tutorial.view(ctx).ready, "Accepted current baseline at zero is recognized statefully")
	ctx.rpm = 0.2
	_check(not tutorial.view(ctx).ready, "Tutorial waits for the same near-zero threshold as the visible drive state")
	ctx.rpm = 0.0
	_go(tutorial, "trial_fit")
	ctx.baseline.merge({"masses": [0.0, 0.0], "angles": [0.0, 0.0]})
	ctx.masses = [0.25, 0.25]
	_check(not tutorial.view(ctx).ready, "Trial lesson rejects simultaneous changes to both planes")
	ctx.masses = [0.25, 0.0]
	_check(tutorial.view(ctx).ready, "Independent A trial is recognized without relying on command names")
	_go(tutorial, "solve")
	ctx.solution = {"condition_number": 31.0}
	_check(not tutorial.view(ctx).ready, "Poorly conditioned solution does not satisfy solve lesson")
	ctx.solution = {"condition_number": 2.0, "masses_g": [0.4, 0.0], "angles_deg": [90.0, 0.0]}
	_check(tutorial.view(ctx).ready, "Valid measured solution supplies solve evidence")
	_go(tutorial, "verify")
	ctx.latest = {"kind": "verify", "accepted": true, "id": 4, "verified": false}
	ctx.masses = [0.4, 0.0]
	ctx.angles = [90.0, 0.0]
	tutorial.observe(ctx, {"command": "apply", "ok": true})
	_check(not tutorial.view(ctx).ready, "An old Verify cannot satisfy a newly applied correction")
	ctx.latest.id = 5
	_check(tutorial.view(ctx).ready, "Fresh failed Verify still teaches a valid measurement outcome")
	ctx.latest.configuration_changed = true
	_check(not tutorial.view(ctx).ready, "Stale configuration-changed verification is rejected")
	ctx.latest.configuration_changed = false
	ctx.masses[0] = 0.5
	_check(not tutorial.view(ctx).ready, "Fresh Verify after a manual mass change cannot stand in for installed calculated correction")
	ctx.masses[0] = 0.4
	ctx.processing = true
	_check(not tutorial.view(ctx).ready, "Still-processing verification cannot advance")
	ctx.processing = false
	ctx.fault = "Sensor dropout"
	_check(not tutorial.view(ctx).ready, "Faulted verification cannot advance")
	_go(tutorial, "report")
	ctx.fault = ""
	tutorial.observe(ctx, {"command": "save", "ok": false})
	_check(not tutorial.view(ctx).ready, "Failed write does not count as a saved report")
	tutorial.observe(ctx, {"command": "save", "ok": true})
	_check(tutorial.view(ctx).ready, "Confirmed successful write supplies report evidence")
	# Seeing two fault names is not enough: each must be followed by successful
	# reset/reference restoration, which the model expresses as healthy+homed.
	var recovery = Tutorial.new("")
	recovery.start(ctx)
	_go(recovery, "faults")
	ctx.homed = false
	ctx.fault = "Sensor dropout"
	recovery.observe(ctx)
	ctx.fault = "Tachometer signal lost"
	recovery.observe(ctx)
	ctx.fault = ""
	ctx.homed = true
	_check(not recovery.view(ctx).ready, "Fault practice requires recovery after each fault, not just two injections")
	ctx.homed = false
	ctx.fault = "Sensor dropout"
	recovery.observe(ctx)
	ctx.fault = ""
	ctx.homed = true
	_check(recovery.view(ctx).ready, "Both independently recovered faults satisfy practice")

func _test_new_session_record_ids() -> void:
	var ctx: Dictionary = _context(Science.new())
	ctx.solution = {"condition_number": 2.0, "masses_g": [0.4, 0.0], "angles_deg": [90.0, 0.0]}
	ctx.masses = [0.4, 0.0]
	ctx.angles = [90.0, 0.0]
	ctx.latest = {"kind": "verify", "accepted": true, "id": 50}
	var tutorial = Tutorial.new("")
	tutorial.start(ctx)
	_go(tutorial, "verify")
	tutorial.observe(ctx, {"command": "apply", "ok": true})
	_check(not tutorial.view(ctx).ready, "Old Apply checkpoint requires a later measurement")
	ctx.latest = {}
	ctx.solution = {}
	tutorial.observe(ctx, {"command": "new", "ok": true})
	ctx.solution = {"condition_number": 2.0, "masses_g": [0.4, 0.0], "angles_deg": [90.0, 0.0]}
	ctx.latest = {"kind": "verify", "accepted": true, "id": 3}
	_check(tutorial.view(ctx).ready, "New-session verification is not stranded behind an old high record ID")
	ctx.latest.id = 60
	tutorial.observe(ctx, {"command": "apply", "ok": true})
	ctx.latest = {}
	tutorial.observe(ctx)
	ctx.latest = {"kind": "verify", "accepted": true, "id": 3}
	_check(tutorial.view(ctx).ready, "Observed record-ID reset also invalidates Apply evidence without a command event")

func _test_complete_measured_workflow() -> void:
	_chart_kind = "sweep"
	_saved_report = false
	var lab = Science.new()
	var tutorial = Tutorial.new("")
	tutorial.start(_context(lab))
	_advance(tutorial, lab, "welcome")
	tutorial.observe(_context(lab), {"command": "distance", "ok": true})
	_advance(tutorial, lab, "comfort")
	tutorial.observe(_context(lab), {"command": "tutorial:touch", "ok": true})
	_advance(tutorial, lab, "touch")
	_accepted(tutorial, lab, "mount", lab.mount_rotor())
	_advance(tutorial, lab, "load")
	_accepted(tutorial, lab, "home", lab.home_probe())
	_advance(tutorial, lab, "home")
	_accepted(tutorial, lab, "dial:probe", lab.set_probe(6.1), {"changed": true})
	_check(not tutorial.view(_context(lab)).ready, "Changed probe must be restored before next preparation step")
	_accepted(tutorial, lab, "home", lab.home_probe())
	_advance(tutorial, lab, "dials")
	_accepted(tutorial, lab, "guard", lab.toggle_guard())
	_advance(tutorial, lab, "guard")
	_capture(lab, "baseline", tutorial)
	_advance(tutorial, lab, "baseline")
	_advance(tutorial, lab, "phasor")
	_chart_kind = "time"
	tutorial.observe(_context(lab))
	_chart_kind = "order"
	tutorial.observe(_context(lab))
	_advance(tutorial, lab, "analyzer")
	lab.toggle_guard()
	_accepted(tutorial, lab, "fit_trial", lab.fit_trial(0))
	_advance(tutorial, lab, "trial_fit")
	lab.toggle_guard()
	_capture(lab, "trial_a", tutorial)
	_advance(tutorial, lab, "trial_measure")
	_accepted(tutorial, lab, "solve", lab.solve_balance())
	_advance(tutorial, lab, "solve")
	lab.toggle_guard()
	_accepted(tutorial, lab, "apply", lab.apply_solution())
	lab.toggle_guard()
	_capture(lab, "verify", tutorial)
	_advance(tutorial, lab, "verify")
	_capture(lab, "repeat", tutorial)
	_advance(tutorial, lab, "repeat")
	_capture(lab, "sweep", tutorial)
	_advance(tutorial, lab, "sweep")
	_accepted(tutorial, lab, "mode", lab.set_mode("two_plane"))
	_advance(tutorial, lab, "two_plane")
	_accepted(tutorial, lab, "estop", lab.emergency_stop())
	_check(not tutorial.view(_context(lab)).ready, "Latched E-stop requires explicit recovery")
	_accepted(tutorial, lab, "recover", lab.release_estop())
	_check(not tutorial.view(_context(lab)).ready, "E-stop release alone cannot replace rehoming")
	_accepted(tutorial, lab, "home", lab.home_probe())
	_advance(tutorial, lab, "estop")
	_accepted(tutorial, lab, "fault_sensor", lab.inject_fault("sensor"))
	_accepted(tutorial, lab, "recover", lab.reset_fault())
	_accepted(tutorial, lab, "home", lab.home_probe())
	_check(not tutorial.view(_context(lab)).ready, "Sensor recovery alone does not complete tach practice")
	_accepted(tutorial, lab, "fault_tach", lab.inject_fault("tach"))
	_accepted(tutorial, lab, "recover", lab.reset_fault())
	_accepted(tutorial, lab, "home", lab.home_probe())
	_advance(tutorial, lab, "faults")
	_advance(tutorial, lab, "references")
	_saved_report = true
	_advance(tutorial, lab, "report")
	var preserved: Dictionary = lab.report().duplicate(true)
	_advance(tutorial, lab, "session")
	_advance(tutorial, lab, "finish")
	_check(not tutorial.active and tutorial.completed and not tutorial.startup_enabled, "Measured workflow finishes with completion history and startup prompt off")
	_check(lab.report() == preserved, "Tutorial finish and session guidance never clear or mutate lab records")
	_check(lab.records.size() == 5 and not lab.running and not lab.estop and lab.fault.is_empty(), "Full practice retains five measured records and recovered stopped fixture")
