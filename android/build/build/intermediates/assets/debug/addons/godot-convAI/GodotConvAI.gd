extends Node
## This is a script to query convAI for AI-generated NPC dialogue.  
## You need a convAI API key for this to work; put it as a string in the
## export variable for api_key and in the ready script for Godot-AI-NPC Controller
## (if using the demo scene).

# Signal used to alert other entities of the final convAI response text
signal AI_response_generated(response)

# Signal used to alert other entities that voice sample was played
signal convAI_voice_sample_played

@export var api_key: String = "insert your api key": set = set_api_key
@export var convai_session_id: String = "-1": get = get_session_id, set = set_session_id
@export var convai_character_id: String = "insert your convai character code"
@export var voice_response: bool = false
@export var voice_sample_rate: int = 22050
@export var voice_pitch_scale = 1.0
@export var use_standalone_text_to_speech: bool = false: set = set_use_standalone_tts

# Array of standard convai voices as of creation of this script (April 2023): https://docs.convai.com/api-docs/reference/core-api-reference/standalone-voice-api/text-to-speech-api
var convai_standalone_tts_voices : Array = [
	"WUKMale 1",
	"WUKMale 2",
	"WUKFemale 1",
	"WUKFemale 2",
	"WUKFemale 3",
	"WAMale 1",
	"WAMale 2",
	"WAFemale 1",
	"WAFemale 2",
	"WIMale 1",
	"WIMale 2",
	"WIFemale 1",
	"WIFemale 2",
	"WUMale 1",
	"WUMale 2",
	"WUMale 3",
	"WUMale 4",
	"WUMale 5",
	"WUFemale 1",
	"WUFemale 2",
	"WUFemale 3",
	"WUFemale 4",
	"WUFemale 5"
]

# Specific selection for standalone voice - this can be used without the array, but the array may be useful for randomizing results or otherwise choosing appropriate selection in code
@export_enum("WUKMale 1",
	"WUKMale 2",
	"WUKFemale 1",
	"WUKFemale 2",
	"WUKFemale 3",
	"WAMale 1",
	"WAMale 2",
	"WAFemale 1",
	"WAFemale 2",
	"WIMale 1",
	"WIMale 2",
	"WIFemale 1",
	"WIFemale 2",
	"WUMale 1",
	"WUMale 2",
	"WUMale 3",
	"WUMale 4",
	"WUMale 5",
	"WUFemale 1",
	"WUFemale 2",
	"WUFemale 3",
	"WUFemale 4",
	"WUFemale 5") var convai_standalone_tts_voice_selection : String = "WUMale 1": set = set_convai_standalone_tts_voice
#var convai_standalone_tts_voice_selection = "WUMale 1"
@onready var godothttpfilepost = preload("res://addons/godot-httpfilepost/HTTPFilePost.gd")
var url = "https://api.convai.com/character/getResponse" 
var tts_url = "https://api.convai.com/tts/"
var headers
var tts_headers
var voice_file_headers
var http_request : HTTPRequest
var http_client : HTTPClient
var convai_speech_player : AudioStreamPlayer
var convai_stream : AudioStreamWAV
var convai_tts_stream : AudioStreamMP3
var TTS_http_request : HTTPRequest
var http_file_post_request
var stream_http_request : HTTPRequest
var stored_streamed_audio : PackedByteArray = []
var stream_queued_text : String = ""
# Variables for possible voice requests to server
var can_send_audio_request : bool = true
var record_effect : AudioEffectRecord = null
var interface_enabled = false
var recording
var micrecordplayer : AudioStreamPlayer

# Test variables for wit.ai style recording
var sending = false
var microphone_gain_db: float = 1.2
var command_minlen_sec: float = 0.1
var maxlen_sec : float = 10.0 
var capture_effect = null
var audio_buffer = PackedByteArray()
var audio_buffer_pos = 0
var target_rate = 16000
var actual_rate = AudioServer.get_mix_rate()
var save_path = ""	

func _ready():
	# Make sure audio input is enabled even if program is not set to otherwise to prevent inadvertent errors in use
	ProjectSettings.set_setting("audio/driver/enable_input", true)
	
	# Set up normal http request node for calls to call_convAI function
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", Callable(self, "_on_request_completed"))
	
	# Add http client to perform transition from dictionary to form-data needed for convAI API
	http_client = HTTPClient.new()
	
	set_api_key(api_key)
	set_session_id(convai_session_id)
	set_character_id(convai_character_id)
	set_voice_response_mode(voice_response)
	
	# Set up second http request and response signal for call_convAI_TTS function
	TTS_http_request = HTTPRequest.new()
	add_child(TTS_http_request)
	TTS_http_request.connect("request_completed", Callable(self, "_on_TTS_request_completed"))
	
	# Set up third http request anad response signal for call_convAI_stream function
	stream_http_request = HTTPRequest.new()
	add_child(stream_http_request)
	stream_http_request.connect("request_completed", Callable(self, "_on_stream_request_completed"))
	
	# Set up headers for use for normal convAI AI-generated speech responses and standalone text-to-speech
	headers = PackedStringArray(["CONVAI-API-KEY: " + api_key, "Content-Type: application/x-www-form-urlencoded"])
	tts_headers = PackedStringArray(["CONVAI-API-KEY: " + api_key, "Content-Type: application/json"])
	voice_file_headers = PackedStringArray(["CONVAI-API-KEY: " + api_key])
	
	# Create audio player node for speech playback
	convai_speech_player = AudioStreamPlayer.new()
	convai_speech_player.pitch_scale = voice_pitch_scale
	convai_speech_player.connect("finished", Callable(self, "_on_speech_player_finished"))
	add_child(convai_speech_player)
	convai_stream = AudioStreamWAV.new()	
	
	# If godothttpfilepost addon is not present, turn ability to send audio request off
	if godothttpfilepost == null:
		can_send_audio_request = false
	
	# If can send audio request and godot file post addon is present set up file post for form-data capability	
	if can_send_audio_request == true:
		http_file_post_request = godothttpfilepost.new()
		add_child(http_file_post_request)
		http_file_post_request.timeout = 10.0
		http_file_post_request.use_threads = true
		http_file_post_request.connect("request_completed", Callable(self, "_on_voice_stream_request_completed"))
	
	# Audio request ready stuff to allow recording of microphone; right now this is broken because of Godot not being able to record a mono wav file, but leaving here for future potential use
#		ProjectSettings.set_setting("audio/driver/enable_input", true)
#		print("Available input devices found by Convai: " + str(AudioServer.get_input_device_list()))
#		var current_number = 0
#		while AudioServer.get_bus_index("ConvaiMicRecorder" + str(current_number)) != -1:
#			current_number += 1
#
#		var bus_name = "ConvaiMicRecorder" + str(current_number)
#		var record_bus_idx = AudioServer.bus_count
#		print("number of buses for convai node before adding convai bus: " + str(AudioServer.get_bus_count()))
#		AudioServer.add_bus(record_bus_idx)
#		AudioServer.set_bus_name(record_bus_idx, bus_name)
#		print("Convai bus index is: " + str(AudioServer.get_bus_index(bus_name)))
#
#		record_effect = AudioEffectRecord.new()
#		AudioServer.add_bus_effect(record_bus_idx, record_effect)
#		AudioServer.set_bus_mute(record_bus_idx, true)
#
#		micrecordplayer = AudioStreamPlayer.new()
#		add_child(micrecordplayer)
#		micrecordplayer.bus = bus_name
#		micrecordplayer.stream = AudioStreamMicrophone.new()
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

		micrecordplayer = AudioStreamPlayer.new()
		add_child(micrecordplayer)
		micrecordplayer.bus = bus_name
		
		
# Used to call normal convai API endpoint
func call_convAI(prompt):
	var voice_response_string : String
	
	if voice_response == true:
		voice_response_string = "True"
	else:
		voice_response_string = "False"
			
	print("calling convAI with prompt:" + prompt)
	var body = {
		"userText": prompt,
		"charID": convai_character_id,
		"sessionID": convai_session_id,
		"voiceResponse": voice_response_string
	}
	
	var form_data = http_client.query_string_from_dict(body)
	print(form_data)
	
	# Now call convAI
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, form_data)
	
	if error != OK:
		push_error("Something Went Wrong!")
		print(error)
	
	
# This GDScript code is used to handle the response from a request.
func _on_request_completed(result, responseCode, headers, body):
	# Should recieve 200 if all is fine; if not print code
	if responseCode != 200:
		print("There was an error with convAI's response, response code:" + str(responseCode))
		print(result)
		print(headers)
		print(body.get_string_from_utf8())
		return
		
	var data = body.get_string_from_utf8()#fix_chunked_response(body.get_string_from_utf8())
	print ("Data received: %s"%data)
	var test_json_conv = JSON.new()
	test_json_conv.parse(data)
	var response = test_json_conv.get_data()
	var AI_generated_dialogue = response["text"]
	set_session_id(response["sessionID"])
	# Let other nodes know that AI generated dialogue is ready from convAI	
	emit_signal("AI_response_generated", AI_generated_dialogue)
	
	# If voice response is true, get audio from response from convAI and make it a .wav audio stream
	if voice_response == true:
		var AI_generated_audio = response["audio"]
		#print(AI_generated_audio)
		var encoded_audio = Marshalls.base64_to_raw(AI_generated_audio)
		convai_stream.data = encoded_audio
		convai_stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
		convai_stream.format = AudioStreamWAV.FORMAT_16_BITS
		convai_stream.mix_rate = voice_sample_rate
		convai_speech_player.set_stream(convai_stream)
		convai_speech_player.play()
		emit_signal("convAI_voice_sample_played")


# Function to call convAI's standalone text-to-speech API (not using convAI to generate AI response text)
func call_convAI_TTS(text):
	TTS_http_request.set_download_file("user://convaiaudio.mp3")
	if convai_tts_stream == null:
		convai_tts_stream = AudioStreamMP3.new()
	
	var body = JSON.stringify({
		"transcript": text,
		"voice": convai_standalone_tts_voice_selection,
		"filename": "convaiaudio",
		"encoding": "mp3"
	})
	
	# Now call convAI TTS
	var error = TTS_http_request.request(tts_url, tts_headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		push_error("Something Went Wrong!")


# Receiver function for when using call to convAI in standalone text to speech mode (not using Convai for AI generated response content)
func _on_TTS_request_completed(result, responseCode, headers, body):
	# Should recieve 200 if all is fine; if not print code
	if responseCode != 200:
		print("There was an error with convAI's standalone TTS response, response code:" + str(responseCode))
		print(result)
		print(headers)
		print(body.get_string_from_utf8())
		return
		
	#var audio_file_from_convai = body
	
	var file = FileAccess.open("user://convaiaudio.mp3", FileAccess.READ)
	var bytes = file.get_buffer(file.get_length())
	convai_tts_stream.data = bytes 
	convai_speech_player.set_stream(convai_tts_stream)
	convai_speech_player.play()
	
	emit_signal("convAI_voice_sample_played")


# Function to call convAI's AI generation using convAI's stream protocol instead, should be faster for response time
func call_convAI_stream(prompt):
	var voice_response_string : String
	
	if voice_response == true:
		voice_response_string = "True"
		# If we know we're using a voice response AND stream mode, then set the audio stream variables now so they will be ready
		convai_stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
		convai_stream.format = AudioStreamWAV.FORMAT_16_BITS
		convai_stream.mix_rate = voice_sample_rate
	else:
		voice_response_string = "False"
			
	print("calling convAI with prompt:" + prompt)
	var body = {
		"userText": prompt,
		"charID": convai_character_id,
		"sessionID": convai_session_id,
		"voiceResponse": voice_response_string,
		"stream": "True"
	}
	
	var form_data = http_client.query_string_from_dict(body)
	print(form_data)
	
	# Now call convAI
	var error = stream_http_request.request(url, headers, HTTPClient.METHOD_POST, form_data)
	
	if error != OK:
		push_error("Something Went Wrong!")
		print(error)
	


# Function to receive response to convAI's AI generation using the stream protocol
func _on_stream_request_completed(result, responseCode, headers, body):
	# Should recieve 200 if all is fine; if not print code
	if responseCode != 200:
		print("There was an error with ConvAI's stream response, response code:" + str(responseCode))
		print(result)
		print(headers)
		print(body.get_string_from_utf8())
		return
		
	var body_text = body.get_string_from_utf8()
	var lines = body_text.split("\n")
	for line in lines:
		if line.begins_with("data:"):
			var data = line.substr(5).strip_edges() # Remove "data:" and strip any whitespace
			var test_json_conv = JSON.new()
			test_json_conv.parse(data)
			var data_json = test_json_conv.get_data()
			if "text" in data_json:
				print("Text: ", data_json["text"])
				var AI_generated_dialogue = data_json["text"]
				stream_queued_text += AI_generated_dialogue
				
			if "sessionID" in data_json:
				#print("SessionID: ", data_json["sessionID"])
				set_session_id(data_json["sessionID"])
				
			if (voice_response == true) and ("audio" in data_json):
				#print("Audio received: ", data_json["audio"])
				var AI_generated_audio = data_json["audio"]
				#print(AI_generated_audio)
				var encoded_audio = Marshalls.base64_to_raw(AI_generated_audio)
				# Try to eliminate pops in audio
				for n in 60:
					encoded_audio.remove_at(0)
				encoded_audio.resize(encoded_audio.size()-80)
				stored_streamed_audio.append_array(encoded_audio)
				# If speech player not playing, play streamed audio and delete the queue if any; if audio is currently playing just queue audio for delivery after
				if !convai_speech_player.playing:
					convai_stream.data = stored_streamed_audio
					convai_speech_player.set_stream(convai_stream)
					convai_speech_player.play()
					stored_streamed_audio.resize(0)
					emit_signal("convAI_voice_sample_played")	
	
	# Let other nodes know that AI generated dialogue is ready from convAI	
	emit_signal("AI_response_generated", stream_queued_text)
	stream_queued_text = ""

# Function to call convAI's AI generation using convAI's stream with voice protocol instead, here, this is sending an audio file recorded from the microphone above to convAI directly with mono
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


func call_convAI_stream_with_voice():
	if !can_send_audio_request:
		print("Error, tried calling convai stream with voice method, but required component [HTTPFilePost addon and script] is missing.")
		return
		
	var voice_response_string : String
	
	if voice_response == true:
		voice_response_string = "True"
		# If we know we're using a voice response AND stream mode, then set the audio stream variables now so they will be ready
		convai_stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
		convai_stream.format = AudioStreamWAV.FORMAT_16_BITS
		convai_stream.mix_rate = voice_sample_rate
	else:
		voice_response_string = "False"
	
		
	print("calling convAI with audio file prompt")
	
	# There seems to be a bug with convAI's API with sending by voice that sending a session ID other than -1 with the call freezes the response
	# So setting for now always sending -1 as session rather than convai_session_id
	var body = {
		"charID": convai_character_id,
		"sessionID": "-1",
		"voiceResponse": voice_response_string,
		"stream": "True"
	}
	# This is the format godothttpfilepost expects:
	#post_file(url: String, field_name: String, file_name: String, file_path: String, post_fields: Dictionary = {}, content_type: String = "", custom_headers: Array = [])
	
	http_file_post_request.post_file(url, "file", "audio.wav", save_path, body, "audio/wav", voice_file_headers)


# Function to receive response to convAI's AI generation using the stream protocol and audio file prompt
func _on_voice_stream_request_completed(result, responseCode, headers, body):
	# Should recieve 200 if all is fine; if not print code
	if responseCode != 200:
		print("There was an error with ConvAI's voice stream response, response code:" + str(responseCode))
		print(result)
		print(headers)
		print(body.get_string_from_utf8())
		return
		
	var body_text = body.get_string_from_utf8()
	var lines = body_text.split("\n")
	for line in lines:
		if line.begins_with("data:"):
			var data = line.substr(5).strip_edges() # Remove "data:" and strip any whitespace
			var test_json_conv = JSON.new()
			test_json_conv.parse(data)
			var data_json = test_json_conv.get_data()
			if "text" in data_json:
				print("Text: ", data_json["text"])
				var AI_generated_dialogue = data_json["text"]
				stream_queued_text += AI_generated_dialogue
				
			if "sessionID" in data_json:
				#print("SessionID: ", data_json["sessionID"])
				set_session_id(data_json["sessionID"])
				
			if (voice_response == true) and ("audio" in data_json):
				#print("Audio received: ", data_json["audio"])
				var AI_generated_audio = data_json["audio"]
				#print(AI_generated_audio)
				var encoded_audio = Marshalls.base64_to_raw(AI_generated_audio)
				# Try to eliminate pops in audio
				for n in 60:
					encoded_audio.remove_at(0)
				encoded_audio.resize(encoded_audio.size()-80)
				stored_streamed_audio.append_array(encoded_audio)
				# If speech player not playing, play streamed audio and delete the queue if any; if audio is currently playing just queue audio for delivery after
				if !convai_speech_player.playing:
					convai_stream.data = stored_streamed_audio
					convai_speech_player.set_stream(convai_stream)
					convai_speech_player.play()
					stored_streamed_audio.resize(0)
					emit_signal("convAI_voice_sample_played")	
	# Let other nodes know that AI generated dialogue is ready from convAI	
	emit_signal("AI_response_generated", stream_queued_text)
	stream_queued_text = ""	
		
# This is needed to activate the voice commands in the node.  Right now this is force-deactivated because not working as explained above.
func activate_voice_commands(value):
	print("Convai voice commands activated")
	if can_send_audio_request == false:
		print("Tried to activate Convai Voice Commands but they are deactivated.")
		return
	interface_enabled = value
	if value:
		if micrecordplayer.stream == null:
			micrecordplayer.stream = AudioStreamMicrophone.new()
			capture_effect.clear_buffer()
		if !micrecordplayer.playing:
			micrecordplayer.play()
	else:	
		if micrecordplayer.playing:
			micrecordplayer.stop()

		micrecordplayer.stream = null
	

# Start voice capture		
func start_voice_command():
	#print ("Reading sound")
#	micrecordplayer.play()
#	record_effect.set_recording_active(true)
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
			save_path = ""
			if OS.has_feature("editor"):
				save_path = "user://audio.wav"
			elif OS.has_feature("android"):
				save_path = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS, false) + "/audio.wav"
			else:
				save_path = OS.get_executable_path().get_base_dir() + "/audio.wav"
			var new_wav_stream = AudioStreamWAV.new()
			new_wav_stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
			new_wav_stream.stereo = false
			new_wav_stream.mix_rate = target_rate
			new_wav_stream.FORMAT_16_BITS # was 8 bits
			new_wav_stream.data = audio_content
			var err = new_wav_stream.save_to_wav(save_path)
			#print(err)
			call_convAI_stream_with_voice()
			
					
# Setter function for character
func set_character_id(new_character_id : String):
	convai_character_id = new_character_id
	
	
# Setter function for session
func set_session_id(new_session_id : String):
	convai_session_id = new_session_id


# Getter function for session
func get_session_id():
	return convai_session_id


# Setter function for API Key
func set_api_key(new_api_key : String):
	api_key = new_api_key
	headers = PackedStringArray(["CONVAI-API-KEY: " + api_key, "Content-Type: application/x-www-form-urlencoded"])
	tts_headers = PackedStringArray(["CONVAI-API-KEY: " + api_key, "Content-Type: application/json"])
	voice_file_headers = PackedStringArray(["CONVAI-API-KEY: " + api_key])


# Reset session ID so conversation is not remembered
func reset_session():
	convai_session_id = "-1"
	
	
# Determine if AI-generated response content also includes and uses voice file
func set_voice_response_mode(mode : bool):
	voice_response = mode
	

# Set if using convAI solely for standalone text to speech
func set_use_standalone_tts(mode : bool):
	use_standalone_text_to_speech = mode
	if mode == true and TTS_http_request:
		TTS_http_request.set_download_file("user://convaiaudio.mp3")
	elif mode == false and TTS_http_request:
		TTS_http_request.set_download_file("")
	
	# Create tts stream if it has not already been created
	if mode == true and convai_tts_stream == null:
		convai_tts_stream = AudioStreamMP3.new()			


# Allow setting of convai standalone tts voice
func set_convai_standalone_tts_voice(selection : String):
	if !convai_standalone_tts_voices.has(selection):
		print("error, standalone voice selection string does not exist in Convai options")
		return
	convai_standalone_tts_voice_selection = selection
		
		
# Receiver function for when speech player finishes					
func _on_speech_player_finished():
	# If not using streamed audio endpoint, then stored_streamed_audio will always be zero, if using streaming, then will be over 0 if being queued while player is already playing
	if stored_streamed_audio.size() > 0:
		convai_stream.data = stored_streamed_audio
		convai_speech_player.set_stream(convai_stream)
		convai_speech_player.play()
		stored_streamed_audio.resize(0)
		emit_signal("convAI_voice_sample_played")
	
	
func call_convai_speech_to_text_standalone(speechfile_path):
	var http_post_new = godothttpfilepost.new()
	add_child(http_post_new)
	http_post_new.connect("request_completed", Callable(self, "_convai_speech_to_text_request_completed"))
	var body = {
		"enableTimestamps": "False",
	}
	# This is the format godothttpfilepost expects:
	#post_file(url: String, field_name: String, file_name: String, file_path: String, post_fields: Dictionary = {}, content_type: String = "", custom_headers: Array = [])
	
	http_file_post_request.post_file("https://api.convai.com/stt/", "file", "audio.wav", speechfile_path, body, "audio/wav", voice_file_headers)
	
	
# Receiver function for standalone convai speech to text
func convai_speech_to_text_standalone(result, responseCode, headers, body):
	# Should recieve 200 if all is fine; if not print code
	if responseCode != 200:
		print("There was an error with ConvAI's standalone speech to text response, response code:" + str(responseCode))
		print(result)
		print(headers)
		print(body.get_string_from_utf8())
		return
	
	var data = body.get_string_from_utf8()
	print ("Data received: %s"%data)
	var test_json_conv = JSON.new()
	test_json_conv.parse(data)
	var response = test_json_conv.get_data()
	var convai_text_from_speech = response["text"]	
	print("convai generated this text from speech: " + convai_text_from_speech)

#If needed someday
func fix_chunked_response(data):
	var tmp = data.replace("}\r\n{","},\n{")
	return ("[%s]"%tmp)
