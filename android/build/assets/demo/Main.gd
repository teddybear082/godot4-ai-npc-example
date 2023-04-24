extends Node3D

## This is a demo created to showcase a potential example flow of using an AI NPC in VR.
## You need API keys for wit.ai (presently free) and GPT to use this demo.  
## This implementation uses GPT-3.5-turbo since it is pretty cheap.  However, you could sub out the GPT node for 
## a node that implements your preferred generator.
## In this demo, the player can start interacting with the NPC either by pointing at the NPC
## and clicking trigger, or by getting close enough to the NPC and pressing B or Y on the VR controller.
## Messsages are displayed to show when interaction is available as well as when the mic is recording
## or when hte program is waiting for the AI response.



@onready var player = $Player

@onready var player_left_controller : XRController3D = $Player/LeftHandController
@onready var player_right_controller : XRController3D = $Player/RightHandController
@onready var npc_dialogue_enabled_area : Area3D = $AI_NPC/npc_dialogue_enabled_area
@onready var npc_interaction_area : Area3D = $AI_NPC/npc_pointer_interaction_area
@onready var ai_npc_controller : Node = get_node("Godot-AI-NPC-Controller")


# Code to quit if player presses both grip buttons together to avoid more detailed quitting interface.
# In a real game you would make a menu to quit.
func _process(delta):
	if !player_left_controller.is_button_pressed("grip_click"):
		return
		
	if !player_right_controller.is_button_pressed("grip_click"):
		return
		
	if player_left_controller.is_button_pressed("grip_click") and player_right_controller.is_button_pressed("grip_click"):
		ai_npc_controller.save_api_info()
		await ai_npc_controller.options_saved
		get_tree().quit() 
		
		
# Connect signals between AI npc areas and handlers in AI NPC Controller node
func _ready():
	
	# Connect NPC area entered and exited signals to AI NPC Controller node. 
	# Note that the dialogue enabled area node has its collision mask set to 2.  
	# This is the same layer we have put the VR Player's player body node on and no other objects.
	npc_dialogue_enabled_area.connect("body_entered", Callable(ai_npc_controller, "_on_npc_dialogue_enabled_area_entered"))
	npc_dialogue_enabled_area.connect("body_exited", Callable(ai_npc_controller, "_on_npc_dialogue_enabled_area_exited"))

	# Connect pointer clicked function of NPC Interaction area to the AI NPC Controller node.
	# Note that there is a script attached to the NPC Interaction area that creates a "pointer pressed" signal
	# Which the function pointer on the VR Player looks to trigger when its activation button is pressed.
	# Note that the NPC Interaction area is on collision layer 3, which we have set for AI NPCs only.
	# Meanwhile the Function Pointer nodes' collision masks are set to look for layer 3 as well.
	npc_interaction_area.connect("pointer_pressed", Callable(ai_npc_controller, "_on_npc_area_interaction_area_clicked"))

	# Connect player's grip buttons to the AI NPC Controller mode handler function
	player_left_controller.connect("button_pressed", Callable(ai_npc_controller, "_on_player_controller_button_pressed"))
	player_right_controller.connect("button_pressed", Callable(ai_npc_controller, "_on_player_controller_button_pressed"))
