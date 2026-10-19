extends SceneTree
## Original glove pose comparison, rendered without the full lab or XR runtime.
## godot --xr-mode off --path native --script res://tools/preview_hands.gd
## Optional: -- --output=<absolute.png>. A GPU/windowed display is required.

const HandScript = preload("res://scripts/virtual_hand.gd")
var _output := "res://../.local/virtual-gloves-qa.png"


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output=argument.trim_prefix("--output=")
	call_deferred("_render_preview")


func _render_preview() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Hand preview needs a rendering display; omit --headless. Use test_hand_visual.gd for headless QA.")
		quit(1)
		return
	root.size=Vector2i(1400,1100)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color("142536")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("b9d7e1")
	settings.ambient_light_energy=0.7
	environment.environment=settings
	root.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-58,-30,0)
	light.light_energy=1.5
	root.add_child(light)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position=Vector3(0.08,0.59,0.47)
	camera.look_at(Vector3(0,0,-0.025))
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=0.68
	camera.current=true
	for column in range(2):
		for row in range(2):
			var hand=HandScript.new()
			hand.configure("left_hand" if column==0 else "right_hand")
			root.add_child(hand)
			hand.position=Vector3(-0.14 if column==0 else 0.14,0,-0.165 if row==0 else 0.165)
			hand.set_pose(0.0 if row==0 else 1.0,0.0 if row==0 else 1.0,false,row==1)
			# Present the CANONICAL dorsal anatomy to the camera. This comparison
			# deliberately does not imply a measured headset grip calibration.
			hand._hand_root.transform=Transform3D.IDENTITY
			if row==1:
				hand.rotation.z=deg_to_rad(-18 if column==0 else 18)
			var caption := Label3D.new()
			caption.text=("LEFT" if column==0 else "RIGHT")+(" / POINT" if row==0 else " / GRIP")
			caption.pixel_size=0.00037
			caption.font_size=32
			caption.outline_size=0
			caption.position=hand.position+Vector3(0,0,0.084)
			caption.rotation.x=-PI/2
			root.add_child(caption)
	for frame in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(_output)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := root.get_texture().get_image().save_png(path)
	if error!=OK:
		push_error("Hand preview could not save: "+str(error))
		quit(1)
		return
	print("HAND_PREVIEW ",path)
	quit(0)
