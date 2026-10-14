class_name EngagementLinks
extends RefCounted

## Store and support destinations are fixed and allowlisted here. mailto is
## intentionally separate from LegalLinks, whose HTTPS-only rule stays intact.

const PACKAGE_ID := "com.ofsgames.lumabounce"
const PLAY_STORE_URL := "https://play.google.com/store/apps/details?id=" + PACKAGE_ID
const SUPPORT_ADDRESS := "ofsgamesofficial@gmail.com"


static func open_store_page() -> bool:
	return OS.shell_open(PLAY_STORE_URL) == OK


static func feedback_uri(level_id := 0) -> String:
	var subject := tr_key("LumaBounce geri bildirim - %s") % GameVersion.GAME
	var lines := PackedStringArray([
		tr_key("FEEDBACK_EMAIL_GREETING"),
		"",
		tr_key("FEEDBACK_EMAIL_PROMPT"),
		"",
		"",
		"---",
		tr_key("Sürüm: %s") % GameVersion.describe(),
	])
	if level_id > 0:
		lines.append(tr_key("Bölüm: %d") % level_id)
	var body := "\n".join(lines)
	return "mailto:%s?subject=%s&body=%s" % [
		SUPPORT_ADDRESS, subject.uri_encode(), body.uri_encode()]


static func open_feedback_draft(level_id := 0) -> bool:
	return OS.shell_open(feedback_uri(level_id)) == OK


static func tr_key(key: StringName) -> String:
	return TranslationServer.translate(key)
