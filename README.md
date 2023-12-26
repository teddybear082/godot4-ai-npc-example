# godot4-ai-npc-example
 A Godot 4 Artificial Intelligence (AI) NPC example project.

![ai-npc](https://user-images.githubusercontent.com/87204721/236790720-ab62b7d0-b542-49dd-8ec9-a294a72afe3e.gif)

Example of using various AI and speech technologies to create an AI NPC in Godot 4.  There is also an example of some of these scripts for Godot 3 here: https://github.com/teddybear082/godot-ai-npc-example. 

This repo is more an experimental playground for coders and tinkerers than a true consumer final release.  **I haven't worked on this repo in quite some time and have moved on to some other things, but if you are interested in things like this repo, I also have a gitbhub gist here with a node that contains all recent openai API's implemented: https://gist.github.com/teddybear082/53a6dc08a085de6a5caecee8cd70b040**

Download the release marked for **PCVR** to use with windows PCVR: https://github.com/teddybear082/godot4-ai-npc-example/releases/download/v.0.02-alpha/pcvrrelease.zip. This is a very early version and does not have all the features of the underlying code I later added.

Download the release marked for **Quest** to use with Quest: https://github.com/teddybear082/godot4-ai-npc-example/releases/download/v.0.02-alpha/quest-release.zip.  This is a very early version and does not have all the features of the underlying code I later added.

**Instructions and information on use and the various options available are in the Wiki: https://github.com/teddybear082/godot4-ai-npc-example/wiki**

At a high level, included options/scripts are:

* Wit.ai API (requires free API key) (for speech to text and text to speech)

* Convai.com API (requires free or paid API key) (for AI character response generation and text to speech)

* OpenAI GPT 3.5 Turbo API (requires paid API key) (for AI character response generation)

* OpenAI Whisper API (requires paid API key) (for speech to text)

* Whisper.cpp (locally run, no paid API key required) (for speech to text)

* GPT4All - Llama GPT-J-Chat (locally run, no paid API key required) (for AI character response generation)

* GPT4All - regular windows program server mode (locally run, no paid API key required) (for AI character response generation)

* Godot Text to Speech (locally run, no paid API Key rquired) (this is just an implementation of Godot 4's native text to speech functionality through Display Server)

* XVASynth Text to Speech (locally run, no paid API Key required; requires download of XVASynth v.3.0 from Steam or NexusMods and a v3 voice model installed at the location where XVASynth expects)

**KNOWN ISSUES:**

* Convai speech to text does not work, seems to be an API issue with the .wav file format Godot uses

* ElevenLabs text to speech will only process first request if several are sent, e.g., streaming text (needs better httprequest management)

**Special Thanks to:**

* The Godot XR / XR tools team for all the VR functions used in this project, for making getting into VR easy (including the built in scripts for pointer, movement, passthrough mode!)

* VR Workout for the initial Wit.ai scripts that got me going getting my voice converted into text and learning how APIs worked

* Convai support team for awesome quick and robust support as I was trying to figure out integrating their API into Godot

* nisovin from the Godot discord who helped me a ton with getting HTTP multipart / form data requests working and creating the "HTTPFilePost" script, without their help I would not have been able to integrate whisper and certain Convai functions

* Jukka Maatta / Kuvaus for making LlamaGPTJ-chat and helping me with various issues getting it into Godot

* Dekork for helping me solve a major roadblock

* GDQuest for "Mannequinny" used in this project

* Kenney for the free cc0 art assets used in this project

* ChatGPT for helping me with some of the audio conversion scripts lol (yes, used some AI to create the AI project)

* XVASynth dev, DanRuta for making a great free program and helping me use its largely undocumented headless server mode

* All the other creators of the various tools used in this project.

**LICENSE**

License is MIT for everything unless otherwise specified in the respective files.
