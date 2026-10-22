extends Node

## Session-scoped flags that must outlive scene changes (autoload).
## Nothing here is saved: restart the game and every flag resets — by design.

enum TutorialPolicy { ONCE_PER_SESSION, ALWAYS, NEVER }

## When the tutorial runs. ONCE_PER_SESSION (default): first level load
## per app launch, then skipped until the game is closed and reopened.
@export var tutorial_policy: TutorialPolicy = TutorialPolicy.ONCE_PER_SESSION

var tutorial_done := false

func should_run_tutorial() -> bool:
	match tutorial_policy:
		TutorialPolicy.ALWAYS:
			return true
		TutorialPolicy.NEVER:
			return false
		_:
			return not tutorial_done

func mark_tutorial_done() -> void:
	tutorial_done = true
