extends SceneTree
## Actual integration for the novice two-plane rotor-balancing course.
## Simulated fingertip contacts and accepted commands exercise real dispatch,
## acquisition, automatic UI progression, interruption, persistence and file I/O.
## This suite does not establish headset pose fit, stereo or physical usability.
class SilentGuide extends "res://scripts/main.gd":
	func _setup_sound() -> void:pass
	func _init() -> void:narration_enabled=false;narration_settings_path=""

class TestController extends Node3D:
	var tracker: StringName = &"right_hand"
	var stick := Vector2.ZERO
	func get_vector2(_input_name: String) -> Vector2:return stick

const DT := 0.05
const IDS := ["load","home","probe_adjust","probe_restore","open_setup","mass_practice","angle_practice","clear_mass","mode_two","plane_b","plane_a","speed_explore","speed_restore","guard","preview_start","stop","estop","recover","rehome","baseline","chart_order","open_trial","trial_fit","close_trial","trial_measure","open_trial_b","plane_b_trial","trial_fit_b","close_trial_b","trial_measure_b","solve","open_apply","apply","close_verify","sweep","verify","repeat","report"]
var checks := 0
var failures := 0
var app
var left: Dictionary
var right: Dictionary
var settings_path := ""
var report_directory := ""
var saved_files: Array[String] = []

func _initialize() -> void:
	var token := str(Time.get_ticks_usec())
	settings_path = "user://tutorial-app-test-" + token + ".cfg"
	report_directory = "user://tutorial-app-reports-" + token
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1;push_error("TUTORIAL APP: " + description)

func _spawn() -> void:
	app = SilentGuide.new();app.tutorial_settings_path = settings_path
	root.add_child(app)
	app.set_process(false);app.set_process_unhandled_input(false)
	app.model.async_processing = false;app.report_directory = report_directory
	left = _hand(&"left_hand");right = _hand(&"right_hand")

func _hand(side: StringName) -> Dictionary:
	var controller := TestController.new();controller.tracker = side;app.rig.add_child(controller)
	var grip := Node3D.new();grip.position = Vector3(3,2,3);app.rig.add_child(grip)
	var entry: Dictionary = app._make_hand_entry(controller,grip)
	entry.tracked = true;app.controllers.append(entry)
	return entry

func _dispose() -> void:
	app._cancel_hand_interactions();app.controllers.clear();left.clear();right.clear()
	app.queue_free()
	await process_frame
	app = null

func _view() -> Dictionary:return app.tutorial.view(app._tutorial_context())

func _step(id: String) -> void:
	app._update_ui()
	var view: Dictionary = _view()
	_check(view.id == id, "Current instruction: expected " + id + ", actual " + str(view.id))
	_check(app.tutorial_panel.labels.title.text == str(app.tutorial_panel.SHORT_ACTIONS.get(view.get("prompt_id",view.id),"Follow highlighted target")), "Minimal imperative follows actual instruction")
	_check(app.tutorial_panel.labels.progress.text.ends_with("/38"), "Visible progress shows the full novice course")

func _frames(count: int) -> void:
	for frame in range(count):app._process(DT)

func _auto_to(id: String) -> void:
	var previous_id: String = _view().id
	_check(_view().ready, "Real completed task is ready before process: " + previous_id)
	_frames(1)
	_step(id)
	_check(_view().id != previous_id, "One frame advances completed work without waiting for speech or dwell")

func _go(id: String) -> void:
	for unused in range(IDS.size()):
		if _view().id == id: return
		app._tutorial_action("tutorial:skip_step")
	_check(false, "Isolated test stage exists: " + id)

func _physical(command: String) -> void:
	var button = app.geometry.physical_by_action.get(command)
	_check(is_instance_valid(button), "Operating command has a real physical cap: " + command)
	if not is_instance_valid(button):return
	_check(not app.menu_open, "Physical operation occurs with explicit menu closed")
	var offsets: Array = []
	for frame in range(10):offsets.append(0.06)
	offsets.append(-0.008);offsets.append(0.06)
	for z in offsets:
		app.frame_latches.clear();app.frame_depths.clear()
		app._process_pokes(left,button.to_global(Vector3(0,0,button.front_z_m+z)),1.0/72.0)
		app._finish_pokes()

func _guard(closed: bool) -> void:
	_check(app.model.guard_closed != closed, "Guard command begins in opposite mechanical state")
	app._action("guard","grip")
	_check(app.model.guard_closed == closed, "Actual guarded fixture command is accepted")

func _menu(command: String) -> void:
	app._set_menu_open(true)
	app._physical_action("tab:session","pointer")
	app._physical_action(command,"pointer")

func _finish_capture() -> void:
	for frame in range(850):
		_frames(1)
		if not app.model.running and not app.model.processing and app.model.rpm < 0.1:return
	_check(false,"Acquisition and coast-down finish within bounded simulated time")

func _capture(kind: String, next_id: String) -> void:
	var count_before: int = app.model.records.size()
	_physical(kind)
	_check(app.model.running,"Physical cap starts actual acquisition: " + kind)
	_check(not _view().ready,"Running capture cannot satisfy a finished-measurement instruction")
	_finish_capture()
	_check(app.model.records.size() == count_before+1,"Exactly one new accepted measurement is committed: " + kind)
	_check(not app.model.running and not app.model.processing and app.model.rpm < 0.1,"Capture and analysis end at zero speed: " + kind)
	_step(next_id)

func _save_actual() -> String:
	_physical("save")
	var path: String = app.saved_path
	_check(not path.is_empty() and FileAccess.file_exists(path),"Physical SAVE REPORT writes an actual JSON file")
	if not path.is_empty() and not saved_files.has(path):saved_files.append(path)
	return path

func _run() -> void:
	_spawn()
	_test_initial_ui()
	_test_complete_physical_workflow()
	_test_review_and_interruptions()
	_test_fresh_report_and_session_reset()
	await _test_preferences_and_relaunch()
	for path in saved_files:
		if FileAccess.file_exists(path):DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if DirAccess.dir_exists_absolute(report_directory):DirAccess.remove_absolute(ProjectSettings.globalize_path(report_directory))
	if FileAccess.file_exists(settings_path):DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	print("TUTORIAL APP TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _test_initial_ui() -> void:
	_check(not app.menu_open and app.tutorial.active and app.tutorial_panel.visible,"Fresh launch shows work guide with menu hidden")
	_check(app.tutorial.steps.map(func(step):return step.id) == IDS,"Actual application uses the complete ordered novice experiment")
	_check(not app.controls.is_ancestor_of(app.tutorial_panel),"Guide is independent of the application menu")
	_check(app.tutorial_panel.interactive_buttons.is_empty() and app.tutorial_panel.find_children("*","CollisionObject3D",true,false).is_empty(),"Read-only work guide has no input targets")
	_check(not app.model.mounted and app.model.records.is_empty() and not app.model.running,"Initial guidance leaves laboratory untouched")
	_step("load")
	app._controller_pressed("ax_button",right)
	_check(_view().id == "load" and not _view().ready,"A cannot bypass an unfinished physical task")
	app._controller_pressed("by_button",right)
	_check(app.menu_open and app.controls.visible and not app.tutorial_panel.visible,"B opens explicit pointer menu and hides work guide")
	_check(app.menu_tab_buttons.size() == 2 and app.menu_tab_buttons.has("diagnostic") and app.menu_tab_buttons.has("session"),"Menu keeps optional Tools and Session; all operating controls are physical")
	for key in ["diagnostic","session"]:
		app._action("tab:"+key)
		_check(app.menu_tab_buttons[key].normal_color != app.menu_tab_buttons["session" if key != "session" else "diagnostic"].normal_color,"Selected menu tab is highlighted")
	var session_commands: Array = []
	for button in app.buttons:
		if is_instance_valid(button) and button.get_meta("ui",false):session_commands.append(button.action)
	_check(session_commands.has("new") and not session_commands.has("exit"),"Session exposes New Session and leaves exit to Quest system UI")
	app._controller_pressed("ax_button",right)
	_check(_view().id == "load","A in menu cannot navigate hidden work guide")
	app._controller_pressed("by_button",left)
	_check(not app.menu_open and app.tutorial_panel.visible,"Y returns to physical glove/work-guide mode")
	_frames(50)
	_check(_view().id == "load" and not app.model.mounted,"Idle time or menu navigation cannot seat rotor or advance guide")

func _test_complete_physical_workflow() -> void:
	app._action("mount","grip");_auto_to("home")
	_check(not _view().ready,"HOME requires its own accepted physical action")
	_physical("home");_auto_to("probe_adjust")
	app._set_dial("probe",6.10);_auto_to("probe_restore")
	_physical("home");_auto_to("open_setup");_auto_to("mass_practice")
	app._set_dial("mass",0.08);_auto_to("angle_practice")
	app._set_dial("mass",0.0)
	_check(_view().id == "angle_practice" and _view().prompt_id == "mass_practice" and not _view().ready,"Accidentally clearing the practice mass directs restoring MASS before ANGLE")
	app._set_dial("mass",0.08)
	_check(_view().prompt_id == "angle_practice" and not _view().ready,"Restoring mass exposes the still-unfinished angle experiment")
	app._set_dial("angle",30.0);_auto_to("clear_mass")
	app._set_dial("mass",0.0);_auto_to("mode_two")
	_physical("mode");_auto_to("plane_b")
	_physical("plane");_auto_to("plane_a")
	_physical("plane");_auto_to("speed_explore")
	_physical("speed");_auto_to("speed_restore")
	_physical("speed");_check(not _view().ready,"900RPM does not satisfy the matched-speed setup")
	_physical("speed");_auto_to("guard")
	_guard(true);_auto_to("preview_start")
	_physical("sweep");_auto_to("stop")
	_physical("stop");_frames(30);_step("estop")
	_check(app.model.records.is_empty(),"STOP practice discards the interrupted sweep")
	_physical("estop");_auto_to("recover")
	_physical("recover");_auto_to("rehome")
	_check(not app.model.homed and not app.model.running,"Recovery leaves the spindle stopped and requires HOME")
	_physical("home");_auto_to("baseline")
	_guard(false);_physical("baseline")
	_check(not app.model.running and not _view().ready,"Rejected open-guard baseline cannot satisfy work")
	_guard(true);_capture("baseline","chart_order")
	_check(app.chart_kind == "time" and app.model.waveform.size() > 0,"Baseline displays actual time-domain data before spectrum lesson")
	_physical("chart");_auto_to("open_trial")
	_check(app.chart_kind == "order" and app.model.spectrum.size() > 0,"Physical CHART selects populated order spectrum")
	_guard(false);_auto_to("trial_fit")
	_physical("fit_trial");_auto_to("close_trial")
	# A novice accidentally removes the installed trial before closing the guard.
	app._set_dial("mass",0.0);_guard(true);_auto_to("trial_measure")
	_check(_view().prompt_id == "open_setup" and not _view().ready,"Edited A trial directs opening the guard before restoration")
	_physical("trial_a")
	_check(not app.model.running and not _view().ready,"Rejected Trial A with a missing trial cannot complete the lesson")
	_guard(false)
	_check(_view().prompt_id == "trial_fit","Open fixture points to the known-trial helper")
	_physical("fit_trial");_guard(true)
	_check(_view().id == "trial_measure" and not _view().ready,"Restoring a trial still needs a fresh accepted capture")
	_capture("trial_a","open_trial_b")
	_guard(false);_auto_to("plane_b_trial")
	_physical("plane");_auto_to("trial_fit_b")
	_physical("fit_trial");_auto_to("close_trial_b")
	_guard(true);_auto_to("trial_measure_b")
	_capture("trial_b","solve")
	_physical("solve");_auto_to("open_apply")
	_check(not app.model.solution.is_empty() and app.model.solution.mode == "two_plane","Physical SOLVE uses both independent measured trial columns")
	_guard(false);_auto_to("apply")
	_physical("apply");_auto_to("close_verify")
	app._set_dial("mass",float(app.model.masses[app.active_plane])+0.050)
	_guard(true);_auto_to("sweep")
	_check(_view().prompt_id == "open_setup" and not _view().ready,"Edited correction directs opening the guard before the corrected sweep")
	_guard(false)
	_check(_view().prompt_id == "apply","An edited calculated correction directs physical APPLY")
	_physical("apply");_guard(true)
	_check(_view().id == "sweep" and not _view().ready,"Applying the solution does not itself count as a completed sweep")
	_capture("sweep","verify")
	_check(app.model.sweep_points.size() >= 3 and app.chart_kind == "sweep","A complete speed sweep produces an actual resonance curve")
	_capture("verify","repeat")
	_check(app.chart_kind == "time","Fixed-speed verification restores a populated time plot")
	_capture("repeat","report")
	var path: String = _save_actual()
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if not path.is_empty() else null
	_check(report is Dictionary and report.records.size() == 6,"Saved JSON contains baseline, A/Btrials, sweep, verification and repeatability")
	_check(report is Dictionary and report.tutorial.step_id == "report" and report.tutorial.step_count == IDS.size(),"Report records guide stage separately from scientific result")
	_check(report is Dictionary and report.has("operator_navigation"),"Report preserves operator context alongside measurements")
	var scientific_before: String = JSON.stringify(app.model.report())
	_frames(1)
	_check(not app.tutorial.active and app.tutorial.completed and not app.tutorial.startup_enabled and not app.tutorial_panel.visible,"Successful save ends the guide immediately and persists startup OFF")
	_check(JSON.stringify(app.model.report()) == scientific_before,"Guide completion leaves all scientific evidence unchanged")
	var preferences = app.Tutorial.new(settings_path)
	_check(preferences.completed and not preferences.should_autostart(),"Completion preferences reload from the actual config file")

func _test_review_and_interruptions() -> void:
	var preserved: String = JSON.stringify(app.model.report())
	_menu("tutorial:restart")
	_check(app.tutorial.active and _view().id == "load" and not app.tutorial_panel.visible,"Restart begins the course behind the explicit menu")
	_check(JSON.stringify(app.model.report()) == preserved,"Restart preserves completed laboratory data")
	_frames(10);_check(_view().id == "load","Open menu pauses automatic progression")
	app._set_menu_open(false);_auto_to("home")
	_frames(10);_check(_view().id == "home" and not _view().ready,"Old HOME and captures cannot satisfy a fresh restarted HOME")
	_physical("home")
	app._controller_pressed("ax_button",left)
	_check(_view().id == "load" and _view().reviewing,"X enters review without discarding current HOME proof")
	_frames(10);app._controller_pressed("ax_button",right)
	_check(_view().id == "home" and _view().ready,"A returns to the unfinished work checkpoint")
	_menu("tutorial:toggle")
	var index: int = app.tutorial.index
	_frames(10);_check(not app.tutorial.active and app.guide_paused and app.tutorial.index == index,"Pause freezes the checkpoint")
	app._physical_action("tutorial:toggle","pointer")
	app._set_menu_open(false);_auto_to("probe_adjust")
	app._set_dial("probe",6.10);_auto_to("probe_restore")
	_physical("home");_auto_to("open_setup")
	_check(not _view().ready and _view().target == "guard","A restart with the guard closed now explicitly teaches opening it before dial practice")
	_guard(false);_auto_to("mass_practice")
	_check(_view().prompt_id == "plane_a" and _view().target == "plane","Retained B editor directs the user to A rather than a rejected dial")
	_physical("plane")
	_check(_view().prompt_id == "mass_practice","Completing a prerequisite restores the original unfinished task")
	app._set_dial("mass",0.10);_auto_to("angle_practice")
	# Isolate capture interruption without repeating the entire physical course.
	_go("baseline");_guard(true)
	_physical("baseline");_frames(3);app._set_xr_focus(false);_frames(80)
	_check(not app.model.running and app.model.rpm < 0.1,"Focus loss stops the acquisition and coasts to zero")
	var count: int = app.model.records.size()
	app._set_xr_focus(true);_frames(10)
	_check(_view().id == "baseline" and not _view().ready and app.model.records.size() == count,"Focus return does not resume a run or invent a new capture")
	_capture("baseline","chart_order")
	_physical("chart");_auto_to("open_trial")
	# Unexpected E-stop/fault recovery changes the prompt, never the checkpoint.
	_physical("estop");_check(_view().id == "baseline" and _view().prompt_id == "recover","Unexpected E-stop revisits the invalidated baseline and targets actual recovery")
	_physical("recover");_check(_view().id == "baseline" and _view().prompt_id == "rehome","Recovered fixture directs a fresh HOME before the new calibration")
	_physical("home");_check(_view().id == "baseline" and _view().prompt_id == "baseline","HOME returns to the fresh-baseline task rather than a rejected old trial")
	_check(not _view().ready,"Historical captures cannot satisfy the invalidated baseline")
	_capture("baseline","chart_order");_physical("chart");_auto_to("open_trial")
	_guard(false);_auto_to("trial_fit")
	if app.active_plane != 0:_physical("plane")
	_physical("fit_trial");_auto_to("close_trial");_guard(true);_auto_to("trial_measure")
	_capture("trial_a","open_trial_b");_guard(false);_auto_to("plane_b_trial")
	_physical("plane");_auto_to("trial_fit_b");_physical("fit_trial");_auto_to("close_trial_b")
	_guard(true);_auto_to("trial_measure_b");_capture("trial_b","solve")
	_physical("solve");_auto_to("open_apply")
	_check(not app.model.solution.is_empty(),"Fault recovery reacquires both real trial columns and reaches a usable solve without dead-end controls")
	# A deliberate replacement baseline also replaces its dependent calibration.
	var history_count: int = app.model.records.size()
	_physical("baseline")
	_check(app.model.running and _view().id == "baseline" and not _view().ready,"A fresh BASELINE pressed after Solve revisits the correct acquisition checkpoint")
	_check(app.model.solution.is_empty() and app.model.trial_a.is_empty() and app.model.trial_b.is_empty(),"New baseline start clears obsolete trial/solution dependencies in the real instrument")
	_check(app.model.records.size() == history_count,"Revisiting baseline preserves all historical evidence while acquiring")
	_finish_capture();_step("chart_order")
	_check(app.model.records.size() == history_count+1,"The replacement baseline must commit one fresh accepted record")

func _test_fresh_report_and_session_reset() -> void:
	var old_report: String = app.saved_path
	var preserved: String = JSON.stringify(app.model.report())
	_menu("tutorial:restart");app._set_menu_open(false)
	for stage in range(IDS.size()-1):app._action("tutorial:skip_step")
	_step("report")
	_check(app.saved_path == old_report and FileAccess.file_exists(old_report) and not _view().ready,"Old saved file cannot satisfy fresh report stage after restart/explicit skips")
	_check(JSON.stringify(app.model.report()) == preserved,"Skipping instructions preserves laboratory data")
	DirAccess.make_dir_recursive_absolute(report_directory)
	var blocker_path := report_directory + "/file-is-not-directory"
	var blocker := FileAccess.open(blocker_path,FileAccess.WRITE);blocker.store_string("test");blocker.close();saved_files.append(blocker_path)
	app.report_directory = blocker_path
	_physical("save")
	_check(app.saved_path.is_empty() and not _view().ready and (app.status.contains("unavailable") or app.status.contains("could not") or app.status.contains("failed")),"Actual report I/O failure cannot satisfy report objective")
	app.report_directory = report_directory
	var new_report: String = _save_actual()
	_check(new_report != old_report and _view().ready,"Only fresh successful file output completes the report task")
	_menu("new")
	_check(app.model.records.is_empty() and not app.model.mounted and app.saved_path.is_empty(),"Session New Session resets live lab and saved-file reference")
	_check(app.tutorial.active and _view().id == "load" and not _view().ready,"Accepted New Session clears old work proofs and returns guide to rotor load")
	_check(FileAccess.file_exists(new_report) and FileAccess.file_exists(old_report),"Reset preserves previously exported report files")
	app._set_menu_open(false)
	app._action("tutorial:skip_step")
	_step("home")
	app._action("tutorial:restart")
	_step("load")
	_menu("tutorial:startup")
	_check(app.tutorial.startup_enabled and app.Tutorial.new(settings_path).should_autostart(),"Explicit startup ON persists even after prior completion")
	app._physical_action("tutorial:startup","pointer")
	_check(not app.tutorial.startup_enabled,"Startup OFF remains available independently of active work")
	app._physical_action("tutorial:toggle","pointer")
	_check(not app.tutorial.active and not app.tutorial.startup_enabled,"Pause leaves startup preference unchanged")

func _test_preferences_and_relaunch() -> void:
	await _dispose()
	_spawn()
	_check(not app.menu_open and not app.tutorial.active and not app.tutorial_panel.visible,"Persisted startup OFF launches ordinary physical-work station")
	_menu("tutorial:restart");app._set_menu_open(false)
	_check(app.tutorial.active and app.tutorial_panel.visible and _view().id == "load","Disabled startup still permits manual restart")
	await _dispose()
	print("TUTORIAL APP: expected malformed-settings diagnostic follows; fallback is asserted.")
	var malformed := FileAccess.open(settings_path,FileAccess.WRITE);malformed.store_string("[invalid settings");malformed.close()
	_spawn()
	_check(app.tutorial.active and not app.menu_open and not app.tutorial.settings_error.is_empty() and app.status.contains("Could not load"),"Corrupt settings diagnose error and recover to default work guide")
	await _dispose()
