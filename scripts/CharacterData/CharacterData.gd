class_name CharacterData
extends Resource
## Describes one hero or enemy. Create a .tres per character in the inspector
## (right click in FileSystem > New Resource > CharacterData).

enum Team { ALLY, ENEMY }

const TILE_SIZE := 32

@export_group("Identity")
@export var id: StringName
@export var display_name: String = ""
@export var team: Team = Team.ENEMY
## Heroes only. Locked heroes are hidden from the team selection.
## TODO: replace by the player's save data once there is one.
@export var unlocked_by_default: bool = true

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


## The whole sprite, cut from the tileset.
func get_sprite_texture() -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = tileset
	atlas.region = Rect2(Vector2(tile_coords * TILE_SIZE), Vector2(size_in_tiles * TILE_SIZE))
	return atlas


## A cut of the sprite centered on the head (portraits, intent icons...).
## Never goes outside the sprite, so it can't show a neighbouring tile.
func get_head_texture(size: Vector2 = Vector2(16, 16)) -> AtlasTexture:
	var full := get_sprite_texture()
	var atlas := AtlasTexture.new()
	atlas.atlas = tileset
	var crop := Rect2(full.region.position + head_position - size / 2.0, size)
	atlas.region = crop.intersection(full.region)
	return atlas
