# godot4-ai-npc-example
 A Godot 4 Artificial Intelligence (AI) NPC example project.

![ai-npc](https://user-images.githubusercontent.com/87204721/236790720-ab62b7d0-b542-49dd-8ec9-a294a72afe3e.gif)

Example of using various AI and speech technologies to create an AI NPC in Godot 4.  There is also an example of some of these scripts for Godot 3 here: https://github.com/teddybear082/godot-ai-npc-example. 

Will be creating a separate more refined and streamlined final project in collaboration with **DigitalN8m4r3** where you talk to an AI-generated Gordon Freeman in your living room in a different repo.  Stay tuned.  This repo is more an experimental playground for coders and tinkerers than a true consumer final release.

Download the release marked for PCVR to use with windows PCVR; download the release marked for Quest to use with Quest.  

**Instructions and information on use and the various options available are in the Wiki.**

At a high level, included options/scripts are:

* Wit.ai API (requires free API key) (for speech to text and text to speech)

* Convai.com API (requires free or paid API key) (for AI character response generation and text to speech)

* OpenAI GPT 3.5 Turbo API (requires paid API key) (for AI character response generation)

* OpenAI Whisper API (requires paid API key) (for speech to text)

* Whisper.cpp (locally run, no paid API key required) (for speech to text)

* GPT4All - Llama GPT-J-Chat (locally run, no paid API key required) (for AI character response generation)

* Godot Text to Speech (locally run, no paid API Key rquired) (this is just an implementation of Godot 4's native text to speech functionality through Display Server)

**Special Thanks to:**

* The Godot XR / XR tools team for all the VR functions used in this project, for making getting into VR eay (including the built in scripts for pointer, movement, passthrough mode!)

* VR Workout for the initial Wit.ai scripts that got me going getting my voice converted into text and learning how APIs worked

* Convai support team for awesome quick and robust support as I was trying to figure out integrating their API into Godot

* nisovin from the Godot discord who helped me a ton with getting HTTP multipart / form data requests working and creating the "HTTPFilePost" script, without their help I would not have been able to integrate whisper and certain Convai functions

* Jukka Maatta / Kuvaus for making LlamaGPTJ-chat and helping me with various issues getting it into Godot

* Dekork for helping me solve a major roadblock

* GDQuest for "Mannequinny" used in this project

* Kenney for the free cc0 art assets used in this project

* ChatGPT for helping me with some of the audio conversion scripts lol (yes, used some AI to create the AI project)

* All the other creators of the various tools used in this project.

**LICENSE**

License is MIT for everything unless otherwise specified in the respective files.
