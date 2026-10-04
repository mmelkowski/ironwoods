class_name StatusData
extends Resource
## Defines one kind of status (Bleeding, Stun, Evasion...).
## Create one .tres per status. Stacks are NOT stored here: a status on a
## character is just "this StatusData x N stacks".

## TURNS: X stacks = active for X turns (e.g. Stun, Bleeding).
## USES:  X stacks = can be consumed X times (e.g. Evasion).
enum DurationType { TURNS, USES }

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var duration_type: DurationType = DurationType.TURNS
