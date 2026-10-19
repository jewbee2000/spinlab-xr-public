class_name PanelChart
extends Node3D

var line_mesh: MeshInstance3D
var grid_mesh: MeshInstance3D
var width_m := 0.70
var height_m := 0.26
var line_color := Color("6ce5c9")

func _ready() -> void:
	line_mesh = MeshInstance3D.new()
	add_child(line_mesh)
	grid_mesh = MeshInstance3D.new()
	grid_mesh.position.z = -0.001
	add_child(grid_mesh)
	var mesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material(Color("254557")))
	for k in range(5):
		var y = height_m * float(k) / 4.0
		mesh.surface_add_vertex(Vector3(0,y,0))
		mesh.surface_add_vertex(Vector3(width_m,y,0))
	for k in range(7):
		var x = width_m * float(k) / 6.0
		mesh.surface_add_vertex(Vector3(x,0,0))
		mesh.surface_add_vertex(Vector3(x,height_m,0))
	mesh.surface_end()
	grid_mesh.mesh = mesh

func _material(color: Color) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat

func set_points(points: Array, x_min: float, x_max: float, y_min: float, y_max: float, second: Array = []) -> void:
	if not is_instance_valid(line_mesh): return
	var mesh = ImmediateMesh.new()
	_add_trace(mesh, points, x_min, x_max, y_min, y_max, line_color)
	_add_trace(mesh, second, x_min, x_max, y_min, y_max, Color("ffb675"))
	line_mesh.mesh = mesh

func _add_trace(mesh: ImmediateMesh, points: Array, x_min: float, x_max: float, y_min: float, y_max: float, color: Color) -> void:
	if points.size() < 2: return
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _material(color))
	for point in points:
		var x = clampf((float(point.x)-x_min)/maxf(x_max-x_min,0.000001),0,1)*width_m
		var y = clampf((float(point.y)-y_min)/maxf(y_max-y_min,0.000001),0,1)*height_m
		mesh.surface_add_vertex(Vector3(x,y,0))
	mesh.surface_end()
