class_name Ads
extends Node
## Ads from Google AdMob, through the Poing Studios AdMob plugin (addons/admob):
## - a rewarded video for double coins, offered on the results screen (the player chooses it);
## - a full-screen ad between games, at most every INTERSTITIAL_EVERY games and never sooner
##   than INTERSTITIAL_GAP seconds after the last one, never in the first games, the tutorial,
##   2 Players or Online (an ad covers the game long enough to drop the online connection).
## Players in Europe (and anywhere Google requires it) see Google's consent message first.
##
## Only active on a phone with the plugin built in; everywhere else (the computer tests, the
## editor) it stays quiet and is_on() is false.

const PLUGIN := "PoingGodotAdMob"
const INTERSTITIAL_EVERY := 3 # games between full-screen ads
const INTERSTITIAL_GAP := 120.0 # seconds, at least
const FIRST_FREE_GAMES := 3 # a new player's first games have no full-screen ads
const RETRY := 30.0 # seconds before loading again after a failure

## Google's own test ad units, for trying ads safely (Services.CONFIG.admob_test_ads)
const TEST_REWARDED := "ca-app-pub-3940256099942544/5224354917"
const TEST_INTERSTITIAL := "ca-app-pub-3940256099942544/1033173712"

static var me: Ads

var _ready_to_load := false
var _rewarded: RewardedAd
var _interstitial: InterstitialAd
var _loading_rewarded := false
var _loading_interstitial := false
var _retry_rewarded := -1.0
var _retry_interstitial := -1.0
var _games_since := 0
var _last_shown := -1000.0
var _clock := 0.0
var _showing := false
var shown := {"rewarded": 0, "interstitial": 0} # for the crash log and tests
var _was_muted := false


func _ready() -> void:
	me = self
	if not is_on():
		return
	_ask_consent()


func _exit_tree() -> void:
	if me == self:
		me = null


## Is AdMob in this build (on a phone)?
static func is_on() -> bool:
	return Engine.has_singleton(PLUGIN)


## Does the law ask for consent here? 1: yes (Google shows its consent message here: Europe,
## the UK, Switzerland), 0: no, -1: not known yet (still asking Google). Without AdMob in the
## build (the computer tests) there's nothing to ask: 0.
static func consent_region() -> int:
	if not is_on():
		return 0
	match UserMessagingPlatform.consent_information.get_consent_status():
		ConsentInformation.ConsentStatus.NOT_REQUIRED:
			return 0
		ConsentInformation.ConsentStatus.REQUIRED, ConsentInformation.ConsentStatus.OBTAINED:
			return 1
	return -1


func _rewarded_id() -> String:
	return TEST_REWARDED if Services.CONFIG.admob_test_ads else Services.CONFIG.admob_rewarded_unit


func _interstitial_id() -> String:
	return TEST_INTERSTITIAL if Services.CONFIG.admob_test_ads else Services.CONFIG.admob_interstitial_unit


# ---------- Consent (Google's User Messaging Platform) ----------

func _ask_consent() -> void:
	var request := ConsentRequestParameters.new()
	UserMessagingPlatform.consent_information.update(request, _on_consent_info, func(err: FormError):
		CrashLog.note("ads  consent info failed: %s" % err.message)
		_start_ads())


func _on_consent_info() -> void:
	var info := UserMessagingPlatform.consent_information
	if info.get_is_consent_form_available() and info.get_consent_status() == ConsentInformation.ConsentStatus.REQUIRED:
		UserMessagingPlatform.load_consent_form(func(form: ConsentForm):
			form.show(func(_err: FormError): _start_ads()),
		func(err: FormError):
			CrashLog.note("ads  consent form failed: %s" % err.message)
			_start_ads())
	else:
		_start_ads()


## Players who must be able to change their consent (Europe) get a button in Settings
func privacy_options_required() -> bool:
	return is_on() and UserMessagingPlatform.consent_information.get_privacy_options_requirement_status() \
		== ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED


func show_privacy_options() -> void:
	if is_on():
		UserMessagingPlatform.show_privacy_options_form(func(_err: FormError): pass)


func _start_ads() -> void:
	if _ready_to_load:
		return
	CrashLog.note("ads  starting")
	var done := OnInitializationCompleteListener.new()
	done.on_initialization_complete = func(_status: InitializationStatus):
		_ready_to_load = true
		_load_rewarded()
		_load_interstitial()
	MobileAds.initialize(done)


# ---------- Loading ----------

func _process(dt: float) -> void:
	_clock += dt
	if not _ready_to_load:
		return
	if _rewarded == null and not _loading_rewarded and _retry_rewarded >= 0 and _clock >= _retry_rewarded:
		_load_rewarded()
	if _interstitial == null and not _loading_interstitial and _retry_interstitial >= 0 and _clock >= _retry_interstitial:
		_load_interstitial()


func _load_rewarded() -> void:
	if _rewarded_id() == "":
		return
	_loading_rewarded = true
	_retry_rewarded = -1.0
	var cb := RewardedAdLoadCallback.new()
	cb.on_ad_loaded = func(ad: RewardedAd):
		_loading_rewarded = false
		_rewarded = ad
	cb.on_ad_failed_to_load = func(err: LoadAdError):
		_loading_rewarded = false
		_retry_rewarded = _clock + RETRY
		CrashLog.note("ads  rewarded failed to load: %s" % err.message)
	RewardedAdLoader.new().load(_rewarded_id(), AdRequest.new(), cb)


func _load_interstitial() -> void:
	if _interstitial_id() == "":
		return
	_loading_interstitial = true
	_retry_interstitial = -1.0
	var cb := InterstitialAdLoadCallback.new()
	cb.on_ad_loaded = func(ad: InterstitialAd):
		_loading_interstitial = false
		_interstitial = ad
	cb.on_ad_failed_to_load = func(err: LoadAdError):
		_loading_interstitial = false
		_retry_interstitial = _clock + RETRY
		CrashLog.note("ads  interstitial failed to load: %s" % err.message)
	InterstitialAdLoader.new().load(_interstitial_id(), AdRequest.new(), cb)


# ---------- Showing ----------

func rewarded_ready() -> bool:
	return _rewarded != null and not _showing


## Shows the rewarded video; `done` gets true if the player watched it to the end
func show_rewarded(done: Callable) -> void:
	if not rewarded_ready():
		done.call(false)
		return
	var ad := _rewarded
	_rewarded = null
	_showing = true
	var earned := [false]
	var content := FullScreenContentCallback.new()
	content.on_ad_dismissed_full_screen_content = func():
		_finish(ad)
		done.call(earned[0])
		_load_rewarded()
	content.on_ad_failed_to_show_full_screen_content = func(err: AdError):
		CrashLog.note("ads  rewarded failed to show: %s" % err.message)
		_finish(ad)
		done.call(false)
		_load_rewarded()
	ad.full_screen_content_callback = content
	var reward := OnUserEarnedRewardListener.new()
	reward.on_user_earned_reward = func(_item: RewardedItem): earned[0] = true
	shown.rewarded += 1
	_mute(true)
	_last_shown = _clock # a rewarded video counts as an ad break too
	_games_since = 0
	ad.show(reward)


## A game ended (counts towards the next full-screen ad)
func game_finished() -> void:
	_games_since += 1


## Is it time for a full-screen ad? `games_ever` is the player's total games played.
func interstitial_due(games_ever: int, mode: String) -> bool:
	return _interstitial != null and not _showing and should_show(games_ever, mode, _games_since, _clock - _last_shown)


## The rules for a full-screen ad, on their own (so they can be tested without a phone)
static func should_show(games_ever: int, mode: String, games_since: int, seconds_since: float) -> bool:
	if mode == "tutorial" or mode == "duo" or mode == "online":
		return false
	return games_ever > FIRST_FREE_GAMES and games_since >= INTERSTITIAL_EVERY and seconds_since >= INTERSTITIAL_GAP


## Shows the full-screen ad if one is due, then calls `then` (straight away if not)
func between_games(games_ever: int, mode: String, then: Callable) -> void:
	if not interstitial_due(games_ever, mode):
		then.call()
		return
	var ad := _interstitial
	_interstitial = null
	_showing = true
	var content := FullScreenContentCallback.new()
	content.on_ad_dismissed_full_screen_content = func():
		_finish(ad)
		then.call()
		_load_interstitial()
	content.on_ad_failed_to_show_full_screen_content = func(err: AdError):
		CrashLog.note("ads  interstitial failed to show: %s" % err.message)
		_finish(ad)
		then.call()
		_load_interstitial()
	ad.full_screen_content_callback = content
	shown.interstitial += 1
	_mute(true)
	_games_since = 0
	_last_shown = _clock
	ad.show()


func _finish(ad) -> void:
	_showing = false
	_mute(false)
	if ad:
		ad.destroy()


## The game's music and sounds go quiet while an ad plays (ads have their own sound)
func _mute(on: bool) -> void:
	if on:
		_was_muted = AudioServer.is_bus_mute(0)
		AudioServer.set_bus_mute(0, true)
	else:
		AudioServer.set_bus_mute(0, _was_muted)
