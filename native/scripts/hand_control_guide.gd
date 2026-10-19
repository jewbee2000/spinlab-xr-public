class_name HandControlGuide
extends Node3D
## Read-only controller legend beside a tracked glove. Owns no input, colliders,
## rays, or depth override. The root owns lifetime, tracking and mode visibility.
## A viewer-facing frame keeps text upright independently of wrist rotation.

const WIDTH_M := 0.36
const HEIGHT_M := 0.34
const OUTSIDE_OFFSET_M := 0.26
const MIN_READING_DISTANCE_M := 0.50
const TEXT := Color("e6f1f5")
const DIM := Color("9cb4c3")
const ACCENT := Color("6ce5c9")
const WAIT := Color("ffd085")

var labels: Dictionary = {}
var button_positions: Dictionary = {}
var _side := "right_hand"
var _content: Node3D
var _guide_active := true
var _next_ready := true
var _at_first := false
var _walking_enabled := true
var _holding := false
var _navigation_blocked := false


func configure(side: String) -> void:
	var chosen := "left_hand" if side in ["left_hand","left"] else "right_hand"
	if is_instance_valid(_content) and chosen==_side:return
	_side=chosen
	if is_instance_valid(_content):
		remove_child(_content);_content.queue_free()
	_content=Node3D.new();_content.name="ControllerButtonLegend";add_child(_content)
	labels.clear();button_positions.clear()
	_box("Backplate",Vector3(WIDTH_M,HEIGHT_M,0.008),Vector3(0,0,-0.006),Color("102936"))
	_box("Accent",Vector3(WIDTH_M,0.003,0.002),Vector3(0,HEIGHT_M/2-0.002,0),ACCENT)
	_box("Divider",Vector3(0.314,0.0015,0.002),Vector3(0,-0.004,0),Color("3b5968"))
	# A tiny deck diagram preserves the physical order: secondary upper/outside,
	# primary lower/inside. Only lateral positions mirror; glyph frames do not.
	_box("ThumbDeckDiagram",Vector3(0.067,0.112,0.004),Vector3(-0.132,0.064,0),Color("203f4e"))
	var handed := -1.0 if _side=="left_hand" else 1.0
	var upper := Vector3(-0.132+handed*0.006,0.091,0.005)
	var lower := Vector3(-0.132-handed*0.004,0.036,0.005)
	_disc("UpperButton",upper,0.018,Color("32665f"))
	_disc("LowerButton",lower,0.018,Color("344d60"))
	button_positions.upper=upper;button_positions.lower=lower
	labels.header=_label("LEFT HAND" if _side=="left_hand" else "RIGHT HAND",Vector3(-0.157,0.151,0.005),23,0.00062,ACCENT)
	labels.upper_button=_label("Y" if _side=="left_hand" else "B",upper+Vector3(0,0,0.003),30,0.00062,TEXT,true)
	labels.lower_button=_label("X" if _side=="left_hand" else "A",lower+Vector3(0,0,0.003),30,0.00062,TEXT,true)
	labels.upper_function=_label("Menu",Vector3(-0.093,0.103,0.005),27,0.00062,TEXT)
	labels.lower_function=_label("",Vector3(-0.093,0.048,0.005),26,0.00062,TEXT)
	labels.stick=_label("",Vector3(-0.157,-0.024,0.005),24,0.00058,TEXT)
	labels.grip=_label("",Vector3(-0.157,-0.060,0.005),24,0.00058,TEXT)
	labels.trigger=_label("Trigger  Curl index",Vector3(-0.157,-0.096,0.005),24,0.00058,TEXT)
	labels.point=_label("Release trigger to point",Vector3(-0.157,-0.125,0.005),23,0.00058,ACCENT)
	_refresh_context()
	visible=false


func set_context(guide_active: bool, next_ready: bool=true, at_first: bool=false, walking_enabled: bool=true, holding: bool=false, navigation_blocked: bool=false) -> void:
	_guide_active=guide_active;_next_ready=next_ready;_at_first=at_first
	_walking_enabled=walking_enabled;_holding=holding
	_navigation_blocked=navigation_blocked
	_refresh_context()


func _refresh_context() -> void:
	if labels.is_empty():return
	var guide_function := "Guide back" if _side=="left_hand" else "Guide next"
	var guide_color := TEXT
	if not _guide_active:guide_function+=" · off";guide_color=DIM
	elif _side=="left_hand" and _at_first:guide_function+=" · first";guide_color=DIM
	elif _side=="right_hand" and not _next_ready:guide_function+=" · wait";guide_color=WAIT
	labels.lower_function.text=guide_function
	labels.lower_function.modulate=guide_color;labels.lower_button.modulate=guide_color
	var stick_function := "Stick  Bench height" if _side=="left_hand" else "Stick  Walk"
	if _side=="right_hand" and not _walking_enabled:stick_function+=" · off"
	elif _holding or _navigation_blocked:stick_function+=" · held"
	labels.stick.text=stick_function
	labels.stick.modulate=DIM if _holding or _navigation_blocked or (_side=="right_hand" and not _walking_enabled) else TEXT
	labels.grip.text="Grip  Release to let go" if _holding else "Grip  Hold rotor / handle / dial"


func update_placement(hand_position: Vector3, viewer: Transform3D, active: bool) -> void:
	visible=false
	if not active or not is_instance_valid(_content) or not hand_position.is_finite() or not viewer.is_finite():return
	if absf(viewer.basis.determinant())<0.001:return
	var view_right := viewer.basis.x
	view_right.y=0
	if view_right.length_squared()<0.001:
		view_right=(-viewer.basis.z).cross(Vector3.UP)
	if view_right.length_squared()<0.001:view_right=Vector3.RIGHT
	view_right=view_right.normalized()
	var view_up := viewer.basis.y.normalized()
	var position_m := hand_position+view_right*(-OUTSIDE_OFFSET_M if _side=="left_hand" else OUTSIDE_OFFSET_M)+view_up*0.10
	var offset := position_m-viewer.origin
	if offset.length()<MIN_READING_DISTANCE_M:
		var direction := offset.normalized() if offset.length_squared()>0.000001 else -viewer.basis.z.normalized()
		position_m=viewer.origin+direction*MIN_READING_DISTANCE_M
	var normal := (viewer.origin-position_m).normalized()
	var up := view_up-normal*view_up.dot(normal)
	if up.length_squared()<0.000001:up=viewer.basis.z-normal*viewer.basis.z.dot(normal)
	if up.length_squared()<0.000001:return
	up=up.normalized()
	var right := up.cross(normal).normalized()
	up=normal.cross(right).normalized()
	global_transform=Transform3D(Basis(right,up,normal),position_m)
	visible=true


func _label(value: String, position_m: Vector3, font_size: int, pixel_size: float, color: Color, centered: bool=false) -> Label3D:
	var label:=Label3D.new()
	label.text=value;label.position=position_m;label.font_size=font_size;label.pixel_size=pixel_size
	label.modulate=color;label.outline_size=0;label.shaded=false
	label.no_depth_test=false;label.double_sided=false
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER if centered else VERTICAL_ALIGNMENT_TOP
	_content.add_child(label)
	return label


func _box(node_name: String, size_m: Vector3, position_m: Vector3, color: Color) -> void:
	var mesh:=BoxMesh.new();mesh.size=size_m
	_mesh(node_name,mesh,position_m,color)


func _disc(node_name: String, position_m: Vector3, radius_m: float, color: Color) -> void:
	var mesh:=CylinderMesh.new()
	mesh.top_radius=radius_m;mesh.bottom_radius=radius_m;mesh.height=0.003;mesh.radial_segments=20
	var instance:=_mesh(node_name,mesh,position_m,color)
	instance.rotation.x=PI/2


func _mesh(node_name: String, mesh: Mesh, position_m: Vector3, color: Color) -> MeshInstance3D:
	var instance:=MeshInstance3D.new();instance.name=node_name;instance.mesh=mesh;instance.position=position_m
	var material:=StandardMaterial3D.new()
	material.albedo_color=color;material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test=false
	instance.material_override=material;instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_content.add_child(instance)
	return instance
