extends Node
## This is a script to query a local GPT4All Install for AI-generated NPC dialogue. 
## The script expects the model and chat.exe file to be in the same directory
## As user data for the editor version and the executable for other versions.
## This is only compatible with windows at this time.
## You can get the required chat.exe at https://github.com/kuvaus/LlamaGPTJ-chat/releases
## And the models are anything model compatible with gpt4all (https://github.com/nomic-ai/gpt4all)
## Which are typically models with a ggml- prefix.
## This project comes with an example release (1.6, as of May 5, 2023) and llm (ggml-gpt4all-j-1.3-groovy.bin
## Which are MIT and Apache-2 licensed respectively so can be used for commercial or personal purposes.  


#Signal used to alert other entities of the final GPT response text
signal AI_response_generated(response)

var executable_path : String
var GPT4Allexecutable : String
var model_path : String
var json_path : String
var prompt_template_path : String

# Called when the node enters the scene tree for the first time.
func _ready():
	# Gets user directory path
	if OS.has_feature("editor"):
		executable_path = OS.get_user_data_dir()
	# This script will not work on android right now - maybe someday there will be an android release of GPT4All!
	elif OS.has_feature("android"):
		print("GPT4All option will not function on android.")
	# Gets executable path if running outside of editor
	else:
		executable_path = OS.get_executable_path().get_base_dir()
	GPT4Allexecutable = executable_path.path_join("chat.exe")
	#model_path = executable_path.path_join("ggml-gpt4all-j-v1.3-groovy.bin")
	model_path = executable_path.path_join("ggml-gpt4all-l13b-snoozy.bin")
	json_path = executable_path.path_join("gpt4all.json")
	prompt_template_path = executable_path.path_join("prompt_template.txt")

# Call to local GPT4All model - thanks so much to derkork on godot discord for helping me figure out OS.execute arguments
func call_GPT4All(prompt):
	var arguments = ["-m", model_path, "-j", json_path, "-p", prompt, "--load_template", prompt_template_path]
	print(GPT4Allexecutable)
	#print(arguments)
	var output = []
	var exit_code = OS.execute(GPT4Allexecutable, arguments, output, true, false)
	var response = output[0].get_slice(prompt, 1)
	#print(output)
	#print(response)
	var last_part_of_response = response.get_slice_count(":")
	#print(last_part_of_response)
	var final_response = response.get_slice(":", last_part_of_response-1)
	#print(final_response.c_escape())
	var final_response_without_breaks = final_response.replace("\n", "")
	var final_response_without_returns = final_response_without_breaks.replace("\r", "")
	var final_response_clean = final_response_without_returns.replace("#", "")
	print(final_response_clean)
	emit_signal("AI_response_generated", final_response_clean)


# Function to set model name
func set_model(new_model_name : String):
	model_path = executable_path.path_join(new_model_name)
