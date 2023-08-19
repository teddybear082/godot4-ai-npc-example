extends Control

signal ai_brain_option_chosen(choice)
signal tts_option_chosen(choice)
#signal stt_option_chosen(choice)

# Enum for speech to text choice - note, if convai is chosen, convai will automatically be set as brain
#enum speech_to_text_type {
#	WIT,
#	CONVAI,
#	WHISPER,
#	LOCALWHISPER
#}

# Enum for text to speech choice
enum text_to_speech_type {
	GODOT,
	ELEVENLABS,
	CONVAI,
	WIT,
	XVASYNTH
}

# Enum for AI brain choice
enum ai_brain_type {
	CONVAI,
	GPTTURBO,
	GPT4ALL,
	TEXTGENWEBUI,
	TEXGENWEBUISTREAMING
}

@onready var AIBrainOptionButton : OptionButton = $ColorRect/AIBrainOptionButton
#@onready var STTOptionButton : OptionButton = $ColorRect/STTOptionButton
@onready var TTSOptionButton : OptionButton = $ColorRect/TTSOptionButton

# Called when the node enters the scene tree for the first time.
func _ready():
	# Connect option button item selected signals to receiver function
	AIBrainOptionButton.connect("item_selected", Callable(self, "_on_ai_brain_choice"))
#	STTOptionButton.connect("item_selected", Callable(self, "_on_stt_choice"))
	TTSOptionButton.connect("item_selected", Callable(self, "_on_tts_choice"))
	
	#Populate option buttons with enums
	AIBrainOptionButton.add_item("Convai", 0)
	AIBrainOptionButton.add_item("GPTTurbo", 1)
	AIBrainOptionButton.add_item("GPT4All-PCVR Only", 2)
	AIBrainOptionButton.add_item("TextgenWebUI - PCVR Only", 3)
	AIBrainOptionButton.add_item("TextgenWebUI-Streaming - PCVR Only", 4)
	if OS.has_feature("android"):
		AIBrainOptionButton.set_item_disabled(2, true)
	
		
#	STTOptionButton.add_item("Wit.ai", 0)
#	STTOptionButton.add_item("Convai (Not Working)", 1)
#	STTOptionButton.add_item("Whisper", 2)
#	STTOptionButton.add_item("Whisper.cpp(local)-PCVR Only", 3)
#	if OS.has_feature("android"):
#		STTOptionButton.set_item_disabled(3, true)
	
	TTSOptionButton.add_item("Godot-PCVR only", 0)
	TTSOptionButton.add_item("Eleven Labs", 1)
	TTSOptionButton.add_item("Convai", 2)
	TTSOptionButton.add_item("Wit.ai", 3)
	TTSOptionButton.add_item("XVASynth-PCVR only", 4)
	if OS.has_feature("android"):
		TTSOptionButton.set_item_disabled(0, true)
		TTSOptionButton.set_item_disabled(4, true)
			
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
	

func _on_ai_brain_choice(selection):
	emit_signal("ai_brain_option_chosen", selection)
	

func _on_tts_choice(selection):
	emit_signal("tts_option_chosen", selection)
	

#func _on_stt_choice(selection):
#	emit_signal("stt_option_chosen", selection)
