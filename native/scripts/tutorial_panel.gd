class_name TutorialPanel
extends Node3D
## Minimal target-adjacent callout. Long-form lesson text belongs to narration,
## not this visual. Root owns safe world placement and lab action dispatch.

signal command_requested(command: String)

const WIDTH_M: float = 0.24
const HEIGHT_M: float = 0.10
const DEPTH_M: float = 0.016
const TEXT_WIDTH_M: float = 0.183
const TASK_FONT_SIZE: int = 24
const TASK_PIXEL_SIZE: float = 0.00055
const TEXT: Color = Color("eff9fc")
const ACCENT: Color = Color("6ce5c9")
const SHORT_ACTIONS: Dictionary = {
	"load": "Seat rotor upright", "home": "Press HOME", "probe_adjust": "Turn probe micrometer",
	"probe_restore": "Restore HOME reference", "open_setup": "Lift guard for setup", "mass_practice": "Try MASS dial", "angle_practice": "Try ANGLE dial",
	"clear_mass": "Return MASS to zero", "mode_two": "Choose TWO-PLANE mode", "plane_b": "Select plane B",
	"plane_a": "Select plane A", "speed_explore": "Try SPEED setting", "speed_restore": "Set 1200 RPM",
	"guard": "Lower and release", "preview_start": "Start practice SWEEP", "stop": "Press STOP",
	"estop": "Test E-STOP latch", "recover": "Release with RECOVER", "rehome": "Rehome after recovery",
	"baseline": "Measure starting vibration", "chart_order": "Show ORDER spectrum", "open_trial": "Lift guard",
	"trial_fit": "Fit known A trial", "close_trial": "Lower and release", "trial_measure": "Measure Trial A",
	"open_trial_b": "Lift guard", "plane_b_trial": "Select trial plane B", "trial_fit_b": "Fit known B trial",
	"close_trial_b": "Lower and release", "trial_measure_b": "Measure Trial B", "solve": "Solve both planes",
	"open_apply": "Lift guard", "apply": "Apply correction", "close_verify": "Lower and release",
	"verify": "Verify measured reduction", "repeat": "Measure repeatability", "sweep": "Explore resonance curve",
	"report": "Save report"
}

var interactive_buttons: Array = []
var navigation_buttons: Array = []
var labels: Dictionary = {}
var overflowed: bool = false
var _built: bool = false
var _active: bool = true
var _view: Dictionary = {}
var _arrow: Node3D

func configure() -> void:
	if _built: return
	_box(Vector3(WIDTH_M, HEIGHT_M, 0.008), Vector3(0, 0, -0.004), Color("102532")).name = "CalloutBackplate"
	_box(Vector3(WIDTH_M, 0.002, 0.002), Vector3(0, 0.049, 0.001), ACCENT).name = "CalloutAccent"
	labels.imperative = _label("Seat rotor upright", Vector3(-0.076, 0.022, 0.004), TASK_FONT_SIZE, TASK_PIXEL_SIZE, TEXT)
	labels.title = labels.imperative
	labels.progress = _label("1/38", Vector3(-0.107, -0.025, 0.004), 20, 0.0005, ACCENT)
	labels.state = _label("", Vector3(0.107, -0.025, 0.004), 20, 0.0005, ACCENT)
	labels.state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_arrow = Node3D.new()
	_arrow.name = "TargetArrow"
	_arrow.position = Vector3(-0.101, 0.012, 0.004)
	add_child(_arrow)
	# A geometric arrow avoids reliance on an icon font. It turns toward the
	# target in the callout plane; the fixture highlight identifies its depth.
	_segment(Vector2(-0.008, 0), Vector2(0.008, 0))
	_segment(Vector2(0.002, 0.006), Vector2(0.008, 0))
	_segment(Vector2(0.002, -0.006), Vector2(0.008, 0))
	_built = true
	visible = _active
	update_view(_view)

func update_view(view: Dictionary) -> void:
	_view = view.duplicate(true)
	if not _built: return
	# Deliberately ignore body/theory/hint/title: these may be long scientific
	# narration. Only the fixed, reviewed 2–5 word action is drawn on screen.
	labels.imperative.text = str(SHORT_ACTIONS.get(str(view.get("prompt_id", view.get("id", "load"))), "Follow highlighted target"))
	var total: int = maxi(1, int(view.get("total", view.get("step_count", 38))))
	var current: int = clampi(int(view.get("index", int(view.get("step_index", 1)) - 1)) + 1, 1, total)
	labels.progress.text = "%d/%d" % [current, total]
	var state: String = "Review" if bool(view.get("review", view.get("reviewing", false))) else "Done" if bool(view.get("ready", false)) else ""
	var supplied: String = str(view.get("display_state", ""))
	if supplied in ["Wait", "Measuring", "Analyzing", "Coasting"] and state.is_empty(): state = supplied
	labels.state.text = state
	overflowed = ThemeDB.fallback_font.get_string_size(labels.imperative.text, HORIZONTAL_ALIGNMENT_LEFT, -1, TASK_FONT_SIZE).x * TASK_PIXEL_SIZE > TEXT_WIDTH_M

func set_target_world_position(world_point: Vector3) -> void:
	if not _built: return
	var point: Vector3 = to_local(world_point) - _arrow.position
	if Vector2(point.x, point.y).length_squared() > 0.000001:
		_arrow.rotation.z = atan2(point.y, point.x)

func set_panel_active(enabled: bool) -> void:
	_active = enabled
	visible = enabled

func request_command(_command: String) -> void:
	# Kept for API compatibility; this visual cannot dispatch actions.
	pass

func local_bounds() -> AABB:
	return AABB(Vector3(-WIDTH_M * 0.5, -HEIGHT_M * 0.5, -DEPTH_M * 0.5), Vector3(WIDTH_M, HEIGHT_M, DEPTH_M))

static func angular_extent(span_m: float, distance_m: float) -> float:
	return rad_to_deg(2.0 * atan2(span_m * 0.5, distance_m)) if distance_m > 0.0 else 0.0

func _segment(from: Vector2, to: Vector2) -> void:
	var direction: Vector2 = to - from
	var part: MeshInstance3D = _box(Vector3(direction.length(), 0.0017, 0.0015), Vector3.ZERO, ACCENT)
	part.reparent(_arrow, false)
	part.position = Vector3((from.x + to.x) * 0.5, (from.y + to.y) * 0.5, 0)
	part.rotation.z = direction.angle()

func _label(value: String, pos: Vector3, font_size: int, pixel_size: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.position = pos
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.no_depth_test = false
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
