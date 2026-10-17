class_name FirebaseAnalyticsProvider
extends AnalyticsProvider

## Godotx Firebase (Core + Analytics + Crashlytics) Android eklentisini
## normalize AnalyticsService eventlerine uyarlar. Bu dosya disinda hicbir
## runtime kodu Firebase singleton adini bilmez.
##
## IZIN: export'taki "privacy_safe_defaults" sayesinde toplama ve Consent Mode
## sinyalleri uygulama acilirken KAPALIDIR (Firebase'in kendi otomatik
## first_open/session_start eventleri dahil). AppRoot, UMP sonucuna gore
## set_collection_enabled() cagirana kadar bu sinif eventleri sinirli bir
## kuyrukta TUTAR: izin gelirse gonderir, gelmezse atar. Reklam
## kisisellestirme sinyalleri (ad_*) analitik icin hic acilmaz.

const CORE_SINGLETON := "GodotxFirebaseCore"
const ANALYTICS_SINGLETON := "GodotxFirebaseAnalytics"
const CRASHLYTICS_SINGLETON := "GodotxFirebaseCrashlytics"

## Firebase'in kendi otomatik eventleriyle ayni adi tasiyanlar yeniden
## adlandirilir; aksi halde bizim session_start'imiz Firebase'inkine karisirdi.
const RESERVED_RENAMES := {
	&"session_start": "game_session_start",
	&"session_end": "game_session_end",
}
## Firebase sinirlari: event/parametre adi 40, metin degeri 100 karakter,
## event basina 25 parametre.
const MAX_NAME_LENGTH := 40
const MAX_STRING_VALUE := 100
const MAX_PARAMS := 25
const MAX_QUEUED_EVENTS := 64

enum Consent { UNKNOWN, GRANTED, DENIED }

var _core: Object
var _analytics: Object
var _crashlytics: Object
var _analytics_ready := false
var _crashlytics_ready := false
## initialize() basarili oldu (Firebase yuklu); hazir olmasa da saglayici budur.
var _started := false
var _consent := Consent.UNKNOWN
var _queue: Array[Dictionary] = []


func _init(core_override: Object = null, analytics_override: Object = null,
		crashlytics_override: Object = null) -> void:
	_core = core_override
	_analytics = analytics_override
	_crashlytics = crashlytics_override


## Android'de eklenti yuklu mu (masaustu ve editorde false).
static func is_available() -> bool:
	return Engine.has_singleton(CORE_SINGLETON) and Engine.has_singleton(ANALYTICS_SINGLETON)


func provider_name() -> StringName:
	return &"firebase" if _started else &"firebase_unavailable"


## Config bilerek kullanilmaz: Firebase'in kimligi google-services.json'dan,
## toplama izni ise UMP'den gelir (bkz. set_collection_enabled).
func initialize(_config: GameAnalyticsConfig) -> bool:
	if _core == null and Engine.has_singleton(CORE_SINGLETON):
		_core = Engine.get_singleton(CORE_SINGLETON)
	if _analytics == null and Engine.has_singleton(ANALYTICS_SINGLETON):
		_analytics = Engine.get_singleton(ANALYTICS_SINGLETON)
	if _crashlytics == null and Engine.has_singleton(CRASHLYTICS_SINGLETON):
		_crashlytics = Engine.get_singleton(CRASHLYTICS_SINGLETON)
	if _core == null or _analytics == null or not _has_required_api():
		return false
	_core.connect("core_initialized", _on_core_initialized)
	_analytics.connect("analytics_initialized", _on_analytics_initialized)
	if _crashlytics != null and _crashlytics.has_signal("crashlytics_initialized"):
		_crashlytics.connect("crashlytics_initialized", _on_crashlytics_initialized)
	_core.call("initialize")
	_started = true
	return true


func send_event(event_name: StringName, properties: Dictionary) -> bool:
	if _consent == Consent.DENIED:
		# Izin yok: event bilincli olarak atilir; bu bir hata degildir.
		return true
	var event := {
		"name": firebase_event_name(event_name),
		"params": firebase_params(properties),
	}
	if not _analytics_ready or _consent != Consent.GRANTED:
		if _queue.size() >= MAX_QUEUED_EVENTS:
			_queue.pop_front()
		_queue.append(event)
		return true
	_analytics.call("log_event", event["name"], event["params"])
	return true


## UMP sonucu (AppRoot). Hem analitik hem cokme raporu ayni karari izler.
func set_collection_enabled(enabled: bool) -> void:
	_consent = Consent.GRANTED if enabled else Consent.DENIED
	if not enabled:
		_queue.clear()
	_apply_consent()
	_flush_queue()


func shutdown() -> void:
	_queue.clear()


func queued_event_count() -> int:
	return _queue.size()


static func firebase_event_name(event_name: StringName) -> String:
	var name := String(RESERVED_RENAMES.get(event_name, String(event_name)))
	return _clean_identifier(name)


## Bool degerler 0/1'e cevrilir (Firebase parametreleri metin veya sayidir).
static func firebase_params(properties: Dictionary) -> Dictionary:
	var params := {}
	for raw_key in properties:
		if params.size() >= MAX_PARAMS:
			break
		var key := _clean_identifier(String(raw_key))
		if key.is_empty():
			continue
		var value: Variant = properties[raw_key]
		match typeof(value):
			TYPE_BOOL:
				params[key] = 1 if value else 0
			TYPE_INT, TYPE_FLOAT:
				params[key] = value
			_:
				params[key] = String(value).left(MAX_STRING_VALUE)
	return params


static func _clean_identifier(raw: String) -> String:
	var output := ""
	for character in raw.to_lower():
		var code := character.unicode_at(0)
		var allowed := (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or character == "_"
		output += character if allowed else "_"
	while not output.is_empty() and not (output.unicode_at(0) >= 97 and output.unicode_at(0) <= 122):
		output = output.substr(1)
	return output.left(MAX_NAME_LENGTH)


func _on_core_initialized(success: bool) -> void:
	if not success:
		return
	_analytics.call("initialize")
	if _crashlytics != null and _can_call(_crashlytics, &"initialize"):
		_crashlytics.call("initialize")


func _on_analytics_initialized(success: bool) -> void:
	_analytics_ready = success
	if success:
		_apply_consent()
		_flush_queue()


func _on_crashlytics_initialized(success: bool) -> void:
	_crashlytics_ready = success
	if success:
		_apply_consent()


func _apply_consent() -> void:
	if _consent == Consent.UNKNOWN:
		return
	var granted := _consent == Consent.GRANTED
	if _analytics_ready:
		_analytics.call("set_consent", {
			"analytics_storage": "granted" if granted else "denied",
			"ad_storage": "denied",
			"ad_user_data": "denied",
			"ad_personalization": "denied",
		})
		_analytics.call("set_analytics_collection_enabled", granted)
	if _crashlytics_ready and _can_call(_crashlytics, &"set_crashlytics_collection_enabled"):
		_crashlytics.call("set_crashlytics_collection_enabled", granted)


func _flush_queue() -> void:
	if not _analytics_ready or _consent != Consent.GRANTED:
		return
	for event in _queue:
		_analytics.call("log_event", event["name"], event["params"])
	_queue.clear()


func _has_required_api() -> bool:
	if not _can_call(_core, &"initialize") or not _core.has_signal("core_initialized"):
		return false
	for method in [&"initialize", &"log_event", &"set_consent",
			&"set_analytics_collection_enabled"]:
		if not _can_call(_analytics, method):
			return false
	return _analytics.has_signal("analytics_initialized")


## Android eklenti singleton'lari (JNISingleton) Java metotlarini has_method
## ile GOSTERMEZ - cihazda bu kontrol yuzunden saglayici hic baslamiyordu.
## Gercek singleton'da metot denetimi atlanir (sinyaller yine denetlenir:
## eklenti onlari kullanici sinyali olarak kaydeder); test sahtelerinde
## has_method tam calisir.
static func _can_call(target: Object, method: StringName) -> bool:
	if target == null:
		return false
	if target.get_class() == "JNISingleton":
		return true
	return target.has_method(method)
