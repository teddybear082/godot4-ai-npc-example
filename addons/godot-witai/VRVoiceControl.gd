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

@export var token: String = "insert_your_wit_api_token_here": set = set_token
@export var microphone_gain_db: float = 1.2
@export var command_minlen_sec: float = 0.3
@export_range (0.1, 0.99, .01) var selected_score : float = 0.85 #Set this from 0-.99 depending on how often you want input diverted into the set intents in wit.ai; lower the value more script defers to those intents vs free text
@export_range (1.0, 20.0, 1.0) var maxlen_sec : float = 10.0 # Max length of audio buffer for recording player speech

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
	if response_code == 200:
		var data = fix_chunked_response(body.get_string_from_utf8())

		#print ("Data received: %s"%data)
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
			selected_text = "Tell me about this factory as if the game world was real and not a video game"
		"asking_player_task":
			selected_text = "What is a mission I can do in this game about factories and packing and shipping boxes? When you answer, pretend the missions are real life and not a video game."
		"how_are_you":
			selected_text = "How are you doing?"
		"say_hi":
			selected_text = "Hi Bob!"
		"what_do_you_do":
			selected_text = "What is your favorite thing to do?"
		"whats_your_name":
			selected_text = "What is your name?"
		# Example of matching intent to an in-game action for a voice command, here used to quit the game, rather than speech
		"quit_game":
			get_parent().save_api_info()
			get_tree().quit()
	#print(selected_text)
	emit_signal("wit_ai_speech_to_text_received", selected_text)
	#print("wit emitted text received signal")


func set_token(new_token : String):
	token = new_token
	
