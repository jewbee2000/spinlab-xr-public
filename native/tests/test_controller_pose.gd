extends SceneTree
## Actual Quest 2 assets, authored control ranges and runtime fallback lifecycle.
## Optional GPU QA: -- --capture-dir=<absolute directory>. No XR claim is made.
const Controller = preload("res://scripts/virtual_controller.gd")
var checks:=0
var failures:=0
var _capture_dir:=""
var _controllers: Array[Node3D]=[]

class ModelHost extends Node3D:
	var loaded: Node3D
	func get_render_model_node() -> Node3D:return loaded
	func has_render_model_node() -> bool:return is_instance_valid(loaded)


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):_capture_dir=argument.trim_prefix("--capture-dir=")
	call_deferred("_run")


func _run() -> void:
	var provenance: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Controller.ASSET_DIRECTORY+"PROVENANCE.json"))
	for side in ["left_hand","right_hand"]:
		var controller=Controller.new();controller.configure(side);root.add_child(controller)
		_controllers.append(controller)
		_test_asset(controller,side,provenance)
		_test_controls(controller)
		_test_runtime_lifecycle(controller)
	if not _capture_dir.is_empty():await _render_qa()
	for controller in _controllers:controller.queue_free()
	await process_frame
	print("CONTROLLER ASSET TESTS: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)


func _check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:failures+=1;push_error("CONTROLLER ASSET: "+message)


func _test_asset(controller, side: String, provenance: Dictionary) -> void:
	var file_name: String="left.glb" if side=="left_hand" else "right.glb"
	_check(FileAccess.get_sha256(Controller.ASSET_DIRECTORY+file_name)==provenance.files[file_name].sha256,"Pinned source GLB hash is unchanged")
	_check(provenance.license=="MIT" and FileAccess.file_exists(Controller.ASSET_DIRECTORY+"LICENSE.txt"),"Asset provenance and full redistribution notice are present")
	_check(controller.visual_source=="bundled_quest2" and controller.fallback_root.visible,"Actual Quest 2 fallback is immediately available")
	var meshes: Array=controller.model_root.find_children("*","MeshInstance3D",true,false)
	_check(meshes.size()==6,"Asset contains its six source mesh parts")
	var textured:=true
	for mesh in meshes:
		var material: Material=mesh.mesh.surface_get_material(0)
		textured=textured and material is StandardMaterial3D and material.albedo_texture!=null
	_check(textured,"Source textures carry casing detail and button lettering")
	_check(controller.find_children("*","Label3D",true,false).is_empty(),"No invented lettering overlays the source button positions")
	_check(controller.find_children("*","CollisionObject3D",true,false).is_empty() and controller.find_children("*","RayCast3D",true,false).is_empty(),"Visual asset cannot intercept application input or replace its aim ray")
	_check(controller.controls.size()==8,"All eight authored visual response ranges bind")
	_check(controller.controls.primary_click.name==("x_button_pressed_value" if side=="left_hand" else "a_button_pressed_value"),"Primary control binds actual handed source node")
	_check(controller.controls.secondary_click.name==("y_button_pressed_value" if side=="left_hand" else "b_button_pressed_value"),"Secondary control binds actual handed source node")
	var root_transform: Transform3D=controller.model_root.transform
	controller.update_inputs({"stick":Vector2(0.8,-0.5),"trigger":0.8},0.016)
	_check(controller.model_root.transform.is_equal_approx(root_transform),"Input does not rotate or reposition the source grip frame")


func _test_controls(controller) -> void:
	controller.update_inputs({})
	var released: Transform3D=controller.controls.primary_click.transform
	controller.update_inputs({"primary_touch":true,"secondary_touch":true,"trigger_touch":true,"stick_touch":true})
	_check(controller.controls.primary_click.transform.is_equal_approx(released) and not controller.input_state.primary_click,"Capacitive touch remains distinct from button actuation")
	controller.update_inputs({"primary_click":true,"secondary_click":true,"stick_click":true,"trigger":1.0,"grip":1.0,"stick":Vector2(1,-1)})
	for key in ["primary_click","secondary_click","stick_click","trigger","grip","stick_x"]:
		_check(controller.controls[key].transform.is_equal_approx(controller._channels[key].maximum),"Physical control reaches authored maximum: "+key)
	_check(controller.controls.stick_y.transform.is_equal_approx(controller._channels.stick_y.minimum),"Negative stick axis reaches authored minimum")
	_check(controller.controls.primary_click.position.distance_to(released.origin)>0.0005,"Source face button visibly depresses")
	_check(not controller._channels.trigger.minimum.basis.is_equal_approx(controller._channels.trigger.maximum.basis),"Source index trigger includes authored rotation")
	controller.update_inputs({"trigger":0.35,"grip":0.6,"stick":Vector2(-0.4,0.7),"primary_click":true})
	_check(controller.controls.trigger.transform.is_equal_approx(controller._channels.trigger.minimum.interpolate_with(controller._channels.trigger.maximum,0.35)),"Analog trigger interpolates authored transforms")
	_check(controller.controls.stick_x.transform.is_equal_approx(controller._channels.stick_x.minimum.interpolate_with(controller._channels.stick_x.maximum,0.3)),"Stick axis maps signed input to its authored range")
	controller.set_pose(0.2,0.3)
	_check(controller.input_state.primary_click and controller.input_state.stick.is_equal_approx(Vector2(-0.4,0.7)),"Legacy pose API retains independent button and stick state")
	controller.update_inputs({"trigger":NAN,"grip":INF,"stick":Vector2(NAN,0),"primary_click":"pressed"})
	_check(is_zero_approx(controller.input_state.trigger) and is_zero_approx(controller.input_state.grip) and controller.input_state.stick==Vector2.ZERO and not controller.input_state.primary_click,"Invalid values cannot create input or corrupt geometry")
	controller.update_inputs({"trigger":9.0,"grip":-4.0,"stick":Vector2(3,-7)})
	_check(controller.input_state.trigger==1.0 and controller.input_state.grip==0.0 and controller.input_state.stick==Vector2(1,-1),"Physical analog ranges clamp safely")
	controller.transform=Transform3D(Basis.from_euler(Vector3(0.3,-0.4,0.6)),Vector3(0.1,1.2,-0.7))
	var grip_transform: Transform3D=controller.transform
	controller.update_inputs({"trigger":0.5})
	_check(controller.transform.is_equal_approx(grip_transform),"Animation leaves the externally tracked grip unchanged")
	controller.transform=Transform3D.IDENTITY
	controller.update_inputs({})


func _test_runtime_lifecycle(controller) -> void:
	_check(not controller.enable_runtime() and controller.fallback_root.visible,"A desktop without XR keeps the bundled model")
	_check(not controller.enable_runtime(),"Runtime request is idempotent")
	# Exercise the asynchronous callback with a real asset scene through a
	# simulated host. This proves switching logic, not device extension support.
	var host:=ModelHost.new();controller.add_child(host);controller._runtime_host=host
	var packed:=load(Controller.ASSET_DIRECTORY+("left.glb" if controller._side=="left_hand" else "right.glb")) as PackedScene
	host.loaded=packed.instantiate();host.add_child(host.loaded)
	controller._runtime_model_loaded()
	_check(controller.visual_source=="runtime_fb" and not controller.fallback_root.visible and host.visible,"Loaded runtime scene replaces bundled geometry")
	_check(controller.get_diagnostics().animation_channels==8,"Runtime scene animates only its discovered ranges")
	host.loaded.queue_free();controller.update_inputs({})
	_check(controller.visual_source=="bundled_quest2" and controller.fallback_root.visible,"Retired runtime geometry restores the fallback during reload")
	# Some runtime GLBs contain geometry but no authored control ranges.
	var static_scene:=Node3D.new();host.loaded=static_scene;host.add_child(static_scene)
	var source_mesh: MeshInstance3D=controller.fallback_root.find_children("*","MeshInstance3D",true,false)[0]
	var static_mesh:=MeshInstance3D.new();static_mesh.mesh=source_mesh.mesh;static_scene.add_child(static_mesh)
	controller._runtime_model_loaded();controller.update_inputs({"trigger":1.0,"primary_click":true})
	_check(controller.visual_source=="runtime_fb" and controller.get_diagnostics().animation_channels==0,"Static runtime model is reported honestly and remains usable")
	static_scene.queue_free();controller.update_inputs({})


func _render_qa() -> void:
	if DisplayServer.get_name()=="headless":_check(false,"Render QA needs a display");return
	DirAccess.make_dir_recursive_absolute(_capture_dir)
	root.size=Vector2i(1600,1100)
	var world:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("102331")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("c8dfe5");settings.ambient_light_energy=0.8
	world.environment=settings;root.add_child(world)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-20,0);light.light_energy=1.5;root.add_child(light)
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=0.34
	for index in range(2):
		_controllers[index].transform=Transform3D(Basis(Vector3.RIGHT,PI/2),Vector3(-0.10 if index==0 else 0.10,0,0))
		_controllers[index].update_inputs({})
	camera.position=Vector3(0,0.32,0.34);camera.look_at(Vector3(0,0,0.01))
	await _save_frame("quest2-controller-top.png")
	_controllers[0].update_inputs({"trigger":1.0,"grip":1.0,"stick":Vector2(-1,0.8),"primary_click":true})
	camera.position=Vector3(0.12,0.18,0.34);camera.look_at(Vector3(0,0,0.01))
	await _save_frame("quest2-controller-inputs.png")


func _save_frame(filename: String) -> void:
	for frame in range(5):await process_frame
	await RenderingServer.frame_post_draw
	var destination: String=_capture_dir.path_join(filename)
	_check(root.get_texture().get_image().save_png(destination)==OK,"Saved actual controller asset render")
	print("CONTROLLER_ASSET_CAPTURE ",destination)
