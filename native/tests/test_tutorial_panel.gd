extends SceneTree
## Standalone panel contracts. Omit --headless and add -- --capture=<png>
## to render the welcome and measured-trial lessons side by side.

const PanelScript=preload("res://scripts/tutorial_panel.gd")
const TutorialScript=preload("res://scripts/lab_tutorial.gd")
var checks := 0
var failures := 0
var commands: Array[String]=[]
var _capture := ""
var _app_capture := ""


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):_capture=argument.trim_prefix("--capture=")
		if argument.begins_with("--app-capture="):_app_capture=argument.trim_prefix("--app-capture=")
	call_deferred("_run")


func _check(value: bool, description: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("TUTORIAL PANEL: "+description)


func _run() -> void:
	var panel=PanelScript.new()
	panel.configure()
	root.add_child(panel)
	panel.command_requested.connect(func(command: String):commands.append(command))
	_check(panel.interactive_buttons.size()==8,"Tutorial provides navigation and contextual controls")
	_check(panel.navigation_buttons.size()==2,"Back and Next are available as the navigation subset")
	panel.configure()
	_check(panel.interactive_buttons.size()==8,"Repeated configure is idempotent")
	panel.update_view(_welcome())
	var next=_button(panel,"tutorial:next")
	var back=_button(panel,"tutorial:back")
	var practice=_button(panel,"tutorial:practice")
	_check(next.enabled and next.collision_layer==1,"Theory step can continue")
	_check(not back.enabled and back.collision_layer==0,"Initial Back is visibly and physically disabled")
	_check(not practice.enabled,"Theory with no practice menu disables Practice")
	panel.update_view(_trial(false))
	_check(not panel.overflowed,"Representative 450-character lesson fits without truncation")
	_check(not next.enabled and next.collision_layer==0,"Practice gate disables Next collider")
	_check(next.contact_depth(next.to_global(Vector3(0,0,0)))<0,"Disabled button rejects direct contact")
	next.hover(true)
	next.set_depression(0.008)
	_check(is_zero_approx(next.depression_m),"Disabled cap does not depress or hover")
	panel.request_command("tutorial:next")
	_check(commands.is_empty(),"Disabled Next cannot dispatch through signal bridge")
	_check(practice.enabled and back.enabled,"Practice and Back remain available at a gated step")
	_check(_button(panel,"tutorial:skip").enabled,"Skip for now remains available at a gated step")
	_check(_button(panel,"tutorial:skip_step").enabled,"Skip lesson remains available at a gated step")
	panel.request_command("tutorial:practice")
	_check(commands==["tutorial:practice"],"Context practice request is dispatched without operating the lab")
	var muted: Color=next.text_label.modulate
	panel.update_view(_trial(true))
	_check(next.enabled and next.collision_layer==1,"Met requirement enables Next")
	_check(next.text_label.modulate!=muted,"Enabled Next restores a readable active caption")
	panel.request_command("tutorial:next")
	_check(commands[-1]=="tutorial:next","Ready Next dispatches the requested command")
	_check(_button(panel,"tutorial:startup").text_label.text=="STARTUP: OFF","Startup preference appears in its control")
	_check(panel.labels.target.text.contains("Fit Known Trial"),"Target command is translated into a readable target name")
	_check(panel.labels.progress.text.contains("Step 12 / 23"),"Progress remains visible with the lesson")
	_check(panel.labels.hint.text.begins_with("READY /"),"Ready state is communicated in words")
	for key in ["what","why"]:
		_check(panel.labels[key].text.split("\n").size()<=4,"Lesson body has a bounded line count")
		for line in panel.labels[key].text.split("\n"):
			var width: float=ThemeDB.fallback_font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,28).x*0.00065
			_check(width<=0.741,"Wrapped lesson line stays inside the 0.74m text region")
	for button in panel.interactive_buttons:
		_check(button.position.y-button.height_m/2>=-0.41,"Tutorial controls fit expanded existing backplate")
		_check(absf(button.position.x)+button.width_m/2<=0.375,"Tutorial controls fit existing panel width")
		_check(button.get_meta("tutorial",false),"Root can identify tutorial controls by metadata")
	panel.set_panel_active(false)
	_check(not panel.visible,"Leaving Learn hides its content")
	for button in panel.interactive_buttons:
		_check(not button.enabled and button.collision_layer==0,"Hidden lesson leaves no active tutorial target")
	panel.request_command("tutorial:skip")
	_check(commands[-1]=="tutorial:next","Hidden panel cannot dispatch a navigation request")
	panel.set_panel_active(true)
	_check(panel.visible and next.enabled and practice.enabled,"Returning to Learn restores view-specific button state")
	var touch_view := _trial(false)
	touch_view.id="touch"
	touch_view.target="tutorial:touch"
	panel.update_view(touch_view)
	var touch=_button(panel,"tutorial:touch")
	_check(touch.visible and touch.enabled and touch.collision_layer==1,"Touch lesson exposes its real practice control")
	_check(not practice.visible and not practice.enabled and practice.collision_layer==0,"Touch control replaces contextual Practice without an overlapping target")
	panel.request_command("tutorial:touch")
	_check(commands[-1]=="tutorial:touch","Touch practice records only a tutorial command")
	panel.update_view(_trial(true))
	_check(not touch.visible and not touch.enabled,"Other lessons hide the touch practice target")
	_test_actual_lessons(panel)
	_test_actual_tabs()
	var long_view := _trial(true)
	long_view.title="This title intentionally exceeds the entire panel width and must remain inside a single line"
	panel.update_view(long_view)
	_check(panel.overflowed and panel.labels.title.text.ends_with("…"),"Overlong titles are bounded rather than crossing the panel")
	panel.update_view(_trial(true))
	_check(not panel.overflowed,"Fitting content clears overflow diagnostics")
	if not _capture.is_empty():
		await _clear_stage()
		await _render_comparison()
	if not _app_capture.is_empty():
		await _clear_stage()
		await _render_app_learn()
	print("TUTORIAL PANEL TESTS: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)


func _button(panel, command: String):
	for button in panel.interactive_buttons:
		if button.action==command:return button
	_check(false,"Required control exists: "+command)
	return null


func _label_bottom(label: Label3D) -> float:
	var lines := 0 if label.text.is_empty() else label.text.split("\n").size()
	return label.position.y-ThemeDB.fallback_font.get_height(label.font_size)*label.pixel_size*lines


func _test_actual_lessons(panel) -> void:
	var tutorial=TutorialScript.new("")
	tutorial.start({})
	for index in range(tutorial.steps.size()):
		tutorial.index=index
		var view: Dictionary=tutorial.view({})
		panel.update_view(view)
		var context := "lesson "+str(view.id)
		_check(not panel.overflowed,"Actual "+context+" has no text truncation")
		_check(panel.labels.what.text.replace("\n"," ")==str(view.body),"Actual "+context+" retains its full WHAT text")
		_check(panel.labels.why.text.replace("\n"," ")==str(view.theory),"Actual "+context+" retains its full WHY text")
		_check(_label_bottom(panel.labels.title)>=panel.labels.progress.position.y+0.003,context+" title clears progress using actual font height")
		_check(_label_bottom(panel.labels.what_heading)>=panel.labels.what.position.y+0.002,context+" WHAT heading clears body")
		_check(_label_bottom(panel.labels.what)>=panel.labels.why_heading.position.y+0.004,context+" WHAT body clears WHY heading")
		_check(_label_bottom(panel.labels.why_heading)>=panel.labels.why.position.y+0.002,context+" WHY heading clears body")
		_check(_label_bottom(panel.labels.why)>=panel.labels.hint.position.y+0.004,context+" WHY body clears hint")
		_check(_label_bottom(panel.labels.hint)>=panel.labels.target.position.y+0.004,context+" hint clears target")
		_check(_label_bottom(panel.labels.target)>=_button(panel,"tutorial:back").position.y+0.034,context+" target clears physical buttons")
		for label in [panel.labels.title,panel.labels.progress,panel.labels.what,panel.labels.why,panel.labels.hint,panel.labels.target]:
			for line in label.text.split("\n"):
				var width: float=ThemeDB.fallback_font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size).x*label.pixel_size
				_check(width<=0.741,"Actual "+context+" line fits its 0.74m region")
	_check(_button(panel,"tutorial:next").text_label.text=="FINISH","Last page offers FINISH before any completion is recorded")
	_check(not tutorial.completed,"Rendering the final page does not record completion")
	tutorial.completed=true
	tutorial.index=0
	panel.update_view(tutorial.view({}))
	_check(_button(panel,"tutorial:next").text_label.text=="NEXT","Historical completion does not label an earlier page FINISH")
	_check(not panel.labels.progress.text.contains("COMPLETE"),"Historical completion does not mislabel the current practice state")


func _test_actual_tabs() -> void:
	var app=load("res://main.tscn").instantiate()
	app.tutorial_settings_path=""
	app.tutorial_autostart=true
	root.add_child(app)
	app.set_process(false)
	app.set_process_unhandled_input(false)
	var count := 0
	for button in app.buttons:
		if not button.action.begins_with("tab:"):continue
		count+=1
		var label: Label3D=button.text_label
		var width: float=ThemeDB.fallback_font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size).x*label.pixel_size
		_check(width<=button.width_m-0.012,"Actual "+button.action+" caption fits five-tab control")
		_check(absf(button.position.x)+button.width_m/2<=0.41,"Actual "+button.action+" fits panel width")
	_check(count==5,"Actual application includes five readable menu tabs")
	_check(app.tab=="learn" and app.tutorial.active,"Memory-only initial app opens Learn without fixture actions")
	_check(not app.model.mounted and not app.model.running,"Opening the actual lesson leaves lab state untouched")
	app.queue_free()


func _clear_stage() -> void:
	for node in root.get_children():node.queue_free()
	await process_frame


func _welcome() -> Dictionary:
	return {"title":"Welcome to SpinLab","progress":"Step 1 / 23","index":0,"total":23,"what":"Learn how a reaction-wheel test station measures vibration and calculates a correction. Read each short explanation, then practice the step on the real lab controls. You can leave the lesson at any time and return to the same step.","why":"A reaction wheel changes spacecraft attitude, but its rotating mass can also disturb sensitive instruments. This synthetic laboratory makes the preparation, measurement, and verification sequence visible without operating physical machinery.","hint":"Read WHAT and WHY, then press Next. This introduction does not start the rotor.","ready":true,"practice_tab":"","startup_enabled":true,"can_back":false}


func _trial(ready: bool) -> Dictionary:
	return {"title":"Identify the influence coefficient","progress":"Step 12 / 23","index":11,"total":23,"what":"Record a baseline first, then fit the known trial on plane A with the guard open. Close the guard and capture Trial A at the same speed. Wait for the rotor to stop before changing the installed mass or opening the enclosure.","why":"The difference between trial and baseline vibration shows how a known mass-radius vector affects the measured response. This measured influence coefficient supplies both magnitude and phase for the correction; the solver does not use a hidden heavy-spot answer.","hint":"Open Balance with Practice. Fit the known trial only after a matching baseline is recorded.","target":"fit_trial","ready":ready,"practice_tab":"balance","startup_enabled":false,"can_back":true}


func _render_comparison() -> void:
	if DisplayServer.get_name()=="headless":
		_check(false,"Rendered comparison requires a display; omit --headless")
		return
	root.size=Vector2i(1920,1200)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color("08131f")
	environment.environment=settings
	root.add_child(environment)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position=Vector3(0,0,2)
	camera.look_at(Vector3.ZERO)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=1.42
	camera.current=true
	for index in range(2):
		var mount := Node3D.new()
		mount.position.x=-0.44 if index==0 else 0.44
		root.add_child(mount)
		var panel=PanelScript.new()
		mount.add_child(panel)
		panel.configure()
		panel._box(Vector3(0.82,0.82,0.025),Vector3(0,0,-0.013),Color("132634"))
		panel._label("SPINLAB XR  /  LEARN",Vector3(-0.37,0.36,0.038),27,0.00065,Color("6ce5c9"))
		panel._label("OPERATE    BALANCE    ANALYZE    SESSION    LEARN",Vector3(-0.37,0.284,0.038),18,0.00060,Color("a5bdc9"))
		panel.update_view(_welcome() if index==0 else _trial(false))
	for frame in range(6):await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(_capture)
	_check(error==OK,"Welcome and theory panel comparison saves")
	print("TUTORIAL_PANEL_CAPTURE ",_capture)


func _render_app_learn() -> void:
	if DisplayServer.get_name()=="headless":
		_check(false,"Actual Learn capture requires a display")
		return
	root.size=Vector2i(1500,1500)
	var app=load("res://main.tscn").instantiate()
	app.tutorial_settings_path=""
	app.tutorial_autostart=true
	root.add_child(app)
	app.set_process(false)
	app.set_process_unhandled_input(false)
	for layer in app.find_children("*","CanvasLayer",true,false):layer.visible=false
	var center: Vector3=app.controls.global_position+Vector3(0,-0.075,0.04)
	app.camera.position=center+Vector3(0,0,1.16)
	app.camera.look_at(center)
	app.camera.fov=48
	app.camera.current=true
	app._update_ui()
	for frame in range(6):await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_app_capture.get_base_dir())
	var error := root.get_texture().get_image().save_png(_app_capture)
	_check(error==OK,"Actual app welcome lesson capture saves")
	print("TUTORIAL_APP_CAPTURE ",_app_capture)
	app.tutorial.index=12
	app._update_ui()
	for frame in range(4):await process_frame
	await RenderingServer.frame_post_draw
	var theory_path := ProjectSettings.globalize_path("res://../.local/tutorial-native-theory.png")
	error=root.get_texture().get_image().save_png(theory_path)
	_check(error==OK,"Actual app measured-influence lesson capture saves")
	print("TUTORIAL_APP_THEORY_CAPTURE ",theory_path)
