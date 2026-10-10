class_name CharacterData
extends Resource
## Describes one hero or enemy. Create a .tres per character in the inspector
## (right click in FileSystem > New Resource > CharacterData).

enum Team { ALLY, ENEMY }

@export_group("Identity")
@export var id: StringName
@export var display_name: String = ""
@export var team: Team = Team.ENEMY

@export_group("Sprite")
## The tileset image (e.g. the 32x32 spritesheet).
@export var tileset: Texture2D
## Tile position in the sheet, in tiles (not pixels). (0, 0) is the top-left tile.
@export var tile_coords: Vector2i = Vector2i.ZERO
## Size in tiles. Leave at (1, 1) for 32x32, use (2, 2) for a big boss.
@export var size_in_tiles: Vector2i = Vector2i.ONE
## Where the head is, in pixels from the top-left of the sprite.
## Used to cut the head out for the intent icon shown above enemies.
@export var head_position: Vector2 = Vector2(16, 8)

@export_group("Stats")
@export var max_health: int = 50
@export var starting_armor: int = 0
@export var starting_evasion: int = 0

@export_group("Cards")
## Heroes: the cards this hero adds to the shared draw pile.
@export var deck: Array[CardData] = []

@export_group("Default attack (enemies, placeholder)")
## Used until enemies get real attack patterns made of cards.
@export var attack_damage: int = 5
@export_range(0.0, 1000.0, 1.0, "or_greater", "suffix:px") var attack_range: float = 32.0

# Extension point for later:
# @export var action_pattern: Array[CardData]  # enemies: telegraphed actions
