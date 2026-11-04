class_name MovePlan
extends RefCounted
## What a move action would do, computed by Battle.plan_walk() / plan_push() for the preview
## and given back to Battle.do_move() to run it. Runtime only, never saved.

enum Kind { WALK, PUSH }

var kind: Kind = Kind.WALK
var mover: Character
## False when the move can't be done (spot taken, wall in the way, nothing to push...).
var valid := false
## Where the mover ends: the clicked spot (WALK) or the contact point behind the victim (PUSH).
var destination := Vector2.ZERO

# PUSH only
var victim: Character
## Unit vector from the mover to the victim: the center of the 40 degree cone.
var axis := Vector2.RIGHT
## Unit vector the victim slides along: the mouse direction kept inside the cone.
var direction := Vector2.RIGHT
## Where the victim ends (it stops at a wall or on the character it hits).
var push_end := Vector2.ZERO
## The character the victim runs into, null when the way is clear.
var collided: Character
var damage_to_victim := 0
var damage_to_other := 0
