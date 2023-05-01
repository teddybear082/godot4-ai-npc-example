extends Node

## This code is based on code shared by VRWorkout found here: https://github.com/mgschwan/godot_witai_voiceinterface
## License is MIT license
## This code has functions to capture the player's microphone input, then send it to wit.ai for processing of speech to text
## and then send either a pre-determined intent set in wit.ai to GPT or, if no pre-set intent is found, send the free text
## to a signal to be handled by the rest of the program.  The idea is the pre-determined intents would be common player commands or questions to the NPC that can then be
## funneled into the best possible prompt for that scenario rather than leaving everything to messier free text.
## In this demo, wit.ai's output is used as an input for a GPT-3.5-turbo query but you could use a different AI response generator instead by connecting to the signals here.  
## NOTE: For this to work you need "Enable audio input" as checked "On" in the Project Settings / Audio menu.

# Signal emitted for wit.ai defined intent that was found from speech; connecting to this signal could be used for defdined voice commands in game
signal voice_command(command)

# Signal emitted with free text that is generated either by matching free text to correspond with intent found or transcription of player speech
signal wit_ai_speech_to_text_received(text)

# Signal emitted when receiving dictionary of voices from wit
signal wit_ai_voices_available(voices_dictionary)

# Signal used to alert other entities that voice sample was played
signal wit_voice_sample_played

@export var token: String = "insert_your_wit_api_token_here": set = set_token
@export var microphone_gain_db: float = 1.2
@export var command_minlen_sec: float = 0.3
@export_range (0.1, 0.99, .01) var selected_score : float = 0.85 #Set this from 0-.99 depending on how often you want input diverted into the set intents in wit.ai; lower the value more script defers to those intents vs free text
@export_range (1.0, 20.0, 1.0) var maxlen_sec : float = 10.0 # Max length of audio buffer for recording player speech
# Array of standard convai voices as of creation of this script (April 2023): https://docs.convai.com/api-docs/reference/core-api-reference/standalone-voice-api/text-to-speech-api
var wit_tts_voices : Array = [
"Charlie",
"Cooper",
"Prospector",
"Rebecca",
"Vampire",
"wit/Cael",
"wit/Cam",
"wit/Carl",
"wit/Cody",
"wit/Colin",
"wit/Connor",
"wit/Railey",
"wit/Remi",
"wit/Rosie",
"wit/Rubie"
]

# Specific selection for standalone voice - this can be used without the array, but the array may be useful for randomizing results or otherwise choosing appropriate selection in code
@export_enum("Charlie",
"Cooper",
"Prospector",
"Rebecca",
"Vampire",
"wit/Cael",
"wit/Cam",
"wit/Carl",
"wit/Cody",
"wit/Colin",
"wit/Connor",
"wit/Railey",
"wit/Remi",
"wit/Rosie",
"wit/Rubie") var wit_tts_voice_selection : String = "Cooper": set = set_wit_tts_voice

# Speech speed used for wit TTS if using wit TTS
@export_range (10, 400, 1) var wit_tts_speech_speed : int = 100 : set = set_wit_tts_speech_speed
# Speech pitch used for wit TTS if using wit TTS
@export_range (25, 400, 1) var wit_tts_speech_pitch : int = 100 : set = set_wit_tts_speech_pitch

var capture_effect = null

var request

var audio_player

var audio_buffer = PackedByteArray()
var audio_buffer_pos = 0

var endpoint
var is_ssl = true
var target_rate = 16000
var actual_rate = AudioServer.get_mix_rate()
var sending = false	
var interface_enabled = false
var voices_query_request = HTTPRequest
var stored_streamed_audio : PackedByteArray = []
var wit_speech_player : AudioStreamPlayer
var wit_stream : AudioStreamMP3

func _ready():
	#token = "put your wit.ai token here"
	# Make sure audio input is enabled even if program is not set to otherwise to prevent inadvertent errors in use
	ProjectSettings.set_setting("audio/driver/enable_input", true)
	
	endpoint = "https://api.wit.ai/speech"
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
	
	# Optional: connect to voice command signal internally to match intents found
	self.connect("voice_command", Callable(self, "_on_voice_command_detected"))
	
	voices_query_request = HTTPRequest.new()
	add_child(voices_query_request)
	voices_query_request.connect("request_completed", Callable(self, "_available_voices_received"))
	
	# Create audio player node for speech playback
	wit_speech_player = AudioStreamPlayer.new()
	wit_speech_player.pitch_scale = 1.0
	wit_speech_player.connect("finished", Callable(self, "_on_speech_player_finished"))
	add_child(wit_speech_player)
	wit_stream = AudioStreamMP3.new()	
		
		
# This is needed to activate the voice commands in the node.
func activate_voice_commands(value):
	interface_enabled = value
	if value:
		if audio_player.stream == null:
			audio_player.stream = AudioStreamMicrophone.new()
		capture_effect.clear_buffer()
		audio_player.play()
	else:	
		if audio_player.playing:
			audio_player.stop()

		audio_player.stream = null
	
	
func _process(delta):
	if capture_effect and sending:
		var data: PackedVector2Array = capture_effect.get_buffer(capture_effect.get_frames_available())
		var sample_skip = actual_rate/target_rate 
		var samples = ceil(float(data.size())/sample_skip)
		
		if data.size() > 0:
			var max_value = 0.0
			var min_value = 0.0
			var idx = 0
			var buffer_len = data.size()
			var target_idx = 0
		
			while idx < buffer_len:
				var val =  (data[int(idx)].x + data[int(idx)].y)/2.0
				#var val_discreet = int( clamp( val * 32768, -32768, 32768))
				var val_discreet = int(clamp(val*32768, 0, 32768))
				audio_buffer[2*audio_buffer_pos] = 0xFF & (val_discreet >> 8)
				audio_buffer[2*audio_buffer_pos+1] = 0xFF & val_discreet

				idx += sample_skip
				audio_buffer_pos = min(audio_buffer_pos+1, audio_buffer.size()/2-1)
		
# Start voice capture		
func start_voice_command():
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
			
			#Only process audio if there is enough speech
			#Prevent spurious calls	
		
			#var audio_content = audio_buffer.subarray(0,audio_buffer_pos*2)
			var audio_content = audio_buffer.slice(0, audio_buffer_pos*2)
			# Make request to wit.ai speech endpoint		
			request = HTTPRequest.new()
			add_child(request)
			request.connect("request_completed", Callable(self, "_http_request_completed"))
			var error = request.request_raw("https://api.wit.ai/speech", ["Authorization: Bearer %s"%token, "Content-type: audio/raw;encoding=signed-integer;bits=16;rate=%d;endian=big"%target_rate], HTTPClient.METHOD_POST, audio_content)
			#print(error)
			if error != OK:
				push_error("An error occurred in the HTTP request.")


# Called when the HTTP request to wit.ai is completed.
func _http_request_completed(result, response_code, headers, body):
	# Should recieve 200 if all is fine; if not print code
	if response_code != 200:
		print("There was an error with wit.ai's response, response code:" + str(response_code))
		print(result)
		print(headers)
		print(body.get_string_from_utf8())
		return
		
	if response_code == 200:
		var data = fix_chunked_response(body.get_string_from_utf8())

		print ("Data received: %s"%data)
		var test_json_conv = JSON.new()
		test_json_conv.parse(data)
		var response = test_json_conv.get_data()
		#print("response as parsed json is " + str(response))
		var selected_intent = ""
		var selected_text = ""
		
		
		# Iterate through each potential wit.ai text to speech object
		for r in response:
			# Determine if any pre-set intents were found that exceeded the confidence score, if multiple, identify the best one and send it to GPT
			var intents = r.get("intents",Array())
			for i in intents:
				#print(str(i["confidence"]))
				if i["confidence"] > selected_score:
					selected_score = i["confidence"]
					selected_intent = i["name"]
			if selected_intent:
				print ("Command is: %s"%selected_intent)
				emit_signal("voice_command",selected_intent)	
				return
			# If no pre-set intents were found that exceed the required confidence, send the final response free text to GPT instead
			var is_final = r.get("is_final")
			if is_final == null:
				#print("is final was null for this r in response")
				continue
			if is_final and is_final == true:
				selected_text = r.get("text")
				print("selected_text is " + selected_text)
				emit_signal("wit_ai_speech_to_text_received", selected_text)
			else:
				# if didn't receive anything back, use placeholder to ask user for input again
				emit_signal("wit_ai_speech_to_text_received", "Tell me you didn't hear what I said.")
				return
				
				
#We don't understand chunks so we have to fix it
func fix_chunked_response(data):
	var tmp = data.replace("}\r\n{","},\n{")
	return ("[%s]"%tmp)


#Receiver for when an intent is detected to figure out which one it was and translate it to a GPT prompt
func _on_voice_command_detected(intent: String):
	var selected_text = ""
	match intent:
		# Here you use the intents you have set up in your software as the match values, and provide text for the prompt to use when that intent is detected
		"asking_video_game":
			selected_text = "Tell me about something you have done."
		"asking_player_task":
			selected_text = "What is something a person could do in City 17?"
		"how_are_you":
			selected_text = "How are you doing?"
		"say_hi":
			selected_text = "Hi Gordon!"
		"what_do_you_do":
			selected_text = "What is your favorite thing to do?"
		"whats_your_name":
			selected_text = "What is your name?"
		# Example of matching intent to an in-game action for a voice command, here used to quit the game, rather than speech
		"quit_game":
			get_parent().save_api_info()
			await get_tree().create_timer(1.0).timeout
			get_tree().quit()
	#print(selected_text)
	emit_signal("wit_ai_speech_to_text_received", selected_text)
	#print("wit emitted text received signal")


# Method to set api token from code
func set_token(new_token : String):
	token = new_token
	
	
# Method to get available voices for wit's text to speech
func get_available_voices():
	#print("getting available voices from Wit")
	var voices_query_headers = ["Authorization: Bearer %s"%token]
	var voices_query_endpoint = "https://api.wit.ai/voices"
	var error = voices_query_request.request(voices_query_endpoint, voices_query_headers, HTTPClient.METHOD_GET)
	#print(error)
	if error != OK:
		push_error("An error occurred in the HTTP request.")


func _available_voices_received(result, response_code, headers, body):
	# Should recieve 200 if all is fine; if not print code
	if response_code != 200:
		print("There was an error with wit.ai's availabe voices response, response code:" + str(response_code))
		print(result)
		print(headers)
		print(body.get_string_from_utf8())
		return
		
	var data = body.get_string_from_utf8()
	#print ("Data received: %s"%data)
	var test_json_conv = JSON.new()
	test_json_conv.parse(data)
	var response = test_json_conv.get_data()
	#print(response)
	emit_signal("wit_ai_voices_available", response)
	
	
# Function to set TTS voice
func set_wit_tts_voice(voice_selection : String):
	if !wit_tts_voices.has(voice_selection):
		print("error, wit voice selection string does not exist in wit options")
		return
	wit_tts_voice_selection = voice_selection


# Function to set TTS speech speed	
func set_wit_tts_speech_speed(speed : int):
	wit_tts_speech_speed = speed
	

# Function to set TTS speech pitch
func set_wit_tts_speech_pitch(pitch : int):
	wit_tts_speech_pitch = pitch	
	
	
# Method to call wit's text to speech function with selected voice
func call_wit_TTS(text):
	#print("calling Wit TTS")
	var tts_headers = ["Authorization: Bearer %s"%token, "Content-Type: application/json", "Accept: audio/mpeg"]
	var tts_endpoint = "https://api.wit.ai/synthesize"
	
	# Wit only allows requests up to 250 characters, so we will split multiple sentences into separate HTTP requests if we get over that limit
	if text.length() > 250:
		var dialogue_sections = text.split(".")
		for each_sentence in dialogue_sections:
			if each_sentence == "":
				continue
			var body = JSON.stringify({
				"q": each_sentence,
				"voice": wit_tts_voice_selection
			})
			var tts_request = HTTPRequest.new()
			add_child(tts_request)
			tts_request.connect("request_completed", Callable(self, "_wit_TTS_response_received"))
			var error = tts_request.request(tts_endpoint, tts_headers, HTTPClient.METHOD_POST, body)
			#print(error)
			if error != OK:
				push_error("An error occurred in the HTTP request.")
	
	# If does not exceed limit, do not split up request
	else:
		var body = JSON.stringify({
				"q": text,
				"voice": wit_tts_voice_selection,
				"speed": wit_tts_speech_speed,
				"pitch": wit_tts_speech_pitch
			})
		var tts_request = HTTPRequest.new()
		add_child(tts_request)
		tts_request.connect("request_completed", Callable(self, "_wit_TTS_response_received"))
		var error = tts_request.request(tts_endpoint, tts_headers, HTTPClient.METHOD_POST, body)
		#print(error)
		if error != OK:
			push_error("An error occurred in the HTTP request.")
		
		
func _wit_TTS_response_received(result, response_code, headers, body):
	# Should recieve 200 if all is fine; if not print code
	if response_code != 200:
		print("There was an error with wit.ai's text to speech, response code:" + str(response_code))
		print(result)
		print(headers)
		print(body.get_string_from_utf8())
		return
	
	#print("audio received from wit is")
	#print(body)
	var encoded_audio = body

	stored_streamed_audio.append_array(encoded_audio)
	# If speech player not playing, play streamed audio and delete the queue if any; if audio is currently playing just queue audio for delivery after
	if !wit_speech_player.playing:
		wit_stream.data = stored_streamed_audio
		wit_speech_player.set_stream(wit_stream)
		wit_speech_player.play()
		stored_streamed_audio.resize(0)
		emit_signal("wit_voice_sample_played")	


# Receiver function for when speech player finishes for streaming purposes					
func _on_speech_player_finished():
	# If not using streamed audio endpoint, then stored_streamed_audio will always be zero, if using streaming, then will be over 0 if being queued while player is already playing
	if stored_streamed_audio.size() > 0:
		wit_stream.data = stored_streamed_audio
		wit_speech_player.set_stream(wit_stream)
		wit_speech_player.play()
		stored_streamed_audio.resize(0)
		emit_signal("wit_voice_sample_played")
	
	
