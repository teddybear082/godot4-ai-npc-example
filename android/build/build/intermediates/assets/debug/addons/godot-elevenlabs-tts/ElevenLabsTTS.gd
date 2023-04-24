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

func _ready():
	# Create httprequest node
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.set_download_file("user://elevenlabs.mp3")
	http_request.connect("request_completed", Callable(self, "_on_request_completed"))
	
	# Create audio player node for speech playback
	eleven_labs_speech_player = AudioStreamPlayer.new()
	add_child(eleven_labs_speech_player)
	
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
	
	# Now call Eleven Labs
	var error = http_request.request(endpoint, headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		push_error("Something Went Wrong!")
		print(error)
		
# Called when response received from Eleven Labs		
func _on_request_completed(result, responseCode, headers, body):
	# Should recieve 200 if all is fine; if not print code
	if responseCode != 200:
		print("There was an error, response code:" + str(responseCode))
		print(result)
		print(headers)
		print(body)
		return
		
	var audio_file_from_eleven = body
	
	var file = FileAccess.open("user://elevenlabs.mp3", FileAccess.READ)
	var bytes = file.get_buffer(file.get_length())
	eleven_labs_stream.data = bytes 
	eleven_labs_speech_player.set_stream(eleven_labs_stream)
	eleven_labs_speech_player.play()
	
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
		endpoint = endpoint + character_code + "/stream"
	else:
		endpoint = endpoint + character_code
