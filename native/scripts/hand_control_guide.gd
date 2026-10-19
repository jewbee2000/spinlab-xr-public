class_name HandControlGuide
extends Node3D
## Two letter markers at the real Quest 2 controller buttons under each glove.
## The root supplies the complete tracked grip frame. Only each marker's facing
## follows the viewer; its center stays at the authored cap + normal offset.
## No instruction card, input target, ray, or depth override is created.

const ButtonAnchors = preload("res://scripts/controller_button_anchors.gd")
const DIAMETER_M := 0.020
# The procedural glove's thenar pad covers the real cap. This fixed clearance
# moves only along the authored cap normal, never sideways or with the viewer.
const CAP_NORMAL_OFFSET_M := 0.046
var anchors: Dictionary = {}
var markers: Dictionary = {}
var labels: Dictionary = {}
var _side := "right_hand"
var _content: Node3D


func configure(side: String) -> void:
	var chosen := "left_hand" if side in ["left_hand","left"] else "right_hand"
	if is_instance_valid(_content) and chosen==_side:return
	_side=chosen
	if is_instance_valid(_content):
		remove_child(_content);_content.queue_free()
	_content=Node3D.new();_content.name="PhysicalButtonLetters";add_child(_content)
	anchors=ButtonAnchors.for_hand(_side)
	markers.clear();labels.clear()
	for key in anchors:
		var marker:=Node3D.new();marker.name=str(anchors[key].letter)+"ButtonMarker";_content.add_child(marker)
		markers[key]=marker
		var face:=MeshInstance3D.new();face.name="CircularLetterFace"
		var circle:=CylinderMesh.new()
		circle.top_radius=DIAMETER_M/2;circle.bottom_radius=DIAMETER_M/2
		circle.height=0.0015;circle.radial_segments=24
		face.mesh=circle;face.rotation.x=PI/2
		face.material_override=_material(Color("173b48"));face.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.add_child(face)
		var rim:=MeshInstance3D.new();rim.name="CircularRim"
		var ring:=TorusMesh.new();ring.inner_radius=DIAMETER_M/2-0.0006;ring.outer_radius=DIAMETER_M/2
		ring.rings=24;ring.ring_segments=4
		rim.mesh=ring;rim.rotation.x=PI/2;rim.position.z=0.0008
		rim.material_override=_material(Color("7fe6d1"));rim.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.add_child(rim)
		var label:=Label3D.new();label.name="ButtonLetter"
		label.text=str(anchors[key].letter);label.font_size=30;label.pixel_size=0.00038
		label.position.z=0.0016;label.outline_size=0;label.modulate=Color("f1fcfa")
		label.shaded=false;label.no_depth_test=false;label.double_sided=false
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		marker.add_child(label);labels[key]=label
	visible=false


## Kept for root compatibility. These are hardware letters regardless of the
## current lesson, walking state, or held object; no extra functions are shown.
func set_context(_guide_active: bool, _next_ready: bool=true, _at_first: bool=false, _walking_enabled: bool=true, _holding: bool=false, _navigation_blocked: bool=false) -> void:
	pass


func update_placement(grip: Transform3D, viewer: Transform3D, active: bool) -> void:
	visible=false
	if not active or not is_instance_valid(_content) or not grip.is_finite() or not viewer.is_finite():return
	if absf(grip.basis.determinant())<0.001 or absf(viewer.basis.determinant())<0.001:return
	global_transform=grip
	for key in markers:
		var marker: Node3D=markers[key]
		var anchor: Dictionary=anchors[key]
		var position_m: Vector3=grip*(anchor.center+anchor.normal*CAP_NORMAL_OFFSET_M)
		var towards_viewer: Vector3=viewer.origin-position_m
		if towards_viewer.length_squared()<0.000001:return
		var normal:=towards_viewer.normalized()
		var up:=viewer.basis.y-normal*viewer.basis.y.dot(normal)
		if up.length_squared()<0.000001:up=viewer.basis.x-normal*viewer.basis.x.dot(normal)
		if up.length_squared()<0.000001:return
		up=up.normalized()
		var right:=up.cross(normal).normalized()
		marker.global_transform=Transform3D(Basis(right,normal.cross(right).normalized(),normal),position_m)
	visible=markers.size()==2


func _material(color: Color) -> StandardMaterial3D:
	var material:=StandardMaterial3D.new()
	material.albedo_color=color;material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test=false
	return material
