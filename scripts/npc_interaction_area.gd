extends Area3D

# This area needs a pointer_pressed signal so that the VR function pointer can trigger it,
# And pointer entered and exited signals so it can tell other nodes when the player's pointer enters
# And exits it.
signal pointer_pressed(location)
signal pointer_entered
signal pointer_exited

# Label3D to show player they can interact with the NPC
@onready var interact_label_3D : Label3D = $InteractLabel3D

# Connect enter and exited signals to prompt
func _ready():
	self.connect("pointer_entered", Callable(self, "_on_pointer_entered"))
	self.connect("pointer_exited", Callable(self, "_on_pointer_exited"))


# When VR Player's pointer enters, make interaction label visible. 
func _on_pointer_entered():
	interact_label_3D.visible = true
	
# When VR Player's pointer exits, make interaction label hidden	
func _on_pointer_exited():
	interact_label_3D.visible = false

