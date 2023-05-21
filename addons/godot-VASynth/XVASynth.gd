extends Node
## This is a script that allows the running of a local XVASynth server via a .bat file and then queries it for TTS
## This is windows-only and requires that you have XVASynth installed on your computer and have edited the .bat file to point to your install location
## This is only compatible with FastPitch1.1 models as of right now because most of the variables related to those models are hard-coded in the script.
signal xvasynth_model_loaded
signal xvasynth_stored_voicefile(file_path)
signal xvasynth_voice_sample_played()
@export var autoload_model : bool = true
@export var model_path : String = "D:/DExtraSteamGames/steamapps/common/xVASynth/resources/app/models/GodofWar/kratos": set=set_model, get=get_model
@onready var userdirectory : String = OS.get_user_data_dir()
@onready var executabledirectory : String = OS.get_executable_path().get_base_dir()
var model_ready : bool = false
var xvasynthplayer : AudioStreamPlayer
var xvasynthaudiostream : AudioStreamWAV
var outfile : String = ""
# To control output speed of sound
var pace : float = 1.00: set=set_pace
# To allow for queuing of prompts and audio files
var stored_prompts : Array = []
var stored_audio : Array = []
var ok_to_synthesize : bool = true

# Set up an audio player to play audio from xvasynth
func _ready():
	xvasynthplayer = AudioStreamPlayer.new()
	add_child(xvasynthplayer)
	xvasynthaudiostream = AudioStreamWAV.new()
	xvasynthplayer.stream = xvasynthaudiostream
	xvasynthaudiostream.mix_rate = 22050
	xvasynthaudiostream.stereo = false
	xvasynthaudiostream.format = AudioStreamWAV.FORMAT_16_BITS
	xvasynthplayer.connect("finished", Callable(self, "_on_xvasynth_player_finished"))

# Initiate the xvasynth API server using a bat file, note this must be called inside of a thread function otherwise it will lock up Godot
func initiate_XVASynth():
	print("Initiating XVASynth")
	var userdirectory : String = OS.get_user_data_dir()
	var batfilepath : String = userdirectory.path_join("xvasynthserverstart.bat")
	var arguments = PackedStringArray([])
	var output : Array = []
	OS.execute(batfilepath, arguments, output)
	

# Load the voice file selected by the user to xvasynth
func load_XVASynth_model():
	var http_request : HTTPRequest = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", Callable(self, "_on_XVASynth_model_request_completed"))
	var body = JSON.stringify({
		"outputs": null, "model": model_path, "modelType": "FastPitch1.1", "version": "2.0", "base_lang": "en", "pluginsContext": "{}"
	})
	var headers = PackedStringArray([])
	http_request.request("http://localhost:8008/loadModel", headers, HTTPClient.METHOD_POST, body)
	

# Handle response from xvasynth server to load model
func _on_XVASynth_model_request_completed(result, responseCode, headers, body):
	if responseCode != 200:
		print("There was an error with XVASynth's API's response, response code:" + str(responseCode))
		print(result)
		print(headers)
		print(body.get_string_from_utf8())
		return
	
	print("VASynth model initialized")
	model_ready = true
	emit_signal("xvasynth_model_loaded")


# Queue prompt to generate speech audio file from text prompt using vasynth server API
func XVASynth_synthesize(prompt):
	stored_prompts.append(prompt)
	process_XVASynth_prompt_queue()


# Generate audio file from next queued prompt
func XVASynth_synthesize_queued_prompt(prompt):
	var outfile_prefix = "vasynth"
	if stored_audio.size()>0:
		outfile_prefix+=str(stored_audio.size())
	if OS.has_feature("editor"):
		outfile = userdirectory.path_join(outfile_prefix + ".wav")
	elif OS.has_feature("android"):
		print("VASynth will not work on an android build")
		outfile = executabledirectory.path_join(outfile_prefix+".wav")
	else:
		outfile = executabledirectory.path_join(outfile_prefix+".wav")
	var body = JSON.stringify({"sequence": prompt, "pitch": [], "duration": [], "energy":[], "pace": pace, "modelType":"FastPitch1.1", "outfile": outfile, "pluginsContext":"[]", "vocoder": ""})
	var headers = PackedStringArray([])
	var http_request : HTTPRequest = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", Callable(self, "_on_XVASynth_synthesize_request_completed"))
	http_request.request("http://localhost:8008/synthesize", headers, HTTPClient.METHOD_POST, body)
	
		
# Handle response from xvasynth server API to create audio file from text prompt
func _on_XVASynth_synthesize_request_completed(result, responseCode, headers, body):
	if responseCode != 200:
		print("There was an error with XVASynth's API's response, response code:" + str(responseCode))
		print(result)
		print(headers)
		print(body.get_string_from_utf8())
		return
	
	print("VASynth generated an audio file at: " + outfile)
	emit_signal("xvasynth_stored_voicefile", outfile)
	if !xvasynthplayer.playing: #and stored_audio.size() == 0 
		stored_audio.append(outfile)
		XVASynth_play_audio(outfile)
	else:
		queue_XVASynth_audio(outfile)
	ok_to_synthesize = true
	if stored_prompts.size() > 0:
		process_XVASynth_prompt_queue()


# Queue prompt for synthesizing after current prompt completed
func process_XVASynth_prompt_queue():
	if ok_to_synthesize:
		ok_to_synthesize = false
		XVASynth_synthesize_queued_prompt(stored_prompts[0])
		stored_prompts.pop_front()


# Queue audio file for playing after current sound completed
func queue_XVASynth_audio(file_path):
	stored_audio.append(file_path)


# Play the generated audio
func XVASynth_play_audio(file_path):
	var file = FileAccess.open(file_path, FileAccess.READ)
	var data = file.get_buffer(file.get_length())
	xvasynthaudiostream.data = data
	file.close()
	xvasynthplayer.play()
	print("VASynth played audio file at: " + file_path)
	emit_signal("xvasynth_voice_sample_played")


# Receiver function when audio player finishes playing
func _on_xvasynth_player_finished():
	stored_audio.pop_front()
	if stored_audio.size() > 0:
		XVASynth_play_audio(stored_audio[0])
		
	
	
# Set model used for voice
func set_model(new_model_path : String):
	model_ready = false
	model_path = new_model_path
	load_XVASynth_model()


# Get model used for voice
func get_model():
	return model_path


# Set pace to be used for voice
func set_pace(new_pace : float):
	pace = new_pace
