extends Node
# This node implements the OpenAI Whisper API for getting text from speech.
# It allows capture of a mono audio wav file and then uses the godot http file post addon to post form-data to the API.
# In response, it generates text and emits a signal to alert other nodes.


# Signal emitted with free text that is generated by transcription of player speech
signal whisper_speech_to_text_received(text)

@export var api_key: String = "insert your whisper api key": set = set_api_key
@onready var godothttpfilepost = preload("res://addons/godot-httpfilepost/HTTPFilePost.gd")
var record_effect = null
var request
var micrecordplayer
var endpoint
var interface_enabled : bool = false
var can_send_audio_request : bool = true
var save_path : String

# Create the necessary bus and audio nodes for speech capture to work.
func _ready():
	#api_key= "put your whisper api key here"
	
	# Make sure audio input is enabled even if program is not set to otherwise to prevent inadvertent errors in use
	ProjectSettings.set_setting("audio/driver/enable_input", true)
	
	endpoint = "https://api.openai.com/v1/audio/transcriptions"
	
	var current_number = 0
	while AudioServer.get_bus_index("WhisperMicRecorder" + str(current_number)) != -1:
		current_number += 1

	var bus_name = "WhisperMicRecorder" + str(current_number)
	var record_bus_idx = AudioServer.bus_count

	AudioServer.add_bus(record_bus_idx)
	AudioServer.set_bus_name(record_bus_idx, bus_name)

	record_effect = AudioEffectRecord.new()
	AudioServer.add_bus_effect(record_bus_idx, record_effect)

	AudioServer.set_bus_mute(record_bus_idx, true)
	
	micrecordplayer = AudioStreamPlayer.new()
	add_child(micrecordplayer)
	micrecordplayer.bus = bus_name
	
	# If godothttpfilepost addon is not present, turn ability to send audio request off
	if godothttpfilepost == null:
		can_send_audio_request = false
	
	# If can send audio request and godot file post addon is present set up file post for form-data capability	
	if can_send_audio_request == true:
		request = godothttpfilepost.new()
		add_child(request)
		request.timeout = 10.0
		request.use_threads = true
		request.connect("request_completed", Callable(self, "_on_whisper_request_completed"))
	


func call_whisper(audio_file_path):
	if !can_send_audio_request:
		print("Error, tried calling whisper, but required component [HTTPFilePost addon and script] is missing.")
		return
		
	print("calling whisper with audio file prompt")
	
	# Body of request to whisper
	var body = {
		"model": "whisper-1",
		"language": "en",
		"response_format": "text"
	}
	
	var headers = ["Authorization: Bearer " + api_key]
	# This is the format godothttpfilepost expects:
	#post_file(url: String, field_name: String, file_name: String, file_path: String, post_fields: Dictionary = {}, content_type: String = "", custom_headers: Array = [])
	
	request.post_file(endpoint, "file", "audio.wav", audio_file_path, body, "audio/wav", headers)


# Function to receive response to whisper API call with audio file prompt
func _on_whisper_request_completed(result, responseCode, headers, body):
	# Should recieve 200 if all is fine; if not print code
	if responseCode != 200:
		print("There was an error with Whisper API's response, response code:" + str(responseCode))
		print(result)
		print(headers)
		print(body.get_string_from_utf8())
		return
	
	print("Whisper text generated: " + body.get_string_from_utf8())
	emit_signal("whisper_speech_to_text_received", body.get_string_from_utf8())	
		
		
# This is needed to activate the voice commands in the node.
func activate_voice_commands(value):
	print("WhisperAPI voice commands activated")
	if can_send_audio_request == false:
		print("Tried to activate Wit Voice Commands but they are deactivated.")
		return

	interface_enabled = value
	if value:
		if micrecordplayer.stream == null:
			micrecordplayer.stream = AudioStreamMicrophone.new()
		if !micrecordplayer.playing:
			micrecordplayer.play()
	else:	
		if micrecordplayer.playing:
			micrecordplayer.stop()

		micrecordplayer.stream = null

# Start voice capture		
func start_voice_command():
	print("Reading sound")
	if !micrecordplayer.playing:
		micrecordplayer.play()
	record_effect.set_recording_active(true)	
		
		
# End voice capture		
func end_voice_command():
	print("stop reading sound")
	var recording = record_effect.get_recording()
	await get_tree().create_timer(1.0).timeout
	record_effect.set_recording_active(false)
	micrecordplayer.stop()

	if OS.has_feature("editor"):
		save_path = OS.get_user_data_dir().path_join("whisper_audio.wav")
	elif OS.has_feature("android"):
		save_path = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS, false).path_join("whisper_audio.wav")
	else:
		save_path = OS.get_executable_path().get_base_dir().path_join("whisper_audio.wav")
	var check_ok = recording.save_to_wav(save_path)
	#print(check_ok)		
	call_whisper(save_path)
	
	
# Method to set api token from code
func set_api_key(new_api_key : String):
	api_key = new_api_key
	
