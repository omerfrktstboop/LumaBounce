class_name DebugPanel
extends Control

## Yalnizca debug build'de var olan gelistirici test paneli.
##
## _ready() icinde OS.is_debug_build() degilse kendini agactan tamamen
## kaldirir (queue_free) - release export'ta hicbir govde, gorunurluk veya
## girdi izi birakmaz.
##
## Varsayilan olarak gizlidir. Uc parmakla KISA dokunma (mobil) veya F3
## tusu (masaustu/editor) ile acilip kapanir. Hicbir sahneyi kendisi acmaz
## veya gercek ilerlemeyi degistirmez; yalnizca sinyal yayar, AppRoot karar verir.

signal previous_level_requested()
signal next_level_requested()
signal restart_level_requested()
signal unlock_all_toggled(enabled: bool)
signal reset_stats_requested()
signal editor_requested()

## Uc parmagin ayni anda basili kaldigi andan tum parmaklarin kalkmasina
## kadar gecen sure bunun altindaysa "kisa dokunma" sayilir.
const THREE_FINGER_MAX_HOLD_MSEC := 450
const PANEL_PADDING := Vector2(12.0, 12.0)

@onready var _panel: Control = $Panel
@onready var _info_label: Label = $Panel/Margin/Rows/InfoLabel
@onready var _unlock_button: Button = $Panel/Margin/Rows/ToolRow/UnlockAllButton

## AppRoot ekran degisiminde set eder; oynanis disindaysa null.
var _active_gameplay: Gameplay
var _unlock_all := false
var _active_touch_count := 0
var _three_finger_start_msec := -1


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_apply_safe_area_offset()
	get_viewport().size_changed.connect(_apply_safe_area_offset)

	$Panel/Margin/Rows/ActionRow/PrevButton.pressed.connect(previous_level_requested.emit)
	$Panel/Margin/Rows/ActionRow/NextButton.pressed.connect(next_level_requested.emit)
	$Panel/Margin/Rows/ActionRow/RestartButton.pressed.connect(restart_level_requested.emit)
	_unlock_button.pressed.connect(_on_unlock_all_pressed)
	$Panel/Margin/Rows/ToolRow/ResetStatsButton.pressed.connect(reset_stats_requested.emit)
	$Panel/Margin/Rows/EditorButton.pressed.connect(editor_requested.emit)


func _process(_delta: float) -> void:
	if not _panel.visible:
		return
	_info_label.text = _build_info_text()


## AppRoot her ekran degisiminde cagirir; oynanis ekrani degilse null verir.
func set_active_gameplay(gameplay: Gameplay) -> void:
	_active_gameplay = gameplay


func toggle_visible() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_apply_safe_area_offset()


func _build_info_text() -> String:
	var lines := PackedStringArray()
	lines.append("FPS: %d" % Engine.get_frames_per_second())
	_append_audio_lines(lines)

	if _active_gameplay == null or not is_instance_valid(_active_gameplay):
		lines.append("")
		lines.append("(oynanis ekrani degil)")
		return "\n".join(lines)

	var snapshot := _active_gameplay.get_debug_snapshot()
	lines.append("Bolum: %d" % int(snapshot.get("level_id", 0)))
	lines.append("Top hakki: %d / %d" % [
		int(snapshot.get("lives_remaining", 0)), int(snapshot.get("max_lives", 0))])
	lines.append("Top hizi: %.0f px/s" % float(snapshot.get("ball_speed", 0.0)))
	lines.append("Son atis gucu: %.0f" % float(snapshot.get("last_shot_power", 0.0)))
	lines.append("Son atis acisi: %.1f deg" % float(snapshot.get("last_shot_angle_deg", 0.0)))
	lines.append("Son basarisizlik: %s" % String(snapshot.get("last_failure_reason", "-")))
	_append_block_lines(lines, snapshot)
	_append_attempt_lines(lines, snapshot)
	_append_stats_lines(lines, snapshot.get("stats", {}))
	return "\n".join(lines)


## Kirilabilir blok sayaclari. Bloksuz bolumlerde satir hic gosterilmez,
## boylece 1-20 arasindaki panel gorunumu aynen kalir.
func _append_block_lines(lines: PackedStringArray, snapshot: Dictionary) -> void:
	var total := int(snapshot.get("blocks_total", 0))
	if total <= 0:
		return
	lines.append("Blok: %d kalan / %d kirik / %d toplam" % [
		int(snapshot.get("blocks_remaining", 0)),
		int(snapshot.get("blocks_broken", 0)),
		total])


## Su anki deneme ve yildiz durumu - yalnizca debug panelinde.
func _append_attempt_lines(lines: PackedStringArray, snapshot: Dictionary) -> void:
	lines.append("")
	# Kronometre ilk gecerli nisanla baslar; o ana kadar "bekliyor" gorunur.
	lines.append("Deneme: %d atis / %.1f sn %s" % [
		int(snapshot.get("attempt_shots", 0)),
		float(snapshot.get("attempt_seconds", 0.0)),
		"" if bool(snapshot.get("attempt_timer_running", false)) else "(sure bekliyor)"])
	lines.append("Yildiz: simdi %d | kayitli %d | toplam %d/%d" % [
		int(snapshot.get("projected_stars", 0)),
		int(snapshot.get("saved_stars", 0)),
		int(snapshot.get("total_stars", 0)),
		int(snapshot.get("max_total_stars", 0))])


func _on_unlock_all_pressed() -> void:
	_unlock_all = not _unlock_all
	_unlock_button.text = "Kilitleri Ac: ACIK" if _unlock_all else "Kilitleri Ac: KAPALI"
	unlock_all_toggled.emit(_unlock_all)


## Ses durumu: yalnizca debug panelinde gorunur, oyuncu arayuzunde yer almaz.
func _append_audio_lines(lines: PackedStringArray) -> void:
	var audio := AudioManager.get_debug_snapshot()
	lines.append("Ses: %s | aktif SFX: %d/%d" % [
		"KAPALI" if bool(audio.get("muted", false)) else "ACIK",
		int(audio.get("active_sfx", 0)),
		int(audio.get("sfx_pool_size", 0))])
	lines.append("Son ses: %s" % String(audio.get("last_sound", "-")))


func _append_stats_lines(lines: PackedStringArray, raw_stats: Variant) -> void:
	if not (raw_stats is Dictionary):
		return
	var stats: Dictionary = raw_stats
	if stats.is_empty():
		return

	var min_shots := int(stats.get("min_shots_to_complete", -1))
	lines.append("")
	lines.append("Playtest (bu bolum)")
	lines.append("Giris / bitis: %d / %d" % [
		int(stats.get("entries", 0)), int(stats.get("completions", 0))])
	lines.append("Atis / basarisiz: %d / %d" % [
		int(stats.get("total_shots", 0)), int(stats.get("failed_shots", 0))])
	lines.append("Restart: %d" % int(stats.get("restarts", 0)))
	lines.append("Sure toplam / ort.: %s / %s" % [
		_format_seconds(float(stats.get("total_time_seconds", 0.0))),
		_format_seconds(float(stats.get("average_completion_seconds", 0.0)))])
	lines.append("En az atis: %s" % (str(min_shots) if min_shots >= 0 else "-"))
	lines.append("OOB / settled: %d / %d" % [
		int(stats.get("out_of_bounds_failures", 0)),
		int(stats.get("settled_failures", 0))])
	lines.append("Manual iptal: %d" % int(stats.get("manual_cancels", 0)))


func _format_seconds(seconds: float) -> String:
	var total_seconds := maxi(roundi(seconds), 0)
	var minutes := int(total_seconds / 60)
	var remainder := total_seconds % 60
	return "%02d:%02d" % [minutes, remainder]


func _apply_safe_area_offset() -> void:
	var insets := _safe_area_insets()
	_panel.offset_left = PANEL_PADDING.x + insets.x
	_panel.offset_top = PANEL_PADDING.y + insets.y


func _safe_area_insets() -> Vector2:
	var window_size := Vector2(DisplayServer.window_get_size())
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return Vector2.ZERO

	var safe := Rect2(DisplayServer.get_display_safe_area())
	if safe.size.x <= 0.0 or safe.size.y <= 0.0:
		return Vector2.ZERO

	var viewport_size := get_viewport_rect().size
	return Vector2(
		maxf(safe.position.x, 0.0) / window_size.x * viewport_size.x,
		maxf(safe.position.y, 0.0) / window_size.y * viewport_size.y)


# --- Acma/kapama jesti ---------------------------------------------------------

func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch != null:
		_handle_touch(touch)
		return

	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		toggle_visible()


func _handle_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		_active_touch_count += 1
		if _active_touch_count == 3 and _three_finger_start_msec < 0:
			_three_finger_start_msec = Time.get_ticks_msec()
		return

	_active_touch_count = maxi(_active_touch_count - 1, 0)
	if _active_touch_count > 0:
		return

	# Tum parmaklar kalkti: bu jest ucten gecti mi ve kisa mi surdu?
	if _three_finger_start_msec >= 0:
		var held_msec := Time.get_ticks_msec() - _three_finger_start_msec
		if held_msec <= THREE_FINGER_MAX_HOLD_MSEC:
			toggle_visible()
	_three_finger_start_msec = -1
