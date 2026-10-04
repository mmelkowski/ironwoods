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

@export_group("Stats")
@export var max_health: int = 50
@export var starting_armor: int = 0
@export var starting_evasion: int = 0

# Extension points for later:
# @export var deck: Array[CardData]            # heroes: cards drawn each turn
# @export var action_pattern: Array[CardData]  # enemies: telegraphed actions
