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
	_check(is_equal_approx(panel.WIDTH_M, 0.72) and is_equal_approx(panel.HEIGHT_M, 0.48), "Guide uses independent 0.72 by 0.48 metre layout")
	var tutorial = TutorialScript.new("")
	tutorial.start({})
	for index in range(tutorial.steps.size()):
		tutorial.index = index
		var view: Dictionary = tutorial.view({})
		panel.update_view(view)
		_test_page(panel, view)
	_check(panel.labels.legend.text.begins_with("A Finish"), "Only final current lesson labels A as Finish")
	_check(not tutorial.completed, "Rendering final page does not complete tour")
	tutorial.completed = true
	tutorial.index = 0
	panel.update_view(tutorial.view({}))
	_check(panel.labels.legend.text.begins_with("A Continue"), "Historical completion cannot label replay's first page Finish")
	_check(panel.labels.task == panel.labels.body and panel.labels.what == panel.labels.task and panel.labels.why == panel.labels.theory, "Presentation aliases reference the same read-only labels")
	_check(panel.labels.legend.text.contains("X Back") and panel.labels.legend.text.contains("B/Y Menu"), "Controller navigation legend is visible")
	_check(panel.labels.movement.text.contains("Right stick: walk") and panel.labels.movement.text.contains("Left stick: height"), "Movement conventions are visible")
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
	return label.position.y - ThemeDB.fallback_font.get_height(label.font_size) * label.pixel_size * label.text.split("\n").size()

func _test_page(panel, view: Dictionary) -> void:
	var context: String = str(view.id)
	_check(not panel.overflowed, context + " displays all copy without truncation")
	_check(panel.labels.task.text.replace("\n", " ") == view.body, context + " retains full instruction")
	_check(panel.labels.theory.text.replace("\n", " ") == view.theory, context + " retains full theory")
	_check(panel.labels.progress.text == view.progress and panel.labels.chapter.text == view.chapter, context + " identifies progress and chapter")
	_check(_bottom(panel.labels.chapter) > panel.labels.title.position.y + 0.003, context + " chapter clears title")
	_check(_bottom(panel.labels.title) > 0.151, context + " title clears progress bar")
	_check(_bottom(panel.labels.task_heading) > panel.labels.task.position.y + 0.002, context + " instruction heading clears body")
	_check(_bottom(panel.labels.task) > panel.labels.theory_heading.position.y + 0.003, context + " instruction clears theory heading")
	_check(_bottom(panel.labels.theory_heading) > panel.labels.theory.position.y + 0.002, context + " theory heading clears body")
	_check(_bottom(panel.labels.theory) > panel.labels.hint.position.y + 0.003, context + " theory clears action hint")
	_check(_bottom(panel.labels.hint) > panel.labels.legend.position.y + 0.003, context + " hint clears controller legend")
	_check(_bottom(panel.labels.legend) > panel.labels.movement.position.y + 0.003, context + " controller legend clears movement legend")
	_check(_bottom(panel.labels.movement) > panel.labels.footer.position.y + 0.003, context + " movement legend clears footer")
	for key in ["chapter", "progress", "title", "task", "theory", "hint", "legend", "movement", "footer"]:
		var label: Label3D = panel.labels[key]
		_check(_bottom(label) >= -panel.HEIGHT_M / 2.0 + 0.010, context + " " + key + " stays above backplate edge")
		for line in label.text.split("\n"):
			var width: float = ThemeDB.fallback_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x * label.pixel_size
			_check(width <= panel.TEXT_WIDTH_M + 0.001, context + " " + key + " line fits text region")
	_check(panel.labels.task.text.split("\n").size() <= 3 and panel.labels.theory.text.split("\n").size() <= 3, context + " uses at most three lines per instruction/theory")

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
	camera.size = 1.25
	camera.current = true
	var tutorial = TutorialScript.new("")
	tutorial.start({})
	for index in range(2):
		var panel = PanelScript.new()
		root.add_child(panel)
		panel.position.x = -0.40 if index == 0 else 0.40
		panel.configure()
		tutorial.index = 0 if index == 0 else 12
		panel.update_view(tutorial.view({}))
	for frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png(capture_path)
	_check(result == OK, "Read-only guide comparison image saves")
	print("TUTORIAL_PANEL_CAPTURE ", capture_path)
