class_name TutorialPanel
extends Node3D
## Read-only floating guide. The root positions it independently from the
## four-tab menu and dispatches A/X/B/Y. This panel has no interaction targets.

signal command_requested(command: String)

const WIDTH_M: float = 0.94
const HEIGHT_M: float = 0.66
const TEXT_WIDTH_M: float = 0.86
const BODY_FONT_SIZE: int = 30
const BODY_PIXEL_SIZE: float = 0.00076
const SECONDARY_FONT_SIZE: int = 22
const SECONDARY_PIXEL_SIZE: float = 0.00078
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
	labels.chapter = _label("ORIENT", Vector3(-0.43, 0.302, 0.008), SECONDARY_FONT_SIZE, SECONDARY_PIXEL_SIZE, ACCENT)
	labels.progress = _label("Step 1 / 23", Vector3(0.43, 0.302, 0.008), SECONDARY_FONT_SIZE, SECONDARY_PIXEL_SIZE, TEXT)
	labels.progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	labels.title = _label("Welcome to SpinLab", Vector3(-0.43, 0.259, 0.008), 34, 0.0008, TEXT)
	_box(Vector3(TEXT_WIDTH_M, 0.004, 0.002), Vector3(0, 0.216, 0.007), Color("2b4655")).name = "ProgressTrack"
	_progress_fill = _box(Vector3(1, 0.004, 0.002), Vector3(-TEXT_WIDTH_M / 2.0, 0.216, 0.009), ACCENT)
	_progress_fill.name = "ProgressFill"
	labels.task_heading = _label("DO THIS", Vector3(-0.43, 0.199, 0.008), SECONDARY_FONT_SIZE, SECONDARY_PIXEL_SIZE, ACCENT)
	labels.task = _label("", Vector3(-0.43, 0.166, 0.008), BODY_FONT_SIZE, BODY_PIXEL_SIZE, TEXT)
	labels.theory_heading = _label("WHY", Vector3(-0.43, 0.027, 0.008), SECONDARY_FONT_SIZE, SECONDARY_PIXEL_SIZE, ACCENT)
	labels.theory = _label("", Vector3(-0.43, -0.006, 0.008), BODY_FONT_SIZE, BODY_PIXEL_SIZE, TEXT)
	labels.hint = _label("", Vector3(-0.43, -0.146, 0.008), 25, 0.00076, ACCENT)
	labels.legend = _label("A Continue  ·  X Back  ·  B/Y Menu", Vector3(-0.43, -0.216, 0.008), 27, 0.00078, TEXT)
	labels.movement = _label("Right stick: walk  ·  Left stick: height", Vector3(-0.43, -0.263, 0.008), 24, 0.00076, TEXT)
	# The old decorative footer is omitted to reserve real four-line blocks at
	# the larger reading size. Keep the label key for presentation compatibility.
	labels.footer = _label("", Vector3(-0.43, -0.310, 0.008), 22, 0.00074, TEXT)
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
	labels.chapter.text = _wrap(str(view.get("chapter", "ORIENT")), SECONDARY_FONT_SIZE, SECONDARY_PIXEL_SIZE, 1)
	labels.title.text = _wrap(str(view.get("title", "Welcome to SpinLab")), 34, 0.0008, 1)
	var step_index: int = maxi(0, int(view.get("index", int(view.get("step_index", 1)) - 1)))
	var total: int = maxi(1, int(view.get("total", view.get("step_count", 23))))
	labels.progress.text = str(view.get("progress", "Step %d / %d" % [step_index + 1, total]))
	var fraction: float = clampf(float(step_index + 1) / float(total), 0, 1)
	_progress_fill.scale.x = maxf(0.001, TEXT_WIDTH_M * fraction)
	_progress_fill.position.x = -TEXT_WIDTH_M / 2.0 + TEXT_WIDTH_M * fraction / 2.0
	labels.task.text = _wrap(str(view.get("body", view.get("what", ""))), BODY_FONT_SIZE, BODY_PIXEL_SIZE, 4)
	labels.theory.text = _wrap(str(view.get("theory", view.get("why", ""))), BODY_FONT_SIZE, BODY_PIXEL_SIZE, 4)
	var ready: bool = bool(view.get("ready", false))
	var hint: String = str(view.get("hint", view.get("gatehint", "")))
	labels.hint.text = _wrap(("READY / " if ready else "NEXT / ") + hint, 25, 0.00076, 2) if not hint.is_empty() else ""
	labels.legend.text = "A Finish  ·  X Back  ·  B/Y Menu" if bool(view.get("is_last", false)) else "A Continue  ·  X Back  ·  B/Y Menu"

func set_panel_active(active: bool) -> void:
	_active = active
	visible = active

func request_command(_command: String) -> void:
	# Compatibility only: input and operations belong to the root application.
	pass

func readability_metrics(distance_m: float = 1.47) -> Dictionary:
	# Nominal em is font_size * pixel_size, not measured glyph ink. Line height
	# includes the font's ascent/descent. Angular sizes use exact pinhole geometry.
	var em_m: float = BODY_FONT_SIZE * BODY_PIXEL_SIZE
	return {"distance_m": distance_m, "task_em_m": em_m, "theory_em_m": em_m,
		"task_line_height_m": ThemeDB.fallback_font.get_height(BODY_FONT_SIZE) * BODY_PIXEL_SIZE,
		"task_em_deg": angular_extent(em_m, distance_m), "theory_em_deg": angular_extent(em_m, distance_m),
		"previous_task_em_m": 25.0 * 0.00058, "previous_theory_em_m": 24.0 * 0.00056,
		"previous_task_em_deg": angular_extent(25.0 * 0.00058, distance_m),
		"previous_theory_em_deg": angular_extent(24.0 * 0.00056, distance_m),
		"card_horizontal_deg": angular_extent(WIDTH_M, distance_m), "card_vertical_deg": angular_extent(HEIGHT_M, distance_m)}

static func angular_extent(span_m: float, distance_m: float) -> float:
	return rad_to_deg(2.0 * atan2(span_m * 0.5, distance_m)) if distance_m > 0.0 else 0.0

func view_bounds(distance_m: float, azimuth_deg: float, elevation_deg: float) -> Dictionary:
	# Geometric corner bounds for a viewer-facing card, independent of any
	# particular headset FOV or optical visibility/comfort guarantee.
	var azimuth: float = deg_to_rad(azimuth_deg)
	var elevation: float = deg_to_rad(elevation_deg)
	var direction := Vector3(sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation))
	var card_right := Vector3(cos(azimuth), 0.0, sin(azimuth))
	var card_up: Vector3 = card_right.cross(direction).normalized()
	var left_deg: float = INF
	var right_deg: float = -INF
	var bottom_deg: float = INF
	var top_deg: float = -INF
	for x in [-WIDTH_M / 2.0, WIDTH_M / 2.0]:
		for y in [-HEIGHT_M / 2.0, HEIGHT_M / 2.0]:
			var corner: Vector3 = direction * distance_m + card_right * x + card_up * y
			var horizontal: float = rad_to_deg(atan2(corner.x, -corner.z))
			var vertical: float = rad_to_deg(atan2(corner.y, Vector2(corner.x, corner.z).length()))
			left_deg = minf(left_deg, horizontal)
			right_deg = maxf(right_deg, horizontal)
			bottom_deg = minf(bottom_deg, vertical)
			top_deg = maxf(top_deg, vertical)
	return {"left_deg": left_deg, "right_deg": right_deg, "bottom_deg": bottom_deg, "top_deg": top_deg}

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
