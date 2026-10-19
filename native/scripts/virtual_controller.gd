class_name VirtualController
extends Node3D
## Actual Quest 2 GLBs, with the headset's FB render model preferred.
## Bundled geometry/layout is unmodified immersive-web oculus-touch-v3 (MIT).
## See assets/controllers/oculus-touch-v3/PROVENANCE.json and LICENSE.txt.
## All authored transforms are retained. Input/aim/grab ownership stays in main.
## FB supplies geometry, not automatic animation. Only discovered authored
## min/max/value control ranges animate; diagnostics report the bound count.

const ASSET_DIRECTORY := "res://assets/controllers/oculus-touch-v3/"
const ASSET_COMMIT := "afcd4423001acd0ff981c6860c71ca49c7b43e52"
const CHANNEL_NAMES := {
	"xr_standard_trigger_pressed":"trigger", "xr_standard_squeeze_pressed":"grip",
	"xr_standard_thumbstick_pressed":"stick_click", "xr_standard_thumbstick_xaxis_pressed":"stick_x",
	"xr_standard_thumbstick_yaxis_pressed":"stick_y", "a_button_pressed":"primary_click",
	"x_button_pressed":"primary_click", "b_button_pressed":"secondary_click",
	"y_button_pressed":"secondary_click", "thumbrest_pressed":"thumbrest_touch"
}

var model_root: Node3D
var fallback_root: Node3D
var visual_source := "bundled_quest2"
var runtime_status := "not_requested"
var controls: Dictionary = {}
var input_state: Dictionary = {}
var _side := "right_hand"
var _channels: Dictionary = {}
var _runtime_host: Node3D
var _runtime_requested := false


func _ready() -> void:
	if not is_instance_valid(fallback_root):configure(_side)


func configure(side: String) -> void:
	var chosen := "left_hand" if side in ["left_hand","left"] else "right_hand"
	if is_instance_valid(fallback_root) and chosen==_side:return
	_side=chosen
	if is_instance_valid(_runtime_host):
		remove_child(_runtime_host);_runtime_host.queue_free();_runtime_host=null
	if is_instance_valid(fallback_root):
		remove_child(fallback_root);fallback_root.queue_free()
	_runtime_requested=false;runtime_status="not_requested"
	var asset_path := ASSET_DIRECTORY+("left.glb" if _side=="left_hand" else "right.glb")
	var packed := load(asset_path) as PackedScene
	if packed==null:
		push_error("Quest 2 controller asset did not import: "+asset_path)
		return
	fallback_root=packed.instantiate() as Node3D
	add_child(fallback_root)
	fallback_root.name="Quest2BundledModel"
	_activate_model(fallback_root,"bundled_quest2")
	update_inputs(input_state,0.0)


func enable_runtime() -> bool:
	if _runtime_requested:return is_instance_valid(_runtime_host)
	_runtime_requested=true
	var interface := XRServer.find_interface("OpenXR")
	if interface==null or not interface.is_initialized() or not ClassDB.class_exists("OpenXRFbRenderModel"):
		runtime_status="unavailable"
		return false
	_runtime_host=ClassDB.instantiate("OpenXRFbRenderModel") as Node3D
	if _runtime_host==null:
		runtime_status="unavailable"
		return false
	_runtime_host.name="QuestRuntimeController"
	_runtime_host.set("render_model_type",0 if _side=="left_hand" else 1)
	_runtime_host.visible=false
	_runtime_host.connect("openxr_fb_render_model_loaded",_runtime_model_loaded)
	runtime_status="waiting"
	add_child(_runtime_host)
	# ENTER_TREE may load synchronously if a session is already active.
	if _runtime_host.call("has_render_model_node"):_runtime_model_loaded()
	return true


func _runtime_model_loaded() -> void:
	if not is_instance_valid(_runtime_host):return
	var loaded := _runtime_host.call("get_render_model_node") as Node3D
	if not is_instance_valid(loaded) or loaded==model_root:return
	if loaded.find_children("*","MeshInstance3D",true,false).is_empty():return
	runtime_status="loaded"
	_runtime_host.visible=true
	fallback_root.visible=false
	_activate_model(loaded,"runtime_fb")
	_apply_inputs()


func set_pose(trigger: float, grip: float, thumb_touch: bool=false, _holding: bool=false) -> void:
	# Compatibility: retain other button and stick states.
	var values := input_state.duplicate()
	values.trigger=trigger;values.grip=grip;values.stick_touch=thumb_touch
	update_inputs(values,0.0)


## Keys: trigger/grip, stick(Vector2), stick_click, primary_click(A/X),
## secondary_click(B/Y), primary_touch, secondary_touch, stick_touch,
## trigger_touch, thumbrest_touch. A touch never becomes a click. Physical
## values apply directly; delta remains available for caller compatibility.
func update_inputs(values: Dictionary, _delta: float=0.0) -> void:
	var stick_value: Variant=values.get("stick",values.get("thumbstick",Vector2.ZERO))
	var stick: Vector2=stick_value if typeof(stick_value)==TYPE_VECTOR2 else Vector2.ZERO
	if not stick.is_finite():stick=Vector2.ZERO
	stick=stick.clamp(Vector2(-1,-1),Vector2.ONE)
	input_state={"trigger":_bounded(values.get("trigger",0.0)),"grip":_bounded(values.get("grip",0.0)),
		"stick":stick,"stick_click":_pressed(values.get("stick_click",false)),
		"primary_click":_pressed(values.get("primary_click",values.get("ax_click",values.get("ax_button",false)))),
		"secondary_click":_pressed(values.get("secondary_click",values.get("by_click",values.get("by_button",false)))),
		"primary_touch":_pressed(values.get("primary_touch",values.get("ax_touch",false))),
		"secondary_touch":_pressed(values.get("secondary_touch",values.get("by_touch",false))),
		"stick_touch":_pressed(values.get("stick_touch",false)),"trigger_touch":_pressed(values.get("trigger_touch",false)),
		"thumbrest_touch":_pressed(values.get("thumbrest_touch",false))}
	# A session reload may retire the old runtime scene before its replacement
	# arrives. Keep the bundled asset visible in that interval.
	if visual_source=="runtime_fb" and (not is_instance_valid(model_root) or model_root.is_queued_for_deletion()):
		fallback_root.visible=true
		if is_instance_valid(_runtime_host):_runtime_host.visible=false
		runtime_status="waiting"
		_activate_model(fallback_root,"bundled_quest2")
	_apply_inputs()


func get_diagnostics() -> Dictionary:
	return {"source":visual_source,"side":_side,"runtime_status":runtime_status,
		"animation_channels":_channels.size(),"channels":_channels.keys(),"asset_commit":ASSET_COMMIT,
		"note":"Authored node ranges only; FB render models are not assumed to animate automatically."}


func _activate_model(model: Node3D, source: String) -> void:
	model_root=model;visual_source=source
	_channels.clear();controls.clear()
	var named: Dictionary={}
	for node in model.find_children("*","Node3D",true,false):named[str(node.name)]=node
	for prefix in CHANNEL_NAMES:
		var value: Node3D=named.get(prefix+"_value")
		var minimum: Node3D=named.get(prefix+"_min")
		var maximum: Node3D=named.get(prefix+"_max")
		if value==null or minimum==null or maximum==null:continue
		if value.get_parent()!=minimum.get_parent() or value.get_parent()!=maximum.get_parent():continue
		var key: String=CHANNEL_NAMES[prefix]
		_channels[key]={"value":value,"minimum":minimum.transform,"maximum":maximum.transform}
		controls[key]=value
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	print("SPINLAB_CONTROLLER_SOURCE side=",_side," source=",source," animation_channels=",_channels.size())


func _apply_inputs() -> void:
	for key in _channels:
		var channel: Dictionary=_channels[key]
		if not is_instance_valid(channel.value):continue
		var amount: float
		if key=="stick_x":amount=(input_state.get("stick",Vector2.ZERO).x+1.0)*0.5
		elif key=="stick_y":amount=(input_state.get("stick",Vector2.ZERO).y+1.0)*0.5
		else:amount=float(input_state.get(key,0.0))
		channel.value.transform=channel.minimum.interpolate_with(channel.maximum,clampf(amount,0.0,1.0))
		channel.value.set_meta("visual_input",amount)


func _bounded(value: Variant) -> float:
	if typeof(value) not in [TYPE_INT,TYPE_FLOAT]:return 0.0
	var number := float(value)
	return clampf(number,0.0,1.0) if is_finite(number) else 0.0


func _pressed(value: Variant) -> bool:
	return value if typeof(value)==TYPE_BOOL else false
