extends Node
## This is a script to query a local Whisper install for speech to text.  
## It expects that you have the whisper.cpp release in your user (editor) or executable (release) directory
## This only works for windows for now.


# Signal emitted with free text that is generated by transcription of player speech
signal whisper_speech_to_text_received(text)
var micrecordplayer : AudioStreamPlayer
var record_effect : AudioEffectRecord = null
var interface_enabled : bool = false
var save_path : String
var executable_path : String
var model_path : String
var Whisper_executable : String


func _ready():
	# Audio request ready stuff to allow recording of microphone
	var current_number = 0
	while AudioServer.get_bus_index("LocalWhisperMicRecorder" + str(current_number)) != -1:
		current_number += 1

	var bus_name = "LocalWhisperMicRecorder" + str(current_number)
	var record_bus_idx = AudioServer.bus_count

	AudioServer.add_bus(record_bus_idx)
	AudioServer.set_bus_name(record_bus_idx, bus_name)

	record_effect = AudioEffectRecord.new()
	AudioServer.add_bus_effect(record_bus_idx, record_effect)

	AudioServer.set_bus_mute(record_bus_idx, true)
	
	micrecordplayer = AudioStreamPlayer.new()
	add_child(micrecordplayer)
	micrecordplayer.bus = bus_name
	
	# Gets user directory path
	if OS.has_feature("editor"):
		executable_path = OS.get_user_data_dir()
	# This script will not work on android right now - maybe someday there will be an android release of GPT4All!
	elif OS.has_feature("android"):
		print("Whisper local option will not function on android.")
		executable_path = OS.get_executable_path()
	# Gets executable path if running outside of editor
	else:
		executable_path = OS.get_executable_path().get_base_dir()
	Whisper_executable = executable_path.path_join("main.exe")
	model_path = executable_path.path_join("ggml-model-whisper-base.en-q5_1.bin")


# Function to call local whisper install for transcription
func call_local_whisper(audiofilepath):
	print("calling local whisper with audio file prompt")
	var arguments = ["-m", model_path, "-f", audiofilepath]
	#print(Whisper_executable)
	#print(arguments)
	var output = []
	var exit_code = OS.execute(Whisper_executable, arguments, output, true, false)
	var response = output[0]
	#print(response)
	var response_after_timestamp = response.get_slice_count("]")
	var text_after_timestamp = response.get_slice("]", response_after_timestamp-1)
	#print(text_after_timestamp)
	var final_text = text_after_timestamp.get_slice("whisper_print_timings", 0)
	var final_text_cleaned = final_text.strip_edges()
	print(final_text_cleaned)
	emit_signal("whisper_speech_to_text_received", final_text_cleaned)
		
		
# This is needed to activate the voice commands in the node.
func activate_voice_commands(value):
	interface_enabled = value
	if value:
		if micrecordplayer.stream == null:
			micrecordplayer.stream = AudioStreamMicrophone.new()
		if !micrecordplayer.playing:
			micrecordplayer.play()
	else:	
		if micrecordplayer.playing:
			micrecordplayer.stop()

		micrecordplayer.stream = null
	

# Start voice capture		
func start_voice_command():
	print ("Reading sound")
	if !micrecordplayer.playing:
		micrecordplayer.play()
	record_effect.set_recording_active(true)
		
		
# End voice capture		
func end_voice_command():
	print("stop reading sound")
	var recording = record_effect.get_recording()
	await get_tree().create_timer(1.0).timeout
	record_effect.set_recording_active(false)
	micrecordplayer.stop()
#	print(recording)
#	print(recording.format)
#	print(recording.mix_rate)
#	print(recording.stereo)
	var data = recording.get_data()
#	print(data.size())
	var new_data = convert_sound_data_to_16000(data)
	recording.data = new_data
	recording.mix_rate = 16000
#	print(recording.mix_rate)
	if OS.has_feature("editor"):
		save_path = OS.get_user_data_dir().path_join("local_whisper_audio.wav")
	elif OS.has_feature("android"):
		save_path = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS, false).path_join("local_whisper_audio.wav")
	else:
		save_path = OS.get_executable_path().get_base_dir().path_join("local_whisper_audio.wav")
	var check_ok = recording.save_to_wav(save_path)
	#print(check_ok)
	var thread = Thread.new()
	var err = thread.start(Callable(self, "call_local_whisper").bind(save_path))
			

#If needed someday
func fix_chunked_response(data):
	var tmp = data.replace("}\r\n{","},\n{")
	return ("[%s]"%tmp)


# Function to convert recorded sound data to 16000 mix rate which is what is required by whisper (Assist by ChatGPT on this one!)
func convert_sound_data_to_16000(data: PackedByteArray) -> PackedByteArray:
	var input_mix_rate = 48000
	var output_mix_rate = 16000
	var input_frames = data.size() / 2  # each sample is 2 bytes (16 bits)
	var output_frames = int(input_frames * output_mix_rate / input_mix_rate)
	var output_data = PackedByteArray()

	for i in range(output_frames):
		var input_index = int(i * input_frames / output_frames) * 2
		output_data.append(data[input_index])
		output_data.append(data[input_index + 1])
	return output_data