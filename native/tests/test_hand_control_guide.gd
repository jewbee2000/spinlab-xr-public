extends SceneTree
## Focused, headset-independent legend tests. Optional rendered glove preview:
## godot --xr-mode off --path native --script res://tests/test_hand_control_guide.gd -- --capture=<absolute.png>

const Guide = preload("res://scripts/hand_control_guide.gd")
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
		var grip:=Node3D.new();root.add_child(grip)
		var guide=Guide.new();guide.configure(side);grip.add_child(guide)
		_check(not guide.visible,"New legend starts hidden")
		var child_count: int=guide.get_child_count()
		guide.configure(side)
		_check(guide.get_child_count()==child_count,"Repeated configure does not duplicate content")
		_check(guide.find_children("*","CollisionObject3D",true,false).is_empty() and guide.find_children("*","RayCast3D",true,false).is_empty(),"Legend cannot intercept input")
		_check(guide.find_children("*","MeshInstance3D",true,false).size()<=6,"Legend mesh budget is bounded")
		_check(guide.labels.upper_button.text==("Y" if side=="left_hand" else "B") and guide.labels.lower_button.text==("X" if side=="left_hand" else "A"),"Button identities match the actual hand")
		_check(guide.button_positions.upper.y>guide.button_positions.lower.y,"Secondary button is shown physically above primary")
		_check(guide.labels.upper_function.text=="Menu" and guide.labels.lower_function.text==("Guide back" if side=="left_hand" else "Guide next"),"Button names explain their functions")
		_test_placement(guide,grip,side)
		_test_context(guide,side)
		grip.queue_free()
	if not _capture.is_empty():await _render_preview()
	await process_frame
	print("HAND CONTROL GUIDE TESTS: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)


func _check(condition: bool, description: String) -> void:
	checks+=1
	if not condition:
		failures+=1;push_error("HAND GUIDE: "+description)


func _test_placement(guide, grip: Node3D, side: String) -> void:
	var sign: float=-1.0 if side=="left_hand" else 1.0
	var viewer:=Transform3D(Basis.from_euler(Vector3(-0.12,0.7,0.18)),Vector3(1,1.6,2))
	var hand_position: Vector3=viewer.origin-viewer.basis.z*0.65+viewer.basis.x*sign*0.17-viewer.basis.y*0.25
	var view_right: Vector3=viewer.basis.x;view_right.y=0;view_right=view_right.normalized()
	for rotation in [Vector3.ZERO,Vector3(PI,0,0),Vector3(0,PI/2,PI/2)]:
		grip.transform=Transform3D(Basis.from_euler(rotation),hand_position)
		guide.update_placement(hand_position,viewer,true)
		var toward_viewer: Vector3=(viewer.origin-guide.global_position).normalized()
		_check(guide.visible and guide.global_basis.z.dot(toward_viewer)>0.999,"Text faces viewer despite wrist rotation")
		_check(guide.global_basis.y.dot(viewer.basis.y)>0.7 and guide.global_basis.determinant()>0.999,"Text stays upright without a mirrored frame")
		_check((guide.global_position-hand_position).dot(view_right)*sign>0.23,"Card stays outside its hand rather than over the shared work area")
	guide.update_placement(viewer.origin-viewer.basis.z*0.01,viewer,true)
	_check(guide.global_position.distance_to(viewer.origin)>=0.499,"Near-face hand placement preserves minimum reading distance")
	guide.update_placement(hand_position,viewer,false)
	_check(not guide.visible,"Inactive or untracked hands can hide legends")
	guide.update_placement(Vector3(NAN,0,0),viewer,true)
	_check(not guide.visible and guide.global_transform.is_finite(),"Invalid tracking position cannot corrupt placement")
	guide.update_placement(hand_position,Transform3D(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),Vector3.ZERO),true)
	_check(not guide.visible,"Invalid viewer frame stays hidden")


func _test_context(guide, side: String) -> void:
	guide.set_context(false)
	_check(guide.labels.lower_function.text.ends_with("off") and guide.labels.upper_function.text=="Menu","Guide-off state preserves Menu and identifies inactive guide action")
	guide.set_context(true,false,true,false,true)
	_check(guide.labels.lower_function.text.ends_with("first" if side=="left_hand" else "wait"),"First-page or unmet objective is explained")
	_check(guide.labels.grip.text.contains("Release") and guide.labels.stick.text.ends_with("held" if side=="left_hand" else "off"),"Hold and walking-disabled states are explained")
	_check(guide.labels.trigger.text.contains("Curl index") and guide.labels.point.text.contains("Release trigger to point"),"Trigger guidance distinguishes curl from pointing")
	guide.set_context(true,true,false,true,false,true)
	_check(guide.labels.stick.text.ends_with("held") and guide.labels.grip.text.begins_with("Grip  Hold"),"Other-hand hold blocks navigation without claiming this hand holds an object")
	for label in guide.find_children("*","Label3D",true,false):
		var size_px: Vector2=ThemeDB.fallback_font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size)
		var width_m: float=size_px.x*label.pixel_size
		var left_m: float=label.position.x-width_m/2 if label.horizontal_alignment==HORIZONTAL_ALIGNMENT_CENTER else label.position.x
		_check(left_m>=-Guide.WIDTH_M/2+0.005 and left_m+width_m<=Guide.WIDTH_M/2-0.005,"Full contextual label fits the card: "+label.text)
		_check(not label.no_depth_test and not label.double_sided,"Labels retain normal occlusion and front-facing text")
	guide.set_context(true)


func _render_preview() -> void:
	if DisplayServer.get_name()=="headless":
		_check(false,"Glove/legend preview needs a display; omit --headless");return
	root.size=Vector2i(1800,1200)
	var world:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("102330")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("b9d7e1");settings.ambient_light_energy=0.7
	world.environment=settings;root.add_child(world)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-48,-25,0);light.light_energy=1.5;root.add_child(light)
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true
	camera.position=Vector3(0,1.6,0.18);camera.look_at(Vector3(0,1.24,-0.48));camera.fov=72
	for side in ["left_hand","right_hand"]:
		var grip:=Node3D.new();root.add_child(grip)
		grip.position=Vector3(-0.22 if side=="left_hand" else 0.22,1.15,-0.42)
		grip.basis=Basis(Vector3.RIGHT,PI/2)
		var hand=Hand.new();hand.configure(side);grip.add_child(hand);hand.set_pose(0,0.20)
		var guide=Guide.new();guide.configure(side);grip.add_child(guide)
		guide.set_context(true,true,false,true,false)
		guide.update_placement(grip.global_position,camera.global_transform,true)
	for frame in range(5):await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_capture.get_base_dir())
	_check(root.get_texture().get_image().save_png(_capture)==OK,"Glove and legend preview saved")
	print("HAND_GUIDE_CAPTURE ",_capture)
