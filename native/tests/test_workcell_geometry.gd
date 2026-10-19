extends SceneTree
## Physical-console and menu-controller construction contracts, without XR.
## Add -- --capture-dir=<absolute directory> with a rendering display for QA.

const Geometry=preload("res://scripts/lab_geometry.gd")
const Controller=preload("res://scripts/virtual_controller.gd")
var checks := 0
var failures := 0
var _capture_dir := ""


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):_capture_dir=argument.trim_prefix("--capture-dir=")
	call_deferred("_run")


func _check(value: bool, description: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("WORKCELL GEOMETRY: "+description)


func _run() -> void:
	var geometry=Geometry.new()
	root.add_child(geometry)
	_test_console(geometry)
	_test_controllers()
	if not _capture_dir.is_empty():
		await _render_qa(geometry)
	print("WORKCELL GEOMETRY TESTS: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)


func _test_console(geometry) -> void:
	_check(geometry.physical_buttons.size()==18,"Physical registry includes existing HOME and seventeen console controls")
	_check(geometry.physical_buttons.has(geometry.probe_home_button),"Existing probe HOME remains registered")
	var commands: Dictionary={}
	var font: Font=ThemeDB.fallback_font
	for button in geometry.physical_buttons:
		commands[button.action]=true
		_check(button is StaticBody3D and button.get_meta("physical",false),"Physical cap exposes metadata and collision body")
		_check(button.get_meta("action","")==button.action and not button.action.is_empty(),"Physical control dispatches a real command")
		_check(button.collision_layer==1 and button.enabled,"Operating controls occupy physical layer one")
		_check(not button.find_children("*","CollisionShape3D",false,false).is_empty(),"Every physical control has a collision shape")
		var label: Label3D=button.text_label
		for line in label.text.split("\n"):
			var width: float=font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size).x*label.pixel_size
			_check(width<=button.width_m-0.009,"Physical control caption fits its cap width: "+button.action)
		var height: float=font.get_height(label.font_size)*label.pixel_size*label.text.split("\n").size()
		_check(height<=button.height_m-0.006,"Physical control caption fits its cap height: "+button.action)
		if button.get_meta("console",false):
			_check(absf(button.position.x)+button.width_m/2<0.81,"Console cap stays inside the chassis width")
			_check(absf(button.position.y)+button.height_m/2<0.138,"Console cap stays inside the chassis height")
			var normal: Vector3=button.global_basis.z.normalized()
			_check(normal.y>0.5 and normal.z>0.5,"Console face approaches forward/up along its true local normal")
			for corner in [Vector3(-button.width_m/2,-button.height_m/2,0),Vector3(button.width_m/2,button.height_m/2,0)]:
				_check(button.to_global(corner).y<0.86,"Front console leaves the table and fixture accessible above it")
	for command in ["home","baseline","stop","estop","recover","fit_trial","trial_a","trial_b","solve","apply","verify","repeat","sweep","plane","mode","chart","save"]:
		_check(commands.has(command),"Normal operating console includes "+command)
	var console: Array=[]
	for button in geometry.physical_buttons:
		if button.get_meta("console",false):console.append(button)
	for first in range(console.size()):
		for second in range(first+1,console.size()):
			var a=console[first];var b=console[second]
			var separated_x: bool=absf(a.position.x-b.position.x)>(a.width_m+b.width_m)*0.5+0.008
			var separated_y: bool=absf(a.position.y-b.position.y)>(a.height_m+b.height_m)*0.5+0.008
			_check(separated_x or separated_y,"Console buttons have distinct separated contact regions")
	var emergency=geometry.physical_by_action.estop
	_check(emergency.height_m>=0.10 and emergency.position.x<-0.65,"E-stop is large and isolated on the left edge")
	_check(emergency.face.material_override.albedo_color.r>emergency.face.material_override.albedo_color.g*1.8,"E-stop has a distinct red cap")
	_check(geometry.monitor_mount.position.is_equal_approx(Vector3(-1.55,1.45,-1.20)) and is_equal_approx(geometry.monitor_mount.rotation.y,deg_to_rad(50.0)),"Monitor anchor is low and left of the guard, yawed toward the operator")
	_check(is_instance_valid(geometry.guard_handle) and is_instance_valid(geometry.rotor_grab) and is_instance_valid(geometry.probe_grab),"Existing nearby fixture mechanisms remain available")


func _test_controllers() -> void:
	for side in ["left_hand","right_hand"]:
		var controller=Controller.new()
		controller.configure(side);root.add_child(controller)
		_check(controller.visual_source=="bundled_quest2","Controller uses the actual Quest 2 GLB asset")
		_check(controller.model_root.basis.determinant()>0.999,"Source controller frame remains a proper rotation")
		_check(controller.controls.size()==8,"Authored trigger, squeeze, stick and face-button ranges bind")
		_check(controller.controls.primary_click.name==("x_button_pressed_value" if side=="left_hand" else "a_button_pressed_value"),"Source face control matches handed hardware")
		var meshes: Array=controller.model_root.find_children("*","MeshInstance3D",true,false)
		_check(meshes.size()==6,"Source controller uses six mesh parts")
		_check(controller.find_children("*","Label3D",true,false).is_empty(),"Textured source lettering replaces invented labels")
		_check(controller.find_children("*","CollisionObject3D",true,false).is_empty(),"Controller remains a noninteractive visualization")
		for mesh in meshes:
			_check(mesh.mesh!=null and mesh.transform.is_finite(),"Controller asset geometry and transform are valid")
		controller.set_pose(0,0)
		var rest: Transform3D=controller.controls.trigger.transform
		controller.set_pose(1,1)
		_check(not controller.controls.trigger.transform.is_equal_approx(rest),"Controller trigger follows authored rotation")
		for input in [Vector2(-9,8),Vector2(NAN,INF),Vector2.ONE]:
			controller.set_pose(input.x,input.y)
			_check(controller.controls.trigger.transform.is_finite() and controller.controls.grip.transform.is_finite(),"Controller input clamps invalid analog values")
		controller.visible=false


func _render_qa(geometry) -> void:
	if DisplayServer.get_name()=="headless":
		_check(false,"Rendering QA needs a display")
		return
	DirAccess.make_dir_recursive_absolute(_capture_dir)
	root.size=Vector2i(1800,1200)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color("101d2a")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("b9d7e1")
	settings.ambient_light_energy=0.7
	environment.environment=settings;root.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-48,-25,0);light.light_energy=1.5;root.add_child(light)
	var camera := Camera3D.new()
	root.add_child(camera);camera.current=true
	geometry.update_state({"mounted":true,"guard_closed":false,"mode":"two_plane","masses":[0.42,0.31],"angles":[214.0,28.0],"sensor_position_mm":6.0})
	camera.position=Vector3(1.12,1.80,0.52);camera.look_at(Vector3(0,1.02,-1.38));camera.fov=53
	await _save_frame("physical-station-qa.png")
	camera.position=Vector3(0,1.32,0.58);camera.look_at(Vector3(0,0.70,-0.84));camera.fov=48
	await _save_frame("physical-console-qa.png")
	geometry.visible=false
	for index in range(2):
		var controller=Controller.new()
		controller.configure("left_hand" if index==0 else "right_hand")
		root.add_child(controller)
		controller.position=Vector3(-0.11 if index==0 else 0.11,0,0)
		controller.basis=Basis(Vector3.RIGHT,PI/2)
		controller.set_pose(0.7 if index==0 else 0.0,0.6 if index==0 else 0.0)
	camera.position=Vector3(0,0.32,0.34);camera.look_at(Vector3(0,0,0.01));camera.fov=48
	await _save_frame("virtual-controllers-qa.png")


func _save_frame(filename: String) -> void:
	for frame in range(5):await process_frame
	await RenderingServer.frame_post_draw
	var path := _capture_dir.path_join(filename)
	var error := root.get_texture().get_image().save_png(path)
	_check(error==OK,"QA image saved: "+filename)
	print("WORKCELL_CAPTURE ",path)
