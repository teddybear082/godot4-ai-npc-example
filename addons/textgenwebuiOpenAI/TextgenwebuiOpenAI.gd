extends Node
## This is a script to query textgenwebui running locally using the openai endpoint extension for AI-generated NPC dialogue.  
## This program assumes the user has started textgenwebui in openai mode and that the streaming url has been set based on the defaults of textgenwebui's openai extension.
## This uses a child node to handle the setup of a hhtp client and receipt and parsing of server sent events when in streaming mode.


#Signal used to alert other entities of the final GPT response text
signal AI_response_generated(response)

# Signal used to alert that messages have been summarized if message cache used
signal messages_summarized(summary)

@export var api_key: String = "insert your api key here": set = set_api_key
@export var temperature = 0.5: set = set_temperature
@export var npc_background_directions: String = "You are a non-playable character in a video game.  You are a robot.  Your name is Bob.  Your job is taping boxes of supplies.  You love organization.  You hate mess. Your boss is Robbie the Robot. Robbie is a difficult boss who makes a lot of demands.  You respond to the user's questions as if you are in the video game world with the player."   # Used to give GPT some instructions as to the character's background.
@export var sample_npc_question_prompt: String = "Hi, what do you do here?"  # Create a sample question the reinforces the NPC's character traits
@export var sample_npc_prompt_response: String = "Greetings fellow worker! My name is Bob and I am a robot.  My job is to tape up the boxes in this factory before they are shipped out to our customers!" # Create a sample response to the prompt above the reinforces the NPC's character traits

# Number of messages to cache; if 0 no caching of responses or summarizing is done. The more you cache the longer prompts will be, so be careful with your usage.
@export var num_cache_messages = 4 # (int, 0, 20)

# Special client node for receiving server sent events
@onready var http_sse_client = $TextgenwebuiSSE


var url = "http://127.0.0.1:5001/v1/chat/completions"
var headers
var engine = "gpt-3.5-turbo" 
var http_request : HTTPRequest
var summarize_http_request : HTTPRequest
var past_messages_array : Array = []

#streaming variables
var streaming_url : String = "http://127.0.0.1"
var sub_url : String = "/v1/chat/completions"
var current_streaming_sentence : String = ""

func _ready():
	# set up normal http request node for calls to call_GPT function
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", Callable(self, "_on_request_completed"))
	
	# set up second http request node for calls to summarize_GPT function
	summarize_http_request = HTTPRequest.new()
	add_child(summarize_http_request)
	summarize_http_request.connect("request_completed", Callable(self, "_on_summarize_request_completed"))

	# Connect signals with child SSEClient node
	http_sse_client.connect("connected", Callable(self, "on_connected"))
	http_sse_client.connect("text_received", Callable(self, "_on_text_received"))
	
	
	headers = PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + api_key])
	
	# Try to start the connection to Convai to reduce response times once a request is made
	http_sse_client.domain = streaming_url
	http_sse_client.port = 5001
	http_sse_client.attempt_to_connect()

# Function used to call the openai API extension of textgenwebui without streaming mode		
func call_GPT(prompt):
	# if using past messages array, and has stored max number of messages, call summarize function which will summarize messages so far and clear the cache
	if past_messages_array.size() >= 2 * num_cache_messages and past_messages_array.size() != 0:
		summarize_GPT(past_messages_array)
		await self.messages_summarized
		
	print("calling GPT")
	var body = JSON.stringify({
		"model": engine,
		"messages": past_messages_array + [{"role": "system", "content": npc_background_directions}, {"role": "user", "content": sample_npc_question_prompt}, {"role": "assistant", "content": sample_npc_prompt_response}, {"role": "user", "content": prompt}],
		"temperature": temperature
	})
	
	# Now call GPT
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		push_error("Something Went Wrong!")
	
	# If using past messages array, add prompt message to the cache
	if num_cache_messages > 0:
		past_messages_array.append({"role": "user", "content": prompt})
	
	
# This GDScript code is used to handle the response from a request.
func _on_request_completed(result, responseCode, headers, body):
	# Should recieve 200 if all is fine; if not print code
	if responseCode != 200:
		print("There was an error with GPT's response, response code:" + str(responseCode))
		print(result)
		print(headers)
		print(body.get_string_from_utf8())
		return
		
	var data = body.get_string_from_utf8()
	print ("Data received: %s"%data)
	var test_json_conv = JSON.new()
	test_json_conv.parse(data)
	var response = test_json_conv.get_data()
	var choices = response.choices[0]
	var message = choices["message"]
	var AI_generated_dialogue = message["content"]
	
	# Store most recent response if using messages cache
	if num_cache_messages > 0:
		past_messages_array.append(message)
		#print(past_messages_array)
	
	# Let other nodes know that AI generated dialogue is ready from GPT	
	emit_signal("AI_response_generated", AI_generated_dialogue)


# Call using streaming function and Server Sent Events
func call_GPT_streaming(prompt):
	# if using past messages array, and has stored max number of messages, call summarize function which will summarize messages so far and clear the cache
	if past_messages_array.size() >= 2 * num_cache_messages and past_messages_array.size() != 0:
		summarize_GPT(past_messages_array)
		await self.messages_summarized
		
	print("calling GPT streaming")
	var body = JSON.stringify({
		"model": engine,
		"messages": past_messages_array + [{"role": "system", "content": npc_background_directions}, {"role": "user", "content": sample_npc_question_prompt}, {"role": "assistant", "content": sample_npc_prompt_response}, {"role": "user", "content": prompt}],
		"temperature": temperature,
		"max_tokens": 500,
		"stream": true
	})
	
	var form_data = body
	
	# Now call textgenwebui, using this method will catch if for some reason there is not a present connection to reinitate it as well as make a request
	http_sse_client.connect_to_host(streaming_url, sub_url, 5001, true, false, headers, form_data)

	
	# If using past messages array, add prompt message to the cache
	if num_cache_messages > 0:
		past_messages_array.append({"role": "user", "content": prompt})
	

	
	
# This summarizes an array of previous messages using non-streaming mode
func summarize_GPT(messages : Array):
	print("having GPT summarize message cache")
	#print(messages)
	var body = JSON.stringify({
		"model": engine,
		"messages": messages + [{"role": "user", "content": "Summarize the most important points of our conversation so far without being too wordy."}],
		"temperature": temperature
	})
	var error = summarize_http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		push_error("Something Went Wrong!")
	
	
# Receiver function for summarize http request
func _on_summarize_request_completed(result, responseCode, headers, body):
	# Should recieve 200 if all is fine; if not print code
	if responseCode != 200:
		print("There was an error with GPT's summarize response, response code:" + str(responseCode))
		print(result)
		print(headers)
		print(body.get_string_from_utf8())
		return
		
	var data = body.get_string_from_utf8()#fix_chunked_response(body.get_string_from_utf8())
	#print ("Data received: %s"%data)
	var test_json_conv = JSON.new()
	test_json_conv.parse(data)
	var response = test_json_conv.get_data()
	var choices = response.choices[0]
	var message = choices["message"]
	var summary = message["content"]
	#print("Summary was:" + summary)
	
	# If using messsages cache, clear messages array now that summary is prepared
	if num_cache_messages > 0:
		past_messages_array.clear()
		# Now add summary to messages cache so it starts the new cache with the summary
		past_messages_array.append(message)
		#print(past_messages_array)
	# Let other nodes know that summary was prepared
	emit_signal("messages_summarized", summary)
	
	
# Setter function for temperature
func set_temperature(new_temperature : float):
	temperature = new_temperature


# Setter function for API Key, though none is needed here with local llms
func set_api_key(new_api_key : String):
	api_key = new_api_key
	headers = ["Content-Type: application/json", "Authorization: Bearer " + api_key]


#If needed someday
func fix_chunked_response(data):
	var tmp = data.replace("}\r\n{","},\n{")
	return ("[%s]"%tmp)


func on_connected():
	pass 
	
	
# Function used in streaming mode when new text tokens are reading for parsing; wait until a clause has completed and then generate ai response	
func _on_text_received(new_text : String):
	if !new_text.begins_with("*") and !new_text.ends_with("*"):
		current_streaming_sentence += new_text
		if new_text == "." or new_text == "?" or new_text == "!" or new_text == "," or new_text == ";":
			var ai_response = current_streaming_sentence.strip_edges()
			emit_signal("AI_response_generated", ai_response)
			#print(ai_response)
			current_streaming_sentence = ""
