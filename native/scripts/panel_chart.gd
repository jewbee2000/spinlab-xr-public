class_name PanelChart
extends Node3D
## Millimetre-wide triangle ribbons survive stereo/mobile rendering; GLES line
## primitives have implementation-dependent one-pixel width on Quest.

var line_mesh: MeshInstance3D
var grid_mesh: MeshInstance3D
var width_m := 0.70
var height_m := 0.36
var trace_width_m := 0.0028
var line_color := Color("6ce5c9")
## CPU geometry retained for deterministic checks with headless dummy GPU.
var trace_vertices := PackedVector3Array()
var grid_vertices := PackedVector3Array()
var view: Dictionary = {}
var _tick_labels: Array[Label3D] = []
var _empty_label: Label3D
var _legend_a: Label3D
var _legend_b: Label3D
var _signature: int = -1
var _axes_signature: int = -1

func _ready() -> void:
	line_mesh = MeshInstance3D.new();line_mesh.name = "AcquiredTraces";line_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(line_mesh)
	grid_mesh = MeshInstance3D.new();grid_mesh.name = "PlotGrid";grid_mesh.position.z = -0.002;grid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(grid_mesh)
	_empty_label = _label("",Vector3(width_m/2.0,height_m/2.0,0.003),Color("bdd3df"))
	_empty_label.font_size = 23;_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_legend_a = _label("A",Vector3(width_m-0.052,height_m+0.026,0.002),line_color)
	_legend_b = _label("B",Vector3(width_m-0.012,height_m+0.026,0.002),Color("ffb675"))
	_legend_a.visible=false;_legend_b.visible=false
	_rebuild_grid()

func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color;mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func _label(caption: String, at: Vector3, color: Color) -> Label3D:
	var label := Label3D.new();label.text = caption;label.position = at
	label.font_size = 20;label.pixel_size = 0.00072;label.modulate = color;label.outline_size = 0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label);return label

func set_view(next_view: Dictionary) -> void:
	view = next_view
	set_points(view.points,view.x_min,view.x_max,view.y_min,view.y_max,view.get("second",[]))
	_empty_label.text = str(view.get("empty_text",""));_empty_label.visible = not _empty_label.text.is_empty()
	_legend_a.visible = not view.get("second",[]).is_empty();_legend_b.visible = _legend_a.visible
	var ticks: Array = view.get("x_ticks",[]).duplicate(true)
	for tick in ticks:
		tick.position = Vector3(width_m*(float(tick.value)-view.x_min)/maxf(view.x_max-view.x_min,0.000001),-0.022,0.002)
		tick.axis = "x"
	for tick in view.get("y_ticks",[]):
		var copy: Dictionary = tick.duplicate()
		copy.position = Vector3(-0.016,height_m*(float(tick.value)-view.y_min)/maxf(view.y_max-view.y_min,0.000001),0.002)
		copy.axis = "y";ticks.append(copy)
	var axes_signature: int = hash([view.get("x_ticks",[]),view.get("y_ticks",[]),width_m,height_m])
	if axes_signature != _axes_signature:
		_axes_signature = axes_signature;_rebuild_grid()
	while _tick_labels.size() < ticks.size():_tick_labels.append(_label("",Vector3.ZERO,Color("a8c4d4")))
	for index in _tick_labels.size():
		var label := _tick_labels[index]
		label.visible = index < ticks.size()
		if label.visible:
			label.text = ticks[index].label;label.position = ticks[index].position
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if ticks[index].axis == "y" else HORIZONTAL_ALIGNMENT_CENTER

func set_points(points: Array, x_min: float, x_max: float, y_min: float, y_max: float, second: Array = []) -> void:
	if not is_instance_valid(line_mesh):return
	var next_signature: int = hash([points,second,x_min,x_max,y_min,y_max,width_m,height_m,trace_width_m])
	if next_signature == _signature:return
	_signature = next_signature;trace_vertices.clear()
	var mesh := ArrayMesh.new()
	_add_trace(mesh,points,x_min,x_max,y_min,y_max,line_color)
	_add_trace(mesh,second,x_min,x_max,y_min,y_max,Color("ffb675"))
	line_mesh.mesh = mesh

func _rebuild_grid() -> void:
	grid_vertices.clear()
	var horizontal: Array = view.get("y_ticks",[])
	var vertical: Array = view.get("x_ticks",[])
	if horizontal.is_empty():
		for index in range(5):horizontal.append({"value":float(index)/4.0})
	if vertical.is_empty():
		for index in range(5):vertical.append({"value":float(index)/4.0})
	for tick in horizontal:
		var y: float = height_m*(float(tick.value)-float(view.get("y_min",0.0)))/maxf(float(view.get("y_max",1.0))-float(view.get("y_min",0.0)),0.000001)
		_ribbon(grid_vertices,Vector2(0,y),Vector2(width_m,y),0.00065)
	for tick in vertical:
		var x: float = width_m*(float(tick.value)-float(view.get("x_min",0.0)))/maxf(float(view.get("x_max",1.0))-float(view.get("x_min",0.0)),0.000001)
		_ribbon(grid_vertices,Vector2(x,0),Vector2(x,height_m),0.00065)
	grid_mesh.mesh = _mesh_surface(grid_vertices,Color("315366"))

func _mesh_surface(vertices: PackedVector3Array, color: Color) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if vertices.is_empty():return mesh
	var arrays: Array = [];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.surface_set_material(0,_material(color))
	return mesh

func _add_trace(mesh: ArrayMesh, points: Array, x_min: float, x_max: float, y_min: float, y_max: float, color: Color) -> void:
	var vertices := PackedVector3Array()
	for index in range(1,points.size()):
		var first: Vector2 = points[index-1];var last: Vector2 = points[index]
		if not first.is_finite() or not last.is_finite():continue
		var a := Vector2((first.x-x_min)/maxf(x_max-x_min,0.000001)*width_m,(first.y-y_min)/maxf(y_max-y_min,0.000001)*height_m)
		var b := Vector2((last.x-x_min)/maxf(x_max-x_min,0.000001)*width_m,(last.y-y_min)/maxf(y_max-y_min,0.000001)*height_m)
		var clipped: Array = _clip_segment(a,b)
		if clipped.size() == 2:_ribbon(vertices,clipped[0],clipped[1],trace_width_m)
	if vertices.is_empty():return
	var arrays: Array = [];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(mesh.get_surface_count()-1,_material(color))
	trace_vertices.append_array(vertices)

func _ribbon(vertices: PackedVector3Array, a: Vector2, b: Vector2, thickness: float) -> void:
	if a.distance_squared_to(b) < 0.0000000001:return
	var normal := (b-a).normalized().orthogonal()*thickness/2.0
	var corners := [a+normal,a-normal,b+normal,b-normal]
	for index in [0,1,2,2,1,3]:
		var corner: Vector2 = corners[index]
		# Width belongs inside the plotted viewport, including boundary samples.
		vertices.append(Vector3(clampf(corner.x,0,width_m),clampf(corner.y,0,height_m),0))

func _clip_segment(a: Vector2, b: Vector2) -> Array:
	# Clip segments, not individual values: outside values cannot become a
	# fictitious horizontal trace along the chart boundary.
	var direction := b-a;var low := 0.0;var high := 1.0
	var p := [-direction.x,direction.x,-direction.y,direction.y]
	var q := [a.x,width_m-a.x,a.y,height_m-a.y]
	for index in range(4):
		if absf(p[index]) < 0.00000001:
			if q[index] < 0:return []
			continue
		var ratio: float = q[index]/p[index]
		if p[index] < 0:low = maxf(low,ratio)
		else:high = minf(high,ratio)
		if low > high:return []
	return [a+direction*low,a+direction*high]
