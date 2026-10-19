class_name ControllerCapsenseHand
extends Node3D
## Menu-only runtime hand visual. Direct child of XROrigin3D; never parent to
## the controller grip, because XRNode3D already applies the tracked palm pose.
## Meta's controller data source supplies inferred, capacitive-sensor poses.
## This class owns no interaction, collision, optical-hand input, or asset export.

var tracker_name: StringName = &"/user/hand_tracker/right"
var runtime_anchor: XRNode3D
var runtime_mesh: Skeleton3D
var hand_modifier: XRHandModifier3D
var runtime_enabled := false
var runtime_status := "not initialized"
var _side := "right_hand"
var _interface: OpenXRInterface
var _mode_active := false
var _grip_tracked := false
var _logged_controller_pose := false
var _reported_status := ""

func configure(side: String) -> void:
	_side = "left_hand" if side in ["left", "left_hand"] else "right_hand"
	tracker_name = &"/user/hand_tracker/left" if _side == "left_hand" else &"/user/hand_tracker/right"
	if is_instance_valid(runtime_anchor):runtime_anchor.tracker = tracker_name
	if is_instance_valid(hand_modifier):hand_modifier.hand_tracker = tracker_name
	if is_instance_valid(runtime_mesh) and runtime_mesh.has_method("set_hand"):
		runtime_mesh.set("hand", 0 if _side == "left_hand" else 1)
	_refresh_visibility()

func enable_runtime(interface: OpenXRInterface = null) -> bool:
	visible = false
	if not get_parent() is XROrigin3D:
		runtime_status = "requires direct XROrigin3D parent"
		return false
	_interface = interface
	if runtime_enabled:
		_ensure_motion_range()
		_refresh_visibility()
		return true
	runtime_mesh = _create_runtime_mesh()
	if not is_instance_valid(runtime_mesh):
		runtime_status = "runtime mesh class unavailable"
		return false
	runtime_anchor = XRNode3D.new()
	runtime_anchor.name = "TrackedControllerPalm"
	runtime_anchor.tracker = tracker_name
	runtime_anchor.pose = &"default"
	runtime_anchor.show_when_tracked = false
	if runtime_mesh.has_method("set_hand"):
		runtime_mesh.set("hand", 0 if _side == "left_hand" else 1)
	if runtime_mesh.has_method("set_material"):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.78, 0.88, 0.95, 0.36)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = false
		runtime_mesh.set("material", material)
	if runtime_mesh.has_signal("openxr_fb_hand_tracking_mesh_ready"):
		runtime_mesh.connect("openxr_fb_hand_tracking_mesh_ready", _on_mesh_ready)
	if runtime_mesh.has_signal("openxr_fb_hand_tracking_mesh_unavailable"):
		runtime_mesh.connect("openxr_fb_hand_tracking_mesh_unavailable", _on_mesh_unavailable)
	hand_modifier = XRHandModifier3D.new()
	hand_modifier.name = "RuntimeControllerFingerPoses"
	hand_modifier.hand_tracker = tracker_name
	hand_modifier.bone_update = XRHandModifier3D.BONE_UPDATE_FULL
	runtime_mesh.add_child(hand_modifier)
	runtime_anchor.add_child(runtime_mesh)
	add_child(runtime_anchor)
	runtime_enabled = true
	_ensure_motion_range()
	_refresh_visibility()
	return true

func set_active(menu_visible: bool, grip_tracking: bool) -> void:
	_mode_active = menu_visible
	_grip_tracked = grip_tracking
	_refresh_visibility()

func _process(_delta: float) -> void:
	if runtime_enabled:
		_ensure_motion_range()
		_refresh_visibility()
		if _mode_active and runtime_status != _reported_status:
			_reported_status = runtime_status
			print("SPINLAB_CAPSENSE_STATUS side=",_side," status=",runtime_status)

func _create_runtime_mesh() -> Skeleton3D:
	if not ClassDB.class_exists("OpenXRFbHandTrackingMesh"):return null
	return ClassDB.instantiate("OpenXRFbHandTrackingMesh") as Skeleton3D

func _ensure_motion_range() -> void:
	if not is_instance_valid(_interface) or not _interface.is_initialized() or not _interface.is_hand_tracking_supported():return
	var hand = OpenXRInterface.HAND_LEFT if _side == "left_hand" else OpenXRInterface.HAND_RIGHT
	if _interface.get_motion_range(hand) != OpenXRInterface.HAND_MOTION_RANGE_CONFORM_TO_CONTROLLER:
		_interface.set_motion_range(hand, OpenXRInterface.HAND_MOTION_RANGE_CONFORM_TO_CONTROLLER)

func _on_mesh_ready() -> void:
	_refresh_visibility()

func _on_mesh_unavailable() -> void:
	runtime_status = "runtime hand mesh unavailable"
	visible = false

func _refresh_visibility() -> void:
	visible = false
	if not runtime_enabled or not _mode_active or not _grip_tracked:return
	if not is_instance_valid(runtime_mesh) or not runtime_mesh.has_method("get_mesh_instance"):return
	var mesh_instance = runtime_mesh.call("get_mesh_instance")
	if not is_instance_valid(mesh_instance) or not mesh_instance is MeshInstance3D or mesh_instance.mesh == null:
		runtime_status = "waiting for runtime mesh"
		return
	var tracker = XRServer.get_tracker(tracker_name)
	if not tracker is XRHandTracker or not tracker.has_tracking_data:
		runtime_status = "waiting for hand data"
		return
	if tracker.hand_tracking_source != XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER:
		runtime_status = "controller data source required"
		return
	var pose = tracker.get_pose(&"default")
	if pose == null or not pose.has_tracking_data or not pose.transform.is_finite():
		runtime_status = "invalid controller palm pose"
		return
	# Inferred joints may be VALID without being optically TRACKED. Requiring
	# TRACKED bits would incorrectly reject the controller/Capsense source.
	var required := XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID
	for joint in range(XRHandTracker.HAND_JOINT_MAX):
		if int(tracker.get_hand_joint_flags(joint)) & required != required or not tracker.get_hand_joint_transform(joint).is_finite():
			runtime_status = "incomplete controller joints"
			return
	visible = true
	runtime_status = "controller poses active"
	if not _logged_controller_pose:
		_logged_controller_pose = true
		print("SPINLAB_CAPSENSE side=", _side, " source=controller valid_joints=26")
