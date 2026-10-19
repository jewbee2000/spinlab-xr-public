class_name LabButton
extends StaticBody3D

var action := ""
var text_label: Label3D
var face: MeshInstance3D
var normal_color := Color("244353")
var hover_color := Color("397262")
var width_m := 0.66
var height_m := 0.062
var front_z_m := 0.008
var stroke_m := 0.008
var depression_m := 0.0
var _hovered := false
var _bezel: MeshInstance3D
var enabled := true:
	set(value):
		enabled=value
		collision_layer=1 if enabled else 0
		if not enabled:
			_hovered=false
			depression_m=0.0
			if face:face.position.z=0.0
			if text_label:text_label.position.z=0.014
		_update_face_color()

func configure(caption: String, command: String, width: float = 0.66, height: float = 0.062, color: Color = Color("244353")) -> void:
	action=command
	set_meta("action",command)
	width_m=width
	height_m=height
	normal_color=color
	_bezel=MeshInstance3D.new()
	var bezel_box=BoxMesh.new()
	bezel_box.size=Vector3(width+0.008,height+0.008,0.012)
	_bezel.mesh=bezel_box
	_bezel.position.z=-0.011
	var bezel_material=StandardMaterial3D.new()
	bezel_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	bezel_material.albedo_color=Color("091b25")
	_bezel.material_override=bezel_material
	add_child(_bezel)
	face=MeshInstance3D.new()
	var box=BoxMesh.new()
	box.size=Vector3(width,height,0.016)
	face.mesh=box
	var material=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=color
	face.material_override=material
	add_child(face)
	var collision=CollisionShape3D.new()
	var shape=BoxShape3D.new()
	shape.size=Vector3(width,height,0.022)
	collision.shape=shape
	add_child(collision)
	text_label=Label3D.new()
	text_label.text=caption
	text_label.font_size=32
	text_label.pixel_size=minf(0.00094,height/42.0)
	text_label.position.z=0.014
	text_label.modulate=Color("e8f3f6")
	text_label.outline_size=0
	add_child(text_label)
	collision_layer=1 if enabled else 0
	collision_mask=0
	_update_face_color()

func set_enabled(value: bool) -> void:
	enabled=value

func set_caption(caption: String) -> void:
	if text_label: text_label.text=caption

func hover(value: bool) -> void:
	_hovered=value and enabled
	_update_face_color()

## Local +Z is the approach direction. Negative means outside the touch region;
## zero means the finger is in the 12 mm approach zone in front of the cap.
## Otherwise the value is penetration measured from the cap's REST surface.
func contact_depth(world_point: Vector3) -> float:
	if not enabled:return -1.0
	var point=to_local(world_point)
	if absf(point.x)>width_m*0.5 or absf(point.y)>height_m*0.5:
		return -1.0
	var depth=front_z_m-point.z
	if depth < -0.012 or depth > stroke_m+0.016:
		return -1.0
	return clampf(depth,0.0,stroke_m)

## The interaction controller supplies the maximum contact depth of both hands
## and owns debounce/hysteresis. Mesh and caption share the full physical stroke.
func set_depression(depth: float) -> void:
	depression_m=clampf(depth,0.0,stroke_m) if enabled else 0.0
	if face:face.position.z=-depression_m
	if text_label:text_label.position.z=0.014-depression_m
	_update_face_color()

func _update_face_color() -> void:
	if not face:return
	if not enabled:
		face.material_override.albedo_color=normal_color.lerp(Color("10222d"),0.72)
		if text_label:text_label.modulate=Color("647d89")
		return
	if text_label:text_label.modulate=Color("e8f3f6")
	var color=hover_color if _hovered else normal_color
	face.material_override.albedo_color=color.lerp(Color("6ce5c9"),0.28*depression_m/stroke_m)
