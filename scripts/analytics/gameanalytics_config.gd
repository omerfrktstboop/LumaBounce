class_name GameAnalyticsConfig
extends RefCounted

## Repo disinda tutulan gameanalytics.cfg icin guvenli feature flag.

const DEFAULT_PATH := "res://gameanalytics.cfg"
const ENVIRONMENT_STAGING := &"staging"
const ENVIRONMENT_PRODUCTION := &"production"

var enabled := false
var environment := ENVIRONMENT_STAGING
var game_key := ""
var secret_key := ""
var collection_enabled := true
var rejection_reason := ""


static func load_from_path(path := DEFAULT_PATH, debug_build := OS.is_debug_build()) -> GameAnalyticsConfig:
	var result := GameAnalyticsConfig.new()
	if not FileAccess.file_exists(path):
		result.rejection_reason = "config_missing"
		return result
	var file := ConfigFile.new()
	if file.load(path) != OK:
		result.rejection_reason = "config_invalid"
		return result
	result.enabled = bool(file.get_value("analytics", "enabled", false))
	result.environment = StringName(String(file.get_value(
		"analytics", "environment", "staging")).strip_edges().to_lower())
	result.game_key = String(file.get_value("analytics", "game_key", "")).strip_edges()
	result.secret_key = String(file.get_value("analytics", "secret_key", "")).strip_edges()
	result.collection_enabled = bool(file.get_value(
		"analytics", "collection_enabled", true))
	result._validate(debug_build)
	return result


func is_ready() -> bool:
	return enabled and rejection_reason.is_empty()


func _validate(debug_build: bool) -> void:
	if not enabled:
		rejection_reason = "disabled"
		return
	if environment != ENVIRONMENT_STAGING and environment != ENVIRONMENT_PRODUCTION:
		enabled = false
		rejection_reason = "environment_invalid"
		return
	# Dahili/debug build'in production projesini kirletmesini engeller.
	if debug_build and environment == ENVIRONMENT_PRODUCTION:
		enabled = false
		rejection_reason = "production_blocked_in_debug"
		return
	if game_key.is_empty() or secret_key.is_empty():
		enabled = false
		rejection_reason = "credentials_missing"
