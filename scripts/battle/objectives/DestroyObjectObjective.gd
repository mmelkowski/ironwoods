class_name DestroyObjectObjective
extends KillRoleObjective
## Win when the object (a totem, a casket...) is destroyed, even if the boss and its escorts
## are still alive. The object is any enemy whose CharacterData.roles contains Role.OBJECT.
## It should also have `acts` and `can_be_moved` off, so it neither attacks nor slides.


func _init() -> void:
	role = CharacterData.Role.OBJECT
	verb = "Destroy"
	progress_label = "Objects left"
	description = "Destroy the object"


func _on_target_found(target: Character) -> void:
	if target.data.acts:
		push_warning("DestroyObjectObjective: '%s' has `acts` on, it will attack like an enemy. Turn off `acts` and `can_be_moved` in its CharacterData." % target.data.display_name)
