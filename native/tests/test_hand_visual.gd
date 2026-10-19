extends SceneTree
## Geometry/contact contracts, independent of an OpenXR runtime or GPU.
## godot --headless --xr-mode off --path native --script res://tests/test_hand_visual.gd

const HandScript = preload("res://scripts/virtual_hand.gd")
const ButtonScript = preload("res://scripts/lab_button.gd")
var checks := 0
var failures := 0
var _space: Node3D


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_space=Node3D.new()
	_space.position=Vector3(0.7,1.3,-0.8)
	_space.rotation=Vector3(0.2,-0.5,0.16)
	_space.scale=Vector3.ONE*0.85
	root.add_child(_space)
	var right=HandScript.new()
	right.configure("right_hand")
	_space.add_child(right)
	var left=HandScript.new()
	_space.add_child(left)
	left.configure("left_hand")
	_test_handedness_and_axes(left,right)
	_test_pose_and_contact_marker(right)
	_test_budget(left)
	_test_budget(right)
	_test_button()
	print("HAND VISUAL TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)


func _check(condition: bool, description: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("HAND VISUAL TEST: "+description)


func _test_handedness_and_axes(left, right) -> void:
	for hand in [left,right]:
		_check(is_equal_approx(hand._hand_root.basis.determinant(),1.0),"Handedness uses a proper rotation rather than negative scale")
		_check((hand._hand_root.basis*Vector3.FORWARD).is_equal_approx(Vector3.DOWN),"Extended fingers follow anatomical grip -Y, separate from aim -Z")
		var palm_normal: Vector3=hand._hand_root.basis*Vector3.DOWN
		_check(palm_normal.is_equal_approx(Vector3.RIGHT if hand==left else Vector3.LEFT),"Palm outward normal matches handed OpenXR grip definition")
		var index_side := Vector3.RIGHT if hand==left else Vector3.LEFT
		_check((hand._hand_root.basis*index_side).is_equal_approx(Vector3.FORWARD),"Little-to-index direction matches grip -Z")
		_check(hand._fingers.size()==5,"Glove has five articulated digits")
	for pose in [[0.0,0.0,false,false],[0.45,0.7,true,false],[1.0,1.0,true,true]]:
		left.set_pose(pose[0],pose[1],pose[2],pose[3])
		right.set_pose(pose[0],pose[1],pose[2],pose[3])
		for finger_index in range(5):
			var l: Dictionary=left._fingers[finger_index]
			var r: Dictionary=right._fingers[finger_index]
			_check(l.joints.size()==3 and r.joints.size()==3,"Each finger retains a three-joint chain")
			for joint_index in range(3):
				var lp: Vector3=left._hand_root.to_local(l.joints[joint_index].global_position)
				var rp: Vector3=right._hand_root.to_local(r.joints[joint_index].global_position)
				_check(lp.is_equal_approx(Vector3(-rp.x,rp.y,rp.z)),"Left/right anatomical chains mirror without changing finger lengths")
		var left_tip: Vector3=left._hand_root.to_local(left.index_tip_global())
		var right_tip: Vector3=right._hand_root.to_local(right.index_tip_global())
		_check(left_tip.is_equal_approx(Vector3(-right_tip.x,right_tip.y,right_tip.z)),"Fingertip mirrors in each pose")
	left.set_pose(0,0)
	right.set_pose(0,0)
	var reach: float=right.index_tip_global().distance_to(right.palm_global())/_space.scale.x
	_check(reach>0.07 and reach<0.16,"Modeled palm-to-index reach has human hand proportions")


func _test_pose_and_contact_marker(hand) -> void:
	hand.set_pose(0,0)
	var pointing: Vector3=hand.index_tip_global()
	hand.set_pose(1,1,true,true)
	var clenched: Vector3=hand.index_tip_global()
	_check(pointing.distance_to(clenched)>0.04,"Trigger/grip produce visibly distinct pointing and clenched index poses")
	hand.set_pose(0,0,false,true)
	_check(pointing.distance_to(hand.index_tip_global())>0.03,"Holding an object curls the glove without an input trigger")
	hand.orientation_offset_degrees=Vector3(14,-22,7)
	hand.position_offset_m=Vector3(0.01,-0.005,0.025)
	_check(is_equal_approx(hand._hand_root.basis.determinant(),1.0),"Calibration offset retains a proper orientation basis")
	for input in [Vector2.ZERO,Vector2.ONE,Vector2(-10,4),Vector2(4,-10),Vector2(NAN,INF),Vector2(-INF,NAN)]:
		hand.set_pose(input.x,input.y,true,false)
		_check(is_finite(hand._trigger) and hand._trigger>=0 and hand._trigger<=1,"Trigger curl is finite and clamped")
		_check(is_finite(hand._grip) and hand._grip>=0 and hand._grip<=1,"Grip curl is finite and clamped")
		var visible_tip: MeshInstance3D=hand._tip_marker.get_node("VisibleTouchPoint")
		_check(visible_tip.is_visible_in_tree(),"Touchpoint has visible glove geometry")
		_check(hand.index_tip_global().is_equal_approx(visible_tip.global_position),"Collision fingertip exactly matches visible fingertip under pose/calibration/parent transform")
		_check(hand.palm_global().is_finite(),"Palm contact stays finite under every pose")
		for finger in hand._fingers:
			for joint in finger.joints:
				_check(joint.position.is_finite() and joint.rotation.is_finite() and joint.global_position.is_finite(),"Articulated joint transforms remain finite")
		for batch in [hand._segments,hand._seams,hand._pads]:
			for index in range(batch.multimesh.instance_count):
				var transform: Transform3D=batch.multimesh.get_instance_transform(index)
				_check(transform.origin.is_finite() and transform.basis.x.is_finite() and transform.basis.y.is_finite() and transform.basis.z.is_finite(),"Rendered finger instance transform remains finite")
	hand.set_pose(-8,-4)
	var clamped_open: Vector3=hand.index_tip_global()
	hand.set_pose(0,0)
	_check(clamped_open.is_equal_approx(hand.index_tip_global()),"Negative curl inputs match neutral pose")
	hand.set_pose(8,4)
	var clamped_closed: Vector3=hand.index_tip_global()
	hand.set_pose(1,1)
	_check(clamped_closed.is_equal_approx(hand.index_tip_global()),"Excess curl inputs match fully closed pose")
	hand.orientation_offset_degrees=Vector3.ZERO
	hand.position_offset_m=Vector3(0,0.021,0)


func _test_budget(hand) -> void:
	var batches := 0
	var triangles := 0
	for instance in hand.find_children("*","MeshInstance3D",true,false):
		batches+=instance.mesh.get_surface_count()
		triangles+=instance.mesh.get_faces().size()/3
	for instance in hand.find_children("*","MultiMeshInstance3D",true,false):
		batches+=instance.multimesh.mesh.get_surface_count()
		triangles+=(instance.multimesh.mesh.get_faces().size()/3)*instance.multimesh.instance_count
		_check(instance.multimesh.instance_count<=15,"Repeated finger details use bounded MultiMesh batches")
	batches+=hand.find_children("*","Label3D",true,false).size()
	_check(batches<=12,"Each glove stays within 12 estimated render batches")
	_check(triangles<7500,"Each glove stays below 7,500 instanced triangles")
	print("HAND BUDGET side=",hand._side," batches=",batches," triangles=",triangles)


func _test_button() -> void:
	var parent := Node3D.new()
	_space.add_child(parent)
	parent.position=Vector3(-0.5,0.2,-0.1)
	parent.rotation=Vector3(0.19,-0.42,0.28)
	var button=ButtonScript.new()
	parent.add_child(button)
	button.position=Vector3(0.1,0.1,-0.2)
	button.rotation=Vector3(-0.13,0.21,0.06)
	button.configure("CONTACT TEST","test",0.24,0.08)
	_check(button.get_meta("action","")=="test" and button.action=="test","Mechanical button preserves command metadata")
	_check((button.collision_layer&1)==1,"Mechanical button retains pointer collider")
	var face_rest: Vector3=button.face.position
	var caption_rest: Vector3=button.text_label.position
	for depth in [0.0,0.003,0.005,0.008]:
		var point: Vector3=button.to_global(Vector3(0.03,0.01,button.front_z_m-depth))
		_check(absf(button.contact_depth(point)-depth)<0.000001,"Contact depth is measured along rotated button local normal")
		button.set_depression(depth)
		_check(absf(button.face.position.z-(face_rest.z-depth))<0.000001,"Button face follows full physical travel")
		_check(absf(button.text_label.position.z-(caption_rest.z-depth))<0.000001,"Caption follows face without floating at rest height")
		_check(absf(button.contact_depth(point)-depth)<0.000001,"Finger depth remains referenced to rest surface during depression")
	_check(button.contact_depth(button.to_global(Vector3(0.2,0,button.front_z_m)))<0,"Contact outside button width rejected")
	_check(button.contact_depth(button.to_global(Vector3(0,0.1,button.front_z_m)))<0,"Contact outside button height rejected")
	_check(button.contact_depth(button.to_global(Vector3(0,0,button.front_z_m+0.05)))<0,"Distant front contact rejected")
	_check(button.contact_depth(button.to_global(Vector3(0,0,button.front_z_m-0.05)))<0,"Finger deeply behind button rejected")
	button.set_depression(0.2)
	_check(is_equal_approx(button.depression_m,button.stroke_m),"Mechanical travel cannot exceed full stroke")
	button.set_depression(-0.2)
	_check(is_zero_approx(button.depression_m) and button.face.position.is_equal_approx(face_rest),"Release restores original face pose")
	_check(button.text_label.position.is_equal_approx(caption_rest),"Release restores original caption pose")
	button.hover(true)
	button.set_caption("UPDATED")
	_check(button.text_label.text=="UPDATED","Hover/depression retain caption editing compatibility")
