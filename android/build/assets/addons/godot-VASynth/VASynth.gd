extends Node
var model_ready = false

# Called when the node enters the scene tree for the first time.
func _ready():
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func initiate_VASynth():
	var userdirectory : String = OS.get_user_data_dir()
	var batfilepath : String = userdirectory.path_join("testvasythbat.bat")
	var arguments = PackedStringArray([])
	var output : Array = []
	OS.execute(batfilepath, arguments, output)


func load_VASynth_model():
	var http_request : HTTPRequest = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", Callable(self, "_on_VASynth_model_request_completed"))
	var body = JSON.stringify({
		'outputs': null, 'model': 'D:/DExtraSteamGames/steamapps/common/xVASynth/resources/app/models/skyrim/sk_femalenord', 'modelType': 'FastPitch1.1', 'version': '2.0', 'base_lang': 'en', 'pluginsContext': '{}'
	})
	var headers = PackedStringArray([])
	http_request.request("http://localhost:8008/loadModel", headers, HTTPClient.METHOD_POST, body)


func _on_VASynth_model_request_completed(result, responseCode, headers, body):
	if responseCode != 200:
		print("There was an error with VASynth's API's response, response code:" + str(responseCode))
		print(result)
		print(headers)
		print(body.get_string_from_utf8())
		return
	
	print("VASynth responded: " + body.get_string_from_utf8())
	model_ready = true

func VASynth_synthesize(prompt):
	var userdirectory : String = OS.get_user_data_dir()
	var outfile = userdirectory.path_join("vasynth.wav")
	var body = JSON.stringify({"sequence": prompt, "pitch": 1.0, "duration": 2.0, "pace": 1, "outfile": outfile, "vocoder": "skyrim/sk_femalenord.hg.pt"})
	var headers = PackedStringArray([])
	var http_request : HTTPRequest = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", Callable(self, "_on_VASynth_synthesize_request_completed"))
	http_request.request("http://localhost:8008/synthesize", headers, HTTPClient.METHOD_POST, body)


func _on_VASynth_synthesize_request_completed(result, responseCode, headers, body):
	if responseCode != 200:
		print("There was an error with VASynth's API's response, response code:" + str(responseCode))
		print(result)
		print(headers)
		print(body.get_string_from_utf8())
		return
	
	print("VASynth responded: " + body.get_string_from_utf8())
