extends SceneTree
## Minimal visual content only; narration retains the source lesson paragraphs.
## Optional -- --capture=<absolute.png> produces the full fifteen-callout grid.
const CalloutPanel = preload("res://scripts/tutorial_panel.gd")
const Tutorial = preload("res://scripts/lab_tutorial.gd")
var checks: int = 0
var failures: int = 0
var commands: Array = []
var capture_path: String = ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="): capture_path = argument.trim_prefix("--capture=")
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CALLOUT PANEL: " + description)

func _run() -> void:
	var panel = CalloutPanel.new()
	root.add_child(panel)
	panel.configure()
	var child_count: int = panel.get_child_count()
	panel.configure()
	_check(panel.get_child_count() == child_count, "Configure is idempotent")
	_check(is_equal_approx(panel.WIDTH_M, 0.24) and is_equal_approx(panel.HEIGHT_M, 0.10), "Visual footprint is a24by10cm target callout")
	_check(panel.interactive_buttons.is_empty() and panel.navigation_buttons.is_empty(), "Callout has no interactive controls")
	_check(panel.find_children("*", "CollisionObject3D", true, false).is_empty() and panel.find_children("*", "CollisionShape3D", true, false).is_empty(), "Callout cannot intercept fingers or controller rays")
	_check(panel.find_children("*", "Label3D", true, false).size() == 3, "Only imperative/progress/small-state labels exist")
	_check(not panel.labels.has("body") and not panel.labels.has("theory") and not panel.labels.has("legend"), "Long-form text and controller footers are removed entirely")
	var guide = Tutorial.new("")
	guide.start({})
	var preserved: Array = guide.steps.duplicate(true)
	for step_index in range(guide.steps.size()):
		guide.index = step_index
		var view: Dictionary = guide.view({})
		panel.update_view(view)
		_test_callout(panel, view)
	_check(guide.steps == preserved and guide.index == 14 and not guide.completed, "Minimal rendering preserves every narration source and procedure gate")
	var display: Dictionary = guide.view({})
	display.body = "Long narration instruction. ".repeat(100)
	display.theory = "Long narration science. ".repeat(100)
	display.hint = "A paragraph must never reach a visible label. ".repeat(100)
	display.title = "A long title is not the short imperative. ".repeat(100)
	panel.update_view(display)
	_check(panel.labels.imperative.text == "Save report" and not panel.overflowed, "Arbitrary long lesson fields never become visible text")
	for state in ["Wait", "Measuring", "Analyzing", "Coasting"]:
		display.display_state = state
		panel.update_view(display)
		_check(panel.labels.state.text == state, "Only a short supported state can accompany the action: " + state)
	display.display_state = "This is an injected long-form state that must not render."
	panel.update_view(display)
	_check(panel.labels.state.text.is_empty(), "Unreviewed state paragraphs are ignored")
	display.ready = true
	panel.update_view(display)
	_check(panel.labels.state.text == "Done", "Confirmed outcome uses a one-word success state")
	display.review = true
	panel.update_view(display)
	_check(panel.labels.state.text == "Review", "Review is clearly distinct from new work success")
	var arrow: Node3D = panel.get_node("TargetArrow")
	panel.set_target_world_position(panel.to_global(Vector3(-1, arrow.position.y, 0)))
	_check(absf(absf(arrow.rotation.z) - PI) < 0.001, "Geometric arrow points left to a left-hand target")
	panel.set_target_world_position(panel.to_global(Vector3(1, arrow.position.y, 0)))
	_check(absf(arrow.rotation.z) < 0.001, "Geometric arrow points right to a right-hand target")
	panel.command_requested.connect(func(command: String): commands.append(command))
	panel.request_command("baseline")
	_check(commands.is_empty(), "Visual has no action dispatch")
	panel.set_panel_active(false)
	_check(not panel.visible, "Unavailable/blocked prompt can hide")
	panel.set_panel_active(true)
	_check(panel.visible, "Valid target placement can show prompt again")
	panel.queue_free()
	await process_frame
	if not capture_path.is_empty(): await _render_grid()
	print("TUTORIAL PANEL TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_callout(panel, view: Dictionary) -> void:
	var action: String = panel.labels.imperative.text
	var context: String = str(view.id)
	_check(action.split(" ", false).size() >= 2 and action.split(" ", false).size() <= 5, context + " uses a2–5word imperative")
	_check(not action.contains("\n") and action.length() <= 28 and not panel.overflowed, context + " never wraps or truncates")
	_check(panel.labels.progress.text == "%d/15" % [int(view.index) + 1], context + " retains minimal progression")
	_check(action != view.body and action != view.theory and action != view.title, context + " never renders source narration or long title")
	for label in panel.find_children("*", "Label3D", true, false):
		var width: float = ThemeDB.fallback_font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x * label.pixel_size
		var height: float = ThemeDB.fallback_font.get_height(label.font_size) * label.pixel_size
		var left: float = label.position.x - width if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT else label.position.x
		_check(left >= -panel.WIDTH_M / 2.0 + 0.003 and left + width <= panel.WIDTH_M / 2.0 - 0.003, context + " label stays inside full horizontal bounds")
		_check(label.position.y <= panel.HEIGHT_M / 2.0 - 0.003 and label.position.y - height >= -panel.HEIGHT_M / 2.0 + 0.003, context + " label stays inside full vertical bounds")
		_check(label.text.length() <= 28 and not label.text.contains("\n"), context + " label is superminimal")
	_check(panel.local_bounds().size == Vector3(0.24, 0.10, 0.016), context + " placement bounds enclose the full callout")

func _render_grid() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "Visual capture needs a renderer; omit headless")
		return
	root.size = Vector2i(1800, 1200)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("08131f")
	environment.environment = settings
	root.add_child(environment)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 0, 2)
	camera.look_at(Vector3.ZERO)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.82
	camera.current = true
	var guide = Tutorial.new("")
	guide.start({})
	for step_index in range(15):
		var panel = CalloutPanel.new()
		root.add_child(panel)
		panel.position = Vector3((step_index % 3 - 1) * 0.30, (2 - step_index / 3) * 0.14, 0)
		panel.configure()
		guide.index = step_index
		panel.update_view(guide.view({}))
		panel.set_target_world_position(panel.global_position - Vector3(0.20, 0.02, 0))
	for unused in range(5): await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(capture_path) == OK, "All fifteen minimal callouts render to QA image")
	print("TUTORIAL_PANEL_CAPTURE ", capture_path)
