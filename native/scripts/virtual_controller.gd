class_name VirtualController
extends Node3D
## Original controller visualization, not a vendor CAD model. Uses the OpenXR
## grip frame: the handle follows +Z toward the lower grip; its controls/ring
## sit toward -Z. The application supplies the separate aim ray and input.

var model_root: Node3D
var button_labels: Array[Label3D] = []
var _side := "right_hand"
var _built := false
var _trigger: Node3D
var _grip: Node3D
var _trigger_value := 0.0
var _grip_value := 0.0
var _materials: Dictionary = {}


func _ready() -> void:
	if not _built:_build()


func configure(side: String) -> void:
	var chosen := "left_hand" if side in ["left_hand","left"] else "right_hand"
	if _built and chosen!=_side:
		remove_child(model_root)
		model_root.queue_free()
		_built=false
	_side=chosen
	if not _built:_build()
	set_pose(_trigger_value,_grip_value)


func _build() -> void:
	model_root=Node3D.new()
	model_root.name="TrackedControllerVisual"
	add_child(model_root)
	button_labels.clear()
	_materials.clear()
	_material("shell",Color("18212b"),0.56)
	_material("plate",Color("35414d"),0.43)
	_material("rubber",Color("0b1118"),0.87)
	_material("trigger",Color("788894"),0.45)
	_material("text",Color("e6f6f5"),0.8,true)
	_material("accent",Color("65e6da"),0.5,true)
	var mirror := -1.0 if _side=="left_hand" else 1.0
	var handle := CapsuleMesh.new()
	handle.radius=0.023;handle.height=0.125
	handle.radial_segments=16;handle.rings=6
	var body=_mesh(model_root,handle,"shell","ErgonomicHandle")
	body.transform=Transform3D(Basis(Vector3.RIGHT,PI/2).scaled(Vector3(0.92,1.12,1)),Vector3(0,0.008,0.019))
	var face=_mesh(model_root,_sphere(),"plate","ThumbControlDeck")
	face.position=Vector3(0,-0.015,-0.052)
	face.scale=Vector3(0.039,0.052,0.017)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius=0.060;ring_mesh.outer_radius=0.067
	ring_mesh.rings=40;ring_mesh.ring_segments=6
	var ring=_mesh(model_root,ring_mesh,"shell","TrackingRing")
	ring.position=Vector3(0,-0.019,-0.049)
	ring.rotation.x=PI/2
	var ring_stripe := TorusMesh.new()
	ring_stripe.inner_radius=0.0645;ring_stripe.outer_radius=0.0655
	ring_stripe.rings=40;ring_stripe.ring_segments=4
	var stripe=_mesh(model_root,ring_stripe,"trigger","RingSeam")
	stripe.position=Vector3(0,-0.019,-0.053)
	stripe.rotation.x=PI/2
	var ribs_mesh := TorusMesh.new()
	ribs_mesh.inner_radius=0.0220;ribs_mesh.outer_radius=0.0231
	ribs_mesh.rings=16;ribs_mesh.ring_segments=4
	var ribs := MultiMesh.new()
	ribs.transform_format=MultiMesh.TRANSFORM_3D
	ribs.mesh=ribs_mesh;ribs.instance_count=4
	for index in range(4):
		ribs.set_instance_transform(index,Transform3D(Basis(Vector3.RIGHT,PI/2).scaled(Vector3(0.92,1.12,1)),Vector3(0,0.008,0.001+index*0.018)))
	var rib_instance := MultiMeshInstance3D.new()
	rib_instance.name="GripTextureRibs";rib_instance.multimesh=ribs;rib_instance.material_override=_materials.rubber
	rib_instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model_root.add_child(rib_instance)
	_trigger=Node3D.new()
	_trigger.name="IndexTrigger"
	_trigger.position=Vector3(0,-0.044,-0.014)
	model_root.add_child(_trigger)
	var trigger=_mesh(_trigger,_sphere(),"trigger","TriggerPaddle")
	trigger.scale=Vector3(0.022,0.011,0.019)
	_grip=Node3D.new()
	_grip.name="SideGripButton"
	_grip.position=Vector3(mirror*0.022,0.006,0.022)
	model_root.add_child(_grip)
	var grip_shape := BoxMesh.new()
	grip_shape.size=Vector3(0.006,0.026,0.037)
	_mesh(_grip,grip_shape,"trigger","GripPaddle")
	var stick_pos := Vector3(-mirror*0.013,-0.027,-0.073)
	_disc(model_root,"JoystickSocket",0.015,0.003,stick_pos,"rubber")
	_disc(model_root,"JoystickStem",0.006,0.010,stick_pos+Vector3(0,0,-0.005),"trigger")
	_disc(model_root,"JoystickCap",0.012,0.005,stick_pos+Vector3(0,0,-0.012),"rubber")
	var labels := ["X","Y"] if _side=="left_hand" else ["A","B"]
	for index in range(2):
		var pos := Vector3(mirror*(0.013+index*0.008),-0.030+index*0.024,-0.073)
		_disc(model_root,"FaceButton"+str(index),0.0087,0.006,pos,"rubber")
		var label=_label(labels[index],pos+Vector3(0,0,-0.0045),0.00025)
		button_labels.append(label)
	_disc(model_root,"SystemButton",0.006,0.004,Vector3(-mirror*0.020,0.006,-0.071),"rubber")
	_label("≡",Vector3(-mirror*0.020,0.006,-0.074),0.00022)
	_label("L" if _side=="left_hand" else "R",Vector3(0,0.021,-0.069),0.00027)
	var led_shape := BoxMesh.new();led_shape.size=Vector3(0.012,0.0025,0.002)
	var led=_mesh(model_root,led_shape,"accent","ControllerStatusLED")
	led.position=Vector3(0,0.012,-0.071)
	_built=true
	set_pose(_trigger_value,_grip_value)


func set_pose(trigger: float, grip: float, _thumb_touch: bool=false, _holding: bool=false) -> void:
	_trigger_value=clampf(trigger,0,1) if is_finite(trigger) else 0.0
	_grip_value=clampf(grip,0,1) if is_finite(grip) else 0.0
	if not _built:return
	_trigger.position.y=-0.044+_trigger_value*0.007
	_trigger.rotation.x=-_trigger_value*0.20
	_grip.position.x=(-1.0 if _side=="left_hand" else 1.0)*(0.022-_grip_value*0.003)


func _material(key: String, color: Color, roughness: float, unshaded: bool=false) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color=color;material.roughness=roughness
	if unshaded:material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	_materials[key]=material


func _mesh(parent: Node3D, mesh: Mesh, key: String, node_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name=node_name;instance.mesh=mesh;instance.material_override=_materials[key]
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _sphere() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius=1.0;mesh.height=2.0;mesh.radial_segments=16;mesh.rings=8
	return mesh


func _disc(parent: Node3D, node_name: String, radius: float, height: float, pos: Vector3, material: String) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=height;mesh.radial_segments=20
	var instance=_mesh(parent,mesh,material,node_name)
	instance.position=pos;instance.rotation.x=PI/2
	return instance


func _label(text: String, pos: Vector3, pixel_size: float) -> Label3D:
	var label := Label3D.new()
	label.text=text;label.position=pos;label.rotation.y=PI
	label.font_size=28;label.pixel_size=pixel_size;label.modulate=Color("e6f6f5")
	label.outline_size=0;label.shaded=false
	model_root.add_child(label)
	return label
