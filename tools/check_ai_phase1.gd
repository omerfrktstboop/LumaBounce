extends SceneTree

const SETTINGS_PATH := "user://ai_settings_phase1_test.cfg"

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_test_contract_and_request()
	_test_response_rules()
	_test_settings()
	_test_cancel()
	print("AI ASAMA 1: %d gecti, %d kaldi." % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_contract_and_request() -> void:
	var client := OpenRouterClient.new()
	root.add_child(client)
	var messages := AILevelPromptBuilder.build_messages({
		"template": "two_routes",
		"difficulty": "hard",
		"mechanics": PackedStringArray(["panel", "wall_gap"]),
		"design_note": "iki farkli rota",
	}, 5)
	var body := client.build_request_body("vendor/exact-model", messages, 5)
	_check("endpoint", client.ENDPOINT, "https://openrouter.ai/api/v1/chat/completions")
	_check("model slug aynen korunuyor", body["model"], "vendor/exact-model")
	_check("json schema etkin", body["response_format"]["type"], "json_schema")
	_check("strict schema", body["response_format"]["json_schema"]["strict"], true)
	_check("provider parametreleri zorunlu", body["provider"]["require_parameters"], true)
	var headers := client.build_headers("secret-test-key")
	_check("authorization olusuyor", headers[0], "Authorization: Bearer secret-test-key")
	_check("prompt anahtari icermiyor", JSON.stringify(messages).contains("secret-test-key"), false)
	root.remove_child(client)
	client.free()


func _test_response_rules() -> void:
	var unsupported := {"error": {"message": "response_format json_schema is unsupported"}}
	_check("acik structured 400 fallback", OpenRouterClient.is_structured_output_unsupported(400, unsupported), true)
	_check("belirsiz 400 fallback degil", OpenRouterClient.is_structured_output_unsupported(400, {"error": {"message": "bad input"}}), false)
	_check("401 retry yok", OpenRouterClient.should_retry_status(401, false), false)
	_check("429 tek retry", OpenRouterClient.should_retry_status(429, false), true)
	_check("429 ikinci retry yok", OpenRouterClient.should_retry_status(429, true), false)
	_check("5xx tek retry", OpenRouterClient.should_retry_status(503, false), true)
	var invalid := OpenRouterClient.parse_chat_response("not-json".to_utf8_buffer())
	_check("gecersiz json reddediliyor", invalid["ok"], false)
	var valid_body := JSON.stringify({
		"choices": [{"message": {"content": JSON.stringify({"levels": []})}}],
		"usage": {"prompt_tokens": 12, "completion_tokens": 34},
	}).to_utf8_buffer()
	var valid := OpenRouterClient.parse_chat_response(valid_body)
	_check("gecerli json okunuyor", valid["ok"], true)
	_check("usage korunuyor", valid["usage"]["completion_tokens"], 34)


func _test_settings() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	var settings := AIGeneratorSettings.new(SETTINGS_PATH)
	var values := settings.defaults()
	values["model_slug"] = "vendor/model"
	values["remember_api_key"] = false
	settings.save_values(values, "must-not-reach-disk")
	var disk_text := FileAccess.get_file_as_string(SETTINGS_PATH)
	_check("model saklaniyor", settings.load_values()["model_slug"], "vendor/model")
	_check("remember false key yazmiyor", disk_text.contains("must-not-reach-disk"), false)
	values["remember_api_key"] = true
	settings.save_values(values, "local-key")
	_check("acik onayla key yerel kayitta", settings.load_values()["api_key"], "local-key")
	settings.clear_api_key()
	_check("anahtar temizleniyor", settings.load_values()["api_key"], "")
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	file.store_string("this is not a config")
	file.close()
	_check("bozuk ayar varsayilana donuyor", settings.load_values()["blueprint_count"], 5)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


func _test_cancel() -> void:
	var client := OpenRouterClient.new()
	root.add_child(client)
	var did_cancel := [false]
	client.cancelled.connect(func() -> void: did_cancel[0] = true)
	client.set("_running", true)
	client.set("_api_key", "temporary-key")
	client.cancel_request()
	_check("cancel calisan istegi durduruyor", client.is_running(), false)
	_check("cancel sinyali", did_cancel[0], true)
	_check("cancel anahtari bellekten siliyor", client.get("_api_key"), "")
	root.remove_child(client)
	client.free()


func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
		return
	_failed += 1
	print("HATA %s: beklenen %s, gelen %s" % [label, expected, actual])
