@tool
class_name EncounterData
extends Resource
## One battle: who the heroes fight, what they have to do, and how everyone is placed.
## Stored in a battle or boss node of an expedition.

## Only STANDARD exists for now (fixed spawn markers). AMBUSH (the heroes surprise
## the enemies) and AMBUSHED (the opposite) are placeholders for the battle's
## spawn-position function.
enum SpawnPattern { STANDARD, AMBUSH, AMBUSHED }

## Enemies that are always in this battle. With `fill_with_pool` off this is the whole fight.
@export var enemies: Array[CharacterData] = []
## On: more enemies are added from the expedition's pool (its enemy_tags) until the threat budget
## of the node is spent (see EncounterGenerator). `enemies` then are the guaranteed ones, for
## example a boss. Leave `enemies` empty for a normal generated fight.
@export var fill_with_pool: bool = false
## A scene whose root extends BattleObjective (kill a boss, destroy an object...).
## Empty = the default objective: defeat all enemies.
@export var objective_scene: PackedScene
@export var spawn_pattern: SpawnPattern = SpawnPattern.STANDARD
