extends Node

## This code sets up the framework to use Textgenwebui's streaming mode, which uses Server Sent Events.
## It is adapted from code in https://github.com/WolfgangSenff/HTTPSSEClient, which is MIT Licensed.
## It is specifically written to capture Textgenwebui's SSE events only that might be relevant for an AI NPC, not for more general purposes.

signal connected
signal connection_error(error)
signal sessionID_received(sessionID)
signal text_received(text)
signal audio_received(audio)
signal action_sequence_received(action_sequence)
signal tag_received(tag)

var httpclient : HTTPClient = HTTPClient.new()
var is_connected : bool = false
var domain : String
var url_after_domain : String
var port : int
var use_ssl : bool
var verify_host : bool
var headers : PackedStringArray
var body
var told_to_connect : bool = false
var connection_in_progress : bool = false
var request_in_progress : bool = false
var is_requested : bool = false
var response_body = PackedByteArray()
var current_responses : Array = []

func connect_to_host(domain : String, url_after_domain : String, port : int = -1, use_ssl : bool = false, verify_host : bool = true, new_headers : PackedStringArray = [], new_body = ""):
	print("Connecting to host")
	self.domain = domain
	self.url_after_domain = url_after_domain
	self.port = port
	self.use_ssl = use_ssl
	self.verify_host = verify_host
	self.headers = new_headers
	self.body = new_body
	told_to_connect = true
	set_process(true)

func attempt_to_connect():
	print("got to attempt to connect")
	var err = httpclient.connect_to_host(domain, port)
	if err == OK:
		emit_signal("connected")
		print("connected after attempt to connect")
		#print(httpclient.get_status())
		is_connected = true
	else:
		emit_signal("connection_error", str(err))
		print("Connection error: " + str(err))

func attempt_to_request(httpclient_status):
	if httpclient_status == HTTPClient.STATUS_CONNECTING or httpclient_status == HTTPClient.STATUS_RESOLVING:
		print("attempt to request failed because status connecting or resolving")
		return
		
	if httpclient_status == HTTPClient.STATUS_CONNECTED:
		print("connected in attempt to request")
		var enhanced_headers = headers + PackedStringArray(["Accept: text/event-stream"])
		#print(enhanced_headers)
		var err = httpclient.request(HTTPClient.METHOD_POST, url_after_domain, enhanced_headers, body)
		if err == OK:
			is_requested = true
			#print("made it to err=OK in attempt to request")
		else:
			print("error in attempt to request: " + str(err))
			
func _process(delta):
	if !told_to_connect:
		return
		
	if !is_connected:
		if !connection_in_progress:
			attempt_to_connect()
			connection_in_progress = true
		return
		
	httpclient.poll()
	
	
	var httpclient_status = httpclient.get_status()
	#print(httpclient_status)
	if !is_requested:
		if !request_in_progress:
			attempt_to_request(httpclient_status)
		return
		
	# attempt to grab chunks of data from textgenwebui streaming
	if httpclient_status == httpclient.STATUS_CONNECTED:
		var peer = httpclient.get_connection()
		if peer != null:
			var bytes_available = peer.get_available_bytes()
			if peer.get_available_bytes() > 0:
				var data_chunk = peer.get_data(bytes_available)
				if data_chunk[1].size() > 0:
					var body : String = data_chunk[1].get_string_from_utf8().strip_edges()
					#print(body)
					#Returns this format: 
					# data: {"id": "chatcmpl-1692376800934870016", "object": "chat.completions.chunk", "created": 1692376800, "model": "TheBloke_Nous-Hermes_Llama2-GGML", "choices": [{"index": 0, "finish_reason": "stop", "message": {"role": "assistant", "content": ""}, "delta": {"role": "assistant", "content": ""}}], "usage": {"prompt_tokens": 195, "completion_tokens": 19, "total_tokens": 214}}
					# The last line is data: [DONE] so that does not end with brackets and signals we are complete if that occurs and should reset httpclient
					if !body.ends_with("}"):
						print("Now restarting connection")
						_restart_connection()
						return
					var lines = body.split("\n")
					for line in lines:
						if line.begins_with("data: "):
							var data = body.substr(5).strip_edges() # Remove "data:" and strip any whitespace
							var test_json_conv = JSON.new()
							var err = test_json_conv.parse(data)
							if err != OK:
								print("error is: " + test_json_conv.get_error_message())#				var data_json = test_json_conv.get_data()
							var data_json = test_json_conv.get_data()
							if "choices" in data_json:
								if data_json["choices"][0]["delta"]["content"] != "":
									emit_signal("text_received", data_json["choices"][0]["delta"]["content"])
									#print("Text: " + data_json["choices"][0]["delta"]["content"])

						
func _restart_connection():
	told_to_connect = false
	is_requested = false
	is_connected = false
	connection_in_progress = false
	request_in_progress = false
	# Close client
	httpclient.close()
	# Set process to false to avoid any unncessary calls when nothing is happening anyway
	set_process(false)
	# Attempt to restart connection so it is all ready for whenever new request is made and lower latency
	attempt_to_connect()

						
func _exit_tree():
	if httpclient:
		httpclient.close()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if httpclient:
			httpclient.close()
		get_tree().quit()
