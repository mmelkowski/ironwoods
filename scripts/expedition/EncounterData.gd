@tool
class_name EncounterData
extends Resource
## One battle: who the heroes fight, what they have to do, and how everyone is placed.
## Stored in a battle or boss node of an expedition.

## Only STANDARD exists for now (fixed spawn markers). AMBUSH (the heroes surprise
## the enemies) and AMBUSHED (the opposite) are placeholders for the battle's
## spawn-position function.
enum SpawnPattern { STANDARD, AMBUSH, AMBUSHED }

@export var enemies: Array[CharacterData] = []
## A scene whose root extends BattleObjective (kill a boss, destroy an object...).
## Empty = the default objective: defeat all enemies.
@export var objective_scene: PackedScene
@export var spawn_pattern: SpawnPattern = SpawnPattern.STANDARD
