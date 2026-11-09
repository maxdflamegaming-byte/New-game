class_name Services
extends RefCounted
## The money side of the game: a rewarded ad (double coins after a win) and purchases (coin
## packs, removing ads) through Google AdMob and Google Play Billing. The game already calls
## these at the right moments, and everything here does nothing until it's switched on.
##
## Rewarded ads run on Android through the game's own small bridge to Google's ads library
## (android/reminders: Ads.java), with Google's test ids until the game has its own AdMob
## account. Purchases need products in Play Console and the Play Billing plugin; until then no
## purchase code runs. See ONLINE-AND-MONEY.md at the top of the repository.

## Filled in once the accounts exist. Empty means off.
const CONFIG := {
	# AdMob: the rewarded ad unit (double coins after a win). Until the game has its own AdMob
	# account this is Google's test unit, which only ever shows a "Test Ad" and pays nothing;
	# replace it (and ADMOB_APP_ID in the build, see android/reminders/build_aar.sh) with the
	# game's own ids before release.
	"admob_rewarded_unit": TEST_REWARDED_UNIT,
	# Google Play Billing: product ids from Play Console -> Monetize -> In-app products
	"product_remove_ads": "",
	"product_coins_small": "",
	"product_coins_big": "",
}
const TEST_REWARDED_UNIT := "ca-app-pub-3940256099942544/5224354917"

## Coins each pack gives (shown in the Upgrades screen once purchases are on)
const COIN_PACKS := {"product_coins_small": 1000, "product_coins_big": 5000}


static func _plugin(name: String) -> Object:
	return Engine.get_singleton(name) if Engine.has_singleton(name) else null


# ---------- Rewarded ads (android/reminders/src/com/towersiege/ads/Ads.java) ----------
## Tests: a stand-in for the Java bridge, with the same methods
static var fake_ads: Object = null


## The ads bridge, or null where there are no ads (not Android, or a build without them)
static func _ads() -> Variant:
	if fake_ads != null:
		return fake_ads
	if CONFIG.admob_rewarded_unit == "" or OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return null
	var cls = JavaClassWrapper.wrap("com.towersiege.ads.Ads")
	return cls if cls != null and cls.has_method("state") else null


static func _activity() -> Variant:
	if fake_ads != null:
		return null
	return Engine.get_singleton("AndroidRuntime").getActivity()


static func test_ads() -> bool:
	return CONFIG.admob_rewarded_unit == TEST_REWARDED_UNIT


## When the game starts: start the ads library and fetch the first ad, so one is ready by the
## first win
static func start_ads() -> void:
	var cls = _ads()
	if cls == null:
		return
	cls.init(_activity())
	prepare_rewarded()


## Fetch a rewarded ad if none is ready or on its way (after one was shown, or failed)
static func prepare_rewarded() -> void:
	var cls = _ads()
	if cls == null:
		return
	cls.reset()
	cls.load(_activity(), CONFIG.admob_rewarded_unit)


## Can the win screen offer "watch an ad for double coins"? Only when an ad is loaded and
## ready to show at once, so the button never leads to waiting or to nothing.
static func rewarded_ready() -> bool:
	var cls = _ads()
	return cls != null and str(cls.state()) == "ready"


## Shows the ad; `done` is called with true if the player watched it to the end
static func show_rewarded(done: Callable) -> void:
	var cls = _ads()
	if cls == null or str(cls.state()) != "ready":
		done.call(false)
		return
	cls.show(_activity())
	# Java can't call back into the game, so watch the ad's state until it goes away (the game
	# is in the background meanwhile; a minute and a half is far longer than any rewarded ad)
	var tree := Engine.get_main_loop() as SceneTree
	var until := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < until:
		await tree.process_frame
		var st := str(cls.state())
		if st == "closed" or st == "failed" or st == "idle":
			break
	var watched: bool = bool(cls.earned())
	prepare_rewarded()
	done.call(watched)


static func purchases_ready() -> bool:
	return CONFIG.product_coins_small != "" and _plugin("GodotGooglePlayBilling") != null


## Starts buying `product` (a key of CONFIG); `done` gets true when Google Play confirms
static func buy(product: String, done: Callable) -> void:
	if not purchases_ready() or CONFIG.get(product, "") == "":
		done.call(false)
		return
	# Wired up with the Play Billing plugin when purchases are switched on
	done.call(false)
