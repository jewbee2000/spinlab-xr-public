extends SceneTree
## Desktop render of the actual workspace, menu and guide, without XR hardware.
## godot --xr-mode off --path native --script res://tools/preview_workspace.gd
## Uses memory-only preferences; never writes a report or modifies lab settings.

const MainScene = preload("res://main.tscn")
const ControllerVisual = preload("res://scripts/virtual_controller.gd")
var app: Node3D
var preview_controllers: Array[Node3D] = []


func _initialize() -> void:
	call_deferred("_render_workspace")


func _render_workspace() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Workspace preview needs a rendering display. Omit --headless.")
		quit(1)
		return
	root.size=Vector2i(1800,1200)
	app=MainScene.instantiate()
	app.tutorial_settings_path=""
	app.tutorial_autostart=false
	root.add_child(app)
	app.set_process(false)
	app.set_process_unhandled_input(false)
	app.model.async_processing=false
	for layer in app.find_children("*","CanvasLayer",true,false):
		layer.visible=false
	app.camera.keep_aspect=Camera3D.KEEP_HEIGHT
	app.camera.fov=110
	app.camera.global_position=Vector3(0,1.6,0.25)
	# A wide desktop perspective presents the operator's downward head pose;
	# this image does not establish the headset's field of view or fit.
	app.camera.look_at(app.station.to_global(Vector3(0,1.45,-1.4)))
	app.camera.current=true
	app._set_menu_open(false)
	app._update_ui()
	_audit_monitor("initial")
	await _capture("res://../.local/operator-forward-workspace.png")
	# Step back 0.4 m within the application's walk area for the complete
	# documentation overview. Keep the initial head pose as separate QA evidence.
	app.camera.global_position=Vector3(0,1.6,0.65)
	app.camera.fov=100
	app.camera.look_at(app.station.to_global(Vector3(0,1.30,-1.4)))
	await _capture("res://../docs/images/operator-workspace.png")
	app.camera.fov=78
	app.camera.global_position=Vector3(0,1.6,0.2)
	app.camera.look_at(Vector3(0,1.54,-1.8))
	app._set_menu_open(true)
	app.camera.look_at(app.controls.global_position)
	_make_preview_controllers()
	await _capture("res://../.local/menu-workspace.png")
	for controller in preview_controllers:controller.visible=false
	app._set_menu_open(false)
	app.camera.look_at(Vector3(0,1.54,-1.8))
	app.tutorial.start(app._tutorial_context())
	for i in app.tutorial.steps.size():
		if app.tutorial.steps[i].id=="solve":app.tutorial.index=i
	app._update_ui()
	var guide_position: Vector3=app.tutorial_panel.global_position
	app.camera.look_at(guide_position)
	app.camera.fov=48
	await _capture("res://../.local/floating-guide-workspace.png")
	print("WORKSPACE_GUIDE overflowed=",app.tutorial_panel.overflowed," id=",app.tutorial.steps[app.tutorial.index].id)
	app.tutorial.skip()
	app._update_ui()
	# Real deterministic measurements also exercise the longest result fields.
	_prepare_verified_state()
	app._update_ui()
	_audit_monitor("verified")
	app.camera.global_position=Vector3(0,2.50,-0.15)
	app.camera.look_at(app.monitor.global_position)
	app.camera.fov=48
	await _capture("res://../.local/analyzer-workspace.png")
	app.queue_free()
	await process_frame
	quit(0)


func _capture(destination: String) -> void:
	for frame in range(5):await process_frame
	await RenderingServer.frame_post_draw
	var path: String=ProjectSettings.globalize_path(destination)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var result: Error=root.get_texture().get_image().save_png(path)
	if result!=OK:
		push_error("Workspace preview could not save %s: %s"%[path,error_string(result)])
		quit(1)
	else:print("WORKSPACE_PREVIEW ",path)


func _make_preview_controllers() -> void:
	# Illustrative grip poses only; no OpenXR tracker or interaction is created.
	for i in range(2):
		var controller: Node3D=ControllerVisual.new()
		controller.configure("left_hand" if i==0 else "right_hand")
		root.add_child(controller)
		var forward: Vector3=-app.camera.global_basis.z
		var right: Vector3=app.camera.global_basis.x
		controller.position=app.camera.global_position+forward*0.43+right*(-0.25 if i==0 else 0.25)+Vector3(0,-0.30,0)
		controller.basis=Basis(Vector3.UP,app.camera.global_rotation.y)*Basis(Vector3.RIGHT,PI/2)
		preview_controllers.append(controller)
		var end: Vector3=app.controls.to_global(Vector3(-0.20 if i==0 else 0.20,0,0.04))
		var start: Vector3=controller.position+forward*0.04+Vector3(0,0.035,0)
		var mesh:=CylinderMesh.new()
		mesh.top_radius=0.0011;mesh.bottom_radius=0.0011
		mesh.height=start.distance_to(end);mesh.radial_segments=6
		var beam:=MeshInstance3D.new();beam.mesh=mesh
		var material:=StandardMaterial3D.new()
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color=Color("6ce5c9")
		beam.material_override=material
		root.add_child(beam)
		beam.position=(start+end)/2
		beam.quaternion=Quaternion(Vector3.UP,(end-start).normalized())
		preview_controllers.append(beam)


func _prepare_verified_state() -> void:
	for action in ["mount","home","guard","baseline"]:
		app._action(action)
	_finish_acquisition()
	for action in ["guard","fit_trial","guard","trial_a"]:
		app._action(action)
	_finish_acquisition()
	for action in ["solve","guard","apply","guard","verify"]:
		app._action(action)
	_finish_acquisition()
	app.chart_kind="order"


func _finish_acquisition() -> void:
	for step in range(850):
		app.model.tick(0.02)
		if not app.model.running and not app.model.processing and app.model.rpm<1.0:break
	app.geometry.update_state(app.model.telemetry())


func _audit_monitor(state_name: String) -> void:
	for key in ["speed","amplitude","phase","quality","solution","result","chart","axis","status","coach"]:
		var label: Label3D=app.readouts[key]
		var font: Font=label.font if label.font else ThemeDB.fallback_font
		var max_width: float=0
		for line in label.text.split("\n"):
			max_width=maxf(max_width,font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size).x*label.pixel_size)
		var available: float=1.68 if key in ["status","coach"] else 0.76 if key in ["chart","axis"] else 0.83
		print("WORKSPACE_TEXT state=%s field=%s width_m=%.3f available_m=%.3f fits=%s text=%s"%[state_name,key,max_width,available,str(max_width<=available),label.text.replace("\n"," | ")])
