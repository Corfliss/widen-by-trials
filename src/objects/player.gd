extends CharacterBody3D

@export_subgroup("Properties")
@export var movement_speed = 5
@export_range(0, 100) var number_of_jumps:int = 2
@export var jump_strength = 8

@export_subgroup("Weapons")
@export var weapons: Array[Weapon] = []

var weapon: Weapon
var weapon_index := 0

var mouse_sensitivity = 700
var gamepad_sensitivity := 0.075

var mouse_captured := true

var movement_velocity: Vector3
var rotation_target: Vector3

var input_mouse: Vector2

@export var max_health: int = 100
var health: int = 0
var gravity := 0.0

var previously_floored := false

var jumps_remaining:int

# Weapon holder base offset (world space), hand-tuned for the 1280x720 composition
# and kept as the design constant for the 1920x1080 baseline. Deliberately NOT derived
# from resolution: under canvas_items stretch its screen effect is resolution-independent
# (recon RECON-ASPECT-RATIO.md, pain point A2).
var container_offset := Vector3(0, 3, -25)

var tween:Tween

signal health_updated(health: int)

@onready var camera = $Head/Camera360
@onready var raycast = $Head/Camera360/RayCast
@onready var muzzle = %Muzzle
@onready var container = %Container
@onready var sound_footsteps = $SoundFootsteps
@onready var blaster_cooldown = $Cooldown

@export var crosshair:TextureRect

# Functions

func _ready():
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group("player")
	health = max_health
	GameManager.register_player(self)
	
	weapon = weapons[weapon_index] # Weapon must never be nil
	initiate_change_weapon(weapon_index)

func _physics_process(delta):
	
	# Handle functions
	handle_controls(delta)
	handle_gravity(delta)
	
	# Movement
	var applied_velocity: Vector3
	
	movement_velocity = transform.basis * movement_velocity # Move forward
	
	applied_velocity = velocity.lerp(movement_velocity, delta * 15)
	applied_velocity.y = -gravity
	
	velocity = applied_velocity
	move_and_slide()
	
	# Rotation 
	container.position = lerp(container.position, container_offset + (basis.inverse() * applied_velocity / 30), delta * 20)

	# Movement sound
	sound_footsteps.stream_paused = true
	
	if is_on_floor():
		if abs(velocity.x) > 1 or abs(velocity.z) > 1:
			sound_footsteps.stream_paused = false
	
	# Landing after jump or falling
	
	camera.position.y = lerp(camera.position.y, 0.0, delta * 5)
	
	if is_on_floor() and gravity > 1 and !previously_floored: # Landed
		Audio.play("src/sounds/land.ogg")
		camera.position.y = -0.1
	
	previously_floored = is_on_floor()
	
	# Falling/respawning
	
	if position.y < -10:
		get_tree().reload_current_scene()

# Mouse movement

func _input(event):
	if event is InputEventMouseMotion and mouse_captured:
		input_mouse = event.relative / mouse_sensitivity
		handle_rotation(event.relative.x, event.relative.y, false)

func handle_controls(delta):
	
	# Mouse capture
	
	if Input.is_action_just_pressed("mouse_capture"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mouse_captured = true
	
	if Input.is_action_just_pressed("mouse_capture_exit"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		mouse_captured = false
		
		input_mouse = Vector2.ZERO
	
	# Movement
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	movement_velocity = Vector3(input.x, 0, input.y).normalized() * movement_speed
	
	# Handle Controller Rotation
	var rotation_input := Input.get_vector("camera_right", "camera_left", "camera_down", "camera_up")
	if rotation_input:
		handle_rotation(rotation_input.x, rotation_input.y, true, delta)
	
	# Shooting
	
	action_shoot()
	
	# Jumping
	
	if Input.is_action_just_pressed("jump"):
		
		if jumps_remaining:
			action_jump()
		
	# Weapon switching
	
	action_weapon_toggle()

# Camera rotation

func handle_rotation(xRot: float, yRot: float, isController: bool, delta: float = 0.0):
	if isController:
		rotation_target -= Vector3(-yRot, -xRot, 0).limit_length(1.0) * gamepad_sensitivity
		rotation_target.x = clamp(rotation_target.x, deg_to_rad(-90), deg_to_rad(90))
		camera.rotation.x = lerp_angle(camera.rotation.x, rotation_target.x, delta * 25)
		rotation.y = lerp_angle(rotation.y, rotation_target.y, delta * 25)
	else:
		rotation_target += (Vector3(-yRot, -xRot, 0) / mouse_sensitivity)
		rotation_target.x = clamp(rotation_target.x, deg_to_rad(-90), deg_to_rad(90))
		camera.rotation.x = rotation_target.x;
		rotation.y = rotation_target.y;
	
# Handle gravity

func handle_gravity(delta):
	gravity += 20 * delta
	
	if gravity > 0 and is_on_floor():
		
		jumps_remaining = number_of_jumps
		gravity = 0

# Jumping

func action_jump():	
	Audio.play("src/sounds/jump_a.ogg, src/sounds/jump_b.ogg, src/sounds/jump_c.ogg")
	gravity = -jump_strength	
	jumps_remaining -= 1

# Shooting

func action_shoot():
	
	if Input.is_action_pressed("shoot"):
	
		if !blaster_cooldown.is_stopped(): return # Cooldown for shooting
		
		Audio.play(weapon.sound_shoot)
		
		# Set muzzle flash position, play animation
		
		muzzle.play("default")
		
		muzzle.rotation_degrees.z = randf_range(-45, 45)
		muzzle.scale = Vector3.ONE * randf_range(0.40, 0.75)
		muzzle.position = container.position - weapon.muzzle_position + Vector3(0.25,0.75,1)
		
		blaster_cooldown.start(weapon.cooldown)
		
		# Shoot the weapon, amount based on shot count
		
		for n in weapon.shot_count:
		
			raycast.target_position.x = randf_range(-weapon.spread, weapon.spread)
			raycast.target_position.y = randf_range(-weapon.spread, weapon.spread)
			
			raycast.force_raycast_update()
			
			if !raycast.is_colliding(): continue # Don't create impact when raycast didn't hit
			
			var collider = raycast.get_collider()
			
			# Hitting an enemy — colorprune-style color match:
			# the gun's color must match the enemy's, otherwise no damage
			
			var target = collider
			if !target.has_method("damage") and target.get_parent() and target.get_parent().has_method("damage"):
				target = target.get_parent()
			if target.has_method("damage"):
				var enemy_color: Variant = target.get("enemy_color_code")
				if enemy_color == null or GameManager.colors_match(weapon.gun_color, int(enemy_color)):
					target.damage(weapon.damage)
			
			# Creating an impact animation
			
			var impact = preload("res://archive/objects/impact.tscn")
			var impact_instance = impact.instantiate()
			
			impact_instance.play("shot")
			
			get_tree().root.add_child(impact_instance)
			
			impact_instance.position = raycast.get_collision_point() + (raycast.get_collision_normal() / 10)
			impact_instance.look_at(camera.global_transform.origin, Vector3.UP, true)
			
		container.position.z += 0.25 # Knockback of weapon visual
		camera.rotation.x += 0.025 # Knockback of camera
		movement_velocity += Vector3(0, 0, weapon.knockback) # Knockback

# Toggle between available weapons (listed in 'weapons')

func action_weapon_toggle():
	
	if Input.is_action_just_pressed("weapon_toggle"):
		
		weapon_index = wrap(weapon_index + 1, 0, weapons.size())
		initiate_change_weapon(weapon_index)
		
		Audio.play("src/sounds/weapon_change.ogg")

# Initiates the weapon changing animation (tween)

func initiate_change_weapon(index):
	
	weapon_index = index
	
	tween = get_tree().create_tween()
	tween.set_ease(Tween.EASE_OUT_IN)
	tween.tween_property(container, "position", container_offset - Vector3(0, 1, 0), 0.1)
	tween.tween_callback(change_weapon) # Changes the model

# Switches the weapon model (off-screen)

func change_weapon():
	
	weapon = weapons[weapon_index]

	# Step 1. Remove previous weapon model(s) from container
	
	for n in container.get_children():
		container.remove_child(n)
	
	# Step 2. Place new weapon model in container
	
	var weapon_model = weapon.model.instantiate()
	container.add_child(weapon_model)
	
	weapon_model.position = weapon.position
	weapon_model.rotation_degrees = weapon.rotation
	weapon_model.scale = Vector3.ONE * weapon.model_scale
	
	# Step 3. Set model to only render on layer 2 (the weapon camera),
	# and tint it to the gun's color so players can read which enemies it damages
	
	var tint: Color = GameManager.gun_color_value(weapon.gun_color)
	for child in weapon_model.find_children("*", "MeshInstance3D"):
		child.layers = 2
		for surface in child.get_surface_override_material_count():
			var mat := child.get_surface_override_material(surface) as ShaderMaterial
			if mat != null:
				mat.set_shader_parameter("wire_color", tint)
				mat.set_shader_parameter("face_color", tint.darkened(0.8))
		
	# Set weapon data
	
	raycast.target_position = Vector3(0, 0, -1) * weapon.max_distance
	crosshair.texture = weapon.crosshair

## Incoming melee damage. HP subtraction, grace reset and death routing all
## live in GameManager.player_hit(); this only tags the hit as enemy-sourced.
func damage(amount: int) -> void:
	GameManager.player_hit(GameManager.HitSource.ENEMY, amount)

func heal(amount: int) -> void:
	if amount <= 0 or health >= max_health:
		return
	health = mini(health + amount, max_health)
	health_updated.emit(health) # Update health on HUD
