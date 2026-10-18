class_name BuildingLevel
extends Resource
## One level of a building: what it costs to reach it and what it gives.
## Used inside BuildingData.levels.

## Resources spent to reach this level: { &"wood": 10, &"stone": 5 }.
@export var cost: Dictionary[StringName, int] = {}
## What this level brings (shown in the carpentry workshop).
@export_multiline var description: String = ""
