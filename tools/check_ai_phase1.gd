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
	_check("reasoning geometri uretiminde kapali", body["reasoning"]["enabled"], false)
	_check("yaratici cesitlilik sicakligi etkin", body["temperature"], 1.0)
	_check("sema tam istenen taslak sayisi", body["response_format"]["json_schema"]
		["schema"]["properties"]["levels"]["minItems"], 5)
	_check("launcher semasi guvenli alt bantta", body["response_format"]["json_schema"]
		["schema"]["properties"]["levels"]["items"]["properties"]
		["launcher"]["properties"]["y"]["minimum"], 1080.0)
	_check("provider parametreleri zorunlu", body["provider"]["require_parameters"], true)
	_check("prompt dogrudan sema ciktisi istiyor",
		String(messages[0]["content"]).contains("Analiz, reasoning, Markdown"), true)
	_check("prompt sayisal guvenli mesafe veriyor",
		String(messages[0]["content"]).contains("hedefe 190 px"), true)
	# Cipa bilerek "zor" kuralinin ASIL sartina bakiyor: cok sekmeli rota
	# istemesi. Eski cipa ("tek ana sektiriciyle") yalnizca bir ifadenin
	# varligini olcuyordu ve prompt tek sekmeli bolum isterken de gecerdi.
	_check("prompt zorluk sozlesmesi cok sekme istiyor",
		String(messages[1]["content"]).contains("2-4 kontrollu sekme"), true)
	var alternate_messages := AILevelPromptBuilder.build_messages({
		"template": "two_routes",
		"difficulty": "hard",
		"mechanics": PackedStringArray(["panel", "wall_gap"]),
		"design_note": "iki farkli rota",
		"diversity_seed": 987654,
	}, 5)
	_check("istek cesitlilik nonce'i tasiyor",
		String(alternate_messages[1]["content"]).contains("987654"), true)
	_check("farkli seed farkli tasarim yonu veriyor",
		alternate_messages[1]["content"] != messages[1]["content"], true)
	_check("yeni sablonlar sozlesmede",
		"ricochet_chain" in AILevelContract.TEMPLATE_IDS
			and "block_corridor" in AILevelContract.TEMPLATE_IDS, true)
	var corridor_messages := AILevelPromptBuilder.build_messages({
		"template": "block_corridor",
		"difficulty": "hard",
		"mechanics": PackedStringArray(["breakable_block"]),
	}, 3)
	_check("blok koridoru promptu zorunlu ilerleme istiyor",
		String(corridor_messages[0]["content"]).contains("2-4 atislik"), true)
	_check("blok koridorunda eski opsiyonel blok talimati yok",
		String(corridor_messages[0]["content"]).contains("hepsini kirmak zorunlu olmamali"), false)
	_check("blok koridoru eski blocksuz zorluk metnini almiyor",
		String(corridor_messages[1]["content"]).contains("blocksuz/paneller"), false)
	var chain_messages := AILevelPromptBuilder.build_messages({
		"template": "ricochet_chain",
		"difficulty": "hard",
		"mechanics": PackedStringArray(["panel"]),
	}, 3)
	_check("sekme zinciri zorlugu uzun rota istiyor",
		String(chain_messages[1]["content"]).contains("6-9 kontrollu sekme"), true)
	_check("sekme zinciri eski 1-2 sekme metnini almiyor",
		String(chain_messages[1]["content"]).contains("1-2 sekmeli"), false)
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
	_check("DNS hatasi ayirt ediliyor",
		OpenRouterClient.transport_error_message(HTTPRequest.RESULT_CANT_RESOLVE).contains("DNS"), true)
	_check("TLS hatasi ayirt ediliyor",
		OpenRouterClient.transport_error_message(HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR).contains("tarih/saat"), true)
	_check("timeout ayirt ediliyor",
		OpenRouterClient.transport_error_message(HTTPRequest.RESULT_TIMEOUT).contains("zaman asimi"), true)
	_check("mesgul istemci ayirt ediliyor",
		OpenRouterClient.request_start_error_message(ERR_BUSY).contains("mesgul"), true)
	var client_source := FileAccess.get_file_as_string("res://scripts/editor/openrouter_client.gd")
	_check("gecersiz 2xx JSON tek fallback aliyor", client_source.contains(
		"elif not _fallback_used:\n\t\t\t_fallback_used = true\n\t\t\t_using_json_fallback = true"), true)
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
	values["template"] = "ricochet_chain"
	values["mechanics"] = PackedStringArray()
	_check("sekme zinciri paneli zorunlu kiliyor",
		settings.sanitize(values)["mechanics"].has("panel"), true)
	values["template"] = "block_corridor"
	values["mechanics"] = PackedStringArray(["panel"])
	_check("blok koridoru kirilabilir blok ekliyor",
		settings.sanitize(values)["mechanics"].has("breakable_block"), true)
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
