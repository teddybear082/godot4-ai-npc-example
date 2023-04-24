extends Node3D

#This script just makes sure the character's idle animation always plays and reports the npc into a AI NPC group

@onready var animation_player : AnimationPlayer = get_node("AnimationPlayer")


func _ready():
	
	animation_player.connect("animation_finished", Callable(self, "_on_animation_finished"))
	animation_player.play("idle")
	

func _on_animation_finished(animation):
	animation_player.play("idle")
