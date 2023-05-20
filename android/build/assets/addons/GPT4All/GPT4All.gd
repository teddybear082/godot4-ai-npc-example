extends Node
## This is a script to query a local GPT4All Install for AI-generated NPC dialogue. 
## The script expects the model and chat.exe file to be in the same directory
## As user data for the editor version and the executable for other versions.
## This is only compatible with Windows at this time.
## You can get the required chat.exe at https://github.com/kuvaus/LlamaGPTJ-chat/releases
## And the models are anything model compatible with gpt4all (https://github.com/nomic-ai/gpt4all)
## Which are typically models with a ggml- prefix.
## This project comes with an example release (2.0, as of May 17, 2023) of kuvaus's chat.exe and llm (ggml-gpt4all-j-1.3-groovy.bin
## Which are MIT and Apache-2 licensed respectively so can be used for commercial or personal purposes.  


#Signal used to alert other entities of the final GPT response text
signal AI_response_generated(response)

var executable_path : String
var GPT4Allexecutable : String
var model_path : String
var json_path : String
var prompt_template_path : String

# Variables for Server mode - to be used when running GPT4All in local server mode on the same computer
@export var npc_background_directions: String = "You are a non-playable character in a video game.  You are a robot.  Your name is Bob.  Your job is taping boxes of supplies.  You love organization.  You hate mess. Your boss is Robbie the Robot. Robbie is a difficult boss who makes a lot of demands.  You respond to the user's questions as if you are in the video game world with the player."   # Used to give GPT some instructions as to the character's background.
@export	var sample_npc_question_prompt: String = "Hi, what do you do here?"  # Create a sample question the reinforces the NPC's character traits
@export	var sample_npc_prompt_response: String = "Greetings fellow worker! My name is Bob and I am a robot.  My job is to tape up the boxes in this factory before they are shipped out to our customers!" # Create a sample response to the prompt above the reinforces the NPC's character traits
# Called when the node enters the scene tree for the first time.
func _ready():
	# Gets user directory path
	if OS.has_feature("editor"):
		executable_path = OS.get_user_data_dir()
	# This script will not work on android right now - maybe someday there will be an android release of GPT4All!
	elif OS.has_feature("android"):
		print("GPT4All option will not function on android.")
		executable_path = OS.get_executable_path()
	# Gets executable path if running outside of editor
	else:
		executable_path = OS.get_executable_path().get_base_dir()
	GPT4Allexecutable = executable_path.path_join("chat.exe")
	model_path = executable_path.path_join("ggml-gpt4all-j-v1.3-groovy.bin")
	json_path = executable_path.path_join("gpt4all.json")
	prompt_template_path = executable_path.path_join("prompt_template.txt")

# Call to local GPT4All model - thanks so much to derkork on godot discord for helping me figure out OS.execute arguments
func call_GPT4All(prompt):
	var arguments = ["-m", model_path, "-j", json_path, "-p", prompt, "--load_template", prompt_template_path]
	print(GPT4Allexecutable)
	#print(arguments)
	var output = []
	var exit_code = OS.execute(GPT4Allexecutable, arguments, output, true, false)
	# Parse the text of output according to its current format; if this doesn't work correctly, the formatting may have chanced since this code was written.
	#print(output[0])
	var last_part_of_response = output[0].get_slice_count("bytes")
	var final_response = output[0].get_slice("bytes", last_part_of_response-1)
	var final_response_without_breaks = final_response.replace("\n", "")
	var final_response_without_returns = final_response_without_breaks.replace("\r", "")
	var final_response_clean = final_response_without_returns.replace("#", "")
	#print(final_response_clean)
	emit_signal("AI_response_generated", final_response_clean)

# Call GPT4All in server mode (running locally on machine)
func call_GPT4All_server(prompt):
	print("Calling GPT4All in server mode")
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", Callable(self, "_on_request_completed"))
	var url = "http://127.0.0.1:4891/v1/chat/completions"
	var headers = []
	var temperature = 0.5
	var body = JSON.stringify({
		"model": model_path,
		"messages": [{"role": "system", "content": npc_background_directions}, {"role": "user", "content": sample_npc_question_prompt}, {"role": "assistant", "content": sample_npc_prompt_response}, {"role": "user", "content": prompt}],
		"temperature": temperature,
		"stream":false,
		"max_tokens":500
	})
	
	# Now call GPT4All local server
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		push_error("Something Went Wrong!")


# Handle response from call to local server mode GPT4All
func _on_request_completed(result, responseCode, headers, body):
	# Should recieve 200 if all is fine; if not print code
	if responseCode != 200:
		print("There was an error with GPT4All's response, response code:" + str(responseCode))
		print(result)
		print(headers)
		print(body.get_string_from_utf8())
		return
		
	var data = body.get_string_from_utf8()
	#print ("Data received: %s"%data)
	var test_json_conv = JSON.new()
	test_json_conv.parse(data)
	var response = test_json_conv.get_data()
	var choices = response.choices[0]
	var AI_generated_dialogue = choices["text"]
	#print(AI_generated_dialogue)
	emit_signal("AI_response_generated", AI_generated_dialogue)
	
	
# Function to set model name
func set_model(new_model_name : String):
	model_path = executable_path.path_join(new_model_name)
