extends SceneTree
## Grip-space controller geometry and readable top-deck labels, without XR.
## godot --headless --xr-mode off --path native --script res://tests/test_controller_pose.gd
## Omit --headless and add -- --capture-dir=<absolute-directory> for two views.
## The representative poses are test fixtures, not measured Touch calibration.

const Controller = preload("res://scripts/virtual_controller.gd")
const Hand = preload("res://scripts/virtual_hand.gd")
const NEUTRAL_GRIP := Basis(Vector3(1,0,0),Vector3(0,0,1),Vector3(0,-1,0))
var checks:=0
var failures:=0
var _capture_dir:=""
var _controllers: Array[Node3D]=[]
var _camera: Camera3D


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):_capture_dir=argument.trim_prefix("--capture-dir=")
	call_deferred("_run")


func _run() -> void:
	root.size=Vector2i(1500,1000)
	_camera=Camera3D.new();root.add_child(_camera);_camera.current=true
	for side in ["left_hand","right_hand"]:
		var controller=Controller.new()
		controller.configure(side);root.add_child(controller)
		_controllers.append(controller)
		_check_geometry(controller,side)
		_check_representative_poses(controller,side)
		_check_animation(controller,side)
	_check_mirrors()
	if not _capture_dir.is_empty():await _render_qa()
	for controller in _controllers:controller.queue_free()
	_camera.queue_free()
	await process_frame
	print("CONTROLLER POSE TESTS: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)


func _check(condition: bool, description: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("CONTROLLER POSE: "+description)


func _check_geometry(controller, side: String) -> void:
	_check(controller.transform.is_equal_approx(Transform3D.IDENTITY),side+" preserves the runtime grip transform")
	_check(controller.model_root.basis.determinant()>0.999,side+" has a proper model frame")
	_check(controller.find_children("*","MeshInstance3D",true,false).size()<=24,side+" mesh count stays bounded")
	_check(controller.find_children("*","CollisionObject3D",true,false).is_empty(),side+" model cannot intercept input")
	_check(controller.find_children("*","RayCast3D",true,false).is_empty(),side+" model does not create an aim ray")
	for name in ["GripOrigin","ThumbDeckFrame","HandleTail","IndexTriggerFront"]:
		_check(controller.pose_markers.has(name),side+" declares coordinate "+name)
	var deck: Marker3D=controller.pose_markers.ThumbDeckFrame
	_check(deck.basis.z.is_equal_approx(Vector3(0,0,-1)),side+" deck front normal follows thumbward -Z")
	_check(deck.basis.y.is_equal_approx(Vector3(0,-1,0)),side+" deck glyph up points forward -Y")
	_check(deck.basis.x.is_equal_approx(Vector3.RIGHT),side+" deck glyph right is grip +X")
	_check(deck.basis.determinant()>0.999,side+" deck frame is not a reflection")
	_check(controller.pose_markers.GripOrigin.position.is_equal_approx(Vector3.ZERO),side+" origin remains centered on grip")
	_check(controller.pose_markers.HandleTail.position.z>0.07,side+" handle extends toward little-finger +Z")
	_check(controller.pose_markers.IndexTriggerFront.position.y<0,side+" trigger is in front of the hand")
	var labels: Array=controller.button_labels
	_check(labels.size()==2,side+" has primary/secondary button labels")
	_check(labels[0].text==("X" if side=="left_hand" else "A"),side+" primary label matches hardware")
	_check(labels[1].text==("Y" if side=="left_hand" else "B"),side+" secondary label matches hardware")
	_check(labels[1].position.y<labels[0].position.y,side+" B/Y is forward of A/X on the deck")
	_check(labels[0].position.z<-0.073 and labels[1].position.z<-0.073,side+" letters sit above button faces")
	for label in controller.find_children("*","Label3D",true,false):
		_check(label.basis.z.is_equal_approx(Vector3(0,0,-1)),side+" label normal is deck outward")
		_check(label.basis.y.is_equal_approx(Vector3(0,-1,0)),side+" label top is forward, not toward wrist")
		_check(label.basis.x.is_equal_approx(Vector3.RIGHT),side+" label is not laterally mirrored")
		_check(not label.double_sided,side+" label back cannot appear reversed through the controller")
	var glove=Hand.new();glove.configure(side);root.add_child(glove)
	var finger_direction: Vector3=glove._hand_root.basis*Vector3.FORWARD
	var palm_outward: Vector3=glove._hand_root.basis*Vector3.DOWN
	_check(finger_direction.is_equal_approx(deck.basis.y),side+" deck up agrees with glove finger extension")
	_check(controller._grip.position.dot(palm_outward)>0.015,side+" squeeze paddle is on the curled-finger side")
	glove.queue_free()


func _check_representative_poses(controller, side: String) -> void:
	# Neutral thumb-up fist: local -Z is world up and local -Y is forward.
	# Yaw/pitch/roll below exercise natural variations while viewing the deck.
	# Keep the deck within the observer's visible hemisphere. A physical deck
	# tipped past edge-on legitimately hides or inverts its projected text.
	var poses: Array=[Vector3.ZERO,Vector3(15,0,0),Vector3(-10,0,0),Vector3(0,25,0),Vector3(0,-25,0),Vector3(0,0,22),Vector3(0,0,-22)]
	for angles in poses:
		var adjustment:=Basis.from_euler(angles*PI/180.0)
		controller.transform=Transform3D(adjustment*NEUTRAL_GRIP,Vector3(-0.18 if side=="left_hand" else 0.18,1.15,-0.38))
		for head_height in [1.45,1.65,1.85]:
			_camera.global_position=Vector3(0,head_height,0.18)
			_camera.look_at(controller.to_global(controller.pose_markers.ThumbDeckFrame.position))
			for label in controller.find_children("*","Label3D",true,false):
				var position_m: Vector3=label.global_position
				var towards_head: Vector3=(_camera.global_position-position_m).normalized()
				var center: Vector2=_camera.unproject_position(position_m)
				var top: Vector2=_camera.unproject_position(position_m+label.global_basis.y*0.005)
				var right: Vector2=_camera.unproject_position(position_m+label.global_basis.x*0.005)
				_check(label.global_basis.z.dot(towards_head)>0.15,side+" deck front faces representative head pose "+str(angles)+" / "+str(head_height))
				_check(top.y<center.y,side+" glyph top projects above baseline for representative head pose "+str(angles)+" / "+str(head_height))
				_check(right.x>center.x,side+" glyph right projects right for representative head pose")
				_check(top.is_finite() and right.is_finite(),side+" projected glyph axes are finite")
	controller.transform=Transform3D.IDENTITY


func _check_animation(controller, side: String) -> void:
	var origin: Transform3D=controller.pose_markers.ThumbDeckFrame.transform
	controller.set_pose(0,0)
	var trigger_rest: Vector3=controller._trigger.position
	var grip_rest: Vector3=controller._grip.position
	controller.set_pose(1,1)
	_check(controller._trigger.position.y>trigger_rest.y,side+" trigger depresses toward the handle")
	_check(absf(controller._grip.position.x)<absf(grip_rest.x),side+" squeeze paddle depresses inward")
	for invalid in [NAN,INF,-INF]:
		controller.set_pose(invalid,invalid)
		_check(controller._trigger.transform.is_finite() and controller._grip.transform.is_finite(),side+" invalid analog input cannot corrupt geometry")
	controller.set_pose(5,-5)
	_check(is_equal_approx(controller._trigger_value,1) and is_equal_approx(controller._grip_value,0),side+" analog values are clamped")
	_check(controller.pose_markers.ThumbDeckFrame.transform.is_equal_approx(origin),side+" animation preserves the deck coordinate frame")
	controller.set_pose(0,0)


func _check_mirrors() -> void:
	var left=_controllers[0]
	var right=_controllers[1]
	for index in range(2):
		_check(is_equal_approx(left.button_labels[index].position.x,-right.button_labels[index].position.x),"Face-button lateral layout mirrors")
		_check(is_equal_approx(left.button_labels[index].position.y,right.button_labels[index].position.y),"Face-button primary/secondary order is identical between hands")
		_check(left.button_labels[index].basis.is_equal_approx(right.button_labels[index].basis),"Both hands use the same upright glyph frame")
	_check(is_equal_approx(left._grip.position.x,-right._grip.position.x),"Squeeze paddles mirror anatomically")
	var grip_frame: Transform3D=left.transform
	left.configure("right_hand")
	_check(left.button_labels[0].text=="A" and left.button_labels[1].text=="B","Reconfigure updates label identities")
	_check(left.transform.is_equal_approx(grip_frame),"Reconfigure cannot rotate the runtime grip frame")
	left.configure("left_hand")


func _render_qa() -> void:
	if DisplayServer.get_name()=="headless":
		_check(false,"Rendering QA needs a display; omit --headless")
		return
	DirAccess.make_dir_recursive_absolute(_capture_dir)
	var world:=WorldEnvironment.new()
	var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("102331")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("b8d6e0");settings.ambient_light_energy=0.7
	world.environment=settings;root.add_child(world)
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-45,-20,0);light.light_energy=1.6;root.add_child(light)
	for index in range(2):
		_controllers[index].transform=Transform3D(NEUTRAL_GRIP,Vector3(-0.11 if index==0 else 0.11,0,0))
	_camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	_camera.size=0.34
	_camera.global_position=Vector3(0,0.55,0.02);_camera.look_at(Vector3(0,0,0))
	await _save_frame("controller-neutral-top.png")
	_camera.global_position=Vector3(0,0.30,0.33);_camera.look_at(Vector3(0,0,0.01))
	await _save_frame("controller-operator-front.png")


func _save_frame(filename: String) -> void:
	for frame in range(5):await process_frame
	await RenderingServer.frame_post_draw
	var path: String=_capture_dir.path_join(filename)
	_check(root.get_texture().get_image().save_png(path)==OK,"Saved controller render "+filename)
	print("CONTROLLER_POSE_CAPTURE ",path)
