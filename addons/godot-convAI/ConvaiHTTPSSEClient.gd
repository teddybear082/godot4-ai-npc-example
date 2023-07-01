extends Node

## This code sets up the framework to use Convai's streaming mode, which uses Server Sent Events.
## It is adapted from code in https://github.com/WolfgangSenff/HTTPSSEClient, which is MIT Licensed.
## It is specifically written to capture Convai's SSE events only that might be relevant for an AI NPC, not for more general purposes.

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
var body : String
var told_to_connect : bool = false
var connection_in_progress : bool = false
var request_in_progress : bool = false
var is_requested : bool = false
var response_body = PackedByteArray()
var current_responses : Array = []

func connect_to_host(domain : String, url_after_domain : String, port : int = -1, use_ssl : bool = false, verify_host : bool = true, new_headers : PackedStringArray = [], new_body : String = ""):
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
		print(httpclient.get_status())
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
		print(enhanced_headers)
		var err = httpclient.request(HTTPClient.METHOD_POST, url_after_domain, enhanced_headers, body)
		if err == OK:
			is_requested = true
			print("made it to err=OK in attempt to request")
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
		
	var httpclient_has_response = httpclient.has_response()
		
	if httpclient_has_response or httpclient_status == HTTPClient.STATUS_BODY:
		var response_headers = httpclient.get_response_headers_as_dictionary()
		print(response_headers)
		httpclient.poll()
		var chunk = httpclient.read_response_body_chunk()
		if(chunk.size() == 0):
			return
		else:
			response_body = response_body + chunk
		var body = response_body.get_string_from_utf8().strip_edges()
		print("body is: " + body)
		if !body.ends_with("}"):
			return
		response_body.resize(0)
		if body.begins_with("data:"):
			var lines = body.split("\n")
			for line in lines:
				if line.begins_with("data:"):
					var data = line.substr(5).strip_edges() # Remove "data:" and strip any whitespace
					var test_json_conv = JSON.new()
					var err = test_json_conv.parse(data)
					if err != OK:
						print("error is: " + test_json_conv.get_error_message())
					var data_json = test_json_conv.get_data()
					if "text" in data_json:
						if current_responses.find(data_json["text"]) == -1:
							current_responses.append(data_json["text"])
							emit_signal("text_received", data_json["text"])
							print("Text: ", data_json["text"])
					if "sessionID" in data_json:
						var new_session_id = data_json["sessionID"]
						emit_signal("sessionID_received", data_json["sessionID"])
						print("Session ID: ", data_json["sessionID"])
					if "audio" in data_json:
						var AI_generated_audio = data_json["audio"]
						emit_signal("audio_received", AI_generated_audio)
						print("Audio found and ready for decoding")
					if "actionSequence" in data_json:
						var action_sequence = data_json["actionSequence"]
						emit_signal("action_sequence_received", data_json["actionSequence"])
						print("Action found so end of stream.  Action was: " + data_json["actionSequence"])
						_restart_connection()							
					# Tag is the last type of data sent for a request by Convai, so now reset everything to prepare for new request
					if "tag" in data_json:
						current_responses.resize(0)
						emit_signal("tag_received", data_json["tag"])
						print("tag found so end of stream")
						_restart_connection()
						
						
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
