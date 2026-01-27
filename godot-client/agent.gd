extends Node2D

@onready var sprite = $Sprite2D
@onready var label = $Label

var agent_name = ""
var current_activity = ""
var current_location = ""

# For smooth movement
var target_position = Vector2.ZERO
var move_speed = 200.0  # pixels per second

func _ready():
	# Default appearance (colored square for now)
	sprite.texture = _create_placeholder_texture()
	label.position = Vector2(-40, -40)
	label.add_theme_font_size_override("font_size", 12)
	target_position = position

func _process(delta):
	# Smooth movement towards target position
	if position.distance_to(target_position) > 5:
		position = position.move_toward(target_position, move_speed * delta)

func update_from_backend(data, location_map):
	"""Update agent based on backend data"""
	agent_name = data.get("name", "unknown")
	current_activity = data.get("activity", "idle")
	current_location = data.get("location", "unknown")
	
	# Update target position based on location
	if location_map.has(current_location):
		target_position = location_map[current_location]
		# Add slight randomness so agents don't stack perfectly
		target_position += Vector2(randf_range(-20, 20), randf_range(-20, 20))
	
	# Update label
	_update_label()
	
	# Update color based on activity keywords
	_update_appearance()

func _update_label():
	"""Update the text label above the agent"""
	var display_text = agent_name
	
	# Truncate long activities
	var activity_display = current_activity
	if activity_display.length() > 30:
		activity_display = activity_display.substr(0, 27) + "..."
	
	label.text = "%s\n%s\n@ %s" % [agent_name, activity_display, current_location]

func _update_appearance():
	"""Change color based on activity/state"""
	var activity_lower = current_activity.to_lower()
	
	if "walk" in activity_lower or "moving" in activity_lower or "going" in activity_lower:
		sprite.modulate = Color.GREEN
	elif "talk" in activity_lower or "conversation" in activity_lower or "speaking" in activity_lower:
		sprite.modulate = Color.YELLOW
	elif "fight" in activity_lower or "attack" in activity_lower or "combat" in activity_lower:
		sprite.modulate = Color.RED
	elif "idle" in activity_lower or "waiting" in activity_lower or "standing" in activity_lower:
		sprite.modulate = Color.GRAY
	else:
		sprite.modulate = Color.WHITE

func _create_placeholder_texture():
	"""Create a simple colored square as placeholder sprite"""
	var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.DODGER_BLUE)
	return ImageTexture.create_from_image(img)

func get_agent_info():
	"""Return agent info for inspection/debugging"""
	return {
		"name": agent_name,
		"activity": current_activity,
		"location": current_location,
		"position": position
	}
