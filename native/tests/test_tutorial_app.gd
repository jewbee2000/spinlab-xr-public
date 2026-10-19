extends SceneTree
## Exercise onboarding through real application commands and contact routing.
var checks := 0
var failures := 0
var app
var settings_path := "user://tutorial-integration-test.cfg"

func _initialize() -> void:call_deferred("_run")

func _check(value: bool, description: String) -> void:
	checks+=1
	if not value:failures+=1;push_error("TUTORIAL APP: "+description)

func _step(id: String) -> void:
	_check(app.tutorial.view(app._tutorial_context()).id==id,"Lesson reached: "+id)

func _next(id: String) -> void:
	_check(app.tutorial.view(app._tutorial_context()).ready,"Objective met before Next")
	app._action("tutorial:open_next");_step(id)

func _run_capture(kind: String) -> void:
	app._action(kind)
	_check(app.model.running,"Actual acquisition starts: "+kind)
	app._update_ui()
	_check(not app.tutorial.view(app._tutorial_context()).ready,"Running acquisition cannot satisfy measurement lesson")
	for i in range(700):
		app.model.tick(0.05)
		if not app.model.running and not app.model.processing and app.model.rpm<0.1:break
	app._update_ui()
	_check(not app.model.running and app.model.rpm<0.1,"Acquisition and coast complete: "+kind)

func _button(command: String):
	for button in app.buttons:
		if is_instance_valid(button) and not button.is_queued_for_deletion() and button.action==command:return button
	return null

func _press(button) -> void:
	var entry={"contacts":{},"held":"","grip_down":false}
	for z in [0.06,-0.008,0.06]:
		app.frame_latches.clear();app.frame_depths.clear()
		app._process_pokes(entry,button.to_global(Vector3(0,0,button.front_z_m+z)),1.0/72.0)
		app._finish_pokes()

func _run() -> void:
	if FileAccess.file_exists(settings_path):DirAccess.remove_absolute(settings_path)
	app=load("res://main.tscn").instantiate()
	app.tutorial_settings_path=settings_path
	root.add_child(app);app.set_process(false);app.set_process_unhandled_input(false)
	app.model.async_processing=false
	_check(app.tab=="learn" and app.tutorial.active,"Fresh launch opens Learn")
	_check(not app.model.mounted and app.model.records.is_empty() and not app.model.running,"Opening tutorial leaves fresh lab untouched")
	_step("welcome");_next("comfort")
	app._action("tutorial:practice")
	_check(app.tab=="session" and not app.tutorial_panel.visible,"Practice opens actual Session controls")
	_check(app.lesson_navigation[1].enabled,"Skip remains available outside Learn")
	app._action("lower");_next("touch")
	var next=_button("tutorial:next")
	_check(not next.enabled and next.collision_layer==0,"Unmet objective visibly disables Next and its collider")
	_press(next);_step("touch")
	_press(_button("tutorial:touch"))
	_check(app.tutorial.view(app._tutorial_context()).ready,"Actual front fingertip press satisfies touch practice")
	_next("load")
	app._action("tutorial:practice")
	var records_before=app.model.records.size()
	for button in app.buttons:
		if button.is_visible_in_tree():button.set_enabled(false)
	_press(_button("tutorial:skip_step"))
	_step("load")
	_check(app.model.records.size()==records_before,"Hidden tutorial contact cannot navigate or affect model")
	app._rebuild_menu()
	app._action("mount");_next("home")
	app._action("home");_next("dials")
	app._set_dial("probe",6.05)
	_check(not app.tutorial.view(app._tutorial_context()).ready,"Dial practice requires restoring the reference")
	app._action("home");_next("guard")
	app._action("guard");_next("baseline")
	app._action("guard");app._action("baseline")
	_check(not app.model.running and not app.tutorial.view(app._tutorial_context()).ready,"Rejected open-guard command cannot complete baseline lesson")
	app._action("guard");_run_capture("baseline");_next("phasor");_next("analyzer")
	app._action("chart");app._action("chart");_next("trial_fit")
	app._action("guard");app._action("fit_trial");_next("trial_measure")
	app._action("guard");_run_capture("trial_a");_next("solve")
	app._action("solve");_next("verify")
	app._action("guard");app._action("apply");app._action("guard")
	_check(not app.tutorial.view(app._tutorial_context()).ready,"Installing a predicted correction is not verification")
	_run_capture("verify");_next("repeat")
	_run_capture("repeat");_next("sweep")
	_run_capture("sweep");_next("two_plane")
	app._action("mode");_next("estop")
	app._action("estop")
	_check(not app.tutorial.view(app._tutorial_context()).ready,"Latched E-stop cannot satisfy recovery")
	app._action("recover");app._action("home");_next("faults")
	for command in ["fault_sensor","fault_tach"]:
		app._action(command);app._action("recover");app._action("home")
	_next("references");_next("report")
	app._action("save")
	_check(FileAccess.file_exists(app.saved_path),"Report lesson writes an actual file")
	var report=JSON.parse_string(FileAccess.get_file_as_string(app.saved_path))
	_check(report is Dictionary and report.has("tutorial") and report.tutorial.step_id=="report","Saved report includes separate tutorial context")
	DirAccess.remove_absolute(app.saved_path)
	_next("session");_next("finish")
	var lab_snapshot=JSON.stringify(app.model.report())
	app._action("tutorial:next")
	_check(not app.tutorial.active and app.tutorial.completed and not app.tutorial.startup_enabled,"Finish closes guide and disables startup persistently")
	_check(JSON.stringify(app.model.report())==lab_snapshot,"Finishing does not mutate laboratory state")
	var reloaded=app.Tutorial.new(settings_path)
	_check(not reloaded.should_autostart() and reloaded.completed,"Completion preferences survive reload")
	app._action("tab:learn")
	_check(app.tutorial.active and app.tutorial.index==0,"Learn manually restarts even with startup disabled")
	_check(JSON.stringify(app.model.report())==lab_snapshot,"Manual restart preserves captures and configuration")
	app._action("tutorial:skip")
	_check(not app.tutorial.active and app.tab=="operate" and not app.tutorial.startup_enabled,"Skip closes tour without altering startup setting")
	app._action("tab:learn");app._action("tutorial:startup")
	_check(app.Tutorial.new(settings_path).should_autostart(),"Explicit startup ON works after completion")
	app._action("new")
	_check(app.tutorial.startup_enabled and app.tutorial.active,"New Session does not discard tutorial preferences")
	_check(not app._tutorial_context().saved_report,"New Session does not inherit a prior report path")
	app._action("tutorial:skip_step")
	app._action("tutorial:back");_step("welcome")
	app._action("tutorial:restart");_step("welcome")
	app.tutorial.index=app.tutorial.steps.size()-1
	app._action("tutorial:skip_step")
	_check(not app.tutorial.active and app.tab=="operate","Skipping last lesson exits cleanly")
	app._action("tab:learn");app._action("tutorial:startup")
	app.queue_free();await process_frame
	app=load("res://main.tscn").instantiate();app.tutorial_settings_path=settings_path
	root.add_child(app);app.set_process(false)
	_check(app.tab=="operate" and not app.tutorial.active,"Persisted startup OFF opens the ordinary lab on next launch")
	app._action("tab:learn")
	_check(app.tutorial.active and app.tutorial_panel.visible,"Disabled startup leaves manual Learn available")
	app.queue_free();await process_frame
	print("TUTORIAL APP: expected malformed-settings diagnostic follows; recovery is asserted.")
	var malformed=FileAccess.open(settings_path,FileAccess.WRITE)
	malformed.store_string("[invalid settings");malformed.close()
	app=load("res://main.tscn").instantiate();app.tutorial_settings_path=settings_path
	root.add_child(app);app.set_process(false)
	_check(app.tutorial.active and not app.tutorial.settings_error.is_empty() and app.status.contains("Could not load"),"Corrupt settings recover to default tutorial and expose the load failure")
	app.queue_free();await process_frame
	DirAccess.remove_absolute(settings_path)
	print("TUTORIAL APP TESTS: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
