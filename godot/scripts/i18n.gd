class_name I18n
extends RefCounted
## Languages: the game's text is written in English, and i18n/<code>.gd holds each translation
## (English text -> translated text). Labels and buttons translate themselves; text built
## with numbers or names goes through tr() first.

## "" follows the phone's language
const LANGS := {
	"": "Auto", "en": "English", "es": "Español", "pt": "Português", "hi": "हिन्दी",
	"id": "Bahasa Indonesia", "ru": "Русский", "tr": "Türkçe",
}

static var lang := "" # the language picked in Settings ("" = the phone's)
static var _loaded := false


static func setup() -> void:
	if not _loaded:
		_loaded = true
		for code in LANGS:
			if code == "" or code == "en":
				continue
			var table: Dictionary = load("res://i18n/%s.gd" % code).T
			var t := Translation.new()
			t.locale = code
			for key in table:
				t.add_message(key, table[key])
			TranslationServer.add_translation(t)
	apply()


## The language in use: the one picked, or the phone's if we have it, or English
static func current() -> String:
	var code := lang if lang != "" else OS.get_locale_language()
	return code if LANGS.has(code) and code != "" else "en"


static func apply() -> void:
	TranslationServer.set_locale(current())


## Adds fonts for letters Fredoka doesn't have: Hindi (Devanagari), Russian (Cyrillic) and
## Turkish (ğ, ş, İ)
static func add_fallbacks(bold: Font, medium: Font) -> void:
	var f := "res://assets/fonts/"
	bold.fallbacks = [load(f + "Baloo2-LatinExt-Bold.ttf"), load(f + "Baloo2-Devanagari-Bold.ttf"), load(f + "Nunito-Cyrillic-ExtraBold.ttf")]
	medium.fallbacks = [load(f + "Baloo2-LatinExt-SemiBold.ttf"), load(f + "Baloo2-Devanagari-SemiBold.ttf"), load(f + "Nunito-Cyrillic-Bold.ttf")]
