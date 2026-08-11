class_name AdmobAdProvider
extends AdProvider

## Google Mobile Ads/UMP adapteri. SDK siniflari, birim kimlikleri ve callback
## ayrintilari bu dosyanin disina cikmaz. Reklam hazir degilse urun API'si
## aninda UNAVAILABLE doner; oyun hicbir zaman reklam yuklenmesini beklemez.

signal _rewarded_completed(token: int, result: int)
signal _interstitial_completed(token: int, result: int)
signal _privacy_options_completed(success: bool)

const RETRY_SECONDS := 30.0
const FULLSCREEN_TIMEOUT_SECONDS := 180.0

var _admob: Admob
var _sdk_ready := false
var _consent_status := UserConsent.Status.UNKNOWN
var _consent_flow_active := false
var _privacy_request_active := false

var _rewarded_ads := {}
var _rewarded_load_queue: Array[StringName] = []
var _rewarded_load_in_flight := &""
var _interstitial_ad_id := ""
var _interstitial_load_in_flight := false

var _fullscreen_busy := false
var _request_token := 0
var _active_rewarded_token := 0
var _active_rewarded_ad_id := ""
var _active_rewarded_placement := &""
var _active_reward_earned := false
var _active_interstitial_token := 0
var _active_interstitial_ad_id := ""


func provider_name() -> StringName:
	return &"admob"


func initialize() -> bool:
	if OS.get_name() != "Android" or not Engine.has_singleton(Admob.PLUGIN_SINGLETON_NAME):
		return false
	_admob = Admob.new()
	_admob.name = "AdmobRuntime"
	_admob.is_real = LumaAdmobConfig.production_ads_enabled()
	_admob.android_debug_application_id = LumaAdmobConfig.ANDROID_APP_ID
	_admob.android_real_application_id = LumaAdmobConfig.ANDROID_APP_ID
	_admob.max_ad_content_rating = AdmobConfig.ContentRating.G
	_admob.remove_interstitial_ads_after_displayed = true
	_connect_admob_signals()
	add_child(_admob)
	_begin_consent_update.call_deferred()
	return true


func is_rewarded_ready(placement: StringName) -> bool:
	return (
		_sdk_ready
		and not _fullscreen_busy
		and MonetizationConfig.is_rewarded_placement(placement)
		and not String(_rewarded_ads.get(placement, "")).is_empty())


func show_rewarded(placement: StringName) -> int:
	if not is_rewarded_ready(placement):
		return AdResult.Code.UNAVAILABLE
	_request_token += 1
	_active_rewarded_token = _request_token
	_active_rewarded_placement = placement
	_active_rewarded_ad_id = String(_rewarded_ads.get(placement, ""))
	_active_reward_earned = false
	_rewarded_ads.erase(placement)
	_fullscreen_busy = true
	availability_changed.emit()
	var token := _active_rewarded_token
	get_tree().create_timer(FULLSCREEN_TIMEOUT_SECONDS).timeout.connect(
		_on_rewarded_timeout.bind(token), CONNECT_ONE_SHOT)
	_admob.show_rewarded_ad(_active_rewarded_ad_id)
	var completed: Array = await _rewarded_completed
	return int(completed[1])


func is_interstitial_ready() -> bool:
	return _sdk_ready and not _fullscreen_busy and not _interstitial_ad_id.is_empty()


func show_interstitial(_context: StringName) -> int:
	if not is_interstitial_ready():
		return AdResult.Code.UNAVAILABLE
	_request_token += 1
	_active_interstitial_token = _request_token
	_active_interstitial_ad_id = _interstitial_ad_id
	_interstitial_ad_id = ""
	_fullscreen_busy = true
	availability_changed.emit()
	var token := _active_interstitial_token
	get_tree().create_timer(FULLSCREEN_TIMEOUT_SECONDS).timeout.connect(
		_on_interstitial_timeout.bind(token), CONNECT_ONE_SHOT)
	_admob.show_interstitial_ad(_active_interstitial_ad_id)
	var completed: Array = await _interstitial_completed
	return int(completed[1])


func is_privacy_options_available() -> bool:
	return (
		_admob != null
		and not _privacy_request_active
		and _consent_status in [UserConsent.Status.REQUIRED, UserConsent.Status.OBTAINED])


func show_privacy_options() -> bool:
	if not is_privacy_options_available():
		return false
	_privacy_request_active = true
	_admob.load_consent_form()
	return bool(await _privacy_options_completed)


func _connect_admob_signals() -> void:
	_admob.consent_info_updated.connect(_on_consent_info_updated)
	_admob.consent_info_update_failed.connect(_on_consent_info_update_failed)
	_admob.consent_form_loaded.connect(_on_consent_form_loaded)
	_admob.consent_form_failed_to_load.connect(_on_consent_form_failed_to_load)
	_admob.consent_form_dismissed.connect(_on_consent_form_dismissed)
	_admob.initialization_completed.connect(_on_initialization_completed)
	_admob.rewarded_ad_loaded.connect(_on_rewarded_loaded)
	_admob.rewarded_ad_failed_to_load.connect(_on_rewarded_failed_to_load)
	_admob.rewarded_ad_user_earned_reward.connect(_on_rewarded_earned)
	_admob.rewarded_ad_failed_to_show_full_screen_content.connect(_on_rewarded_failed_to_show)
	_admob.rewarded_ad_dismissed_full_screen_content.connect(_on_rewarded_dismissed)
	_admob.interstitial_ad_loaded.connect(_on_interstitial_loaded)
	_admob.interstitial_ad_failed_to_load.connect(_on_interstitial_failed_to_load)
	_admob.interstitial_ad_failed_to_show_full_screen_content.connect(
		_on_interstitial_failed_to_show)
	_admob.interstitial_ad_dismissed_full_screen_content.connect(_on_interstitial_dismissed)


func _begin_consent_update() -> void:
	if _admob == null or _consent_flow_active:
		return
	_consent_flow_active = true
	_admob.update_consent_info()


func _refresh_consent_status() -> void:
	var consent := _admob.get_consent_status()
	_consent_status = consent.status if consent != null else UserConsent.Status.UNKNOWN
	privacy_options_availability_changed.emit(is_privacy_options_available())


func _on_consent_info_updated() -> void:
	_consent_flow_active = false
	_refresh_consent_status()
	if _consent_status == UserConsent.Status.REQUIRED:
		_consent_flow_active = true
		_admob.load_consent_form()
	elif _consent_status in [UserConsent.Status.NOT_REQUIRED, UserConsent.Status.OBTAINED]:
		_initialize_ads_sdk_once()


func _on_consent_info_update_failed(_error: FormError) -> void:
	_consent_flow_active = false
	# UMP onceki oturumun gecerli durumunu saklayabilir. Durum yoksa fail
	# closed: production reklam istegi yapilmaz, oyun normal devam eder.
	_refresh_consent_status()
	if _consent_status in [UserConsent.Status.NOT_REQUIRED, UserConsent.Status.OBTAINED]:
		_initialize_ads_sdk_once()


func _on_consent_form_loaded() -> void:
	_admob.show_consent_form()


func _on_consent_form_failed_to_load(_error: FormError) -> void:
	if _privacy_request_active:
		_privacy_request_active = false
		privacy_options_availability_changed.emit(is_privacy_options_available())
		_privacy_options_completed.emit(false)
	else:
		_consent_flow_active = false


func _on_consent_form_dismissed(error: FormError) -> void:
	var was_privacy_request := _privacy_request_active
	_privacy_request_active = false
	_consent_flow_active = false
	_refresh_consent_status()
	var success := error == null or error.get_message().is_empty()
	if was_privacy_request:
		_privacy_options_completed.emit(success)
	if _consent_status in [UserConsent.Status.NOT_REQUIRED, UserConsent.Status.OBTAINED]:
		_initialize_ads_sdk_once()


func _initialize_ads_sdk_once() -> void:
	if _sdk_ready or _admob.is_initialization_completed:
		return
	_admob.initialize()


func _on_initialization_completed(_status: InitializationStatus) -> void:
	if _sdk_ready:
		return
	_sdk_ready = true
	_queue_rewarded_load(MonetizationConfig.PLACEMENT_SHORT_HINT)
	_queue_rewarded_load(MonetizationConfig.PLACEMENT_REVIVE)
	_load_interstitial()
	availability_changed.emit()


func _queue_rewarded_load(placement: StringName) -> void:
	if not _sdk_ready or not MonetizationConfig.is_rewarded_placement(placement):
		return
	if _rewarded_ads.has(placement) or _rewarded_load_in_flight == placement:
		return
	if not _rewarded_load_queue.has(placement):
		_rewarded_load_queue.append(placement)
	_start_next_rewarded_load()


func _start_next_rewarded_load() -> void:
	if not _sdk_ready or not _rewarded_load_in_flight.is_empty() or _rewarded_load_queue.is_empty():
		return
	_rewarded_load_in_flight = _rewarded_load_queue.pop_front()
	var unit_id := LumaAdmobConfig.rewarded_unit_id(_rewarded_load_in_flight)
	if unit_id.is_empty():
		_rewarded_load_in_flight = &""
		_start_next_rewarded_load()
		return
	var request := _admob.create_basic_ad_request().set_ad_unit_id(unit_id)
	_admob.load_rewarded_ad(request)


func _on_rewarded_loaded(ad_info: AdInfo, _response: ResponseInfo) -> void:
	var placement := _rewarded_load_in_flight
	_rewarded_load_in_flight = &""
	if not placement.is_empty():
		_rewarded_ads[placement] = ad_info.get_ad_id()
	availability_changed.emit()
	_start_next_rewarded_load()


func _on_rewarded_failed_to_load(_ad_info: AdInfo, _error: LoadAdError) -> void:
	var placement := _rewarded_load_in_flight
	_rewarded_load_in_flight = &""
	if not placement.is_empty():
		_schedule_rewarded_retry(placement)
	_start_next_rewarded_load()


func _schedule_rewarded_retry(placement: StringName) -> void:
	get_tree().create_timer(RETRY_SECONDS).timeout.connect(
		_queue_rewarded_load.bind(placement), CONNECT_ONE_SHOT)


func _on_rewarded_earned(ad_info: AdInfo, _reward: RewardItem) -> void:
	if ad_info.get_ad_id() == _active_rewarded_ad_id:
		_active_reward_earned = true


func _on_rewarded_dismissed(ad_info: AdInfo) -> void:
	if ad_info.get_ad_id() != _active_rewarded_ad_id:
		return
	_finish_rewarded(
		AdResult.Code.EARNED if _active_reward_earned else AdResult.Code.CLOSED_WITHOUT_REWARD)


func _on_rewarded_failed_to_show(ad_info: AdInfo, _error: AdError) -> void:
	if ad_info.get_ad_id() == _active_rewarded_ad_id:
		_finish_rewarded(AdResult.Code.FAILED)


func _on_rewarded_timeout(token: int) -> void:
	if token == _active_rewarded_token:
		_finish_rewarded(AdResult.Code.FAILED)


func _finish_rewarded(result: int) -> void:
	if _active_rewarded_token == 0:
		return
	var token := _active_rewarded_token
	var placement := _active_rewarded_placement
	_active_rewarded_token = 0
	_active_rewarded_ad_id = ""
	_active_rewarded_placement = &""
	_active_reward_earned = false
	_fullscreen_busy = false
	_queue_rewarded_load(placement)
	availability_changed.emit()
	_rewarded_completed.emit(token, result)


func _load_interstitial() -> void:
	if not _sdk_ready or _interstitial_load_in_flight or not _interstitial_ad_id.is_empty():
		return
	_interstitial_load_in_flight = true
	var request := _admob.create_basic_ad_request().set_ad_unit_id(
		LumaAdmobConfig.interstitial_unit_id())
	_admob.load_interstitial_ad(request)


func _on_interstitial_loaded(ad_info: AdInfo, _response: ResponseInfo) -> void:
	_interstitial_load_in_flight = false
	_interstitial_ad_id = ad_info.get_ad_id()
	availability_changed.emit()


func _on_interstitial_failed_to_load(_ad_info: AdInfo, _error: LoadAdError) -> void:
	_interstitial_load_in_flight = false
	get_tree().create_timer(RETRY_SECONDS).timeout.connect(_load_interstitial, CONNECT_ONE_SHOT)


func _on_interstitial_dismissed(ad_info: AdInfo) -> void:
	if ad_info.get_ad_id() == _active_interstitial_ad_id:
		_finish_interstitial(AdResult.Code.DISPLAYED)


func _on_interstitial_failed_to_show(ad_info: AdInfo, _error: AdError) -> void:
	if ad_info.get_ad_id() == _active_interstitial_ad_id:
		_finish_interstitial(AdResult.Code.FAILED)


func _on_interstitial_timeout(token: int) -> void:
	if token == _active_interstitial_token:
		_finish_interstitial(AdResult.Code.FAILED)


func _finish_interstitial(result: int) -> void:
	if _active_interstitial_token == 0:
		return
	var token := _active_interstitial_token
	_active_interstitial_token = 0
	_active_interstitial_ad_id = ""
	_fullscreen_busy = false
	_load_interstitial()
	availability_changed.emit()
	_interstitial_completed.emit(token, result)
