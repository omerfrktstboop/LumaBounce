extends SceneTree

## Focused stage-4 regression. It never opens an external app, writes a real
## save, requests an ad or calls Google Play.

class MemoryProgress extends ProgressStore:
	var writes := 0
	func save() -> void:
		writes += 1


class MockReviewProvider extends ReviewProvider:
	var available := true
	var busy := false
	var start_allowed := true
	var requests := 0
	var auto_finish := true

	func provider_name() -> StringName:
		return &"mock"

	func initialize() -> bool:
		return true

	func is_available() -> bool:
		return available and not busy

	func is_busy() -> bool:
		return busy

	func request_review() -> bool:
		if not start_allowed or not is_available():
			return false
		requests += 1
		busy = true
		if auto_finish:
			finish.call_deferred(true)
		return true

	func finish(completed: bool) -> void:
		if not busy:
			return
		busy = false
		review_finished.emit(completed)


class BusyAdProvider extends AdProvider:
	func initialize() -> bool:
		return true

	func is_fullscreen_busy() -> bool:
		return true


var _passed := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_persistence_and_policy()
	await _test_request_lifecycle()
	await _test_app_root_guards()
	await _test_settings_ui()
	_test_safe_links_and_plugin_package()
	_check("all test sections executed", _passed + _failed >= 36)
	print("REVIEW + FEEDBACK: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed else 0)


func _test_persistence_and_policy() -> void:
	var existing := MemoryProgress.new()
	existing._read(ConfigFile.new())
	_check("old save defaults to zero review sessions", existing.review_session_count == 0)
	_check("old save defaults to no review attempt", existing.last_review_attempt_unix == 0)
	var stored := ConfigFile.new()
	stored.set_value(ProgressStore.SECTION_SETTINGS,
		ProgressStore.KEY_REVIEW_SESSION_COUNT, 7)
	stored.set_value(ProgressStore.SECTION_SETTINGS,
		ProgressStore.KEY_LAST_REVIEW_ATTEMPT_UNIX, 123456)
	existing._read(stored)
	_check("review session count loads", existing.review_session_count == 7)
	_check("review attempt timestamp loads", existing.last_review_attempt_unix == 123456)
	existing.reset()
	_check("progress reset preserves review sessions", existing.review_session_count == 7)
	_check("progress reset preserves review cooldown", existing.last_review_attempt_unix == 123456)
	var progress := MemoryProgress.new()
	var provider := MockReviewProvider.new()
	var service := _service(progress, provider)
	service.record_session()
	service.record_session()
	_check("one service records one launch", progress.review_session_count == 1)
	_check("session persistence writes once", progress.writes == 1)
	progress.completed_levels.assign([1, 2, 3, 4, 5])
	_check("one session is below threshold", not service.is_eligible(1_000_000))
	progress.review_session_count = 2
	_check("five levels and two sessions are eligible", service.is_eligible(1_000_000))
	progress.completed_levels.assign([1, 2, 3, 4])
	_check("four levels are below threshold", not service.is_eligible(1_000_000))
	progress.completed_levels.append(5)
	progress.last_review_attempt_unix = 1_000_000
	_check("cooldown blocks an early repeat", not service.is_eligible(
		1_000_000 + ReviewService.COOLDOWN_SECONDS - 1))
	_check("cooldown expires exactly at ninety days", service.is_eligible(
		1_000_000 + ReviewService.COOLDOWN_SECONDS))
	_check("future timestamp cannot prompt", not service.is_eligible(999_999))
	service.queue_free()


func _test_request_lifecycle() -> void:
	var progress := _eligible_progress()
	var provider := MockReviewProvider.new()
	var service := _service(progress, provider)
	var result := int(await service.request_if_eligible(false, 2_000_000))
	_check("eligible request reaches provider", provider.requests == 1)
	_check("eligible request reports attempted", result == ReviewService.Result.ATTEMPTED)
	_check("attempt timestamp is persisted", progress.last_review_attempt_unix == 2_000_000)
	_check("request completion clears busy state", not service.is_busy())
	_check("provider completion does not store a rating", not _has_property(progress, "reviewed"))
	var writes_after_attempt := progress.writes
	result = int(await service.request_if_eligible(false, 2_000_001))
	_check("cooldown skips duplicate provider call", provider.requests == 1)
	_check("cooldown result is not eligible", result == ReviewService.Result.NOT_ELIGIBLE)
	_check("cooldown skip does not write", progress.writes == writes_after_attempt)
	service.queue_free()
	await process_frame

	progress = _eligible_progress()
	provider = MockReviewProvider.new()
	service = _service(progress, provider)
	result = int(await service.request_if_eligible(true, 3_000_000))
	_check("external modal blocker skips request", provider.requests == 0)
	_check("blocked request leaves timestamp empty", progress.last_review_attempt_unix == 0)
	provider.start_allowed = false
	result = int(await service.request_if_eligible(false, 3_000_000))
	_check("provider start failure reports unavailable", result == ReviewService.Result.UNAVAILABLE)
	_check("failed start is not persisted as attempt", progress.last_review_attempt_unix == 0)
	service.queue_free()
	await process_frame

	progress = _eligible_progress()
	var noop := NoOpReviewProvider.new()
	service = _service(progress, noop)
	service.record_session()
	_check("missing platform provider does not count a session",
		progress.review_session_count == 2)
	result = int(await service.request_if_eligible(false, 4_000_000))
	_check("missing platform provider continues safely",
		result == ReviewService.Result.NOT_ELIGIBLE)
	_check("missing provider leaves attempt timestamp empty",
		progress.last_review_attempt_unix == 0)
	service.queue_free()
	await process_frame


func _test_app_root_guards() -> void:
	var progress := _eligible_progress()
	var provider := MockReviewProvider.new()
	var service := _service(progress, provider)
	var app = load("res://scripts/app_root.gd").new()
	app.set("_review_service", service)
	var game = (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	game.set("_attempt_finished", true)
	game.set("_attempt_completed", true)
	var attempted: bool = await app._request_review_if_eligible(game)
	_check("completed result can request review", attempted)
	_check("completed result called provider once", provider.requests == 1)
	progress.last_review_attempt_unix = 0
	var ad_service := AdService.new()
	ad_service.configure(BusyAdProvider.new(), null, null)
	root.add_child(ad_service)
	ad_service.initialize()
	app.set("_ad_service", ad_service)
	attempted = await app._request_review_if_eligible(game)
	_check("active ad or consent flow suppresses review", not attempted)
	_check("active ad flow makes no provider call", provider.requests == 1)
	app.set("_ad_service", null)
	var purchase_service := PurchaseService.new()
	purchase_service.set("_purchase_busy", true)
	app.set("_purchase_service", purchase_service)
	attempted = await app._request_review_if_eligible(game)
	_check("active purchase flow suppresses review", not attempted)
	_check("active purchase makes no provider call", provider.requests == 1)
	app.set("_purchase_service", null)
	game.tutorial_replay = true
	attempted = await app._request_review_if_eligible(game)
	_check("tutorial replay suppresses review", not attempted)
	_check("tutorial replay makes no provider call", provider.requests == 1)
	game.tutorial_replay = false
	game.set("_attempt_completed", false)
	attempted = await app._request_review_if_eligible(game)
	_check("failure result suppresses review", not attempted)
	_check("failure makes no provider call", provider.requests == 1)
	game.free()
	app.free()
	ad_service.queue_free()
	purchase_service.free()
	service.queue_free()
	await process_frame


func _test_settings_ui() -> void:
	var previous_size := root.size
	var previous_locale := TranslationServer.get_locale()
	var settings = (load("res://scenes/settings.tscn") as PackedScene).instantiate()
	settings.progress = MemoryProgress.new()
	root.add_child(settings)
	await process_frame
	_check("settings exposes rate action",
		settings.find_child("RateGameIcon", true, false) != null)
	_check("settings exposes feedback action",
		settings.find_child("SendFeedbackIcon", true, false) != null)
	var emitted := [0, 0]
	settings.rate_requested.connect(func() -> void: emitted[0] += 1)
	settings.feedback_requested.connect(func() -> void: emitted[1] += 1)
	var rate_icon := settings.find_child("RateGameIcon", true, false)
	var feedback_icon := settings.find_child("SendFeedbackIcon", true, false)
	var rate_button := rate_icon.get_parent().get_parent() as Button
	var feedback_button := feedback_icon.get_parent().get_parent() as Button
	var settings_scroll := settings.get_node("SafeArea/Content/Scroll") as ScrollContainer
	_check("settings touch scroll keeps a tap deadzone", settings_scroll.scroll_deadzone >= 12)
	var blocked_scroll_buttons: Array[String] = []
	for node in settings_scroll.find_children("*", "Control", true, false):
		var control := node as Control
		if control is BaseButton and control.mouse_filter != Control.MOUSE_FILTER_PASS:
			blocked_scroll_buttons.append(str(control.get_path()))
	_check("settings buttons pass touch drags to scroll container",
		blocked_scroll_buttons.is_empty())
	var volume_slider := _first_slider(settings_scroll)
	_check("volume slider keeps direct horizontal drag input",
		volume_slider != null and volume_slider.mouse_filter == Control.MOUSE_FILTER_STOP)
	var haptics_before := Haptics.enabled
	var shake_before := ScreenShake.trauma_scale
	rate_button.pressed.emit()
	feedback_button.pressed.emit()
	_check("rate row emits request without opening itself", emitted[0] == 1)
	_check("feedback row emits request without sending itself", emitted[1] == 1)
	settings.set("_last_scroll_msec", Time.get_ticks_msec())
	rate_button.pressed.emit()
	feedback_button.pressed.emit()
	_check("recent scroll blocks accidental support actions", emitted == [1, 1])
	settings.set("_last_scroll_msec", -100000)
	_check("support actions keep large touch targets",
		rate_button.custom_minimum_size.y >= 64.0 \
		and feedback_button.custom_minimum_size.y >= 64.0)
	_check("support actions preserve haptics preference", Haptics.enabled == haptics_before)
	_check("support actions preserve shake preference",
		is_equal_approx(ScreenShake.trauma_scale, shake_before))
	_check("support actions use different shape cues",
		int(rate_icon.get("glyph")) != int(feedback_icon.get("glyph")))
	var status := settings.find_child("ExternalLinkStatus", true, false) as Label
	_check("link error starts hidden", status != null and not status.visible)
	settings.show_external_link_error()
	_check("link failure gives visible feedback", status.visible)
	_check("link failure text is translated key output",
		not status.text.is_empty() and status.text != "EXTERNAL_LINK_FAILED")

	var changed_locales: Array[String] = []
	settings.language_changed.connect(func(code: String) -> void: changed_locales.append(code))
	for viewport_size in [Vector2i(360, 640), Vector2i(540, 960), Vector2i(900, 1200),
			Vector2i(1280, 720)]:
		root.size = viewport_size
		await process_frame
		for locale in ["tr", "en", "es", "pt_BR", "de", "fr"]:
			var locale_index := Locale.SUPPORTED.find(locale)
			settings._on_language_chosen(locale_index)
			settings._rebuild()
			await process_frame
			await process_frame
			rate_icon = settings.find_child("RateGameIcon", true, false)
			feedback_icon = settings.find_child("SendFeedbackIcon", true, false)
			rate_button = rate_icon.get_parent().get_parent() as Button
			feedback_button = feedback_icon.get_parent().get_parent() as Button
			var rate_label := _action_label(rate_icon)
			var feedback_label := _action_label(feedback_icon)
			var suffix := "%s %dx%d" % [locale, viewport_size.x, viewport_size.y]
			_check("rate label translated and visible " + suffix,
				rate_label != null and rate_label.text == tr("RATE_GAME") \
				and not rate_label.text.is_empty())
			_check("feedback label translated and visible " + suffix,
				feedback_label != null and feedback_label.text == tr("SEND_FEEDBACK") \
				and not feedback_label.text.is_empty())
			_check("support labels fit " + suffix,
				rate_label.size.x + 1.0 >= rate_label.get_minimum_size().x \
				and feedback_label.size.x + 1.0 >= feedback_label.get_minimum_size().x)
			_check("support touch targets remain usable " + suffix,
				rate_button.size.y >= 64.0 and feedback_button.size.y >= 64.0)
			_check("support rows fit viewport " + suffix,
				rate_button.get_global_rect().end.x <= settings.get_global_rect().end.x + 1.0 \
				and feedback_button.get_global_rect().end.x <= settings.get_global_rect().end.x + 1.0)
	_check("language changes emit for every QA layout", changed_locales.size() == 24)
	var final_rate_label := _action_label(settings.find_child("RateGameIcon", true, false))
	_check("support label contrast meets WCAG AA",
		_contrast_ratio(final_rate_label.get_theme_color("font_color"), Palette.INK_MID) >= 4.5)
	var tutorial_source := FileAccess.get_file_as_string(
		"res://scripts/ui/first_shot_tutorial.gd")
	_check("tutorial combines text with shape markers",
		tutorial_source.contains("_body.text = tr(") \
		and tutorial_source.contains("draw_arc(") \
		and tutorial_source.contains("draw_line("))
	_check("tutorial adds no mandatory haptics or shake",
		not tutorial_source.contains("Haptics.") \
		and not tutorial_source.contains("ScreenShake."))
	TranslationServer.set_locale(previous_locale)
	root.size = previous_size
	settings.queue_free()
	await process_frame


func _test_safe_links_and_plugin_package() -> void:
	var store_url := EngagementLinks.PLAY_STORE_URL
	_check("rating URL is HTTPS", store_url.begins_with("https://"))
	_check("rating URL targets exact package", store_url.ends_with(
		"id=com.ofsgames.lumabounce"))
	var feedback := EngagementLinks.feedback_uri(42)
	_check("feedback uses allowlisted address", feedback.begins_with(
		"mailto:ofsgamesofficial@gmail.com?"))
	_check("feedback draft includes game version", feedback.contains(GameVersion.GAME))
	_check("feedback draft includes optional level", feedback.contains("42"))
	_check("feedback draft contains no ad identifier", not feedback.to_lower().contains("admob"))
	_check("feedback draft contains no purchase token",
		not feedback.to_lower().contains("purchase_token"))
	_check("legal HTTPS helper still rejects mailto", not LegalLinks.is_openable(feedback))
	var previous_locale := TranslationServer.get_locale()
	var expected_subjects := {
		"tr": "geri bildirim",
		"en": "feedback",
		"es": "Comentarios",
		"pt_BR": "Feedback",
		"de": "LumaBounce-Feedback",
		"fr": "Avis",
	}
	for locale in ["tr", "en", "es", "pt_BR", "de", "fr"]:
		TranslationServer.set_locale(locale)
		var localized_draft := EngagementLinks.feedback_uri(42)
		_check("feedback draft is translated for " + locale,
			localized_draft.uri_decode().contains(expected_subjects[locale]))
	TranslationServer.set_locale(previous_locale)
	_check("debug review AAR exists", FileAccess.file_exists(
		"res://addons/LumaReviewPlugin/bin/debug/LumaReviewPlugin-debug.aar"))
	_check("release review AAR exists", FileAccess.file_exists(
		"res://addons/LumaReviewPlugin/bin/release/LumaReviewPlugin-release.aar"))
	var export_source := FileAccess.get_file_as_string(
		"res://addons/LumaReviewPlugin/export_plugin.gd")
	_check("export adds official Play Review dependency",
		export_source.contains("com.google.android.play:review:2.0.2"))
	var manifest := FileAccess.get_file_as_string(
		"res://tools/android_review_plugin/src/main/AndroidManifest.xml")
	_check("plugin manifest uses Godot v2 metadata",
		manifest.contains("org.godotengine.plugin.v2.LumaReviewPlugin"))


func _eligible_progress() -> MemoryProgress:
	var progress := MemoryProgress.new()
	progress.completed_levels.assign([1, 2, 3, 4, 5])
	progress.review_session_count = 2
	return progress


func _service(progress: ProgressStore, provider: ReviewProvider) -> ReviewService:
	var service := ReviewService.new()
	service.configure(provider, progress)
	root.add_child(service)
	service.initialize()
	return service


func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if String(property.get("name", "")) == property_name:
			return true
	return false


func _action_label(icon: Node) -> Label:
	if icon == null or icon.get_parent() == null:
		return null
	for child in icon.get_parent().get_children():
		if child is Label:
			return child as Label
	return null


func _first_slider(parent: Node) -> HSlider:
	for node in parent.find_children("*", "HSlider", true, false):
		return node as HSlider
	return null


func _contrast_ratio(foreground: Color, background: Color) -> float:
	var foreground_luminance := _relative_luminance(foreground)
	var background_luminance := _relative_luminance(background)
	return (maxf(foreground_luminance, background_luminance) + 0.05) \
		/ (minf(foreground_luminance, background_luminance) + 0.05)


func _relative_luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b


func _check(label: String, passed: bool) -> void:
	if passed:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: " + label)
