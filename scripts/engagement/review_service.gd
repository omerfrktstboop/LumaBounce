class_name ReviewService
extends Node

## Product policy for the automatic Google Play review prompt. The service
## deliberately records an attempt, never a claimed rating.

signal request_finished(completed: bool)

enum Result {
	NOT_ELIGIBLE,
	ATTEMPTED,
	UNAVAILABLE,
}

const MIN_COMPLETED_LEVELS := 5
const MIN_SESSIONS := 2
const COOLDOWN_DAYS := 90
const COOLDOWN_SECONDS := COOLDOWN_DAYS * 24 * 60 * 60
const REQUEST_TIMEOUT_SECONDS := 15.0

var _provider: ReviewProvider
var _progress: ProgressStore
var _initialized := false
var _busy := false
var _session_recorded := false
var _request_token := 0


func configure(provider: ReviewProvider, progress: ProgressStore) -> void:
	_provider = provider
	_progress = progress
	if _provider != null and _provider.get_parent() == null:
		add_child(_provider)
	if _provider != null:
		_provider.review_finished.connect(_on_provider_finished)


func initialize() -> bool:
	_initialized = _provider != null and _provider.initialize()
	return _initialized


func provider_name() -> StringName:
	return _provider.provider_name() if _provider != null else &"none"


func record_session() -> void:
	if _session_recorded or _progress == null or not _initialized:
		return
	if _provider == null or not _provider.is_available():
		return
	_session_recorded = true
	_progress.record_review_session()


func is_busy() -> bool:
	return _busy or (_provider != null and _provider.is_busy())


func is_eligible(now_unix := -1) -> bool:
	if not _initialized or _progress == null or _provider == null:
		return false
	if not _provider.is_available() or is_busy():
		return false
	if _progress.completed_levels.size() < MIN_COMPLETED_LEVELS:
		return false
	if _progress.review_session_count < MIN_SESSIONS:
		return false
	var now := _now_unix(now_unix)
	if _progress.last_review_attempt_unix > 0 \
			and now - _progress.last_review_attempt_unix < COOLDOWN_SECONDS:
		return false
	return true


func request_if_eligible(blocked := false, now_unix := -1) -> int:
	if blocked or not is_eligible(now_unix):
		return Result.NOT_ELIGIBLE
	_request_token += 1
	var token := _request_token
	_busy = true
	if not _provider.request_review():
		_busy = false
		return Result.UNAVAILABLE
	# Write before awaiting the platform so killing the app cannot cause a new
	# prompt on every launch. This timestamp is an attempt, not a rating result.
	_progress.mark_review_attempt(_now_unix(now_unix))
	get_tree().create_timer(REQUEST_TIMEOUT_SECONDS).timeout.connect(
		_on_request_timeout.bind(token), CONNECT_ONE_SHOT)
	await request_finished
	return Result.ATTEMPTED


func _on_provider_finished(completed: bool) -> void:
	_finish_request(completed)


func _on_request_timeout(token: int) -> void:
	if token == _request_token:
		_finish_request(false)


func _finish_request(completed: bool) -> void:
	if not _busy:
		return
	_busy = false
	request_finished.emit(completed)


func _now_unix(value: int) -> int:
	return value if value >= 0 else int(Time.get_unix_time_from_system())
