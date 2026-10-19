class_name TutorialPanel
extends Node3D
## Read-only floating guide. The root positions it independently from the
## four-tab menu and dispatches A/X/B/Y. This panel has no interaction targets.

signal command_requested(command: String)

const WIDTH_M: float = 0.72
const HEIGHT_M: float = 0.48
const TEXT_WIDTH_M: float = 0.66
const BODY_FONT_SIZE: int = 25
const BODY_PIXEL_SIZE: float = 0.00058
const TEXT: Color = Color("e6f1f5")
const DIM: Color = Color("a5bdc9")
const ACCENT: Color = Color("6ce5c9")

var interactive_buttons: Array = []
var navigation_buttons: Array = []
var labels: Dictionary = {}
var overflowed: bool = false
var _built: bool = false
var _active: bool = true
var _view: Dictionary = {}
var _progress_fill: MeshInstance3D
var _font: Font

func configure() -> void:
	if _built:
		return
	_font = ThemeDB.fallback_font
	_box(Vector3(WIDTH_M, HEIGHT_M, 0.016), Vector3(0, 0, -0.010), Color("102532")).name = "GuideBackplate"
	_box(Vector3(WIDTH_M, 0.003, 0.003), Vector3(0, HEIGHT_M / 2.0 - 0.002, 0.001), ACCENT).name = "GuideAccent"
	labels.chapter = _label("ORIENT", Vector3(-0.33, 0.215, 0.008), 18, 0.00055, ACCENT)
	labels.progress = _label("Step 1 / 23", Vector3(0.33, 0.215, 0.008), 18, 0.00055, DIM)
	labels.progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	labels.title = _label("Welcome to SpinLab", Vector3(-0.33, 0.185, 0.008), 28, 0.00062, TEXT)
	_box(Vector3(TEXT_WIDTH_M, 0.003, 0.002), Vector3(0, 0.148, 0.007), Color("2b4655")).name = "ProgressTrack"
	_progress_fill = _box(Vector3(1, 0.003, 0.002), Vector3(-TEXT_WIDTH_M / 2.0, 0.148, 0.009), ACCENT)
	_progress_fill.name = "ProgressFill"
	labels.task_heading = _label("DO THIS", Vector3(-0.33, 0.131, 0.008), 18, 0.00052, ACCENT)
	labels.task = _label("", Vector3(-0.33, 0.110, 0.008), BODY_FONT_SIZE, BODY_PIXEL_SIZE, TEXT)
	labels.theory_heading = _label("WHY", Vector3(-0.33, 0.040, 0.008), 18, 0.00052, ACCENT)
	labels.theory = _label("", Vector3(-0.33, 0.019, 0.008), 24, 0.00056, DIM)
	labels.hint = _label("", Vector3(-0.33, -0.056, 0.008), 22, 0.00056, ACCENT)
	labels.legend = _label("A Continue  ·  X Back  ·  B/Y Menu", Vector3(-0.33, -0.121, 0.008), 23, 0.00056, TEXT)
	labels.movement = _label("Right stick: walk  ·  Left stick: height", Vector3(-0.33, -0.151, 0.008), 20, 0.00054, DIM)
	labels.footer = _label("Read-only guide  /  Pause or restart from Session", Vector3(-0.33, -0.192, 0.008), 18, 0.00052, DIM)
	labels.body = labels.task
	labels.what = labels.task
	labels.why = labels.theory
	labels.what_heading = labels.task_heading
	labels.why_heading = labels.theory_heading
	labels.action_hint = labels.hint
	labels.controller_legend = labels.legend
	_built = true
	visible = _active
	update_view(_view)

func update_view(view: Dictionary) -> void:
	_view = view.duplicate(true)
	if not _built:
		return
	overflowed = false
	labels.chapter.text = _wrap(str(view.get("chapter", "ORIENT")), 18, 0.00055, 1)
	labels.title.text = _wrap(str(view.get("title", "Welcome to SpinLab")), 28, 0.00062, 1)
	var step_index: int = maxi(0, int(view.get("index", int(view.get("step_index", 1)) - 1)))
	var total: int = maxi(1, int(view.get("total", view.get("step_count", 23))))
	labels.progress.text = str(view.get("progress", "Step %d / %d" % [step_index + 1, total]))
	var fraction: float = clampf(float(step_index + 1) / float(total), 0, 1)
	_progress_fill.scale.x = maxf(0.001, TEXT_WIDTH_M * fraction)
	_progress_fill.position.x = -TEXT_WIDTH_M / 2.0 + TEXT_WIDTH_M * fraction / 2.0
	labels.task.text = _wrap(str(view.get("body", view.get("what", ""))), BODY_FONT_SIZE, BODY_PIXEL_SIZE, 3)
	labels.theory.text = _wrap(str(view.get("theory", view.get("why", ""))), 24, 0.00056, 3)
	var ready: bool = bool(view.get("ready", false))
	var hint: String = str(view.get("hint", view.get("gatehint", "")))
	labels.hint.text = _wrap(("READY / " if ready else "NEXT / ") + hint, 22, 0.00056, 2) if not hint.is_empty() else ""
	labels.legend.text = "A Finish  ·  X Back  ·  B/Y Menu" if bool(view.get("is_last", false)) else "A Continue  ·  X Back  ·  B/Y Menu"

func set_panel_active(active: bool) -> void:
	_active = active
	visible = active

func request_command(_command: String) -> void:
	# Compatibility only: input and operations belong to the root application.
	pass

func _wrap(value: String, font_size: int, pixel_size: float, max_lines: int) -> String:
	var lines := PackedStringArray()
	var max_pixels: float = TEXT_WIDTH_M / pixel_size
	for paragraph in value.replace("\r", "").split("\n"):
		var line: String = ""
		for word in paragraph.split(" ", false):
			var candidate: String = word if line.is_empty() else line + " " + word
			if _font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_pixels and not line.is_empty():
				lines.append(line)
				line = word
			else:
				line = candidate
		lines.append(line)
	if lines.size() > max_lines:
		overflowed = true
		lines.resize(max_lines)
		var final_line: String = lines[max_lines - 1]
		while not final_line.is_empty() and _font.get_string_size(final_line + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_pixels:
			final_line = final_line.left(final_line.length() - 1)
		lines[max_lines - 1] = final_line + "…"
	return "\n".join(lines)

func _label(value: String, pos: Vector3, font_size: int, pixel_size: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.position = pos
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(label)
	return label

func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance
