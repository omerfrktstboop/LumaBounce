extends SceneTree

## docs/store/STORE_LISTING.md icindeki magaza metinlerinin Play Console
## karakter sinirlarina uydugunu denetler. Her "## <dil>" bolumunde
## <!-- title|short|full|whatsnew --> isaretinden sonraki ``` blogu okunur.
##
## Kullanim:
##   godot --headless --path . --script res://tools/check_store_listing.gd

const LISTING_PATH := "res://docs/store/STORE_LISTING.md"
const LIMITS := {"title": 30, "short": 80, "full": 4000, "whatsnew": 500}
const LOCALES := ["tr-TR", "en-US", "es-ES", "pt-BR", "de-DE", "fr-FR"]


func _initialize() -> void:
	var text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(LISTING_PATH))
	if text.is_empty():
		push_error("Okunamadi: %s" % LISTING_PATH)
		quit(1)
		return
	var sections := _parse(text)
	var failures := 0
	for locale in LOCALES:
		if not sections.has(locale):
			push_error("%s bolumu yok" % locale)
			failures += 1
			continue
		var fields: Dictionary = sections[locale]
		for key in LIMITS:
			if not fields.has(key):
				push_error("%s: '%s' eksik" % [locale, key])
				failures += 1
				continue
			var length := String(fields[key]).length()
			var ok := length > 0 and length <= int(LIMITS[key])
			print("%s %-8s %4d / %4d %s" % [locale, key, length, LIMITS[key], "" if ok else "<-- ASIYOR"])
			if not ok:
				failures += 1
	if failures == 0:
		print("PASS store listing: %d dil, tum alanlar sinir icinde" % LOCALES.size())
	else:
		push_error("FAIL store listing: %d sorun" % failures)
	quit(1 if failures > 0 else 0)


func _parse(text: String) -> Dictionary:
	var sections := {}
	var locale := ""
	var key := ""
	var in_block := false
	var block: PackedStringArray = []
	for raw_line in text.split("\n"):
		var line := raw_line.trim_suffix("\r")
		if in_block:
			if line.begins_with("```"):
				in_block = false
				if not locale.is_empty() and not key.is_empty():
					sections[locale][key] = "\n".join(block).strip_edges()
				key = ""
			else:
				block.append(line)
			continue
		if line.begins_with("## "):
			locale = line.substr(3).strip_edges()
			sections[locale] = {}
		elif line.begins_with("<!--") and line.ends_with("-->"):
			key = line.trim_prefix("<!--").trim_suffix("-->").strip_edges()
		elif line.begins_with("```") and not key.is_empty():
			in_block = true
			block = []
	return sections
