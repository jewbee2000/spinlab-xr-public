extends SceneTree
## Actual application integration for the 15-stage physical balancing procedure.
## Simulated fingertip contacts and accepted commands exercise real dispatch,
## acquisition, automatic UI progression, interruption, persistence and file I/O.
## This suite does not establish headset pose fit, stereo or physical usability.
class SilentGuide extends "res://scripts/main.gd":
	func _setup_sound() -> void:pass

class TestController extends Node3D:
	var tracker: StringName = &"right_hand"
	var stick := Vector2.ZERO
	func get_vector2(_input_name: String) -> Vector2:return stick

const DT := 0.05
const IDS := ["load","home","guard","baseline","open_trial","trial_fit","close_trial","trial_measure","solve","open_apply","apply","close_verify","verify","repeat","report"]
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
	_check(app.tutorial_panel.labels.title.text == view.title, "Visible guide title follows actual instruction")
	_check(app.tutorial_panel.labels.progress.text.ends_with("/ 15"), "Visible progress shows 15 work instructions")

func _frames(count: int) -> void:
	for frame in range(count):app._process(DT)

func _auto_to(id: String) -> void:
	var previous_id: String = _view().id
	_check(_view().ready, "Confirmed real work starts success dwell: " + previous_id)
	_frames(20)
	_check(_view().id == previous_id, "Success remains readable for more than one second: " + previous_id)
	_frames(15)
	_step(id)

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

func _capture(kind: String) -> void:
	var count_before: int = app.model.records.size()
	var id_before: String = _view().id
	_physical(kind)
	_check(app.model.running,"Physical cap starts actual acquisition: " + kind)
	_check(not _view().ready,"Running acquisition cannot satisfy a completed-measurement instruction")
	_finish_capture()
	_check(app.model.records.size() == count_before+1,"Exactly one new accepted measurement is committed: " + kind)
	_check(not app.model.running and not app.model.processing and app.model.rpm < 0.1,"Capture and analysis end at zero speed: " + kind)
	_check(_view().id == id_before and _view().ready,"Accepted measurement begins dwell without skipping its success cue: " + kind)

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
	_check(app.tutorial.steps.map(func(step):return step.id) == IDS,"Actual application uses exactly the ordered 15 physical-work stages")
	_check(not app.controls.is_ancestor_of(app.tutorial_panel),"Guide is independent of the application menu")
	_check(app.tutorial_panel.interactive_buttons.is_empty() and app.tutorial_panel.find_children("*","CollisionObject3D",true,false).is_empty(),"Read-only work guide has no input targets")
	_check(not app.model.mounted and app.model.records.is_empty() and not app.model.running,"Initial guidance leaves laboratory untouched")
	_step("load")
	app._controller_pressed("ax_button",right)
	_check(_view().id == "load" and not _view().ready,"A cannot bypass an unfinished physical task")
	app._controller_pressed("by_button",right)
	_check(app.menu_open and app.controls.visible and not app.tutorial_panel.visible,"B opens explicit pointer menu and hides work guide")
	_check(app.menu_tab_buttons.size() == 3 and app.menu_tab_buttons.has("balance") and app.menu_tab_buttons.has("diagnostic") and app.menu_tab_buttons.has("session"),"Menu has Balance/Analyze/Session only")
	for key in ["balance","diagnostic","session"]:
		app._action("tab:"+key)
		_check(app.menu_tab_buttons[key].normal_color != app.menu_tab_buttons["session" if key != "session" else "balance"].normal_color,"Selected menu tab is highlighted")
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
	app._action("mount","grip")
	_auto_to("home")
	_check(not _view().ready,"HOME requires its own accepted physical action")
	_physical("home")
	_check(app.model.homed and app.geometry.physical_by_action.home.guide_highlight,"Actual HOME reference is accepted and target highlighted")
	_auto_to("guard")
	_guard(true);_auto_to("baseline")
	_guard(false);_physical("baseline")
	_check(not app.model.running and not _view().ready,"Rejected open-guard baseline cannot satisfy work instruction")
	_guard(true);_physical("baseline");_frames(3);_physical("stop");_frames(80)
	_check(app.model.records.is_empty() and not _view().ready and _view().id == "baseline","STOP discards partial acquisition without advancing guide")
	_capture("baseline");_auto_to("open_trial")
	_guard(false);_auto_to("trial_fit")
	_physical("fit_trial");_auto_to("close_trial")
	_guard(true);_auto_to("trial_measure")
	_capture("trial_a");_auto_to("solve")
	_physical("solve")
	_check(not app.model.solution.is_empty(),"Physical SOLVE uses real baseline/trial measurements")
	_auto_to("open_apply")
	_guard(false);_auto_to("apply")
	_physical("apply");_auto_to("close_verify")
	_guard(true);_auto_to("verify")
	_check(not _view().ready,"Installed prediction alone cannot satisfy fresh verification")
	_capture("verify");_auto_to("repeat")
	_capture("repeat");_auto_to("report")
	var path: String = _save_actual()
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if not path.is_empty() else null
	_check(report is Dictionary and report.records.size() == 4,"Saved JSON contains real baseline/trial/verification/repeatability records")
	_check(report is Dictionary and report.tutorial.step_id == "report" and report.tutorial.step_count == 15,"Report records work-guide stage separately from scientific result")
	_check(report is Dictionary and report.has("operator_navigation"),"Report preserves operator context alongside measurements")
	var scientific_before: String = JSON.stringify(app.model.report())
	_frames(35)
	_check(not app.tutorial.active and app.tutorial.completed and not app.tutorial.startup_enabled and not app.tutorial_panel.visible,"Successful save finishes guide automatically and persists startup OFF")
	_check(JSON.stringify(app.model.report()) == scientific_before,"Automatic guide completion leaves scientific records/configuration unchanged")
	var preferences = app.Tutorial.new(settings_path)
	_check(preferences.completed and not preferences.should_autostart(),"Completion preferences reload from actual config file")

func _test_review_and_interruptions() -> void:
	var preserved: String = JSON.stringify(app.model.report())
	_menu("tutorial:restart")
	_check(app.tutorial.active and _view().id == "load" and not app.tutorial_panel.visible,"Session restart starts work guide behind explicit menu")
	_check(JSON.stringify(app.model.report()) == preserved,"Restart preserves completed laboratory data")
	_frames(50)
	_check(_view().id == "load","Open menu pauses automatic success dwell")
	app._set_menu_open(false);_auto_to("home")
	_frames(40)
	_check(_view().id == "home" and not _view().ready,"Earlier HOME and captures cannot satisfy fresh restarted HOME")
	_physical("home")
	var remaining: float = _view().success_remaining_s
	app._controller_pressed("ax_button",left)
	_check(_view().id == "load" and _view().reviewing,"X opens review without resetting actual work checkpoint")
	_frames(50)
	app._controller_pressed("ax_button",right)
	_check(_view().id == "home" and is_equal_approx(_view().success_remaining_s,remaining),"A returns from review with preserved success dwell")
	_menu("tutorial:toggle")
	var index: int = app.tutorial.index
	_frames(50)
	_check(not app.tutorial.active and app.guide_paused and app.tutorial.index == index,"Session pause preserves stage and stops automatic progression")
	app._physical_action("tutorial:toggle","pointer")
	_check(app.tutorial.active and app.tutorial.index == index,"Session resume preserves checkpoint")
	app._set_menu_open(false);_auto_to("guard");_auto_to("baseline")
	_check(not _view().ready,"Earlier baseline cannot replace a new guide calibration")
	_capture("baseline")
	var record_count: int = app.model.records.size()
	app._set_dial("probe",6.05)
	_frames(40)
	_check(_view().id == "baseline" and not _view().ready and app.model.baseline.is_empty(),"Probe change during success dwell invalidates baseline proof instead of auto-advancing")
	_check(app.model.records.size() == record_count,"Calibration invalidation preserves historical measurements")
	_physical("home");_capture("baseline");_auto_to("open_trial")
	_guard(false);_auto_to("trial_fit");_physical("fit_trial");_auto_to("close_trial")
	_guard(true);_auto_to("trial_measure")
	record_count = app.model.records.size()
	_physical("trial_a");_frames(3);app._set_xr_focus(false);_frames(80)
	_check(not app.model.running and app.model.rpm < 0.1 and app.model.records.size() == record_count,"Focus loss stops actual acquisition and discards incomplete record")
	app._set_xr_focus(true);_frames(40)
	_check(_view().id == "trial_measure" and not _view().ready and not app.model.running,"Focus return neither resumes rotor nor invents a completed trial")
	_capture("trial_a");_auto_to("solve");_physical("solve");_frames(5)
	remaining = _view().success_remaining_s
	app._set_xr_focus(false);_frames(60)
	_check(_view().id == "solve" and is_equal_approx(_view().success_remaining_s,remaining),"Focus interruption suspends an otherwise-valid success countdown")
	app._set_xr_focus(true);_frames(30);_step("open_apply")

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
	_check(new_report != old_report and _view().ready,"Only fresh successful file output begins report-stage success")
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
