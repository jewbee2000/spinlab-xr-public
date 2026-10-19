extends SceneTree
## Floating guide integration: actual controller dispatch, physical contacts,
## scientific measurements, menu isolation, reports, and persistent preferences.
class SilentGuide extends "res://scripts/main.gd":
	## Audio is covered by the ordinary scene suite; isolate repeated headless
	## app teardown from the asynchronous audio-server playback lifetime.
	func _setup_sound() -> void:pass

class TestController extends Node3D:
	var tracker: StringName = &"right_hand"
	var stick: Vector2 = Vector2.ZERO
	func get_vector2(_input_name: String) -> Vector2:
		return stick

var checks: int = 0
var failures: int = 0
var app
var left: Dictionary
var right: Dictionary
var settings_path: String = ""

func _initialize() -> void:
	settings_path = "user://tutorial-app-test-%d.cfg" % Time.get_ticks_usec()
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TUTORIAL APP: " + description)

func _spawn() -> void:
	app = SilentGuide.new()
	app.tutorial_settings_path = settings_path
	root.add_child(app)
	app.set_process(false)
	app.set_process_unhandled_input(false)
	app.model.async_processing = false
	left = _hand(&"left_hand")
	right = _hand(&"right_hand")

func _hand(side: StringName) -> Dictionary:
	var controller = TestController.new()
	controller.tracker = side
	app.rig.add_child(controller)
	var grip = Node3D.new()
	app.rig.add_child(grip)
	grip.position = Vector3(3, 2, 3)
	var entry: Dictionary = app._make_hand_entry(controller, grip)
	entry.tracked = true
	var ray := RayCast3D.new()
	ray.target_position = Vector3(0, 0, -4)
	ray.collision_mask = 2
	controller.add_child(ray)
	entry.ray = ray
	app.controllers.append(entry)
	return entry

func _step(id: String) -> void:
	_check(app.tutorial.view(app._tutorial_context()).id == id, "Lesson reached: " + id)

func _next(id: String) -> void:
	if app.menu_open:
		app._set_menu_open(false)
	_check(app.tutorial.view(app._tutorial_context()).ready, "Practice is ready before A continues")
	app._controller_pressed("ax_button", right)
	_step(id)

func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	app._unhandled_input(event)

func _press(button) -> void:
	_check(is_instance_valid(button), "Physical fixture command has a real cap")
	if not is_instance_valid(button):
		return
	if app.menu_open:
		app._set_menu_open(false)
	# Simulate deliberate withdrawal/approach time, including button debounce.
	var positions: Array = []
	for frame in range(10):
		positions.append(0.06)
	positions.append(-0.008)
	positions.append(0.06)
	for z in positions:
		app.frame_latches.clear()
		app.frame_depths.clear()
		app._process_pokes(left, button.to_global(Vector3(0, 0, button.front_z_m + z)), 1.0 / 72.0)
		app._finish_pokes()

func _physical(command: String) -> void:
	_press(app.geometry.physical_by_action.get(command))

func _menu(tab: String, command: String) -> void:
	app._set_menu_open(true)
	app._physical_action("tab:" + tab, "pointer")
	app._physical_action(command, "pointer")

func _run_capture(kind: String) -> void:
	var count_before: int = app.model.records.size()
	_physical(kind)
	_check(app.model.running, "Physical console starts acquisition: " + kind)
	app._update_ui()
	_check(not app.tutorial.view(app._tutorial_context()).ready, "Running capture cannot satisfy measurement lesson")
	for sample_index in range(800):
		app.model.tick(0.02)
		if not app.model.running and not app.model.processing and app.model.rpm < 0.1:
			break
	app._update_ui()
	_check(not app.model.running and app.model.rpm < 0.1, "Acquisition coasts to zero: " + kind)
	_check(app.model.records.size() == count_before + 1, "Exactly one accepted record is committed: " + kind)

func _run() -> void:
	_spawn()
	await _test_initial_guide_and_navigation()
	_test_full_measured_workflow()
	await _test_preferences_and_relaunch()
	if FileAccess.file_exists(settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	print("TUTORIAL APP TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_initial_guide_and_navigation() -> void:
	_check(not app.menu_open and app.tutorial.active and app.tutorial_panel.visible, "Fresh launch shows floating guide with menu hidden")
	_check(app.tutorial_panel.get_parent() != app.controls and not app.controls.is_ancestor_of(app.tutorial_panel), "Guide has an independent world parent rather than a menu tab")
	_check(app.tutorial_panel.interactive_buttons.is_empty() and app.tutorial_panel.find_children("*", "CollisionObject3D", true, false).is_empty(), "Guide has no fingertip buttons or ray colliders")
	_check(app.lesson_navigation.is_empty(), "No legacy lesson buttons overlap fixture or menu")
	_check(not app.model.mounted and app.model.records.is_empty() and not app.model.running, "Initial guidance leaves fresh lab untouched")
	_step("welcome")
	app._controller_pressed("by_button", right)
	_check(app.menu_open and not app.tutorial_panel.visible and app.controls.visible, "B opens explicit controller-pointer menu and hides guide")
	var initial_index: int = app.tutorial.index
	app._controller_pressed("ax_button", right)
	_check(app.tutorial.index == initial_index, "A does not advance guide while menu is open")
	_check(app.menu_tab_buttons.size() == 4 and not app.menu_tab_buttons.has("learn"), "Menu has four operational tabs and no guide tab")
	# This selection checks tab layout only; real pointer input is exercised on
	# the pointer-practice page below so its gate begins without prior evidence.
	app._action("tab:balance")
	_check(app.tab == "balance" and app.menu_tab_buttons.balance.normal_color != app.menu_tab_buttons.operate.normal_color, "Menu highlights its selected operational tab")
	app._controller_pressed("by_button", left)
	_check(not app.menu_open and app.tutorial_panel.visible, "Y closes menu and restores visible guide")
	_next("comfort")
	app._controller_pressed("ax_button", left)
	_step("welcome")
	_check(not app.model.running and not app.model.mounted, "Controller guide navigation does not operate lab")
	_key(KEY_SPACE)
	_step("comfort")
	_key(KEY_BACKSPACE)
	_step("welcome")
	_key(KEY_SPACE)
	_step("comfort")
	_key(KEY_M)
	_check(app.menu_open, "Desktop M opens same explicit menu")
	_key(KEY_M)
	_check(not app.menu_open, "Desktop M closes menu without advancing guide")
	app._update_navigation(0.05)
	left.node.stick = Vector2(0, 0.8)
	var height_before: float = app.station.position.y
	app._update_navigation(0.05)
	left.node.stick = Vector2.ZERO
	_check(app.height_changed and app.station.position.y > height_before, "Actual left-stick adjustment supplies comfort practice evidence")
	_next("touch")
	app._controller_pressed("ax_button", right)
	_step("touch")
	_check(not app.tutorial.view(app._tutorial_context()).ready, "A cannot bypass unfinished menu-pointer practice")
	app._controller_pressed("by_button", right)
	var tab_button = app.menu_tab_buttons.operate
	right.node.global_position = tab_button.global_position + tab_button.global_basis.z * 0.5
	right.node.look_at(tab_button.global_position, Vector3.UP)
	right.aim_tracked = true
	app._controller_released("trigger_click", right)
	await physics_frame
	right.ray.force_raycast_update()
	_check(right.ray.is_colliding() and right.ray.get_collider() == tab_button, "Actual controller ray resolves enabled visible Operate tab")
	app._controller_pressed("trigger_click", right)
	_check(app.tab == "operate" and not app.tutorial.view(app._tutorial_context()).ready, "Real trigger selection is accepted but guide waits for menu closure")
	app._controller_pressed("by_button", right)
	_check(app.tutorial.view(app._tutorial_context()).ready, "Pointer selection plus B/Y closure teaches preferred command input without a hand press")
	_check(not app.model.homed and not app.model.mounted and app.model.records.is_empty(), "Pointer practice does not fabricate accepted preparation or measurements")
	_next("load")
	var index_before: int = app.tutorial.index
	var model_before: String = JSON.stringify(app.model.report())
	app._action("tutorial:practice")
	_check(not app.menu_open and app.tutorial.index == index_before and JSON.stringify(app.model.report()) == model_before, "Practice compatibility closes menu without operating or navigating the lab")

func _test_full_measured_workflow() -> void:
	app._action("mount")
	_next("home")
	_physical("home")
	_next("dials")
	app._set_dial("probe", 6.05)
	_check(not app.tutorial.view(app._tutorial_context()).ready, "Dial practice requires reference restoration")
	_physical("home")
	_next("guard")
	app._action("guard")
	_next("baseline")
	app._action("guard")
	_physical("baseline")
	_check(not app.model.running and not app.tutorial.view(app._tutorial_context()).ready, "Rejected open-guard command cannot complete baseline objective")
	app._action("guard")
	_physical("baseline")
	app.model.tick(0.2)
	_physical("stop")
	app.model.tick(2.0)
	app._update_ui()
	_check(app.model.records.is_empty() and not app.tutorial.view(app._tutorial_context()).ready, "Controlled Stop aborts partial capture without teaching an accepted baseline")
	_run_capture("baseline")
	_next("phasor")
	_next("analyzer")
	_menu("diagnostic", "chart")
	app._physical_action("chart", "pointer")
	_check(app.tutorial.active and app.menu_open and not app.tutorial_panel.visible, "Menu analyzer work preserves active lesson while guide is hidden")
	_next("trial_fit")
	app._action("guard")
	_physical("fit_trial")
	_next("trial_measure")
	app._action("guard")
	_run_capture("trial_a")
	_next("solve")
	_physical("solve")
	_next("verify")
	app._action("guard")
	_physical("apply")
	app._action("guard")
	_check(not app.tutorial.view(app._tutorial_context()).ready, "Calculated correction is not itself verification")
	_run_capture("verify")
	_next("repeat")
	_run_capture("repeat")
	_next("sweep")
	_run_capture("sweep")
	_next("two_plane")
	_physical("mode")
	_next("estop")
	_physical("estop")
	_check(not app.tutorial.view(app._tutorial_context()).ready, "Latched E-stop cannot satisfy recovery")
	_physical("recover")
	_physical("home")
	_next("faults")
	for command in ["fault_sensor", "fault_tach"]:
		_menu("diagnostic", command)
		_physical("recover")
		_physical("home")
	_next("references")
	_next("report")
	_physical("save")
	_check(FileAccess.file_exists(app.saved_path), "Physical Save Report writes an actual JSON file")
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(app.saved_path))
	_check(report is Dictionary and report.has("tutorial") and report.tutorial.step_id == "report", "Report keeps separate tutorial context and current page")
	_check(report.has("operator_navigation") and is_equal_approx(float(report.operator_navigation.height_m), app.station.position.y), "Report records actual operator height/navigation context")
	var paused_index: int = app.tutorial.index
	_menu("session", "tutorial:toggle")
	_check(not app.tutorial.active and app.guide_paused and app.tutorial.index == paused_index, "Pause retains the current guide page")
	app._physical_action("tutorial:toggle", "pointer")
	_check(app.tutorial.active and not app.guide_paused and app.tutorial.index == paused_index and app.tutorial.view(app._tutorial_context()).ready, "Resume retains page and successful practice evidence")
	app._set_menu_open(false)
	var saved_path: String = app.saved_path
	var count_before: int = app.model.records.size()
	app.active_plane = 1
	app.model.processing = true
	app._action("new")
	_check(app.active_plane == 1 and app.saved_path == saved_path, "Rejected New Session preserves active plane and saved-file reference")
	_check(app.model.records.size() == count_before and app.tutorial.view(app._tutorial_context()).ready, "Rejected reset preserves records and confirmed save evidence")
	app.model.processing = false
	app.active_plane = 0
	_next("session")
	_next("finish")
	var preserved: String = JSON.stringify(app.model.report())
	app._controller_pressed("ax_button", right)
	_check(not app.tutorial.active and app.tutorial.completed and not app.tutorial.startup_enabled and not app.tutorial_panel.visible, "Final A finishes guide and persists startup OFF")
	_check(JSON.stringify(app.model.report()) == preserved, "Finishing leaves measurements and configuration unchanged")
	var preferences = app.Tutorial.new(settings_path)
	_check(preferences.completed and not preferences.should_autostart(), "Completion preferences reload correctly")
	_menu("session", "tutorial:restart")
	_check(app.tutorial.active and app.tutorial.index == 0 and not app.tutorial_panel.visible, "Session restart begins guide while explicit menu remains open")
	_check(JSON.stringify(app.model.report()) == preserved, "Manual restart retains laboratory data")
	app._set_menu_open(false)
	_check(app.tutorial_panel.visible, "Closing menu reveals restarted floating guide")
	_menu("session", "tutorial:toggle")
	_check(not app.tutorial.active and not app.tutorial.startup_enabled, "Session Pause leaves startup preference unchanged")
	app._physical_action("tutorial:toggle", "pointer")
	_check(app.tutorial.active and app.tutorial.index == 0, "Session Start remains available with startup disabled")
	app._physical_action("tutorial:startup", "pointer")
	_check(app.Tutorial.new(settings_path).should_autostart(), "Explicit startup ON persists after completion")
	app._action("new")
	_check(app.tutorial.active and app.tutorial.startup_enabled and not app._tutorial_context().saved_report, "New Session preserves guide preference while clearing prior save reference")
	app._physical_action("tutorial:skip_step", "pointer")
	app._action("tutorial:back")
	_step("welcome")
	app._action("tutorial:restart")
	_step("welcome")
	app.tutorial.index = app.tutorial.steps.size() - 1
	app._action("tutorial:skip_step")
	_check(not app.tutorial.active, "Explicit final-step skip closes guide without operating lab")
	app._action("tutorial:startup")
	_check(not app.tutorial.startup_enabled, "Startup OFF is available even while guide paused")
	if FileAccess.file_exists(saved_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(saved_path))

func _test_preferences_and_relaunch() -> void:
	app.queue_free()
	await process_frame
	_spawn()
	_check(not app.menu_open and not app.tutorial.active and not app.tutorial_panel.visible, "Persisted startup OFF launches ordinary lab with no forced menu")
	_menu("session", "tutorial:restart")
	app._set_menu_open(false)
	_check(app.tutorial.active and app.tutorial_panel.visible, "Disabled startup still allows a manual floating guide")
	app.queue_free()
	await process_frame
	print("TUTORIAL APP: expected malformed-settings diagnostic follows; fallback is asserted.")
	var malformed = FileAccess.open(settings_path, FileAccess.WRITE)
	malformed.store_string("[invalid settings")
	malformed.close()
	_spawn()
	_check(app.tutorial.active and not app.menu_open and not app.tutorial.settings_error.is_empty() and app.status.contains("Could not load"), "Corrupt settings show diagnostic and recover to default floating guide")
	app.queue_free()
	await process_frame
