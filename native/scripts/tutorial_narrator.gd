extends Node
## Bundled, offline step narration. No runtime synthesis or network access.
var enabled := true
var current_id := ""
var completed := true
var allowed := false
var settings_path := ""
var manifest: Dictionary = {}
var player: AudioStreamPlayer
var error := ""

func configure(path: String = "res://audio/tutorial/manifest.json", preferences: String = "") -> void:
	settings_path=preferences
	player=AudioStreamPlayer.new();player.name="TutorialVoice";player.volume_db=-1.0;add_child(player)
	player.finished.connect(_finished)
	if FileAccess.file_exists(path):
		var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:manifest=parsed
	if manifest.get("clips",{}).is_empty():error="Tutorial voice assets unavailable."
	if not settings_path.is_empty():
		var settings=ConfigFile.new()
		if settings.load(settings_path)==OK:enabled=bool(settings.get_value("voice","enabled",true))

func sync(view: Dictionary, can_play: bool) -> void:
	allowed=can_play
	if not view.get("active",false):
		if player:player.stop();player.stream=null
		current_id="";completed=true;return
	var step_id=str(view.get("id",""))
	if step_id!=current_id:
		current_id=step_id
		_start()
	if player:player.stream_paused=not allowed or not enabled

func _start() -> void:
	player.stop();completed=not enabled
	if not enabled:return
	var clip: Dictionary=manifest.get("clips",{}).get(current_id,{})
	var path=str(clip.get("path",""))
	if path.is_empty() or not ResourceLoader.exists(path):
		error="Missing voice clip: "+current_id;completed=true;return
	var stream=load(path) as AudioStream
	if stream==null:completed=true;error="Unreadable voice clip: "+current_id;return
	player.stream=stream;player.play();player.stream_paused=not allowed
	print("SPINLAB_NARRATION step=",current_id," duration_s=",stream.get_length())

func _finished() -> void:completed=true

func is_blocking() -> bool:return enabled and not completed

func replay() -> void:
	if not current_id.is_empty():_start()

func set_enabled(value: bool) -> void:
	enabled=value
	if enabled:replay()
	else:player.stop();completed=true
	if not settings_path.is_empty():
		var settings=ConfigFile.new();settings.set_value("voice","enabled",enabled)
		var result=settings.save(settings_path)
		if result!=OK:error="Voice preference could not be saved: "+error_string(result)

func _exit_tree() -> void:
	if player:player.stop();player.stream=null
