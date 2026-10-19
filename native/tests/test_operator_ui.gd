extends SceneTree
## Real application routing with deterministic tracked controller inputs.
## This does not establish physical Quest tracking, stereo, or comfort.
const DT: float = 1.0 / 72.0

class SilentOperator extends "res://scripts/main.gd":
	## Isolate unchanged audio-server teardown from input/geometry contracts.
	## The production scene has no children beyond this same main script.
	var simulate_save_failure: bool = false
	func _setup_sound() -> void:pass
	func _init() -> void:narration_enabled=false;narration_settings_path=""
	func _save_report() -> void:
		if simulate_save_failure:
			status = "Report could not be written: injected I/O failure."
			_update_ui()
			return
		super._save_report()

class SimPose extends RefCounted:
	var tracking_confidence: int = XRPose.XR_TRACKING_CONFIDENCE_HIGH

class SimGrip extends Node3D:
	var tracking: bool = true
	var pose: RefCounted = SimPose.new()
	func get_pose() -> RefCounted:return pose
	func get_has_tracking_data() -> bool:return tracking

class SimController extends Node3D:
	var tracker: StringName = &"right_hand"
	var grip: float = 0.0
	var trigger: float = 0.0
	var stick: Vector2 = Vector2.ZERO
	var tracking: bool = true
	var pose: RefCounted = SimPose.new()
	func get_float(action: String) -> float:return grip if action == "grip" else trigger if action == "trigger" else 0.0
	func get_vector2(_action: String) -> Vector2:return stick
	func is_button_pressed(_action: String) -> bool:return false
	func get_pose() -> RefCounted:return pose
	func get_has_tracking_data() -> bool:return tracking

class SimRay extends Node3D:
	var target: Node3D
	var collision_mask: int = 2
	func force_raycast_update() -> void:pass
	func is_colliding() -> bool:return is_instance_valid(target) and not target.is_queued_for_deletion()
	func get_collider() -> Node3D:return target
	func get_collision_point() -> Vector3:return target.global_position if is_instance_valid(target) else Vector3.ZERO

var checks: int = 0
var failures: int = 0
var app
var left: Dictionary
var right: Dictionary

func _initialize() -> void:call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("OPERATOR UI: " + description)

func _near(actual: Vector3, expected: Vector3, description: String) -> void:
	_check(actual.distance_to(expected) < 0.00001, description)

func _run() -> void:
	app = SilentOperator.new()
	app.narration_enabled=false;app.narration_settings_path=""
	app.tutorial_settings_path = ""
	root.add_child(app)
	app.set_process(false)
	app.set_process_unhandled_input(false)
	app.model.async_processing = false
	_check(not app.menu_open and not app.controls.visible, "Fresh application launch leaves the explicit menu closed")
	_check(app.tutorial.active and app.tutorial_panel.visible, "Default startup presents the floating guide")
	_check(not app.menu_open and not app.controls.visible, "Startup guide does not force the application menu open")
	_check(not app.model.mounted and app.model.records.is_empty() and not app.model.running, "Startup instruction does not operate the fixture")
	for button in app.buttons:
		if button.get_meta("ui", false):_check(button.collision_layer == 0, "Startup menu colliders are disabled behind the floating guide")
	# The test camera has a real local offset from XROrigin3D, as in room-scale
	# tracking. Moving only the camera or using the origin as collision position
	# would violate the relationships asserted below.
	app.camera.reparent(app.rig, false)
	left = _hand(&"left_hand")
	right = _hand(&"right_hand")
	_test_start_and_menu()
	_test_pointer_rearming()
	_test_pointer_outcome_boundary()
	_test_menu_placement()
	await _test_collision_layers()
	_test_physical_fingertip()
	_test_guide_controls()
	_test_navigation()
	_test_navigation_interruptions()
	_test_height_and_room()
	_test_anchor_recovery()
	_test_hand_control_guides()
	_test_callout_after_controller_poll()
	print("OPERATOR UI TESTS: %d checks, %d failures" % [checks, failures])
	app._cancel_hand_interactions()
	app.controllers.clear()
	left.clear()
	right.clear()
	app.queue_free()
	await process_frame
	app = null
	quit(0 if failures == 0 else 1)

func _hand(side: StringName) -> Dictionary:
	var controller := SimController.new()
	controller.tracker = side
	app.rig.add_child(controller)
	var grip := SimGrip.new()
	app.rig.add_child(grip)
	grip.position = Vector3(2.6, 2.0, 2.3)
	var entry: Dictionary = app._make_hand_entry(controller, grip)
	var ray := SimRay.new()
	controller.add_child(ray)
	entry.ray = ray
	var beam := MeshInstance3D.new()
	beam.mesh = CylinderMesh.new()
	controller.add_child(beam)
	entry.beam = beam
	app.controllers.append(entry)
	return entry

func _fresh() -> void:
	app._cancel_hand_interactions()
	app.model.reset()
	app.model.async_processing = false
	app.rig.global_transform = Transform3D.IDENTITY
	app.camera.transform = Transform3D(Basis.IDENTITY, Vector3(0.3, 1.7, 0.2))
	app.station.position.y = 0.0
	app.geometry.guard_preview = -1.0
	app.geometry.update_state(app.model.telemetry())
	app.app_has_focus = true
	app.xr_has_focus = true
	app._apply_input_focus()
	app.walk_enabled = true
	app.simulate_save_failure = false
	app.head_tracking_override = null
	app.walk_distance_m = 0.0
	app.height_changed = false
	app.tab = "balance"
	app.tutorial.skip()
	app.guide_paused = false
	for entry in [left, right]:
		entry.node.grip = 0.0
		entry.node.trigger = 0.0
		entry.node.stick = Vector2.ZERO
		entry.node.tracking = true
		entry.node.pose.tracking_confidence = XRPose.XR_TRACKING_CONFIDENCE_HIGH
		entry.grip_node.tracking = true
		entry.grip_node.pose.tracking_confidence = XRPose.XR_TRACKING_CONFIDENCE_HIGH
		entry.grip_node.position = Vector3(2.6, 2.0, 2.3)
		entry.ray.target = null
	app._set_menu_open(false)
	app._rebuild_menu()
	app._update_controllers(DT)

func _ui_button(command: String):
	for button in app.buttons:
		if is_instance_valid(button) and not button.is_queued_for_deletion() and button.action == command and button.get_meta("ui", false):return button
	_check(false, "Required menu button exists: " + command)
	return null

func _test_start_and_menu() -> void:
	_fresh()
	_check(not app.menu_open and not app.controls.visible, "Station starts with its menu hidden")
	for button in app.buttons:
		if button.get_meta("ui", false):_check(not button.enabled and button.collision_layer == 0, "Hidden menu leaves no active collider")
	_check(app.menu_tab_buttons.size() == 3 and not app.menu_tab_buttons.has("operate") and not app.menu_tab_buttons.has("learn"), "Menu omits redundant Operate tab and keeps three categories plus separate instructions")
	app.tutorial.start(app._tutorial_context())
	app._refresh_tutorial()
	_check(app.tutorial_panel.visible and not app.controls.is_ancestor_of(app.tutorial_panel), "Guide remains independent of the hidden application menu")
	var snapshot: String = JSON.stringify(app.model.report())
	app._controller_pressed("by_button", right)
	_check(app.menu_open and app.controls.visible and not app.tutorial_panel.visible, "B opens pointer menu and hides guide content")
	_check(right.controller_visual.visible and not right.hand.visible, "Open menu replaces gloves with controller representations")
	app._controller_released("by_button", right)
	_check(app.menu_open, "B release cannot toggle the menu a second time")
	for key in ["balance", "diagnostic", "session"]:
		app._action("tab:" + key)
		var selected: int = 0
		for tab_key in app.menu_tab_buttons:
			var button = app.menu_tab_buttons[tab_key]
			if button.get_meta("selected", false):selected += 1
			_check(bool(button.get_meta("selected", false)) == (tab_key == key), "Current category has truthful selection metadata")
		_check(selected == 1, "Exactly one menu category is highlighted")
	for button in app.buttons:
		if button.get_meta("ui", false) and button.is_visible_in_tree():_check(button.action not in ["lower", "raise", "distance"], "Menu has no duplicate station-height/distance controls")
	app._controller_pressed("by_button", left)
	_check(not app.menu_open and left.hand.visible and not left.controller_visual.visible, "Y closes menu and restores gloves")
	_check(app.tutorial_panel.visible, "Closing menu restores the active guide")
	_check(JSON.stringify(app.model.report()) == snapshot, "Mode and category transitions preserve laboratory data")

func _test_pointer_rearming() -> void:
	_fresh()
	right.node.trigger = 1.0
	app._controller_pressed("by_button", right)
	right.ray.target = app.menu_tab_buttons.diagnostic
	app._update_controllers(DT)
	app._controller_pressed("trigger_click", right)
	_check(app.tab == "balance" and not right.trigger_armed, "Opening menu with trigger held cannot select")
	right.node.trigger = 0.0
	app._update_controllers(DT)
	_check(right.trigger_armed and right.aim_tracked, "Tracked neutral trigger rearms menu selection")
	right.node.trigger = 1.0
	app._controller_pressed("trigger_click", right)
	_check(app.tab == "diagnostic" and not right.trigger_armed, "Fresh tracked trigger selects the pointed real UI command once")
	right.ray.target = app.menu_tab_buttons.session
	app._controller_pressed("trigger_click", right)
	_check(app.tab == "diagnostic", "A held trigger cannot activate a replacement menu command")
	right.node.trigger = 0.0
	app._update_controllers(DT)
	right.node.trigger = 1.0
	right.node.tracking = false
	app._update_controllers(DT)
	app._controller_pressed("trigger_click", right)
	_check(app.tab == "diagnostic", "Lost aim tracking blocks pointer commands")
	right.node.tracking = true
	app._update_controllers(DT)
	_check(not right.trigger_armed, "Aim recovery with a held trigger still requires neutral")
	right.node.trigger = 0.0
	app._update_controllers(DT)
	right.ray.target = app.geometry.rotor_grab
	right.node.trigger = 1.0
	app._controller_pressed("trigger_click", right)
	_check(not app.model.mounted and app.grab_owners.is_empty(), "Pointer cannot remotely acquire a mechanical rotor handle")
	right.node.trigger = 0.0
	app._update_controllers(DT)
	right.ray.target = app.geometry.probe_home_button
	app.model.mount_rotor()
	right.node.trigger = 1.0
	app._controller_pressed("trigger_click", right)
	_check(not app.model.homed, "Pointer rejects a physical button even if a fake ray bypasses its layer mask")
	app._action("tab:operate")
	right.node.trigger = 0.0
	app._update_controllers(DT)
	right.ray.target = app.geometry.guard_handle
	right.node.trigger = 1.0
	app._controller_pressed("trigger_click", right)
	_check(not app.model.guard_closed, "Pointer cannot remotely move a guard handle")
	for button in app.buttons:
		if button.get_meta("ui", false) and button.is_visible_in_tree():_check(button.action not in ["mount", "guard"], "Menu omits instructional targets that cannot operate physical handles")
	app._set_menu_open(false)
	right.node.trigger = 0.0
	app._update_controllers(DT)
	right.ray.target = app.menu_tab_buttons.session
	app._controller_pressed("trigger_click", right)
	_check(not app.menu_open and app.tab == "balance", "Trigger has no distant UI behavior with menu closed")

func _test_collision_layers() -> void:
	_fresh()
	app._set_menu_open(true)
	var physical = app._button(app.station, "LAYER CHECK", "home", Vector3.ZERO, 0.1, 0.1)
	var ui = app._button(app.controls, "LAYER CHECK", "chart", Vector3.ZERO, 0.1, 0.1)
	physical.global_position = Vector3(20, 20, 19)
	ui.global_position = Vector3(20, 20, 18)
	_check(physical.collision_layer == 1 and ui.collision_layer == 2, "Actual world-button factory separates physical and UI collision layers")
	var ray := RayCast3D.new()
	app.add_child(ray)
	ray.global_position = Vector3(20, 20, 20)
	ray.target_position = Vector3(0, 0, -4)
	ray.collision_mask = 2
	await physics_frame
	ray.force_raycast_update()
	_check(ray.is_colliding() and ray.get_collider() == ui, "UI-mask ray reaches UI behind a nearer physical collider")
	app._set_menu_open(false)
	await physics_frame
	ray.force_raycast_update()
	_check(ui.collision_layer == 0 and not ray.is_colliding(), "Closing menu removes hidden UI from pointer collision")
	app.buttons.erase(physical)
	app.buttons.erase(ui)
	physical.queue_free()
	ui.queue_free()
	ray.queue_free()
	await process_frame

func _test_pointer_outcome_boundary() -> void:
	_fresh()
	app.saved_path = ""
	app.tutorial.start(app._tutorial_context())
	while app.tutorial.steps[app.tutorial.index].id != "report":app.tutorial.skip_step()
	_check(not app.tutorial.view(app._tutorial_context()).ready, "Report objective begins without a saved result")
	# _physical_action logs pointer contact before command dispatch. Selection
	# telemetry is not the accepted save outcome, which may still fail.
	app._interaction_event("pointer", "save")
	_check(not app.tutorial.view(app._tutorial_context()).ready, "Pointer selection telemetry cannot invent a successful report write")
	app._set_menu_open(true)
	app._action("tab:session")
	app.simulate_save_failure = true
	_pointer_select(_ui_button("save"))
	_check(app.status.contains("injected I/O failure"), "Failed-save injection follows the actual menu pointer/command route")
	_check(not app.tutorial.view(app._tutorial_context()).ready, "Failed pointer save cannot satisfy the report objective")
	_check(app.saved_path.is_empty(), "Failed-save command does not invent a saved file reference")
	app.simulate_save_failure = false
	app._action("tab:balance")
	_pointer_select(_ui_button("apply"))
	_check(app.model.solution.is_empty(), "Pointer Apply is rejected without a measured solution")
	_check(not app.tutorial.view(app._tutorial_context()).ready, "Rejected pointer Apply cannot create an accepted application checkpoint")

func _pointer_select(button) -> void:
	right.ray.target = button
	right.node.trigger = 0.0
	app._update_controllers(DT)
	right.node.trigger = 1.0
	app._controller_pressed("trigger_click", right)

func _test_menu_placement() -> void:
	_fresh()
	var center: Vector3 = app.station.to_global(Vector3(0, 0, -1.4))
	var offsets := [Vector3(0, 0, 0.95), Vector3(-1.4, 0, 0), Vector3(1.4, 0, 0), Vector3(0, 0, -1.55), Vector3(-1.4, 0, -1.0), Vector3(1.4, 0, 1.0)]
	for height in [-0.3, 0.0, 0.3]:
		app.station.position.y = height
		for offset in offsets:
			app._set_menu_open(false)
			app.camera.global_position = Vector3(center.x + offset.x, 1.6, center.z + offset.z)
			app.camera.look_at(app.station.to_global(Vector3(0, 1.2, -1.4)), Vector3.UP)
			app._set_menu_open(true)
			_check(app.menu_open and app.controls.visible, "Menu opens from each tested bench-perimeter position")
			_check(app._menu_placement_clear(), "Menu avoids fixture/monitor: station height=" + str(height) + ", head=" + str(app.camera.global_position) + ", menu=" + str(app.controls.global_position))
		_check(app.monitor.position.is_equal_approx(Vector3(-1.55,1.45,-1.20)), "Analyzer is mounted low and left rather than above the guard")
		_check(is_equal_approx(app.get_node("AnalyzerFloorStand/AnalyzerStandFoot").global_position.y,0.0125), "Analyzer stand foot stays on the floor while bench height changes")
	_fresh()
	app.tutorial.start(app._tutorial_context())
	for eye in [1.2,1.6,1.75]:
		for z in [0.0,0.2]:
			app.camera.global_transform=Transform3D(Basis.IDENTITY,Vector3(0,eye,z))
			app._refresh_tutorial()
			_check(app.guide_placement.visible,"Rotor prompt available beside target for default seated/standing views")
			if app.guide_placement.visible:
				_check(app.tutorial_panel.global_position.distance_to(app.geometry.rotor_grab.global_position)<0.49,"Prompt remains adjacent to rotor, independent of head")
				for bound in app._guide_obstacles().bounds:_check(not app.guide_placement.bounds.intersects(bound),"Whole prompt clears actual station geometry")
	_fresh()

func _reading_obstacles() -> Array[AABB]:
	var result:Array[AABB]=[]
	var meshes:Array=[]
	for branch in [app.geometry.guard,app.geometry.probe]:meshes.append_array(branch.find_children("*","GeometryInstance3D",true,false))
	for child in app.geometry.get_children():
		if child is GeometryInstance3D and str(child.name).begins_with("Lift"):meshes.append(child)
	for item in meshes:
		if not item.is_visible_in_tree() or str(item.name).begins_with("GuardGlass"):continue
		if str(item.name)=="GuardExtrusions":
			for x in [-0.30,0.30]:
				for z in [0.01,0.60]:result.append(item.global_transform*AABB(Vector3(x-0.007,0,z-0.007),Vector3(0.014,0.40,0.014)))
				for y in [0.015,0.39]:result.append(item.global_transform*AABB(Vector3(x-0.007,y-0.007,0),Vector3(0.014,0.014,0.60)))
			for z in [0.01,0.60]:
				for y in [0.015,0.39]:result.append(item.global_transform*AABB(Vector3(-0.30,y-0.007,z-0.007),Vector3(0.60,0.014,0.014)))
		elif item is MeshInstance3D and item.mesh:result.append(item.global_transform*item.mesh.get_aabb())
		elif item is MultiMeshInstance3D and item.multimesh and item.multimesh.mesh:
			for index in item.multimesh.instance_count:result.append(item.global_transform*item.multimesh.get_instance_transform(index)*item.multimesh.mesh.get_aabb())
	return result

func _surface_visible(surface:Node3D,half:Vector2,obstacles:Array[AABB]) -> bool:
	for x in [-half.x,-half.x*0.5,0.0,half.x*0.5,half.x]:
		for y in [-half.y,-half.y*0.5,0.0,half.y*0.5,half.y]:
			var point:Vector3=surface.to_global(Vector3(x,y,0.034 if surface==app.monitor else 0.008))
			for obstacle in obstacles:
				if obstacle.intersects_segment(app.camera.global_position,point)!=null:
					print("READING_OBSTRUCTION surface=",surface.name," eye=",app.camera.global_position," point=",point," box=",obstacle)
					return false
	return true

func _poke(entry: Dictionary, button, offset: float) -> void:
	app.frame_latches.clear()
	app.frame_depths.clear()
	app._process_pokes(entry, button.to_global(Vector3(0, 0, button.front_z_m + offset)), DT)
	app._finish_pokes()

func _press(entry: Dictionary, button) -> void:
	_poke(entry, button, 0.06)
	_poke(entry, button, -0.008)

func _test_physical_fingertip() -> void:
	_fresh()
	app.model.mount_rotor()
	var home = app.geometry.probe_home_button
	left.grip_down = true
	_press(left, home)
	_check(app.model.homed, "Loose grip with no acquired object does not disable physical fingertip pressing")
	app.model.homed = false
	app._reset_pokes()
	var point: Vector3 = app.geometry.probe_grab.global_position
	left.grip_node.global_position = point
	_check(app._begin_near_grab(left, point), "Actual nearby probe resource can be acquired for the held-contact check")
	_press(left, home)
	_check(not app.model.homed, "A real acquired mechanical resource suppresses fingertip commands")
	app._release_near_grab(left, true)
	app._set_menu_open(true)
	_press(left, home)
	_check(not app.model.homed, "Menu mode suppresses physical fingertip commands")
	app._set_menu_open(false)
	_poke(left, home, -0.008)
	_check(not app.model.homed, "Closing menu around an embedded fingertip cannot press")
	_press(left, home)
	_check(app.model.homed, "Fresh withdrawal and approach restore physical pressing")

func _test_guide_controls() -> void:
	_fresh()
	app.tutorial.start(app._tutorial_context())
	app._refresh_tutorial()
	app._controller_pressed("ax_button",right)
	_check(app.tutorial.index==0,"Manual Next cannot bypass the required rotor placement")
	app._process(DT)
	var anchored: Transform3D=app.tutorial_panel.global_transform
	app.camera.look_at(app.tutorial_panel.global_position,Vector3.UP)
	app._action("mount")
	for frame in range(40):app._process(0.05)
	_check(app.tutorial.index==1,"Confirmed rotor placement automatically advances to Home without pressing A")
	_check(app.geometry.physical_by_action.home.guide_highlight,"Work instruction highlights physical HOME rather than a menu tab")
	_check(app.tutorial_panel.global_position.distance_to(app.geometry.physical_by_action.home.global_position)<0.49,"Automatic progression moves the prompt to physical HOME")
	app._controller_pressed("ax_button",left)
	_check(app.tutorial.view(app._tutorial_context()).get("reviewing",false),"Left X reviews earlier work instructions without operating the lab")
	var view_before: Dictionary=app.tutorial.view(app._tutorial_context())
	app._set_menu_open(true)
	app._controller_pressed("ax_button",right)
	_check(app.tutorial.view(app._tutorial_context()).id==view_before.id,"A does not navigate hidden work instructions behind a menu")
	app._set_menu_open(false)
	app.tutorial.skip()
	var chart: String=app.chart_kind
	app._controller_pressed("ax_button",right)
	app._controller_pressed("ax_button",left)
	_check(app.chart_kind==chart,"A/X remain guide review rather than chart shortcuts")
	app._action("tutorial:toggle")
	var lesson_index: int=app.tutorial.index
	app._action("tutorial:toggle")
	_check(not app.tutorial.active and app.guide_paused,"Pause hides work instructions without discarding progress")
	app._action("tutorial:toggle")
	_check(app.tutorial.active and app.tutorial.index==lesson_index,"Resume retains the unfinished work instruction")

func _test_navigation() -> void:
	_fresh()
	var origin: Vector3 = app.rig.global_position
	var local_camera: Vector3 = app.camera.position
	var head: Vector3 = app.camera.global_position
	var guide: Vector3 = app.tutorial_panel.global_position
	right.node.stick = Vector2(1, 0)
	app._update_controllers(DT)
	var expected := Vector3(0.65 * DT, 0, 0)
	_near(app.rig.global_position, origin + expected, "Right stick moves the actual XROrigin horizontally")
	_near(app.camera.position, local_camera, "Artificial movement preserves the camera's room-scale local offset")
	_near(app.camera.global_position, head + expected, "Actual tracked head moves with the origin")
	_near(app.tutorial_panel.global_position, guide, "Target-adjacent prompt is not translated with the walking origin")
	_check(absf(app.walk_distance_m - expected.length()) < 0.00001, "Report distance uses allowed actual displacement")
	right.node.stick = Vector2.ZERO
	app._update_controllers(DT)
	var stopped: Vector3 = app.rig.global_position
	app._update_controllers(DT)
	_near(app.rig.global_position, stopped, "Neutral right stick has no retained walking velocity")
	app.camera.rotation.y = -PI / 2.0
	right.node.stick = Vector2(0, 1)
	app._update_controllers(DT)
	_check(app.rig.global_position.x > stopped.x and absf(app.rig.global_position.z - stopped.z) < 0.00001, "Walking follows current camera yaw rather than a fixed world axis")
	_fresh()
	app.camera.position = Vector3(0, 1.7, -0.05)
	right.node.stick = Vector2(0, 1)
	for frame in range(150):app._update_controllers(DT)
	var front: float = app.station.global_position.z - 1.4 + 0.475 + 0.18
	_check(app.camera.global_position.z >= front - 0.00001 and app.camera.global_position.z < 0, "Actual head-ground collision stops walking at the bench, not at origin location")
	_check(is_equal_approx(app.camera.global_position.y, 1.7), "Bench collision never raises or lowers the viewpoint")

func _test_navigation_interruptions() -> void:
	for reason in ["menu", "focus", "tracking", "head", "held", "disabled"]:
		_fresh()
		right.node.stick = Vector2(1, 0)
		app._update_controllers(DT)
		var before: Vector3 = app.rig.global_position
		match reason:
			"menu":app._set_menu_open(true)
			"focus":app._set_xr_focus(false)
			"tracking":right.grip_node.tracking = false
			"head":app.head_tracking_override = false
			"held":
				var point: Vector3 = app.geometry.probe_grab.global_position
				left.grip_node.global_position = point
				_check(app._begin_near_grab(left, point), "Acquire actual resource before navigation gating")
			"disabled":app._action("walk_toggle")
		app._update_controllers(DT)
		_near(app.rig.global_position, before, "Walking stops for " + reason)
		match reason:
			"menu":app._set_menu_open(false)
			"focus":app._set_xr_focus(true)
			"tracking":right.grip_node.tracking = true
			"head":app.head_tracking_override = true
			"held":app._release_near_grab(left, true)
			"disabled":app._action("walk_toggle")
		app._update_controllers(DT)
		_near(app.rig.global_position, before, "Held stick cannot restart walking after " + reason)
		right.node.stick = Vector2.ZERO
		app._update_controllers(DT)
		right.node.stick = Vector2(1, 0)
		app._update_controllers(DT)
		_check(app.rig.global_position.x > before.x, "Fresh neutral/deflection resumes walking after " + reason)

func _test_height_and_room() -> void:
	_fresh()
	var room := app.get_node("Workshop") as Node3D
	var room_transform: Transform3D = room.global_transform
	var head: Vector3 = app.camera.global_position
	left.node.stick = Vector2(0, 1)
	app._update_controllers(DT)
	_check(app.station.position.y > 0 and app.height_changed, "Left stick adjusts station height through actual polling")
	_check(room.global_transform.is_equal_approx(room_transform), "Station adjustment does not lift the workshop floor")
	_near(app.camera.global_position, head, "Left-stick station adjustment does not elevate the user")
	var previous: float = app.station.position.y
	app._set_menu_open(true)
	app._update_controllers(DT)
	_check(is_equal_approx(app.station.position.y, previous), "Menu blocks station-height input")
	app._set_menu_open(false)
	app._update_controllers(DT)
	_check(is_equal_approx(app.station.position.y, previous), "Held height stick cannot resume after closing menu")
	left.node.stick = Vector2.ZERO
	app._update_controllers(DT)
	left.node.stick = Vector2(0, 1)
	app._update_controllers(DT)
	_check(app.station.position.y > previous, "Neutral rearming deliberately resumes station height")
	app._action("recenter")
	_check(not app.motion_armed and not app.height_armed, "Explicit recenter rearms both navigation inputs")

func _test_anchor_recovery() -> void:
	_fresh()
	app.head_tracking_override=false
	app.guide_anchor_pending=true
	app.tutorial_panel.global_position=Vector3(0,0.2,0)
	var untracked_position: Vector3=app.tutorial_panel.global_position
	app._process(DT)
	_near(app.tutorial_panel.global_position,untracked_position,"Untracked startup cannot place a guide from a stale head pose")
	_check(app.guide_anchor_pending,"Untracked startup retains a pending placement")
	app.head_tracking_override=true
	app._process(DT)
	_check(not app.guide_anchor_pending,"First tracked head pose releases pending target placement")
	app._set_xr_focus(false)
	app._process(DT)
	app.camera.position+=Vector3(0.4,0,0)
	app._set_xr_focus(true)
	app._process(DT)
	_check(not app.guide_anchor_pending,"Focus return recalculates target guidance with the current tracked head")

func _test_hand_control_guides() -> void:
	_fresh()
	left.grip_node.global_position=Vector3(-0.15,1.25,-0.30)
	right.grip_node.global_position=Vector3(0.55,1.25,-0.30)
	app._update_controllers(DT)
	app._refresh_tutorial()
	for entry in [left,right]:
		_check(entry.hand.visible and entry.control_guide.visible,"Tracked gloves show their two physical button letters")
		_check(entry.control_guide.get_parent()==entry.grip_node,"Marker lifetime follows its tracked grip")
		_check(entry.control_guide.labels.size()==2 and entry.control_guide.markers.size()==2,"Hand mode contains exactly two circular hardware markers")
		var expected: Array=["X","Y"] if entry==left else ["A","B"]
		_check([entry.control_guide.labels.primary.text,entry.control_guide.labels.secondary.text]==expected,"Each glove identifies its real handed controller buttons")
		_check(entry.control_guide.find_children("*","CollisionObject3D",true,false).is_empty(),"Letter markers cannot intercept physical or menu input")
	var hand_before: Vector3=right.grip_node.global_position
	var marker_before: Vector3=right.control_guide.markers.primary.global_position
	right.grip_node.global_position+=Vector3(0.06,0.04,0)
	app._update_controllers(DT)
	_near(right.control_guide.markers.primary.global_position-marker_before,Vector3(0.06,0.04,0),"Button centers follow exact grip translation")
	_check(right.grip_node.global_position.distance_to(hand_before)>0.05,"Marker updates do not change the tracked hand pose")
	right.grip_node.global_basis=Basis.from_euler(Vector3(0.4,-0.3,0.5))
	app._update_controllers(DT)
	var anchor: Dictionary=right.control_guide.anchors.primary
	var expected_center: Vector3=right.grip_node.global_transform*(anchor.center+anchor.normal*right.control_guide.CAP_NORMAL_OFFSET_M)
	_near(right.control_guide.markers.primary.global_position,expected_center,"Root supplies full grip rotation to hardware button anchors")
	var center_before_head_move: Vector3=right.control_guide.markers.primary.global_position
	app.camera.global_position+=Vector3(0.12,0.06,0.03)
	app._update_controllers(DT)
	_near(right.control_guide.markers.primary.global_position,center_before_head_move,"Head movement changes letter facing without relocating a physical button")
	app._set_menu_open(true)
	_check(not left.control_guide.visible and not right.control_guide.visible,"Opening pointer menu immediately hides glove markers")
	app._set_menu_open(false)
	_check(left.control_guide.visible and right.control_guide.visible,"Closing menu restores tracked glove markers")
	right.grip_node.tracking=false
	app._update_controllers(DT)
	_check(left.control_guide.visible and not right.control_guide.visible,"Lost grip tracking hides only that glove's markers")
	right.grip_node.tracking=true
	right.node.tracking=false
	app._update_controllers(DT)
	_check(right.control_guide.visible,"Glove markers require grip tracking without requiring menu aim tracking")
	app._set_xr_focus(false)
	_check(not left.control_guide.visible and not right.control_guide.visible,"Focus loss immediately hides glove markers")
	app._set_xr_focus(true)
	app._update_controllers(DT)
	_check(left.control_guide.visible and right.control_guide.visible,"Focused tracked gloves restore their markers")
	app.head_tracking_override=false
	app._update_controllers(DT)
	_check(not left.control_guide.visible and not right.control_guide.visible,"Invalid headset pose hides viewer-facing letters")
	app.head_tracking_override=true
	app._update_controllers(DT)
	_check(left.control_guide.visible and right.control_guide.visible,"Markers recover after valid head tracking returns")
	var target: Vector3=app.geometry.probe_grab.global_position
	right.grip_node.global_position=target
	_check(app._begin_near_grab(right,target),"Marker routing test acquires an actual nearby mechanism")
	app._refresh_tutorial()
	_check(_hand_legend_text(left).strip_edges()=="X Y" and _hand_legend_text(right).strip_edges()=="A B","Held objects add no instruction cards or function text to hardware markers")
	app._release_near_grab(right,true)


func _hand_legend_text(entry:Dictionary) -> String:
	var text: String=""
	for label in entry.control_guide.find_children("*","Label3D",true,false):text+=label.text+" "
	return text


func _test_callout_after_controller_poll() -> void:
	_fresh()
	app.head_tracking_override=true
	for command in ["mount","home","guard"]:app._action(command)
	app.geometry.update_state(app.model.telemetry())
	app.tutorial.start(app._tutorial_context())
	app.tutorial.skip_step();app.tutorial.skip_step()
	app._refresh_tutorial()
	var target: Node3D=app.geometry.guard_handle
	right.grip_node.global_position+=target.global_position-right.hand.palm_global()
	_check(app._begin_near_grab(right,target.global_position),"Callout poll test grips the actual guard handle")
	right.grip_down=true;right.node.grip=0.9
	var guard_before: Vector3=target.global_position
	right.grip_node.global_position.y+=0.14
	# Enable the production controller poll while retaining deterministic pose
	# providers and the head-valid override; no OpenXR interface is fabricated.
	app.xr_active=true
	app._process(DT)
	app.xr_active=false
	_check(target.global_position.y>guard_before.y+0.10,"Production poll moves the held guard during this frame")
	_near(app.guide_placement.target_world_position,target.global_position,"Callout uses the guard's final polled transform in the same frame")
	var clear: bool=true
	if app.guide_placement.visible:
		for bound in app._guide_obstacles().bounds:clear=clear and not app.guide_placement.bounds.intersects(bound)
	_check(clear,"Visible guard callout clears final moving geometry rather than the previous pose")
	_fresh()
	app.head_tracking_override=true
	app.tutorial.start(app._tutorial_context())
	app._refresh_tutorial()
	var rotor_before: Vector3=app.geometry.rotor_grab.global_position
	left.node.stick=Vector2(0,1);app.height_armed=true
	app.xr_active=true
	app._process(DT)
	app.xr_active=false
	_check(app.geometry.rotor_grab.global_position.y>rotor_before.y+0.001,"Production poll adjusts bench height during this frame")
	_near(app.guide_placement.target_world_position,app.geometry.rotor_grab.global_position,"Callout uses final joystick-adjusted station height in the same frame")
	clear=true
	if app.guide_placement.visible:
		for bound in app._guide_obstacles().bounds:clear=clear and not app.guide_placement.bounds.intersects(bound)
	_check(clear,"Visible rotor callout clears final station geometry after height movement")
	_fresh()
