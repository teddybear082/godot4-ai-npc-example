extends Node

# Signal for when speech is generated
signal ElevenLabs_generated_speech

# Your Eleven Labs API key
@export var api_key : String = "insert your Eleven Labs API Key": set = set_api_key

# Character code used for voice to use - insert your proper character code here instead of the placeholder
@export var character_code : String = "nccuBdAiU0VZsr2UBFyD": set = set_character_code

# Whether to use audio stream endpoint
@export var use_stream_mode: bool = false

# The endpoint will actually include the character code below
var endpoint : String = "https://api.elevenlabs.io/v1/text-to-speech/"

# The headers for the request required by Eleven Labs
var headers

# Audiostream player used to play speech
var eleven_labs_speech_player : AudioStreamPlayer

# Audiostream used for speech object produced by API
var eleven_labs_stream

# HTTP Request node used to query Eleven Labs API
var http_request : HTTPRequest

# Stored audio
var stored_streamed_audio : PackedByteArray

# Variables for working with streamed text

# Marks whether request is the first one in a given stream of requests
var first_request : bool = true

# Use to store queue of requests to ensure first in first out
var eleven_tts_request_queue : Array = []


func _ready():
	# Make sure audio input is enabled even if program is not set to otherwise to prevent inadvertent errors in use
	ProjectSettings.set_setting("audio/driver/enable_input", true)
	
	# Create audio player node for speech playback
	eleven_labs_speech_player = AudioStreamPlayer.new()
	add_child(eleven_labs_speech_player)
	eleven_labs_speech_player.connect("finished", Callable(self, "_on_speech_player_finished"))
	# Endpoint and headers change depending on if using stream mode
	if use_stream_mode == true:
		endpoint = endpoint + character_code + "/stream"
		eleven_labs_stream = AudioStreamWAV.new()
		headers = PackedStringArray(["accept: */*", "xi-api-key: " + api_key, "Content-Type: application/json"])
	else:
		endpoint = endpoint + character_code
		eleven_labs_stream = AudioStreamMP3.new()
		headers = PackedStringArray(["accept: audio/mpeg", "xi-api-key: " + api_key, "Content-Type: application/json"])
	
	
# Call Eleven labs API for text to speech	
func call_ElevenLabs(text):
	#print("calling Eleven Labs TTS")
	var body = JSON.stringify({
		"text": text,
		"voice_settings": {"stability": 0, "similarity_boost": 0}
	})
	# Don't queue first request, just send request
	if first_request == true:
		first_request = false
		http_request = HTTPRequest.new()
		add_child(http_request)
		http_request.connect("request_completed", Callable(self, "_on_request_completed"))
		var error = http_request.request(endpoint, headers, HTTPClient.METHOD_POST, body)
		#print(error)
		if error != OK:
			push_error("An error occurred in the HTTP request.")
	# Queue all other sentences to wit to wait to send until after each previous sentence is processed	
	else:
		_queue_eleven_tts_request(body)
		
		
# Called when response received from Eleven Labs		
func _on_request_completed(result, responseCode, headers, body):
	# Should recieve 200 if all is fine; if not print code
	if responseCode != 200:
		print("There was an error with ElevenLabs' response, response code:" + str(responseCode))
		print(result)
		print(headers)
		print(body.get_string_from_utf8())
		return
	
	# Check to see if any requests are waiting to be processed
	_process_request_queue()
	
	stored_streamed_audio.append_array(body)
	# If speech player not playing, play streamed audio and delete the queue if any; if audio is currently playing just queue audio for delivery after
	if !eleven_labs_speech_player.playing:
		eleven_labs_stream.data = stored_streamed_audio
		eleven_labs_speech_player.set_stream(eleven_labs_stream)
		eleven_labs_speech_player.play()
		stored_streamed_audio.resize(0)	
		# Let other nodes know that AI generated dialogue is ready from GPT	
		emit_signal("ElevenLabs_generated_speech")
	
	
# Set new API key
func set_api_key(new_api_key):
	api_key = new_api_key
	if use_stream_mode == true:
		headers = PackedStringArray(["accept: */*", "xi-api-key: " + api_key, "Content-Type: application/json"])
	else:
		headers = PackedStringArray(["accept: audio/mpeg", "xi-api-key: " + api_key, "Content-Type: application/json"])
		
		
# Set new character code		
func set_character_code(new_code):
	character_code = new_code
	if use_stream_mode == true:
		endpoint = "https://api.elevenlabs.io/v1/text-to-speech/" + character_code + "/stream"
	else:
		endpoint = "https://api.elevenlabs.io/v1/text-to-speech/" + character_code


# Receiver function for when speech player finishes					
func _on_speech_player_finished():
	# If not using streamed audio endpoint, then stored_streamed_audio will always be zero, if using streaming, then will be over 0 if being queued while player is already playing
	if stored_streamed_audio.size() > 0:
		eleven_labs_stream.data = stored_streamed_audio
		eleven_labs_speech_player.set_stream(eleven_labs_stream)
		eleven_labs_speech_player.play()
		stored_streamed_audio.resize(0)
		emit_signal("ElevenLabs_generated_speech")


# Internal-only functions used when needing to queue requests, for example where streaming text is used
func _send_queued_tts_request(body):
	var tts_request = HTTPRequest.new()
	add_child(tts_request)
	tts_request.connect("request_completed", Callable(self, "_on_request_completed"))
	var error = tts_request.request(endpoint, headers, HTTPClient.METHOD_POST, body)
	#print(error)
	if error != OK:
		push_error("An error occurred in the HTTP request.")
	
	
# Add text to request queue
func _queue_eleven_tts_request(text):
	eleven_tts_request_queue.append(text)
	
	
# Process next request in line	
func _process_request_queue():
	# If there are requests in the queue and no request is currently being processed, send the next request
	if eleven_tts_request_queue.size() > 0:
		var next_request = eleven_tts_request_queue[0]
		eleven_tts_request_queue.pop_front()
		_send_queued_tts_request(next_request)
	else:
		first_request = true
