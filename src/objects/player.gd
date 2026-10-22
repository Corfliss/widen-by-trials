extends CharacterBody3D

@export_subgroup("Properties")
@export var movement_speed = 5
@export_range(0, 100) var number_of_jumps:int = 2
@export var jump_strength = 8

@export_subgroup("NULLWIDE")
@export var nullwide_fov := 359.9
@export_range(0, 100) var nullwide_meter := 100.0
@export var nullwide_drain := 200.0 # meter units per second while active
@export var nullwide_regen := 8.0 # meter units per second while inactive
## Half-angle (degrees) of the lock-on cone around the aim direction.
@export_range(5.0, 90.0) var nullwide_lock_angle := 30.0
## Engine.time_scale applied while NULLWIDE is active (1.0 = real time).
## Everything delta-driven slows with it — enemies, physics, waves, the
## player included — and the meter drains in that same slowed game-time,
## so a full meter holds for 100 / nullwide_drain / nullwide_time_scale
## real seconds. Camera look is exempted (see _unscaled).
@export_range(0.05, 1.0) var nullwide_time_scale := 0.2
var nullwide_active := false
var _nullwide_key_held := false
var _nullwide_locks: Array[Node3D] = []

@export_subgroup("Weapons")
@export var weapons: Array[Weapon] = []

@export_subgroup("Sounds")
## Comma-separated pool (res-relative) played when a shot lands damage.
@export var sound_hit_confirm: String = "src/sounds/hit_confirm.wav"
## Center pitch of a normal hit-confirm.
@export_range(0.25, 4.0) var hit_confirm_pitch: float = 1.0
## Center pitch boost when the hit killed the enemy.
@export_range(0.25, 4.0) var kill_pitch: float = 1.4
## Half-width of the random per-play pitch jitter around the chosen pitch.
@export_range(0.0, 1.0) var hit_confirm_spread: float = 0.05

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

## Tutorial gates (src/scenes/tutorial/tutorial.gd): while movement_locked,
## WASD input and jumping are ignored; while shooting_locked, no shots
## leave the barrel.
var movement_locked := false
var shooting_locked := false

# Weapon holder base offset (world space), hand-tuned for the 1280x720 composition
# and kept as the design constant for the 1920x1080 baseline. Deliberately NOT derived
# from resolution: under canvas_items stretch its screen effect is resolution-independent
# (recon RECON-ASPECT-RATIO.md, pain point A2).
var container_offset := Vector3(0, 0, -7)

var tween:Tween

signal health_updated(health: int)
## Fired when a shot actually lands damage on an enemy (color gate passed).
signal enemy_hit
## Fired by a mid-air jump that exhausts jumps_remaining — the tutorial's
## "double jump to begin" trigger.
signal double_jumped
## Fired whenever the NULLWIDE hold starts or stops — HUD draws the lock circle.
signal nullwide_hold_changed(holding: bool)
## Fired once per color-matched lock on release — the beam spawner visualizes
## the shot. Player stays visuals-agnostic: it only names start/end/color.
signal nullwide_shot_fired(from: Vector3, to: Vector3, color: Color)

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
	
	# Viewmodel lives on layer 2; Camera360's subcameras inherit an all-layers
	# cull_mask, so strip layer 2 or the gun/muzzle get baked into the 360 image
	# as a ghost 25 units ahead, clipping the arena's outer kill zone.
	for cam in camera.cameras:
		cam.cull_mask &= ~2

func _exit_tree():
	# Death / scene change mid-hold must not leave the engine in slow-mo.
	Engine.time_scale = 1.0

func _physics_process(delta):
	
	# Handle functions
	handle_controls(delta)
	handle_gravity(delta)
	_update_nullwide(delta)
	
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
	# Falling now routes to the game over screen via arena.tscn's FallZone.

# Mouse movement

func _input(event):
	if event is InputEventMouseMotion and mouse_captured:
		input_mouse = event.relative / mouse_sensitivity
		handle_rotation(event.relative.x, event.relative.y, false)
	
	# NULLWIDE hold (InputMap action "nullwide": X key / gamepad X button).
	# Was a raw KEY_X check; that soft-locked gamepad players in the
	# tutorial's NULLWIDE phase, so it moved into the InputMap — it also
	# becomes rebindable in the options input tab this way.
	if event.is_action_pressed("nullwide"):
		action_nullwide_press()
	elif event.is_action_released("nullwide"):
		action_nullwide_release()

func handle_controls(delta):
	
	# Mouse capture
	
	if Input.is_action_just_pressed("mouse_capture"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mouse_captured = true
	
	if Input.is_action_just_pressed("mouse_capture_exit"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		mouse_captured = false
		
		input_mouse = Vector2.ZERO
	
	# Movement (tutorial Phase 1 freezes WASD input without touching gravity)
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if movement_locked:
		input = Vector2.ZERO
	movement_velocity = Vector3(input.x, 0, input.y).normalized() * movement_speed
	
	# Handle Controller Rotation (look stays real-time in NULLWIDE slow-mo)
	var rotation_input := Input.get_vector("camera_right", "camera_left", "camera_down", "camera_up")
	if rotation_input:
		handle_rotation(rotation_input.x, rotation_input.y, true, _unscaled(delta))
	
	# Shooting
	
	action_shoot()
	
	# Jumping
	
	if Input.is_action_just_pressed("jump") and not movement_locked:
		
		if jumps_remaining:
			action_jump()
		
	# Weapon switching
	
	action_weapon_toggle()

# Camera rotation

## Real-time delta. Physics delta is scaled by Engine.time_scale (verified
## in Godot 4.7 main.cpp: physics_process(physics_step * time_scale)), so
## divide it back out for camera look, which the NULLWIDE slow-mo exempts.
func _unscaled(delta: float) -> float:
	return delta / maxf(Engine.time_scale, 0.001)

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

# NULLWIDE (360-degree view on meter): hold X to open the fisheye, slow
# time to nullwide_time_scale, and lock enemies inside the aim cone;
# release to kill the color-matched locks at full speed.

func action_nullwide_press():
	_nullwide_key_held = true
	if not nullwide_active and nullwide_meter > 0.0:
		_nullwide_locks.clear()
		nullwide_active = true
		Engine.time_scale = nullwide_time_scale
		nullwide_hold_changed.emit(true)

func action_nullwide_release():
	if not _nullwide_key_held:
		return
	_nullwide_key_held = false
	if nullwide_active:
		nullwide_active = false
		Engine.time_scale = 1.0
		nullwide_hold_changed.emit(false)
	# Locks survive a meter-empty cancel on purpose: whatever was acquired
	# before the hold died still dies on release.
	for enemy in _nullwide_locks:
		if not is_instance_valid(enemy):
			continue
		# Color gate: only locks matching the current gun die (colorprune-style)
		if GameManager.colors_match(weapon.gun_color, int(enemy.get("enemy_color_code"))):
			# Captured before damage(): death frees the enemy node.
			var shot_from: Vector3 = camera.global_transform.origin
			var shot_to: Vector3 = enemy.global_position
			enemy.damage(9999) # Instant kill through the duck-typed damage() contract
			enemy_hit.emit()
			# A NULLWIDE lock kill is by definition lethal: always the boosted pitch.
			Audio.play(sound_hit_confirm, kill_pitch, hit_confirm_spread)
			nullwide_shot_fired.emit(shot_from, shot_to,
				GameManager.gun_color_value(weapon.gun_color))
	_nullwide_locks.clear()

func _update_nullwide(delta):
	# Rectilinear is only valid below 180: keep fisheye while fovx lerps
	# down past it after deactivation (fisheye handles the full range fine)
	if nullwide_active:
		camera.lens = Camera360.Lens.FISHEYE
	elif camera.fovx < 180.0:
		camera.lens = Camera360.Lens.RECTILINEAR
	var target_fov := 120

	if nullwide_active:
		target_fov = nullwide_fov
		_update_nullwide_locks()
		nullwide_meter = maxf(nullwide_meter - nullwide_drain * delta, 0.0)
		if nullwide_meter <= 0.0:
			nullwide_active = false # Meter empty: revert to rectilinear 120
			Engine.time_scale = 1.0 # Mode ends; kept locks still die on release
			nullwide_hold_changed.emit(false) # Locks kept for the release
	elif nullwide_meter < 100.0:
		nullwide_meter = minf(nullwide_meter + nullwide_regen * delta, 100.0)
	
	# Asymmetric lerp: fast on turn-off so the fisheye->rectilinear descent
	# passes the distorted 180-band too quickly to register as a wobble
	var lerp_speed := 25.0 if not nullwide_active else 8.0
	camera.fovx = lerpf(camera.fovx, target_fov, minf(delta * lerp_speed, 1.0))

## Accumulate the lock set every active tick: a lock is remembered from the
## moment it is detected and survives leaving the aim cone — only death or
## a lost line of sight forgets it. The set survives a meter-empty cancel so
## the release can still kill it.
func _update_nullwide_locks() -> void:
	var origin: Vector3 = camera.global_transform.origin
	var aim: Vector3 = -camera.global_transform.basis.z
	var cos_limit := cos(deg_to_rad(nullwide_lock_angle))
	var space := get_world_3d().direct_space_state
	# Prune: dead enemies and lost line of sight forget; cone exit never does.
	for i in range(_nullwide_locks.size() - 1, -1, -1):
		var locked: Node3D = _nullwide_locks[i]
		if not is_instance_valid(locked) or locked.is_queued_for_deletion() \
				or _nullwide_ray_blocked(space, origin, locked):
			_nullwide_locks.remove_at(i)
	# Accumulate: cone + clear LOS adds a lock for the rest of the hold.
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if _nullwide_locks.has(enemy):
			continue
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var to_enemy: Vector3 = enemy.global_position - origin
		if to_enemy.length_squared() < 0.0001:
			continue
		if to_enemy.normalized().dot(aim) < cos_limit:
			continue
		if _nullwide_ray_blocked(space, origin, enemy):
			continue
		_nullwide_locks.append(enemy)

## LOS probe: the first hit must be the enemy itself (or its child) — any
## world collider in front blocks the lock. Enemies only carry Area3D
## colliders, so areas must participate in the query.
func _nullwide_ray_blocked(space: PhysicsDirectSpaceState3D, origin: Vector3, enemy: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin, enemy.global_position)
	query.exclude = [get_rid()]
	query.collide_with_areas = true
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider: Node = hit["collider"] as Node
	while collider != null:
		if collider == enemy:
			return false
		collider = collider.get_parent()
	return true

# Jumping

func action_jump():	
	Audio.play("src/sounds/jump_a.ogg, src/sounds/jump_b.ogg, src/sounds/jump_c.ogg")
	gravity = -jump_strength	
	jumps_remaining -= 1
	# Mid-air jump that exhausts the pool = the tutorial's forced double jump
	if jumps_remaining == 0 and not is_on_floor():
		double_jumped.emit()

# Shooting

func action_shoot():
	
	# Duck-typed trigger gate: tap-fire weapons (RepeaterWeapon) own the
	# press/release latch; everything else keeps hold-to-fire.
	# can_fire() must run unconditionally — the release frame it needs to
	# re-arm has is_action_pressed == false.
	var trigger_held: bool
	if weapon.has_method("can_fire"):
		trigger_held = weapon.can_fire()
	else:
		trigger_held = Input.is_action_pressed("shoot")

	# Tutorial gate: can_fire() above must still run every frame (its release
	# frame re-arms the tap latch), but no shot leaves a blocked barrel.
	if shooting_locked:
		return

	# NULLWIDE hold: weapons only detect (locks update in _update_nullwide);
	# can_fire() above still ran so the tap latch stays in sync.
	if nullwide_active:
		return

	if trigger_held:
	
		if !blaster_cooldown.is_stopped(): return # Cooldown for shooting
		
		Audio.play(weapon.sound_shoot, weapon.sound_pitch, weapon.sound_pitch_spread)
		
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
			
			# Walk up until a damage() method is found: HitBoxes sit at different
			# depths (bomber: HitBox -> Model -> Bomber), not always on the root.
			var target = collider
			while target != null and not target.has_method("damage"):
				target = target.get_parent()
			if target != null:
				var enemy_color: Variant = target.get("enemy_color_code")
				if enemy_color == null or GameManager.colors_match(weapon.gun_color, int(enemy_color)):
					target.damage(weapon.damage)
					enemy_hit.emit()
					# Duck-typed kill check (same pattern as enemy_color_code):
					# enemies expose a `destroyed` flag set by the lethal blow.
					var killed: bool = target.get("destroyed") == true
					Audio.play(sound_hit_confirm,
						kill_pitch if killed else hit_confirm_pitch, hit_confirm_spread)
			
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
	
	if Input.is_action_just_pressed("weapon_toggle_next"):
		
		weapon_index = wrap(weapon_index + 1, 0, weapons.size())
		initiate_change_weapon(weapon_index)
		
		Audio.play("src/sounds/weapon_change.ogg")
	
	elif Input.is_action_just_pressed("weapon_toggle_prev"):

		weapon_index = wrap(weapon_index - 1, 0, weapons.size())
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
