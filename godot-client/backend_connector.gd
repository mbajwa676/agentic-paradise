extends Node

# Configuration
var backend_url = "http://localhost:8080"
var poll_interval = 0.1  # Poll every 100ms

# References
@onready var agents_container = get_node("../World/Agents")
@onready var debug_label = get_node("../UI/DebugLabel")

# Agent scene to instantiate
var agent_scene = preload("res://agent.tscn")

# Track spawned agents and locations
var agent_nodes = {}
var locations = {}

# Save/load file path
var save_file_path = "user://game_state.json"

func _ready():
	print("Backend Connector initialized")
	
	# Check if we should load a saved state
	if FileAccess.file_exists(save_file_path):
		print("Found saved state, loading...")
		_load_and_initialize_state()
	else:
		print("No saved state, creating new world...")
		_initialize_new_world()
	
	# Fetch locations from backend
	_fetch_locations()
	
	# Set up polling timer
	var timer = Timer.new()
	timer.wait_time = poll_interval
	timer.timeout.connect(_poll_backend)
	add_child(timer)
	timer.start()
	
	# Do first poll immediately
	call_deferred("_poll_backend")

func _initialize_new_world():
	"""Create initial agents and locations"""
	# Define starting locations
	var locations_config = {
		"market": ["produce_stand", "vendor_stalls", "entrance"],
		"tavern": ["bar", "tables", "corner_booth"],
		"coffee_shop": ["counter", "outdoor_seating", "reading_nook"],
		"town_square": ["fountain", "benches"],
		"home": ["kitchen", "bedroom", "living_room"]
	}
	
	# Create locations
	for loc_name in locations_config.keys():
		# Create sub-locations
		for sub_loc in locations_config[loc_name]:
			var full_name = loc_name + ":" + sub_loc
			_create_location(full_name)
	
	# Wait a moment for locations to be created
	await get_tree().create_timer(0.5).timeout
	
	# Create initial agents
	var starting_agents = [
		{
			"name": "Klaus",
			"location": "coffee_shop:counter",
			"memories": ["I love a good cup of coffee in the morning."],
			"activity": "Entering the coffee shop."
		},
		{
			"name": "Maria",
			"location": "market:entrance",
			"memories": ["I need to buy fresh vegetables today."],
			"activity": "Looking at the produce."
		},
		{
			"name": "John",
			"location": "tavern:bar",
			"memories": ["The tavern is a good place to hear local gossip."],
			"activity": "Sitting at the bar."
		}
	]
	
	for agent_data in starting_agents:
		_create_agent(agent_data)

# LOCATION FUNCTIONS
func _create_location(location_name):
	"""POST request to create a location"""
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_location_created.bind(http))  # Pass http as parameter
	
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify({"name":location_name})
	
	var error = http.request(
		backend_url + "/locations",
		headers,
		HTTPClient.METHOD_POST,
		body
	)
	
	if error == OK:
		print("Creating location: ", location_name)
	else:
		push_error("Failed to create location: " + location_name)
		http.queue_free()  # Only free if request failed immediately

func _on_location_created(result, response_code, headers, body, http):
	"""Handle location creation response"""
	if response_code == 200 or response_code == 201:
		var json = JSON.new()
		json.parse(body.get_string_from_utf8())
		var location_data = json.data
		print("Location created: ", location_data.get("name", "unknown"))
	else:
		push_error("Location creation failed with code: " + str(response_code))
	
	# Now it's safe to free
	if is_instance_valid(http):
		http.queue_free()
func _fetch_locations():
	"""GET request to fetch all locations"""
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_locations_received)
	
	var error = http.request(backend_url + "/locations")
	if error != OK:
		push_error("Failed to fetch locations")

func _on_locations_received(result, response_code, headers, body):
	"""Handle locations response"""
	var http_nodes = get_children().filter(func(n): return n is HTTPRequest)
	if http_nodes.size() > 0:
		http_nodes[0].queue_free()
	
	if response_code == 200:
		var json = JSON.new()
		json.parse(body.get_string_from_utf8())
		var response_data = json.data
		
		# Extract locations array
		var locs = []
		if response_data is Dictionary and response_data.has("locations"):
			locs = response_data.locations
		elif response_data is Array:
			locs = response_data
		else:
			push_error("Unexpected locations format: " + str(response_data))
			return
		
		# Assign visual positions to each location
		var positions = [
			Vector2(200, 150),   # coffee_shop
			Vector2(400, 200),   # town_square
			Vector2(600, 150),   # market
			Vector2(300, 350),   # tavern
			Vector2(500, 350)    # home
		]
		
		for i in range(locs.size()):
			var loc_obj = locs[i]
			# Extract the "name" field from the location object
			var loc_name = loc_obj.get("name", "unknown") if loc_obj is Dictionary else str(loc_obj)
			
			if i < positions.size():
				locations[loc_name] = positions[i]
			else:
				# If more locations than positions, spread them out
				locations[loc_name] = Vector2(100 + i * 120, 250)
		
		print("Loaded %d locations: %s" % [locations.size(), locations.keys()])
	else:
		push_error("Failed to fetch locations, code: " + str(response_code))

# AGENT FUNCTIONS
func _create_agent(agent_data):
	"""POST request to create an agent"""
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_agent_created.bind(http))  # Pass http as parameter
	
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify(agent_data)
	
	var error = http.request(
		backend_url + "/agents",
		headers,
		HTTPClient.METHOD_POST,
		body
	)
	
	if error != OK:
		push_error("Failed to create agent: " + agent_data.name)
		http.queue_free()  # Only free if request failed immediately

func _on_agent_created(result, response_code, headers, body, http):
	"""Handle agent creation response"""
	if response_code == 200 or response_code == 201:
		var json = JSON.new()
		json.parse(body.get_string_from_utf8())
		var agent_data = json.data
		print("Agent created: ", agent_data.get("name", "unknown"))
	else:
		push_error("Agent creation failed with code: " + str(response_code))
	
	# Now it's safe to free
	if is_instance_valid(http):
		http.queue_free()



func _poll_backend():
	"""Poll the backend /state endpoint"""
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_state_received)
	
	var error = http.request(backend_url + "/state")
	if error != OK:
		push_error("Failed to poll backend")

func _on_state_received(result, response_code, headers, body):
	"""Handle state response"""
	# Remove the HTTPRequest node
	var http_nodes = get_children().filter(func(n): return n is HTTPRequest)
	if http_nodes.size() > 0:
		http_nodes[0].queue_free()
	
	if response_code != 200:
		debug_label.text = "Backend error: " + str(response_code)
		return
	
	# Parse JSON
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	
	if parse_result != OK:
		push_error("Failed to parse JSON from backend")
		return
	
	var state = json.data
	_update_world(state)

func _update_world(state):
	"""Update agent positions and states from backend data"""
	# Update debug info
	if state.has("agents"):
		var agent_count = state.agents.size()
		var location_count = state.get("locations", []).size()
		var conversation_count = state.get("conversations", []).size()
		debug_label.text = "Agents: %d | Locations: %d | Conversations: %d" % [
			agent_count, location_count, conversation_count
		]
	
	# Update or create agent nodes
	if state.has("agents"):
		for agent_data in state.agents:
			var agent_name = agent_data.get("name", "unknown")
			
			# Create agent node if doesn't exist
			if not agent_nodes.has(agent_name):
				var agent_node = agent_scene.instantiate()
				agent_node.name = agent_name
				agents_container.add_child(agent_node)
				agent_nodes[agent_name] = agent_node
				print("Spawned agent node: ", agent_name)
			
			# Update agent
			var agent = agent_nodes[agent_name]
			agent.update_from_backend(agent_data, locations)

func _progress_simulation():
	"""POST to /state to advance the simulation one step"""
	var http = HTTPRequest.new()
	add_child(http)
	
	var error = http.request(
		backend_url + "/state",
		[],
		HTTPClient.METHOD_POST
	)
	
	if error == OK:
		print("Progressing simulation...")
	else:
		push_error("Failed to progress simulation")
	
	# Clean up after delay
	await get_tree().create_timer(0.1).timeout
	http.queue_free()

func _save_state():
	"""Save current backend state to file"""
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_save_state_received)
	
	# Get current state from backend
	http.request(backend_url + "/state")

func _on_save_state_received(result, response_code, headers, body):
	"""Save the received state to disk"""
	var http = get_children().filter(func(n): return n is HTTPRequest)[0]
	http.queue_free()
	
	if response_code == 200:
		var file = FileAccess.open(save_file_path, FileAccess.WRITE)
		if file:
			file.store_string(body.get_string_from_utf8())
			file.close()
			print("State saved to: ", save_file_path)
		else:
			push_error("Failed to open save file")
	else:
		push_error("Failed to fetch state for saving")

func _load_and_initialize_state():
	"""Load saved state and recreate it in the backend"""
	var file = FileAccess.open(save_file_path, FileAccess.READ)
	if not file:
		push_error("Failed to open save file")
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		push_error("Failed to parse saved state")
		return
	
	var saved_state = json.data
	print("Loaded saved state with %d agents" % saved_state.get("agents", []).size())
	
	# Recreate locations
	if saved_state.has("locations"):
		for loc in saved_state.locations:
			_create_location(loc)
	
	# Wait for locations to be created
	await get_tree().create_timer(1.0).timeout
	
	# Recreate agents
	if saved_state.has("agents"):
		for agent_data in saved_state.agents:
			_create_agent(agent_data)

# Dev Testing actions
func _input(event):
	"""Handle keyboard shortcuts"""
	if event is InputEventKey and event.pressed:
		# Press 'S' to save state
		if event.keycode == KEY_S:
			print("Saving state...")
			_save_state()
		
		# Press 'P' to progress simulation manually
		if event.keycode == KEY_P:
			_progress_simulation()
		
		# Press 'N' to create a new random agent
		if event.keycode == KEY_N:
			_create_random_agent()

func _create_random_agent():
	"""Create a random agent for testing"""
	var names = ["Alice", "Bob", "Charlie", "Diana", "Eve", "Frank"]
	var locs = locations.keys()
	
	if locs.size() == 0:
		print("No locations available yet")
		return
	
	var random_name = names[randi() % names.size()]
	var random_loc = locs[randi() % locs.size()]
	
	var new_agent = {
		"name": random_name,
		"location": random_loc,
		"memories": ["I just arrived in town."],
		"activity": "Looking around."
	}
	
	_create_agent(new_agent)
	print("Created random agent: ", random_name)

func _exit_tree():
	"""Clean up on exit"""
	# Optional: Auto-save on exit
	_save_state()
	
	# Clean up any remaining HTTP requests
	for child in get_children():
		if child is HTTPRequest:
			child.queue_free()
