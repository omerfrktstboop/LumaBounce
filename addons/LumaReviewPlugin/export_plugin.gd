@tool
extends EditorPlugin

var export_plugin: ReviewAndroidExportPlugin


func _enter_tree() -> void:
	export_plugin = ReviewAndroidExportPlugin.new()
	add_export_plugin(export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	export_plugin = null


class ReviewAndroidExportPlugin extends EditorExportPlugin:
	const PLUGIN_NAME := "LumaReviewPlugin"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(
			_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var flavor := "debug" if debug else "release"
		return PackedStringArray([
			"%s/bin/%s/%s-%s.aar" % [PLUGIN_NAME, flavor, PLUGIN_NAME, flavor]
		])

	func _get_android_dependencies(
			_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["com.google.android.play:review:2.0.2"])

	func _get_name() -> String:
		return PLUGIN_NAME
