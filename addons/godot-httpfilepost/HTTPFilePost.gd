extends HTTPRequest

class_name GodotHTTPFilePost
# Code modified slightly from nisovin/GodotHTTPFilePost.gd
# Example usage:
# newpostrequest = load("res://addons/godot-httpfilepost/HTTPFilePost.gd").new()
# newpostrequest.post_file("https://api.convai.com/character/getResponse", "file", "audio.wav", "user://audio.wav", { "charID": "asdf", "sessionID": "-1", "voiceResponse": "True", "stream": "True"}, "audio/wav", [your headers here])

# Get the binary file information as PackedByteArray
func post_file(url: String, field_name: String, file_name: String, file_path: String, post_fields: Dictionary = {}, content_type: String = "", custom_headers: Array = []):
	var file = FileAccess.open(file_path, FileAccess.READ)
	var content = file.get_buffer(file.get_length())
	file.close()
	post_data_as_file(url, field_name, file_name, content, post_fields, content_type, custom_headers)
	
# Send all fields and binary data as multipart/form-data	
func post_data_as_file(url: String, field_name: String, file_name: String, data, post_fields: Dictionary = {}, content_type: String = "", custom_headers: Array = []):
	randomize()
	#var boundary = "---------------------------" + str(randi()) + str(randi())
	var boundary = "boundary"
	custom_headers.append("Content-Type: multipart/form-data; boundary=" + boundary)
	var body1 = "\r\n\r\n"
	for key in post_fields:
		print("key found:" + str(key))
		body1 += "--" + boundary + "\r\n"
		body1 += "Content-Disposition: form-data; name=\"" + key + "\"\r\n\r\n" + post_fields[key] + "\r\n"
	body1 += "--" + boundary + "\r\n"
	body1 += "Content-Disposition: form-data; name=\"" + field_name + "\"; filename=\"" + file_name + "\"\r\nContent-Type: "
	if content_type != "":
		body1 += content_type
	elif data is String:
		body1 += "text/plain"
	else:
		body1 += "application/octet-stream"
	body1 += "\r\n\r\n"
	var body2 = "\r\n" + "--" + boundary + "--"
	var post_content
	if data is String:
		post_content = (body1 + data + body2).to_utf8_buffer()
	elif data is PackedByteArray:
		print("http file content found")
		post_content = body1.to_utf8_buffer() + data + body2.to_utf8_buffer()
	else:
		assert(false)
		return false
	print("making file http request")
	print(url)
	print(custom_headers)
	print(body1 + "binary data, for example audio file data, inserted here" + body2)
	#print(post_content)
	var err = request_raw(url, custom_headers, HTTPClient.METHOD_POST, post_content)
	print("err from request raw from convai voice stream request is: " + str(err))
