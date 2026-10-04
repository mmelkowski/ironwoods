class_name StatusApplication
extends Resource
## "Give X stacks of this status to that recipient when this happens."
## A card holds an array of these, so on-play and on-kill effects share one design.
##
## Examples:
##   ON_PLAY + TARGET + Bleeding x3  -> the hit makes the enemy bleed
##   ON_KILL + SELF   + Evasion x1   -> killing an enemy gives you a dodge

enum Trigger { ON_PLAY, ON_KILL }
enum Recipient { TARGET, SELF }

@export var trigger: Trigger = Trigger.ON_PLAY
@export var recipient: Recipient = Recipient.TARGET
@export var status: StatusData
@export_range(1, 99) var stacks: int = 1

# Note: with ON_KILL the target is already dead, so use SELF for those.
