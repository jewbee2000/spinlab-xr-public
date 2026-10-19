class_name VirtualHand
extends Node3D
## Controller-tracked, original procedural laboratory glove. This estimates an
## expressive hand pose from Touch controls; it does not claim optical tracking.
## Grip convention: https://registry.khronos.org/OpenXR/specs/1.1/html/xrspec.html
## Grip -Z runs little-finger -> index along a held tube; it is not the extended
## finger direction. The anatomical mapping below therefore points fingers -Y.

var orientation_offset_degrees := Vector3.ZERO:
	set(value):
		orientation_offset_degrees=value
		_align_to_grip()
# Recenter the modeled palm centroid on the grip origin (the contact marker
# remains on its surface, 12 mm along the handed palm normal).
var position_offset_m := Vector3(0,0.021,0):
	set(value):
		position_offset_m=value
		_align_to_grip()

var _side := "right_hand"
var _hand_root: Node3D
var _palm_marker: Marker3D
var _tip_marker: Marker3D
var _fingers: Array = []
var _segments: MultiMeshInstance3D
var _seams: MultiMeshInstance3D
var _pads: MultiMeshInstance3D
var _built := false
var _trigger := 0.0
var _grip := 0.0
var _thumb_touch := false
var _holding := false
var _skin: StandardMaterial3D
var _dark: StandardMaterial3D
var _trim: StandardMaterial3D


func _ready() -> void:
	if not _built:
		_build()
	set_pose(_trigger,_grip,_thumb_touch,_holding)


func configure(side: String) -> void:
	var chosen := "left_hand" if side == "left_hand" or side == "left" else "right_hand"
	if _built and chosen != _side:
		remove_child(_hand_root)
		_hand_root.queue_free()
		_built=false
	_side=chosen
	if not _built:
		_build()
	set_pose(_trigger,_grip,_thumb_touch,_holding)


func _align_to_grip() -> void:
	if not is_instance_valid(_hand_root):return
	# Canonical glove has dorsal +Y, extended fingers -Z, and index -X on
	# the right. Map palm normal and finger fan to the actual grip axes.
	var mirror := -1.0 if _side == "left_hand" else 1.0
	var anatomical := Basis(Vector3(0,0,mirror),Vector3(mirror,0,0),Vector3(0,1,0))
	var adjustment := Basis.from_euler(orientation_offset_degrees*PI/180.0)
	_hand_root.transform=Transform3D(adjustment*anatomical,position_offset_m)


func _build() -> void:
	_hand_root=Node3D.new()
	_hand_root.name="LaboratoryGlove"
	add_child(_hand_root)
	_skin=_material(Color("7bbdb8"),0.67)
	_dark=_material(Color("173a4a"),0.78)
	_trim=_material(Color("a4f5e5"),0.48)
	_trim.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var mirror := -1.0 if _side == "left_hand" else 1.0
	_mesh(_hand_root,_palm_mesh(),_skin,"AnatomicalPalm")
	var reinforcement := _mesh(_hand_root,_palm_mesh(),_dark,"DorsalReinforcement")
	reinforcement.scale=Vector3(0.77,0.18,0.70)
	reinforcement.position=Vector3(0,0.014,-0.006)
	var thenar := _mesh(_hand_root,_sphere_mesh(),_skin,"ThumbThenar")
	thenar.position=Vector3(-0.026*mirror,-0.004,-0.005)
	thenar.scale=Vector3(0.022,0.016,0.031)
	var cuff_mesh := CylinderMesh.new()
	cuff_mesh.top_radius=0.030
	cuff_mesh.bottom_radius=0.027
	cuff_mesh.height=0.032
	cuff_mesh.radial_segments=16
	var cuff := _mesh(_hand_root,cuff_mesh,_dark,"ElasticWristCuff")
	cuff.transform=Transform3D(Basis(Vector3.RIGHT,PI/2).scaled(Vector3(1,0.64,1)),Vector3(0,0,0.036))
	var cuff_ring := TorusMesh.new()
	cuff_ring.inner_radius=0.027
	cuff_ring.outer_radius=0.030
	cuff_ring.rings=20
	cuff_ring.ring_segments=6
	var trim := _mesh(_hand_root,cuff_ring,_trim,"CuffIdentityBand")
	trim.transform=Transform3D(Basis(Vector3.RIGHT,PI/2).scaled(Vector3(1,0.64,1)),Vector3(0,0,0.020))
	var badge := Label3D.new()
	badge.text="L" if _side == "left_hand" else "R"
	badge.font_size=32;badge.pixel_size=0.00042
	badge.position=Vector3(0,0.018,0.001)
	badge.rotation.x=-PI/2
	badge.modulate=Color("bff5eb")
	badge.outline_size=0
	_hand_root.add_child(badge)
	_palm_marker=Marker3D.new()
	_palm_marker.name="PalmContact"
	_palm_marker.position=Vector3(0,-0.012,-0.021)
	_hand_root.add_child(_palm_marker)
	_fingers.clear()
	# Segment lengths and cross sections preserve natural finger proportions.
	_make_finger("Index",Vector3(-0.027*mirror,0,-0.063),[0.039,0.025,0.020],[0.009,0.0078,0.0068],0.055*mirror,false)
	_make_finger("Middle",Vector3(-0.008*mirror,0,-0.071),[0.043,0.028,0.022],[0.0094,0.0081,0.0070],0.0,false)
	_make_finger("Ring",Vector3(0.013*mirror,-0.001,-0.067),[0.040,0.026,0.021],[0.0088,0.0076,0.0065],-0.035*mirror,false)
	_make_finger("Little",Vector3(0.031*mirror,-0.002,-0.054),[0.031,0.021,0.018],[0.0075,0.0065,0.0057],-0.13*mirror,false)
	_make_finger("Thumb",Vector3(-0.033*mirror,-0.006,-0.002),[0.030,0.025,0.020],[0.011,0.0096,0.0082],0.85*mirror,true)
	_segments=_batch(_segment_mesh(),_skin,15,"ArticulatedPhalanges")
	var seam_mesh := TorusMesh.new()
	seam_mesh.inner_radius=0.85;seam_mesh.outer_radius=1.0
	seam_mesh.rings=10;seam_mesh.ring_segments=4
	_seams=_batch(seam_mesh,_dark,15,"FlexibleJointSeams")
	_pads=_batch(_sphere_mesh(),_dark,10,"FingerReinforcementPads")
	_tip_marker=Marker3D.new()
	_tip_marker.name="IndexContactPoint"
	var index: Dictionary=_fingers[0]
	index.joints[2].add_child(_tip_marker)
	_tip_marker.position=Vector3(0,-0.001,-float(index.lengths[2])-0.001)
	var tip := _mesh(_tip_marker,_sphere_mesh(),_trim,"VisibleTouchPoint")
	tip.scale=Vector3.ONE*0.0030
	_built=true
	_align_to_grip()


func _make_finger(finger_name: String, origin: Vector3, lengths: Array, widths: Array, spread: float, thumb: bool) -> void:
	var joints: Array[Node3D]=[]
	var parent: Node3D=_hand_root
	for index in range(3):
		var joint := Node3D.new()
		joint.name=finger_name+["MCP","PIP","DIP"][index]
		joint.position=origin if index==0 else Vector3(0,0,-float(lengths[index-1]))
		parent.add_child(joint)
		joints.append(joint)
		parent=joint
	_fingers.append({"name":finger_name,"joints":joints,"lengths":lengths,"widths":widths,"spread":spread,"thumb":thumb})


func set_pose(trigger: float, grip: float, thumb_touch: bool=false, holding: bool=false) -> void:
	_trigger=clampf(trigger,0,1) if is_finite(trigger) else 0.0
	_grip=clampf(grip,0,1) if is_finite(grip) else 0.0
	_thumb_touch=thumb_touch
	_holding=holding
	if not _built:return
	var grasp := maxf(_grip,0.76 if holding else 0.0)
	var index_curl := maxf(_trigger,0.56 if holding else 0.0)
	var mirror := -1.0 if _side == "left_hand" else 1.0
	for finger_index in range(_fingers.size()):
		var finger: Dictionary=_fingers[finger_index]
		var joints: Array=finger.joints
		if finger.thumb:
			var thumb_curl := maxf(grasp,0.45 if thumb_touch else 0.0)
			joints[0].rotation=Vector3(lerpf(-0.12,-0.65,thumb_curl),lerpf(0.85,-0.12,thumb_curl)*mirror,0.22*mirror)
			joints[1].rotation.x=lerpf(-0.10,-0.80,thumb_curl)
			joints[2].rotation.x=lerpf(-0.08,-0.42,thumb_curl)
		elif finger_index==0:
			joints[0].rotation=Vector3(lerpf(-0.015,-0.90,index_curl),float(finger.spread),0)
			joints[1].rotation.x=lerpf(-0.025,-1.35,index_curl)
			joints[2].rotation.x=lerpf(-0.01,-0.82,index_curl)
		else:
			var rest := float(finger_index-1)*0.035
			joints[0].rotation=Vector3(lerpf(-0.15-rest,-1.02,grasp),float(finger.spread)*(1.0-grasp*0.6),0)
			joints[1].rotation.x=lerpf(-0.26-rest,-1.42,grasp)
			joints[2].rotation.x=lerpf(-0.12-rest,-0.88,grasp)
	_update_batches()


func index_tip_global() -> Vector3:
	return _tip_marker.global_position if is_instance_valid(_tip_marker) else global_position


func palm_global() -> Vector3:
	return _palm_marker.global_position if is_instance_valid(_palm_marker) else global_position


func _update_batches() -> void:
	var number := 0
	for finger_index in range(_fingers.size()):
		var finger: Dictionary=_fingers[finger_index]
		var joints: Array=finger.joints
		for joint_index in range(3):
			var joint: Node3D=joints[joint_index]
			# Work entirely in hand-local coordinates so calls are safe before the
			# parent is inserted into the scene tree and do not depend on tracking.
			var transform: Transform3D=joint.transform
			for ancestor in range(joint_index-1,-1,-1):
				transform=(joints[ancestor] as Node3D).transform*transform
			var width := float(finger.widths[joint_index])
			var length := float(finger.lengths[joint_index])
			_segments.multimesh.set_instance_transform(number,transform*Transform3D(Basis.IDENTITY.scaled(Vector3(width,width*0.84,length)),Vector3.ZERO))
			var seam_basis := Basis(Vector3.RIGHT,PI/2).scaled(Vector3(width*1.015,width*0.85,width*1.015))
			_seams.multimesh.set_instance_transform(number,transform*Transform3D(seam_basis,Vector3(0,0,-0.002)))
			if joint_index==2:
				for pad_side in range(2):
					var pad_scale := Vector3(width*0.68,0.0015,length*0.28)
					var pad_pos := Vector3(0,(-1.0 if pad_side==0 else 1.0)*width*0.76,-length*0.58)
					_pads.multimesh.set_instance_transform(finger_index*2+pad_side,transform*Transform3D(Basis.IDENTITY.scaled(pad_scale),pad_pos))
			number+=1


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color=color
	material.roughness=roughness
	return material


func _mesh(parent: Node3D, shape: Mesh, material: StandardMaterial3D, node_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name=node_name;instance.mesh=shape;instance.material_override=material
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _batch(shape: Mesh, material: StandardMaterial3D, count: int, node_name: String) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format=MultiMesh.TRANSFORM_3D
	multi.mesh=shape;multi.instance_count=count
	multi.custom_aabb=AABB(Vector3(-0.2,-0.2,-0.2),Vector3(0.4,0.4,0.4))
	var instance := MultiMeshInstance3D.new()
	instance.name=node_name;instance.multimesh=multi;instance.material_override=material
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hand_root.add_child(instance)
	return instance


func _sphere_mesh() -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius=1.0;sphere.height=2.0
	sphere.radial_segments=12;sphere.rings=6
	return sphere


func _palm_mesh() -> ArrayMesh:
	var rings := [Vector3(0.024,0.011,0.034),Vector3(0.030,0.015,0.015),Vector3(0.040,0.016,-0.022),Vector3(0.038,0.014,-0.053),Vector3(0.030,0.011,-0.069)]
	return _rounded_tube(rings,16)


func _segment_mesh() -> ArrayMesh:
	var rings := [Vector3(0.82,0.82,0),Vector3(0.98,0.98,-0.07),Vector3(1,1,-0.24),Vector3(0.86,0.86,-0.72),Vector3(0.67,0.67,-0.93),Vector3(0.20,0.20,-1.0)]
	return _rounded_tube(rings,10)


func _rounded_tube(rings: Array, sides: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for ring_index in range(rings.size()):
		var ring: Vector3=rings[ring_index]
		for index in range(sides):
			var theta := TAU*float(index)/float(sides)
			vertices.append(Vector3(cos(theta)*ring.x,sin(theta)*ring.y,ring.z))
			normals.append(Vector3(cos(theta)/ring.x,sin(theta)/ring.y,0).normalized())
	for ring_index in range(rings.size()-1):
		for index in range(sides):
			var a := ring_index*sides+index
			var b := ring_index*sides+(index+1)%sides
			var c := a+sides
			var d := b+sides
			indices.append_array(PackedInt32Array([a,c,b,b,c,d]))
	for end in range(2):
		var ring_index := 0 if end==0 else rings.size()-1
		var center := vertices.size()
		vertices.append(Vector3(0,0,rings[ring_index].z))
		normals.append(Vector3.BACK if end==0 else Vector3.FORWARD)
		for index in range(sides):
			var a := ring_index*sides+index
			var b := ring_index*sides+(index+1)%sides
			indices.append_array(PackedInt32Array([center,a,b] if end==0 else [center,b,a]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
