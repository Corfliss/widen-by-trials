extends Resource
class_name Weapon

## Color identity of the gun for the color-match hit rule
## (colorprune-style: a shot only damages an enemy of the same color).
## Order matches colorprune's codes: 0 = RED, 1 = BLACK, 2 = WHITE.
enum GunColor { RED, BLACK, WHITE }

@export_subgroup("Model")
@export var model: PackedScene  # Model of the weapon
@export var position: Vector3  # On-screen position
@export var rotation: Vector3  # On-screen rotation
@export var muzzle_position: Vector3  # On-screen position of muzzle flash
@export var model_scale: float = 1.0  # Scale of the on-screen model

@export_subgroup("Properties")
## Which enemy color this gun matches: Red = Blood Shotgun, Black = Sweat Carbine, White = Tears Machine Gun
@export var gun_color: GunColor = GunColor.BLACK
@export_range(0.1, 1) var cooldown: float = 0.1  # Firerate
@export_range(1, 300) var max_distance: int = 300  # Fire distance
@export_range(0, 100) var damage: float = 25  # Damage per hit
@export_range(0, 5) var spread: float = 0  # Spread of each shot
@export_range(1, 5) var shot_count: int = 1  # Amount of shots
@export_range(0, 50) var knockback: int = 20  # Amount of knockback

@export_subgroup("Sounds")
## Comma-separated pool of shoot-sound paths (res-relative), one picked at random per shot.
@export var sound_shoot: String  # Sound path
## Center pitch of the shoot sound (1.0 = as authored). Lets each gun sit in
## its own register without needing pitch-shifted asset variants.
@export_range(0.25, 4.0) var sound_pitch: float = 1.0
## Half-width of the per-shot random pitch jitter around sound_pitch.
@export_range(0.0, 1.0) var sound_pitch_spread: float = 0.1

@export_subgroup("Crosshair")
@export var crosshair: Texture2D  # Image of crosshair on-screen
