extends SceneTree
## Hardware-anchored letter markers. Optional -- --capture=<absolute.png>
## also writes a second *_rotated.png glove/marker view with a rendering display.
const Guide = preload("res://scripts/hand_control_guide.gd")
const Controller = preload("res://scripts/virtual_controller.gd")
const Hand = preload("res://scripts/virtual_hand.gd")
var checks:=0
var failures:=0
var _capture:=""


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):_capture=argument.trim_prefix("--capture=")
	call_deferred("_run")


func _run() -> void:
	for side in ["left_hand","right_hand"]:
		var parent:=Node3D.new();root.add_child(parent)
		var guide=Guide.new();guide.configure(side);parent.add_child(guide)
		var controller=Controller.new();controller.configure(side);parent.add_child(controller)
		_check(not guide.visible,"Markers start hidden")
		var count: int=guide.get_child_count();guide.configure(side)
		_check(guide.get_child_count()==count,"Configure does not duplicate markers")
		_check(guide.markers.size()==2 and guide.labels.size()==2,"Only two letters are shown per hand")
		_check(guide.labels.primary.text==("X" if side=="left_hand" else "A") and guide.labels.secondary.text==("Y" if side=="left_hand" else "B"),"Letters match the real handed controller")
		_check(guide.find_children("*","MeshInstance3D",true,false).size()==4,"Only circular faces and rims are rendered")
		var no_cards:=true
		var depth_tested:=true
		for mesh in guide.find_children("*","MeshInstance3D",true,false):
			no_cards=no_cards and not mesh.mesh is BoxMesh
			depth_tested=depth_tested and not mesh.material_override.no_depth_test
		_check(no_cards,"No rectangular card or backplate remains")
		_check(depth_tested,"Markers retain ordinary scene occlusion")
		_check(guide.find_children("*","CollisionObject3D",true,false).is_empty() and guide.find_children("*","RayCast3D",true,false).is_empty(),"Markers cannot intercept input")
		var viewer:=Transform3D(Basis.from_euler(Vector3(-0.15,0.3,0.1)),Vector3(0,1.6,0.2))
		for angles in [Vector3.ZERO,Vector3(PI/2,0,0),Vector3(0.4,-0.7,0.9)]:
			parent.transform=Transform3D(Basis.from_euler(angles),Vector3(-0.18 if side=="left_hand" else 0.18,1.1,-0.4))
			guide.update_placement(parent.global_transform,viewer,true)
			_check(guide.visible,"Valid tracking displays markers")
			for key in ["primary","secondary"]:
				var value: Node3D=controller.controls[key+"_click"]
				var mesh: MeshInstance3D=value.find_children("*","MeshInstance3D",true,false)[0]
				var cap_center: Vector3=mesh.global_transform*mesh.get_aabb().get_center()
				var channel: Dictionary=controller._channels[key+"_click"]
				var cap_normal: Vector3=(value.get_parent().to_global(channel.minimum.origin)-value.get_parent().to_global(channel.maximum.origin)).normalized()
				var expected: Vector3=cap_center+cap_normal*Guide.CAP_NORMAL_OFFSET_M
				var marker: Node3D=guide.markers[key]
				_check(marker.global_position.distance_to(expected)<0.00001,"Center follows actual authored controller cap under wrist rotation")
				_check(is_equal_approx(marker.global_position.distance_to(cap_center),Guide.CAP_NORMAL_OFFSET_M),"Only fixed cap-normal clearance separates marker and hardware cap")
				_check((marker.global_position-cap_center).cross(cap_normal).length()<0.00001,"Clearance never shifts the physical button projection sideways")
				_check(marker.global_basis.z.dot((viewer.origin-marker.global_position).normalized())>0.999,"Letter faces viewer without changing its anchored center")
				var old_position: Vector3=marker.global_position
				var moved_viewer:=Transform3D(Basis.from_euler(Vector3(0.2,-0.8,-0.2)),Vector3(0.7,1.8,0.4))
				guide.update_placement(parent.global_transform,moved_viewer,true)
				_check(marker.global_position.is_equal_approx(old_position),"Moving the head cannot relocate a physical button marker")
				guide.update_placement(parent.global_transform,viewer,true)
		var previous_letters: Array=[guide.labels.primary.text,guide.labels.secondary.text]
		guide.set_context(false,false,true,false,true,true)
		_check([guide.labels.primary.text,guide.labels.secondary.text]==previous_letters,"Guide/holding context cannot add function text or hide hardware identity")
		for label in guide.labels.values():
			_check(label.text.length()==1 and not label.no_depth_test and not label.double_sided,"Each label is a single front-facing depth-tested letter")
			var height_m: float=ThemeDB.fallback_font.get_height(label.font_size)*label.pixel_size
			_check(height_m<Guide.DIAMETER_M,"Letter fits inside its20mm circle")
		guide.update_placement(parent.global_transform,viewer,false)
		_check(not guide.visible,"Inactive tracking hides markers")
		guide.update_placement(Transform3D(Basis.IDENTITY,Vector3(NAN,0,0)),viewer,true)
		_check(not guide.visible,"Invalid grip tracking cannot place markers")
		parent.queue_free()
	await process_frame
	if not _capture.is_empty():await _render_preview()
	print("HAND BUTTON MARKER TESTS: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)


func _check(condition: bool, description: String) -> void:
	checks+=1
	if not condition:failures+=1;push_error("HAND BUTTON MARKER: "+description)


func _render_preview() -> void:
	if DisplayServer.get_name()=="headless":_check(false,"Marker preview needs a rendering display");return
	root.size=Vector2i(1600,1100)
	var world:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("102330")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("b9d7e1");settings.ambient_light_energy=0.7
	world.environment=settings;root.add_child(world)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-48,-25,0);light.light_energy=1.5;root.add_child(light)
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true
	camera.position=Vector3(0,1.6,0.18);camera.look_at(Vector3(0,1.18,-0.42));camera.fov=42
	var hands: Array=[]
	for side in ["left_hand","right_hand"]:
		var grip:=Node3D.new();root.add_child(grip)
		grip.position=Vector3(-0.15 if side=="left_hand" else 0.15,1.15,-0.42)
		grip.basis=Basis(Vector3.RIGHT,PI/2)
		var hand=Hand.new();hand.configure(side);grip.add_child(hand);hand.set_pose(0,0.15,false,false)
		var guide=Guide.new();guide.configure(side);grip.add_child(guide)
		guide.update_placement(grip.global_transform,camera.global_transform,true)
		hands.append({"grip":grip,"guide":guide,"hand":hand})
	await _save(_capture)
	for index in range(hands.size()):
		var entry: Dictionary=hands[index]
		entry.grip.basis=Basis.from_euler(Vector3(0.2,-0.4 if index==0 else 0.4,-0.35 if index==0 else 0.35))*Basis(Vector3.RIGHT,PI/2)
		entry.hand.set_pose(0.15,0.7,false,false)
		entry.guide.update_placement(entry.grip.global_transform,camera.global_transform,true)
	await _save(_capture.get_basename()+"_rotated.png")


func _save(destination: String) -> void:
	for frame in range(5):await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	_check(root.get_texture().get_image().save_png(destination)==OK,"Saved actual glove and anchored-marker view")
	print("HAND_BUTTON_MARKER_CAPTURE ",destination)
