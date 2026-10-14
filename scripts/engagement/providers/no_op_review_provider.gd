class_name NoOpReviewProvider
extends ReviewProvider

## Desktop, editor and exports without the Android plugin continue immediately.


func provider_name() -> StringName:
	return &"noop"


func initialize() -> bool:
	return true
