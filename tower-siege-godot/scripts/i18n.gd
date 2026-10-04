class_name I18n
extends RefCounted
## Languages: the game's text is written in English, and i18n/<code>.gd holds each translation
## (English text -> translated text). Labels and buttons translate themselves; text built
## with numbers or names goes through t() (or tr()) first.

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
			var path := "res://i18n/%s.gd" % code
			if not ResourceLoader.exists(path):
				continue
			var table: Dictionary = load(path).T
			var tr := Translation.new()
			tr.locale = code
			for key in table:
				tr.add_message(key, table[key])
			TranslationServer.add_translation(tr)
	apply()


## The language in use: the one picked, or the phone's if we have it, or English
static func current() -> String:
	var code := lang if lang != "" else OS.get_locale_language()
	return code if LANGS.has(code) and code != "" else "en"


static func apply() -> void:
	TranslationServer.set_locale(current())


## Translate (for text that isn't simply a label's or button's whole text)
static func t(s: String) -> String:
	return TranslationServer.translate(s)


## Adds fonts for letters Fredoka doesn't have: Hindi (Devanagari), Russian (Cyrillic) and
## Turkish (ğ, ş, İ). The phone's own fonts still come last, for emoji and symbols.
static func add_fallbacks(bold: Font, medium: Font) -> void:
	var f := "res://assets/fonts/"
	var sys: Array = bold.fallbacks
	bold.fallbacks = [load(f + "Baloo2-LatinExt-Bold.ttf"), load(f + "Baloo2-Devanagari-Bold.ttf"), load(f + "Nunito-Cyrillic-ExtraBold.ttf")] + sys
	sys = medium.fallbacks
	medium.fallbacks = [load(f + "Baloo2-LatinExt-SemiBold.ttf"), load(f + "Baloo2-Devanagari-SemiBold.ttf"), load(f + "Nunito-Cyrillic-Bold.ttf")] + sys
