extends SceneTree
## Read-only guide layout contracts. Optional -- --capture=<absolute.png>.
const PanelScript = preload("res://scripts/tutorial_panel.gd")
const TutorialScript = preload("res://scripts/lab_tutorial.gd")
var checks: int = 0
var failures: int = 0
var commands: Array = []
var capture_path: String = ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
	call_deferred("_run")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("GUIDE PANEL: " + description)

func _run() -> void:
	var panel = PanelScript.new()
	panel.configure()
	root.add_child(panel)
	panel.command_requested.connect(func(command: String): commands.append(command))
	_check(panel.interactive_buttons.is_empty() and panel.navigation_buttons.is_empty(), "Floating guide has no fingertip or ray buttons")
	_check(panel.find_children("*", "CollisionObject3D", true, false).is_empty(), "Floating guide has no physics interaction targets")
	_check(panel.find_children("*", "CollisionShape3D", true, false).is_empty(), "Floating guide cannot intercept a contact or ray")
	var count_before: int = panel.get_child_count()
	panel.configure()
	_check(panel.get_child_count() == count_before, "Repeated configure does not duplicate guide geometry")
	_check(is_equal_approx(panel.WIDTH_M, 0.94) and is_equal_approx(panel.HEIGHT_M, 0.66), "Guide uses enlarged 0.94 by 0.66 metre layout")
	_test_readability_metrics(panel)
	var tutorial = TutorialScript.new("")
	tutorial.start({})
	for index in range(tutorial.steps.size()):
		tutorial.index = index
		var view: Dictionary = tutorial.view({})
		panel.update_view(view)
		_test_page(panel, view)
	_check(panel.labels.legend.text.begins_with("Automatic"), "Final instruction retains automatic work guidance")
	_check(not tutorial.completed, "Rendering final page does not complete tour")
	tutorial.completed = true
	tutorial.index = 0
	panel.update_view(tutorial.view({}))
	_check(panel.labels.legend.text.begins_with("Automatic"), "Replay starts with automatic work guidance")
	_check(panel.labels.task == panel.labels.body and panel.labels.what == panel.labels.task and panel.labels.why == panel.labels.theory, "Presentation aliases reference the same read-only labels")
	_check(panel.labels.legend.text.contains("X Review") and panel.labels.legend.text.contains("B/Y Menu"), "Optional review legend is visible")
	_check(panel.labels.movement.text.contains("next instruction follows"), "Work completion, not manual navigation, is the normal workflow")
	panel.request_command("tutorial:next")
	panel.request_command("baseline")
	_check(commands.is_empty(), "Guide cannot dispatch navigation or laboratory commands")
	panel.set_panel_active(false)
	_check(not panel.visible, "Pausing hides floating guide")
	panel.request_command("tutorial:next")
	_check(commands.is_empty(), "Hidden guide cannot dispatch a command")
	panel.set_panel_active(true)
	_check(panel.visible and panel.interactive_buttons.is_empty(), "Resuming restores content without interaction targets")
	var oversized: Dictionary = tutorial.view({})
	oversized.body = "A very long instruction that must be bounded within the compact guide. ".repeat(30)
	panel.update_view(oversized)
	_check(panel.overflowed and panel.labels.task.text.ends_with("…"), "Unexpected overlong content is bounded")
	panel.update_view(tutorial.view({}))
	_check(not panel.overflowed, "Normal content clears overflow diagnostics")
	if not capture_path.is_empty():
		panel.queue_free()
		await process_frame
		await _render_comparison()
	print("TUTORIAL PANEL TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _bottom(label: Label3D) -> float:
	return label.position.y if label.text.is_empty() else label.position.y - ThemeDB.fallback_font.get_height(label.font_size) * label.pixel_size * label.text.split("\n").size()

func _test_page(panel, view: Dictionary) -> void:
	var context: String = str(view.id)
	_check(not panel.overflowed, context + " displays all copy without truncation")
	_check(panel.labels.task.text.replace("\n", " ") == view.body, context + " retains full instruction")
	_check(panel.labels.theory.text.replace("\n", " ") == view.theory, context + " retains full theory")
	_check(panel.labels.progress.text == view.progress and panel.labels.chapter.text == view.chapter, context + " identifies progress and chapter")
	_check(_bottom(panel.labels.chapter) > panel.labels.title.position.y + 0.003, context + " chapter clears title")
	_check(_bottom(panel.labels.title) > 0.220, context + " title clears progress bar")
	_check(_bottom(panel.labels.task_heading) > panel.labels.task.position.y + 0.002, context + " instruction heading clears body")
	_check(_bottom(panel.labels.task) > panel.labels.theory_heading.position.y + 0.003, context + " instruction clears theory heading")
	_check(_bottom(panel.labels.theory_heading) > panel.labels.theory.position.y + 0.002, context + " theory heading clears body")
	_check(_bottom(panel.labels.theory) > panel.labels.hint.position.y + 0.003, context + " theory clears action hint")
	_check(_bottom(panel.labels.hint) > panel.labels.legend.position.y + 0.003, context + " hint clears controller legend")
	_check(_bottom(panel.labels.legend) > panel.labels.movement.position.y + 0.003, context + " controller legend clears movement legend")
	_check(_bottom(panel.labels.movement) > panel.labels.footer.position.y + 0.003, context + " movement legend clears footer")
	for key in ["chapter", "progress", "title", "task_heading", "task", "theory_heading", "theory", "hint", "legend", "movement", "footer"]:
		var label: Label3D = panel.labels[key]
		_check(label.font_size * label.pixel_size >= 0.016, context + " " + key + " never uses tiny secondary text")
		_check(_bottom(label) >= -panel.HEIGHT_M / 2.0 + 0.010, context + " " + key + " stays above backplate edge")
		for line in label.text.split("\n"):
			var width: float = ThemeDB.fallback_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x * label.pixel_size
			_check(width <= panel.TEXT_WIDTH_M + 0.001, context + " " + key + " line fits text region")
	_check(panel.labels.task.text.split("\n").size() <= 4 and panel.labels.theory.text.split("\n").size() <= 4, context + " retains complete copy in at most four large lines per block")

func _test_readability_metrics(panel) -> void:
	var metrics: Dictionary = panel.readability_metrics(1.47)
	_check(is_equal_approx(metrics.task_em_m, 0.0228) and is_equal_approx(metrics.theory_em_m, 0.0228), "Task and theory share 22.8 mm nominal world em")
	_check(metrics.task_em_m / metrics.previous_task_em_m >= 1.55, "Task typography grows at least55% independently of card size")
	_check(metrics.theory_em_m / metrics.previous_theory_em_m >= 1.69, "Theory typography grows at least69% independently of card size")
	_check(metrics.task_em_deg >= 0.88 and metrics.task_em_deg < 0.90, "At1.47m nominal text em spans about0.889degrees")
	_check(metrics.task_line_height_m > metrics.task_em_m, "Metrics distinguish actual font line height from nominal em")
	_check(panel.labels.task.modulate == panel.labels.theory.modulate, "Theory has the same bright contrast as the main instruction")
	var four_lines: float = ThemeDB.fallback_font.get_height(panel.BODY_FONT_SIZE) * panel.BODY_PIXEL_SIZE * 4.0
	_check(panel.labels.task.position.y - four_lines > panel.labels.theory_heading.position.y + 0.003, "Instruction reserves four full large-font line heights without overlap")
	_check(panel.labels.theory.position.y - four_lines > panel.labels.hint.position.y + 0.003, "Theory reserves four full large-font line heights without overlap")
	_check(metrics.card_horizontal_deg > 35.0 and metrics.card_horizontal_deg < 36.0, "At1.47m entire card spans about35.5horizontaldegrees")
	_check(metrics.card_vertical_deg > 25.0 and metrics.card_vertical_deg < 26.0, "At1.47m entire card spans about25.3verticaldegrees")
	var close: Dictionary = panel.readability_metrics(1.10)
	_check(close.task_em_deg > 1.18 and close.task_em_deg < 1.20, "At1.10m nominal text em spans about1.188degrees")
	var bounds: Dictionary = panel.view_bounds(1.15, -20.0, 8.0)
	_check(bounds.left_deg > -45.0 and bounds.right_deg < 10.0, "Suggested placement fits an explicit -45to+10degree horizontal viewing region")
	_check(bounds.bottom_deg > -20.0 and bounds.top_deg < 30.0, "Suggested placement fits an explicit -20to+30degree vertical viewing region")
	_check(is_zero_approx(panel.angular_extent(0.02, 0.0)), "Invalid viewing distance cannot produce an angular-size claim")
	print("GUIDE_READABILITY ", JSON.stringify(metrics))
	print("GUIDE_SUGGESTED_CORNER_BOUNDS ", JSON.stringify(bounds))

func _render_comparison() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "Render comparison requires a display; omit --headless")
		return
	root.size = Vector2i(1800, 1000)
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
	camera.size = 1.60
	camera.current = true
	var tutorial = TutorialScript.new("")
	tutorial.start({})
	for index in range(2):
		var panel = PanelScript.new()
		root.add_child(panel)
		panel.position.x = -0.51 if index == 0 else 0.51
		panel.configure()
		tutorial.index = 0 if index == 0 else 12
		panel.update_view(tutorial.view({}))
	for frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png(capture_path)
	_check(result == OK, "Read-only guide comparison image saves")
	print("TUTORIAL_PANEL_CAPTURE ", capture_path)
