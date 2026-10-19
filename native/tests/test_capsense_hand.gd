extends SceneTree
## Real XRHandTracker source/pose gating with a synthetic runtime-mesh shell.
## Does not establish Meta joint fidelity, skinning, actual Capsense, or fit.
const Capsense = preload("res://scripts/controller_capsense_hand.gd")

class MeshShell extends Skeleton3D:
	var hand := 0:
		set(value):
			hand = value
			for bone in get_bone_count():set_bone_name(bone,get_bone_name(bone).replace("Right","Left") if hand==0 else get_bone_name(bone).replace("Left","Right"))
	var material: Material
	var instance: MeshInstance3D
	func _init() -> void:
		for suffix in ["Palm","Hand","ThumbMetacarpal","ThumbProximal","ThumbDistal","ThumbTip","IndexMetacarpal","IndexProximal","IndexIntermediate","IndexDistal","IndexTip","MiddleMetacarpal","MiddleProximal","MiddleIntermediate","MiddleDistal","MiddleTip","RingMetacarpal","RingProximal","RingIntermediate","RingDistal","RingTip","LittleMetacarpal","LittleProximal","LittleIntermediate","LittleDistal","LittleTip"]:
			add_bone("Left"+suffix)
			if get_bone_count()>1:set_bone_parent(get_bone_count()-1,0)
		instance = MeshInstance3D.new();instance.mesh = BoxMesh.new();add_child(instance)
	func set_hand(value: int) -> void:hand = value
	func set_material(value: Material) -> void:material = value
	func get_mesh_instance() -> MeshInstance3D:return instance

class RuntimeShell extends Capsense:
	func _create_runtime_mesh() -> Skeleton3D:return MeshShell.new()

class MissingRuntime extends Capsense:
	func _create_runtime_mesh() -> Skeleton3D:return null

var checks := 0
var failures := 0
var tracked_hands: Array[XRHandTracker] = []
var rigs: Array[Node3D] = []
var previous_trackers: Array = []

func _initialize() -> void:call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1;push_error("CAPSENSE: " + message)

func _run() -> void:
	var invalid = RuntimeShell.new();root.add_child(invalid)
	_check(not invalid.enable_runtime(), "Reject placement outside direct XROrigin3D parent")
	_check(not invalid.visible, "Misparented visual stays hidden")
	invalid.queue_free()
	var missing_rig := XROrigin3D.new();root.add_child(missing_rig);rigs.append(missing_rig)
	var missing := MissingRuntime.new();missing_rig.add_child(missing)
	_check(not missing.enable_runtime(), "Missing vendor class fails closed without requiring a plugin on test host")
	missing.set_active(true,true)
	_check(not missing.visible, "Unavailable mesh cannot expose a blank tracked hand")
	for side in ["left_hand", "right_hand"]:
		await _exercise_side(side)
	for tracker in tracked_hands:XRServer.remove_tracker(tracker)
	for previous in previous_trackers:
		if previous != null:XRServer.add_tracker(previous)
	tracked_hands.clear();previous_trackers.clear()
	for rig in rigs:rig.queue_free()
	rigs.clear()
	await process_frame
	print("CAPSENSE HAND TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _exercise_side(side: String) -> void:
	var rig := XROrigin3D.new();rig.position = Vector3(3,0,2);root.add_child(rig);rigs.append(rig)
	var hand := RuntimeShell.new();hand.configure(side);rig.add_child(hand)
	var expected: StringName = &"/user/hand_tracker/left" if side == "left_hand" else &"/user/hand_tracker/right"
	_check(hand.tracker_name == expected, "Hand selects its own runtime tracker")
	_check(hand.enable_runtime(), "Mesh shell initializes the same runtime hierarchy")
	_check(hand.runtime_anchor is XRNode3D and hand.runtime_anchor.get_parent() == hand, "Palm tracking is owned by XRNode3D under rig, independent of grip node")
	_check(hand.runtime_anchor.tracker == expected and hand.runtime_anchor.pose == &"default", "Anchor uses hand-tracker default palm pose")
	_check(hand.runtime_mesh is Skeleton3D and hand.runtime_mesh.get_parent() == hand.runtime_anchor, "Runtime hand mesh is the animated skeleton under tracked palm")
	_check(hand.hand_modifier.get_parent() == hand.runtime_mesh and hand.hand_modifier.hand_tracker == expected, "Skeleton modifier reads matching hand tracker")
	_check(hand.runtime_mesh.hand == (0 if side == "left_hand" else 1), "Runtime mesh receives correct handedness")
	_check(hand.find_children("*","CollisionObject3D",true,false).is_empty(), "Visual contains no collision or input targets")
	var count := hand.runtime_anchor.get_child_count()
	_check(hand.enable_runtime() and hand.runtime_anchor.get_child_count() == count, "Repeated enable does not duplicate mesh or modifier")
	hand.set_active(true,true)
	_check(not hand.visible, "Absent tracker remains hidden")
	var previous = XRServer.get_tracker(expected)
	previous_trackers.append(previous)
	if previous != null:XRServer.remove_tracker(previous)
	var tracker := XRHandTracker.new();tracker.name = expected
	tracker.hand = XRPositionalTracker.TRACKER_HAND_LEFT if side == "left_hand" else XRPositionalTracker.TRACKER_HAND_RIGHT
	tracked_hands.append(tracker);XRServer.add_tracker(tracker)
	_set_valid(tracker)
	hand.set_active(true,true)
	_check(hand.visible, "Controller source with valid inferred joints is visible")
	_check(hand.runtime_status == "controller poses active", "Active status identifies actual controller data source")
	await process_frame
	await process_frame
	_check(hand.runtime_anchor.global_position.distance_to(rig.to_global(Vector3(-0.3,1.2,-0.4))) < 0.0001, "Palm pose is transformed by XROrigin once; no double grip offset")
	var material: StandardMaterial3D = hand.runtime_mesh.material
	_check(material != null and material.albedo_color.a > 0.0 and material.albedo_color.a < 1.0 and not material.no_depth_test, "Neutral hand overlay is translucent and respects scene depth")
	for source in [XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED,XRHandTracker.HAND_TRACKING_SOURCE_UNKNOWN,XRHandTracker.HAND_TRACKING_SOURCE_NOT_TRACKED]:
		tracker.hand_tracking_source = source;hand.set_active(true,true)
		_check(not hand.visible, "Optical/unknown/not-tracked source never masquerades as controller Capsense")
	_set_valid(tracker)
	tracker.has_tracking_data = false;hand.set_active(true,true)
	_check(not hand.visible, "Tracker data loss immediately hides hand")
	_set_valid(tracker)
	tracker.invalidate_pose(&"default");hand.set_active(true,true)
	_check(not hand.visible, "Invalid palm pose immediately hides hand")
	_set_valid(tracker)
	tracker.set_pose(&"default",Transform3D(Basis.IDENTITY,Vector3(NAN,0,0)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	hand.set_active(true,true)
	_check(not hand.visible, "Nonfinite palm pose cannot reach the rendered transform")
	_set_valid(tracker)
	for joint in range(XRHandTracker.HAND_JOINT_MAX):
		tracker.set_hand_joint_flags(joint,0);hand.set_active(true,true)
		_check(not hand.visible, "Missing valid joint flags hide incomplete pose: " + str(joint))
		tracker.set_hand_joint_flags(joint,XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID)
		hand.set_active(true,true)
		_check(hand.visible, "VALID inferred joints recover without requiring optical TRACKED bits: " + str(joint))
	for flag in [XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID,XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID]:
		tracker.set_hand_joint_flags(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP,flag);hand.set_active(true,true)
		_check(not hand.visible, "A joint requires both valid position and orientation, not only one")
	_set_valid(tracker)
	tracker.set_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP,Transform3D(Basis.IDENTITY,Vector3(INF,0,0)))
	hand.set_active(true,true)
	_check(not hand.visible, "Nonfinite finger joint hides malformed runtime pose")
	_set_valid(tracker)
	hand.set_active(false,true);_check(not hand.visible, "Physical-glove mode never shows the controller-conforming overlay")
	hand.set_active(true,false);_check(not hand.visible, "Grip tracking loss hides otherwise-valid runtime fingers")
	hand.set_active(true,true);_check(hand.visible, "Menu and grip tracking recovery restores actual controller poses")
	var saved_mesh: Mesh = hand.runtime_mesh.instance.mesh
	hand.runtime_mesh.instance.mesh = null;hand.set_active(true,true)
	_check(not hand.visible, "Missing asynchronously-loaded mesh fails closed")
	hand.runtime_mesh.instance.mesh = saved_mesh;hand.set_active(true,true)
	_check(hand.visible, "Mesh readiness restores valid runtime data")

func _set_valid(tracker: XRHandTracker) -> void:
	tracker.has_tracking_data = true
	tracker.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER
	tracker.set_pose(&"default",Transform3D(Basis.IDENTITY,Vector3(-0.3,1.2,-0.4)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	for joint in range(XRHandTracker.HAND_JOINT_MAX):
		tracker.set_hand_joint_flags(joint,XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID)
		tracker.set_hand_joint_transform(joint,Transform3D(Basis.IDENTITY,Vector3(-0.3,1.2,-0.4)))
