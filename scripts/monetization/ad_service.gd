class_name AdService
extends Node

## Ekranlarin gorebildigi tek reklam API'si. Provider yalnizca burada yasar;
## Gameplay/MainMenu gercek SDK sinifi veya reklam birimi kimligi bilmez.

signal availability_changed()
signal privacy_options_availability_changed(available: bool)

var _provider: AdProvider
var _policy: AdPolicy
var _analytics: AnalyticsService
var _initialized := false


func configure(provider: AdProvider, policy: AdPolicy,
		analytics: AnalyticsService) -> void:
	_provider = provider
	_policy = policy
	_analytics = analytics
	if _provider != null and _provider.get_parent() == null:
		add_child(_provider)
	if _provider != null:
		_provider.availability_changed.connect(availability_changed.emit)
		_provider.privacy_options_availability_changed.connect(
			privacy_options_availability_changed.emit)


func initialize() -> bool:
	_initialized = _provider != null and _provider.initialize()
	return _initialized


func provider_name() -> StringName:
	return _provider.provider_name() if _provider != null else &"none"


func is_rewarded_ready(placement: StringName) -> bool:
	return (
		_initialized
		and MonetizationConfig.is_rewarded_placement(placement)
		and _provider != null
		and _provider.is_rewarded_ready(placement))


func show_rewarded(placement: StringName) -> int:
	# Tum sonuc yollarini coroutine tutar; unavailable durumda network veya
	# timeout beklenmez, yalnizca mevcut frame tamamlanir.
	await get_tree().process_frame
	_track(AnalyticsService.REWARDED_CLICK, {
		"placement": placement,
		"provider": provider_name(),
	})
	if not is_rewarded_ready(placement):
		return _finish_rewarded(placement, AdResult.Code.UNAVAILABLE)
	var result := int(await _provider.show_rewarded(placement))
	if result < AdResult.Code.EARNED or result > AdResult.Code.SKIPPED_POLICY:
		result = AdResult.Code.FAILED
	if AdResult.is_rewarded_impression(result) and _policy != null:
		_policy.record_rewarded_shown()
	return _finish_rewarded(placement, result)


func is_interstitial_ready() -> bool:
	return (
		_initialized
		and _provider != null
		and _provider.is_interstitial_ready()
		and (_policy == null or _policy.interstitials_enabled()))


func is_privacy_options_available() -> bool:
	return _initialized and _provider != null and _provider.is_privacy_options_available()


func show_privacy_options() -> bool:
	if not is_privacy_options_available():
		return false
	return bool(await _provider.show_privacy_options())


func maybe_show_interstitial(context: StringName, is_candidate := true,
		now_seconds := -1.0) -> int:
	await get_tree().process_frame
	if is_candidate:
		_track(AnalyticsService.INTERSTITIAL_CANDIDATE, {
			"context": context,
		})
	if _policy != null and not _policy.can_show_interstitial(
			context, is_candidate, now_seconds):
		return _finish_interstitial(context, AdResult.Code.SKIPPED_POLICY)
	if not is_interstitial_ready():
		return _finish_interstitial(context, AdResult.Code.UNAVAILABLE)
	var result := int(await _provider.show_interstitial(context))
	if result < AdResult.Code.EARNED or result > AdResult.Code.SKIPPED_POLICY:
		result = AdResult.Code.FAILED
	if result == AdResult.Code.DISPLAYED and _policy != null:
		_policy.record_interstitial_shown(now_seconds)
	return _finish_interstitial(context, result)


func _finish_rewarded(placement: StringName, result: int) -> int:
	_track(AnalyticsService.REWARDED_RESULT, {
		"placement": placement,
		"provider": provider_name(),
		"result": AdResult.label(result),
	})
	return result


func _finish_interstitial(context: StringName, result: int) -> int:
	if result == AdResult.Code.DISPLAYED:
		_track(AnalyticsService.INTERSTITIAL_SHOWN, {
			"context": context,
			"provider": provider_name(),
		})
	elif result == AdResult.Code.FAILED or result == AdResult.Code.UNAVAILABLE:
		_track(AnalyticsService.INTERSTITIAL_FAILED, {
			"context": context,
			"provider": provider_name(),
			"reason": AdResult.label(result),
		})
	return result


func _track(event_name: StringName, properties: Dictionary) -> void:
	if _analytics != null:
		_analytics.track_event(event_name, properties)
