@tool
extends SceneTree

func _init():
    var level = load("res://levels/level_51.tres")
    if level == null:
        print("Failed to load res://levels/level_51.tres")
    else:
        print("Loaded level 51 successfully.")
        var problems = level.validate()
        if problems.size() > 0:
            print("Validation failed:")
            for p in problems:
                print(" - ", p)
        else:
            print("Validation passed.")
    quit()
