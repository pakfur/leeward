extends Node
## MCPServer - WebSocket server for MCP integration

const PORT = 9080
var tcp_server: TCPServer = null
var peers: Array = []  # Array of connected WebSocketPeer clients

func _ready() -> void:
	start_server()

func start_server() -> void:
	tcp_server = TCPServer.new()
	var err = tcp_server.listen(PORT)

	if err != OK:
		push_error("Failed to start MCP WebSocket server on port %d: %s" % [PORT, error_string(err)])
		return

	print("MCP WebSocket server started on port %d" % PORT)

func _process(_delta: float) -> void:
	if not tcp_server:
		return

	# Poll the TCP server
	var poll_result = tcp_server.poll()
	if poll_result != OK:
		return

	# Accept new TCP connections
	if tcp_server.is_connection_available():
		var tcp_peer = tcp_server.take_connection()
		print("MCP TCP connection received from: %s:%d" % [tcp_peer.get_connected_host(), tcp_peer.get_connected_port()])

		var ws_peer = WebSocketPeer.new()
		var accept_result = ws_peer.accept_stream(tcp_peer)

		if accept_result != OK:
			push_error("Failed to accept WebSocket stream: %s" % error_string(accept_result))
			tcp_peer.disconnect_from_host()
			return

		peers.append({
			"ws": ws_peer,
			"tcp": tcp_peer
		})
		print("MCP WebSocket handshake initiated...")

	# Process existing WebSocket connections
	for i in range(peers.size() - 1, -1, -1):
		var peer_data = peers[i]
		var ws_peer: WebSocketPeer = peer_data.ws

		ws_peer.poll()
		var state = ws_peer.get_ready_state()

		if state == WebSocketPeer.STATE_OPEN:
			# Connection established
			if peer_data.get("connected") != true:
				peer_data.connected = true
				print("MCP client connected")

			# Handle incoming messages
			while ws_peer.get_available_packet_count() > 0:
				var packet = ws_peer.get_packet()
				var message = packet.get_string_from_utf8()
				_handle_message(ws_peer, message)

		elif state == WebSocketPeer.STATE_CLOSING:
			# Connection closing
			pass

		elif state == WebSocketPeer.STATE_CLOSED:
			# Connection closed
			var code = ws_peer.get_close_code()
			var reason = ws_peer.get_close_reason()
			print("MCP client disconnected: %d - %s" % [code, reason])
			peers.remove_at(i)

func _handle_message(peer: WebSocketPeer, message: String) -> void:
	print("MCP received: %s" % message)

	var json = JSON.new()
	var parse_result = json.parse(message)

	if parse_result != OK:
		push_warning("Failed to parse MCP message: %s" % message)
		return

	var data = json.data
	if not data is Dictionary:
		return

	var method = data.get("method", "")
	var params = data.get("params", {})
	var id = data.get("id", null)

	var response = _process_request(method, params)

	if id != null:
		_send_response(peer, id, response)

func _process_request(method: String, params: Dictionary) -> Dictionary:
	match method:
		"get_scene_tree":
			return _get_scene_tree()
		"get_node_info":
			var path = params.get("path", "")
			return _get_node_info(path)
		"execute_code":
			var code = params.get("code", "")
			return _execute_code(code)
		_:
			return {"error": "Unknown method: %s" % method}

func _get_scene_tree() -> Dictionary:
	var root = get_tree().root
	return {
		"success": true,
		"tree": _serialize_node(root)
	}

func _serialize_node(node: Node) -> Dictionary:
	var result = {
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path()),
		"children": []
	}

	for child in node.get_children():
		result.children.append(_serialize_node(child))

	return result

func _get_node_info(path: String) -> Dictionary:
	var node = get_node_or_null(path)
	if not node:
		return {"error": "Node not found: %s" % path}

	return {
		"success": true,
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path()),
		"properties": _get_node_properties(node)
	}

func _get_node_properties(node: Node) -> Dictionary:
	var props = {}
	var property_list = node.get_property_list()

	for prop in property_list:
		if prop.usage & PROPERTY_USAGE_EDITOR:
			var prop_name = prop.name
			props[prop_name] = str(node.get(prop_name))

	return props

func _execute_code(code: String) -> Dictionary:
	var script = GDScript.new()
	script.source_code = code
	var err = script.reload()

	if err != OK:
		return {"error": "Failed to compile code: %s" % error_string(err)}

	var instance = script.new()
	if instance.has_method("_run"):
		var result = instance._run()
		return {"success": true, "result": str(result)}

	return {"success": true, "message": "Code executed"}

func _send_response(peer: WebSocketPeer, id: Variant, response: Dictionary) -> void:
	var message = {
		"jsonrpc": "2.0",
		"id": id,
		"result": response
	}

	var json_string = JSON.stringify(message)
	peer.send_text(json_string)

func _exit_tree() -> void:
	if tcp_server:
		tcp_server.stop()

	for peer_data in peers:
		var ws_peer: WebSocketPeer = peer_data.ws
		ws_peer.close()

	print("MCP WebSocket server stopped")
