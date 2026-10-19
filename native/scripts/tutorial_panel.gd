class_name TutorialPanel
extends Node3D
## Compact lesson content inside the existing left-hand control panel.
## The application owns all input/rays and registers interactive_buttons using
## their LabButton action metadata. No independent HUD or input handler is added.

signal command_requested(command: String)

const ButtonScript = preload("res://scripts/lab_button.gd")
const WIDTH_M := 0.74
const BODY_PIXEL_SIZE := 0.00065
const BODY_FONT_SIZE := 28
const TEXT := Color("e6f1f5")
const DIM := Color("a5bdc9")
const ACCENT := Color("6ce5c9")

var interactive_buttons: Array = []
var navigation_buttons: Array = []
var labels: Dictionary = {}
var overflowed := false
var _buttons: Dictionary = {}
var _built := false
var _active := true
var _view: Dictionary = {}
var _progress_fill: MeshInstance3D
var _font: Font


func configure() -> void:
	if _built:return
	_font=ThemeDB.fallback_font
	labels.title=_label("WELCOME TO SPINLAB",Vector3(-0.37,0.172,0.038),30,0.00065,ACCENT)
	labels.progress=_label("Step 1 / 23",Vector3(-0.37,0.139,0.038),22,0.00058,DIM)
	var track := _box(Vector3(WIDTH_M,0.003,0.002),Vector3(0,0.113,0.034),Color("2b4655"))
	track.name="ProgressTrack"
	_progress_fill=_box(Vector3(1,0.003,0.002),Vector3(-WIDTH_M/2,0.113,0.036),ACCENT)
	_progress_fill.name="ProgressFill"
	labels.what_heading=_label("WHAT TO DO",Vector3(-0.37,0.092,0.038),21,0.00055,ACCENT)
	labels.what=_label("",Vector3(-0.37,0.071,0.038),BODY_FONT_SIZE,BODY_PIXEL_SIZE,TEXT)
	labels.why_heading=_label("WHY IT MATTERS",Vector3(-0.37,-0.030,0.038),21,0.00055,ACCENT)
	labels.why=_label("",Vector3(-0.37,-0.051,0.038),BODY_FONT_SIZE,BODY_PIXEL_SIZE,TEXT)
	labels.hint=_label("",Vector3(-0.37,-0.157,0.038),23,0.00058,DIM)
	labels.target=_label("",Vector3(-0.37,-0.207,0.038),21,0.00056,ACCENT)
	_add_button("BACK","tutorial:back",Vector3(-0.255,-0.266,0.039),false)
	_add_button("PRACTICE","tutorial:practice",Vector3(0,-0.266,0.039),false)
	_add_button("TOUCH TO TRY","tutorial:touch",Vector3(0,-0.266,0.039),true)
	_add_button("NEXT","tutorial:next",Vector3(0.255,-0.266,0.039),true)
	_add_button("SKIP LESSON","tutorial:skip_step",Vector3(-0.2775,-0.344,0.039),false,0.175)
	_add_button("SKIP FOR NOW","tutorial:skip",Vector3(-0.0925,-0.344,0.039),false,0.175)
	_add_button("STARTUP: ON","tutorial:startup",Vector3(0.0925,-0.344,0.039),false,0.175)
	_add_button("RESTART","tutorial:restart",Vector3(0.2775,-0.344,0.039),false,0.175)
	navigation_buttons=[_buttons["tutorial:back"],_buttons["tutorial:next"]]
	_built=true
	update_view(_view)


func update_view(view: Dictionary) -> void:
	_view=view.duplicate(true)
	if not _built:return
	overflowed=false
	labels.title.text=_wrap(str(view.get("title","Welcome to SpinLab")),30,0.00065,1)
	var index := maxi(0,int(view.get("index",int(view.get("step_index",1))-1)))
	var total := maxi(1,int(view.get("total",view.get("step_count",23))))
	var ready := bool(view.get("ready",false))
	var is_last := bool(view.get("is_last",false))
	var progress := str(view.get("progress","Step %d / %d" % [index+1,total]))
	labels.progress.text=_wrap(progress+"  ·  "+("READY TO FINISH" if is_last and ready else "READY TO CONTINUE" if ready else "PRACTICE THIS STEP"),22,0.00058,1)
	var fraction := clampf(float(index+1)/float(total),0,1)
	_progress_fill.scale.x=maxf(0.001,WIDTH_M*fraction)
	_progress_fill.position.x=-WIDTH_M/2+WIDTH_M*fraction/2
	var what := str(view.get("what",view.get("body","")))
	var why := str(view.get("why",view.get("theory","")))
	labels.what.text=_wrap(what,BODY_FONT_SIZE,BODY_PIXEL_SIZE,4)
	labels.why.text=_wrap(why,BODY_FONT_SIZE,BODY_PIXEL_SIZE,4)
	var hint := str(view.get("hint",view.get("gatehint","")))
	labels.hint.text=_wrap(("READY / " if ready else "HINT / ")+hint,23,0.00058,2) if not hint.is_empty() else ""
	var target := str(view.get("target",""))
	labels.target.text=_wrap("TARGET / "+_target_name(target),21,0.00056,1) if not target.is_empty() else ""
	_buttons["tutorial:next"].set_caption(("FINISH" if is_last else "NEXT") if ready else "DO STEP FIRST")
	_buttons["tutorial:startup"].set_caption("STARTUP: ON" if bool(view.get("startup_enabled",true)) else "STARTUP: OFF")
	_apply_button_state()


func set_panel_active(active: bool) -> void:
	_active=active
	visible=active
	if _built:_apply_button_state()


func _apply_button_state() -> void:
	var touch_step := bool(_view.get("show_touch",false)) or str(_view.get("id",""))=="touch" or str(_view.get("target","")) in ["tutorial:touch","touch"]
	for button in interactive_buttons:
		var allowed := _active
		if button.action=="tutorial:next":allowed=allowed and bool(_view.get("ready",false))
		elif button.action=="tutorial:back":allowed=allowed and bool(_view.get("can_back",int(_view.get("index",0))>0))
		elif button.action=="tutorial:practice":allowed=allowed and not touch_step and not str(_view.get("practice_tab","")).is_empty()
		elif button.action=="tutorial:touch":allowed=allowed and touch_step
		button.visible=not touch_step if button.action=="tutorial:practice" else touch_step if button.action=="tutorial:touch" else true
		button.set_enabled(allowed)


## Optional signal bridge for callers that prefer signals over action metadata.
func request_command(command: String) -> void:
	if _buttons.has(command) and _buttons[command].enabled:
		command_requested.emit(command)


func _target_name(target: String) -> String:
	var names := {"rotor":"tray rotor / spindle","mount":"tray rotor / spindle","guard":"orange lift handle","home":"probe home button","dial:probe":"probe micrometer","tutorial:touch":"TOUCH TO TRY button","baseline":"Record Baseline","fit_trial":"Fit Known Trial","trial_a":"Measure Trial A","trial_b":"Measure Trial B","solve":"Solve Influence Matrix","apply":"Fit Calculated Correction","verify":"Verify Corrected Rotor"}
	return str(names.get(target,target.replace("_"," ").replace(":"," / ")))


func _wrap(value: String, font_size: int, pixel_size: float, max_lines: int) -> String:
	var lines := PackedStringArray()
	var max_pixels := WIDTH_M/pixel_size
	for paragraph in value.replace("\r","").split("\n"):
		var line := ""
		for word in paragraph.split(" ",false):
			var candidate := word if line.is_empty() else line+" "+word
			if _font.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>max_pixels and not line.is_empty():
				lines.append(line)
				line=word
			else:line=candidate
		lines.append(line)
	if lines.size()>max_lines:
		overflowed=true
		lines.resize(max_lines)
		var final_line := lines[max_lines-1]
		while not final_line.is_empty() and _font.get_string_size(final_line+"…",HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>max_pixels:
			final_line=final_line.left(final_line.length()-1)
		lines[max_lines-1]=final_line+"…"
	return "\n".join(lines)


func _add_button(caption: String, command: String, pos: Vector3, primary: bool, width: float=0.235) -> void:
	var button=ButtonScript.new()
	button.name=command.replace(":","_")
	add_child(button)
	button.position=pos
	button.configure(caption,command,width,0.060,Color("285b4c") if primary else Color("244353"))
	button.text_label.font_size=25 if width<0.2 else 28
	button.text_label.pixel_size=0.00080 if width<0.2 else 0.00085
	button.set_meta("tutorial",true)
	interactive_buttons.append(button)
	_buttons[command]=button


func _label(value: String, pos: Vector3, font_size: int, pixel_size: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text=value;label.position=pos;label.font_size=font_size;label.pixel_size=pixel_size
	label.modulate=color;label.outline_size=0;label.shaded=false
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment=VERTICAL_ALIGNMENT_TOP
	add_child(label)
	return label


func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new();mesh.size=size
	var material := StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=color
	var instance := MeshInstance3D.new()
	instance.mesh=mesh;instance.material_override=material;instance.position=pos
	add_child(instance)
	return instance
