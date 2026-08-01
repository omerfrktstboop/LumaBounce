class_name OpenRouterClient
extends Node

## Debug-only OpenRouter chat/completions istemcisi. Ham yanitlari ve header'lari
## loglamaz; API anahtari yalnizca suren istegin belleginde tutulur.

signal status_changed(message: String)
signal completed(document: Dictionary, usage: Dictionary)
signal failed(message: String, status_code: int)
signal cancelled

const ENDPOINT := "https://openrouter.ai/api/v1/chat/completions"
const REQUEST_TIMEOUT := 60.0
const MAX_TOKENS := 5000

var _http: HTTPRequest
var _running := false
var _cancel_requested := false
var _api_key := ""
var _model_slug := ""
var _options := {}
var _blueprint_count := 5
var _fallback_used := false
var _transient_retry_used := false
var _using_json_fallback := false


func _ready() -> void:
	_ensure_http()


func is_running() -> bool:
	return _running


func request_blueprints(api_key: String, model_slug: String, options: Dictionary,
		blueprint_count: int) -> Error:
	if not OS.is_debug_build():
		_fail("OpenRouter uretimi yalnizca debug surumunde kullanilabilir.", 0)
		return ERR_UNAUTHORIZED
	if _running:
		return ERR_BUSY
	if api_key.strip_edges().is_empty():
		_fail("API anahtari gerekli.", 0)
		return ERR_INVALID_PARAMETER
	if model_slug.strip_edges().is_empty():
		_fail("Model slug'i gerekli.", 0)
		return ERR_INVALID_PARAMETER

	_api_key = api_key.strip_edges()
	_model_slug = model_slug.strip_edges()
	_options = options.duplicate(true)
	_blueprint_count = clampi(blueprint_count, 1, AILevelContract.MAX_LEVELS)
	_fallback_used = false
	_transient_retry_used = false
	_using_json_fallback = false
	_cancel_requested = false
	_running = true
	status_changed.emit("AI taslaklari bekleniyor...")
	return _send_current_request()


func cancel_request() -> void:
	if not _running:
		return
	_cancel_requested = true
	_running = false
	if _http != null:
		_http.cancel_request()
	_clear_secrets()
	cancelled.emit()


func build_headers(api_key: String) -> PackedStringArray:
	return PackedStringArray([
		"Authorization: Bearer %s" % api_key,
		"Content-Type: application/json",
		"X-Title: LumaBounce Debug Level Generator",
	])


func build_request_body(model_slug: String, messages: Array, requested_count: int,
		json_fallback := false) -> Dictionary:
	var body := {
		"model": model_slug,
		"messages": messages,
		"temperature": 0.8,
		"max_tokens": MAX_TOKENS,
		"stream": false,
		"provider": {
			"sort": "latency",
			"allow_fallbacks": true,
			"require_parameters": true,
		},
	}
	body["response_format"] = (
		{"type": "json_object"}
		if json_fallback
		else AILevelContract.structured_response_format(requested_count)
	)
	return body


static func is_structured_output_unsupported(status_code: int, response: Dictionary) -> bool:
	if status_code != 400:
		return false
	var message := _error_message(response).to_lower()
	var names_format := (
		message.contains("response_format")
		or message.contains("json_schema")
		or message.contains("structured output")
	)
	var names_rejection := (
		message.contains("unsupported")
		or message.contains("not support")
		or message.contains("invalid parameter")
	)
	return names_format and names_rejection


static func should_retry_status(status_code: int, already_retried: bool) -> bool:
	return not already_retried and (status_code == 429 or status_code >= 500)


static func parse_chat_response(bytes: PackedByteArray) -> Dictionary:
	var text := bytes.get_string_from_utf8()
	var envelope_parser := JSON.new()
	if envelope_parser.parse(text) != OK:
		return {"ok": false, "error": "OpenRouter gecersiz bir yanit dondurdu."}
	var envelope = envelope_parser.data
	if not envelope is Dictionary:
		return {"ok": false, "error": "OpenRouter gecersiz bir yanit dondurdu."}
	var choices = envelope.get("choices", [])
	if not choices is Array or choices.is_empty() or not choices[0] is Dictionary:
		return {"ok": false, "error": "OpenRouter yanitinda taslak bulunamadi."}
	var message = choices[0].get("message", {})
	if not message is Dictionary or not message.get("content", null) is String:
		return {"ok": false, "error": "OpenRouter yanitinda gecerli JSON metni bulunamadi."}
	var document_parser := JSON.new()
	if document_parser.parse(String(message["content"])) != OK:
		return {"ok": false, "error": "Model gecerli bolum JSON'u dondurmedi."}
	var document = document_parser.data
	if not document is Dictionary or not document.get("levels", null) is Array:
		return {"ok": false, "error": "Model gecerli bolum JSON'u dondurmedi."}
	var usage = envelope.get("usage", {})
	return {
		"ok": true,
		"document": document,
		"usage": usage if usage is Dictionary else {},
	}


func _ensure_http() -> void:
	if _http != null:
		return
	_http = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)


func _send_current_request() -> Error:
	_ensure_http()
	var messages := AILevelPromptBuilder.build_messages(
		_options, _blueprint_count, _using_json_fallback)
	var body := build_request_body(
		_model_slug, messages, _blueprint_count, _using_json_fallback)
	var error := _http.request(
		ENDPOINT, build_headers(_api_key), HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		_fail("Internet baglantisi kurulamadi.", 0)
	return error


func _on_request_completed(result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _running or _cancel_requested:
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("Internet baglantisi kurulamadi.", 0)
		return

	var response = JSON.parse_string(body.get_string_from_utf8())
	var response_dict: Dictionary = response if response is Dictionary else {}
	if response_code >= 200 and response_code < 300:
		var parsed := parse_chat_response(body)
		if bool(parsed["ok"]):
			_finish(parsed["document"], parsed["usage"])
		else:
			_fail(String(parsed["error"]), response_code)
		return

	if not _fallback_used and is_structured_output_unsupported(response_code, response_dict):
		_fallback_used = true
		_using_json_fallback = true
		status_changed.emit("Model icin JSON uyumluluk modu deneniyor...")
		_send_current_request()
		return
	if should_retry_status(response_code, _transient_retry_used):
		_transient_retry_used = true
		status_changed.emit("Gecici servis hatasi; istek bir kez daha deneniyor...")
		_retry_after_delay()
		return
	if response_code == 400 and _using_json_fallback:
		_fail("Secilen model yapilandirilmis JSON ciktisini desteklemiyor.", response_code)
		return
	_fail(_localized_error(response_code), response_code)


func _retry_after_delay() -> void:
	await get_tree().create_timer(1.0, true, false, true).timeout
	if _running and not _cancel_requested:
		_send_current_request()


func _finish(document: Dictionary, usage: Dictionary) -> void:
	_running = false
	_clear_secrets()
	completed.emit(document, usage)


func _fail(message: String, status_code: int) -> void:
	_running = false
	_clear_secrets()
	failed.emit(message, status_code)


func _clear_secrets() -> void:
	_api_key = ""


static func _localized_error(status_code: int) -> String:
	match status_code:
		401:
			return "API anahtari gecersiz."
		402:
			return "OpenRouter bakiyesi yetersiz."
		404:
			return "Model bulunamadi. Model slug'ini kontrol et."
		429:
			return "Istek limiti asildi. Biraz sonra tekrar dene."
		_:
			if status_code >= 500:
				return "OpenRouter veya model saglayicisi gecici olarak kullanilamiyor."
			return "OpenRouter istegi tamamlanamadi."


static func _error_message(response: Dictionary) -> String:
	var error = response.get("error", {})
	if error is Dictionary:
		return String(error.get("message", ""))
	return String(error)
