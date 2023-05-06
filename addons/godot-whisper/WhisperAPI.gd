extends Node
# This node implements the OpenAI Whisper API for getting text from speech.
# It allows capture of a mono audio wav file and then uses the godot http file post addon to post form-data to the API.
# In response, it generates text and emits a signal to alert other nodes.


# Signal emitted with free text that is generated either by matching free text to correspond with intent found or transcription of player speech
signal whisper_speech_to_text_received(text)

@export var api_key: String = "insert your whisper api key": set = set_api_key
@export var microphone_gain_db: float = 1.2
@export var command_minlen_sec: float = 0.2
@export_range (1.0, 20.0, 1.0) var maxlen_sec : float = 10.0 # Max length of audio buffer for recording player speech
@onready var godothttpfilepost = preload("res://addons/godot-httpfilepost/HTTPFilePost.gd")
var capture_effect = null
var request
var audio_player
var audio_buffer = PackedByteArray()
var audio_buffer_pos = 0
var endpoint
var target_rate = 16000
var actual_rate = AudioServer.get_mix_rate()
var sending : bool = false	
var interface_enabled : bool = false
var can_send_audio_request : bool = true

# Create the necessary bus and audio nodes for speech capture to work.
func _ready():
	#api_key= "put your whisper api key here"
	
	# Make sure audio input is enabled even if program is not set to otherwise to prevent inadvertent errors in use
	ProjectSettings.set_setting("audio/driver/enable_input", true)
	
	endpoint = "https://api.openai.com/v1/audio/transcriptions"
	audio_buffer.resize(2*target_rate*maxlen_sec)
	
	var current_number = 0
	while AudioServer.get_bus_index("VoiceMicRecorder" + str(current_number)) != -1:
		current_number += 1

	var bus_name = "VoiceMicRecorder" + str(current_number)
	var record_bus_idx = AudioServer.bus_count

	AudioServer.add_bus(record_bus_idx)
	AudioServer.set_bus_name(record_bus_idx, bus_name)

	capture_effect = AudioEffectCapture.new()
	AudioServer.add_bus_effect(record_bus_idx, capture_effect)
	AudioServer.set_bus_mute(record_bus_idx, true)

	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	audio_player.bus = bus_name
	
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
	

# Used to capture mono audio in a form that can be converted to wav by Godot and sent to Whisper
func _process(delta):
	if capture_effect and sending:
		var data: PackedVector2Array = capture_effect.get_buffer(capture_effect.get_frames_available())
		var sample_skip = actual_rate / target_rate
		var samples = ceil(float(data.size()) / sample_skip)

		if data.size() > 0:
			var max_value = 0.0
			var min_value = 0.0
			var idx = 0
			var buffer_len = data.size()
			var target_idx = 0

			while idx < buffer_len:
				var val = (data[int(idx)].x + data[int(idx)].y) / 2.0
				var val_discreet = int(clamp(val * 255, -128, 127))
				audio_buffer[audio_buffer_pos] = 0xFF & val_discreet

				idx += sample_skip
				audio_buffer_pos = min(audio_buffer_pos + 1, audio_buffer.size() - 1)



func call_whisper(audio_file_path):
	if !can_send_audio_request:
		print("Error, tried calling whisper, but required component [HTTPFilePost addon and script] is missing.")
		return
		
	print("calling whisper with audio file prompt")
	
	# There seems to be a bug with convAI's API with sending by voice that sending a session ID other than -1 with the call freezes the response
	# So setting for now always sending -1 as session rather than convai_session_id
	var body = {
		"model": "whisper-1",
		"language": "en",
		"response_format": "text"
	}
	
	var headers = ["Authorization: Bearer " + api_key]
	# This is the format godothttpfilepost expects:
	#post_file(url: String, field_name: String, file_name: String, file_path: String, post_fields: Dictionary = {}, content_type: String = "", custom_headers: Array = [])
	
	request.post_file(endpoint, "file", "audio.wav", audio_file_path, body, "audio/wav", headers)


# Function to receive response to convAI's AI generation using the stream protocol and audio file prompt
func _on_whisper_request_completed(result, responseCode, headers, body):
	# Should recieve 200 if all is fine; if not print code
	if responseCode != 200:
		print("There was an error with ConvAI's voice stream response, response code:" + str(responseCode))
		print(result)
		print(headers)
		print(body.get_string_from_utf8())
		return
	
	print("Whisper text generated: " + body.get_string_from_utf8())
	emit_signal("whisper_speech_to_text_received", body.get_string_from_utf8())	
		
		
		
# This is needed to activate the voice commands in the node.  Right now this is force-deactivated because not working as explained above.
func activate_voice_commands(value):
	print("WhisperAPI voice commands activated")
	if can_send_audio_request == false:
		print("Tried to activate Convai Voice Commands but they are deactivated.")
		return
	interface_enabled = value
	if value:
		if audio_player.stream == null:
			audio_player.stream = AudioStreamMicrophone.new()
			capture_effect.clear_buffer()
		if !audio_player.playing:
			audio_player.play()
	else:	
		if audio_player.playing:
			audio_player.stop()

		audio_player.stream = null
	

# Start voice capture		
func start_voice_command():
	#print ("Reading sound")
	if not sending and interface_enabled:
		#print ("Reading sound")
		sending = true
		audio_buffer_pos = 0	
		
# End voice capture		
func end_voice_command():
	if sending:
		#print ("Finish reading sound")
		sending = false
		
		if audio_buffer_pos / target_rate > command_minlen_sec:
			var audio_content = audio_buffer.slice(0, audio_buffer_pos * 2)
			var save_path = ""
			if OS.has_feature("editor"):
				save_path = "user://whisper_audio.wav"
			elif OS.has_feature("android"):
				save_path = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS, false) + "/whisper_audio.wav"
			else:
				save_path = OS.get_executable_path().get_base_dir() + "/whisper_audio.wav"
			var new_wav_stream = AudioStreamWAV.new()
			new_wav_stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
			new_wav_stream.stereo = false
			new_wav_stream.mix_rate = target_rate
			new_wav_stream.FORMAT_16_BITS # was 8 bits
			new_wav_stream.data = audio_content
			var err = new_wav_stream.save_to_wav(save_path)
			#print(err)
			call_whisper(save_path)
			


# Method to set api token from code
func set_api_key(new_api_key : String):
	api_key = new_api_key
	
