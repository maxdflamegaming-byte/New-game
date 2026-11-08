class_name Services
extends RefCounted
## The online and money side of the game: rewarded ads (AdMob), purchases (Google Play
## Billing) and leaderboards (Google Play Games). The game calls these at the right moments
## (the end of a game, the shop and so on), and everything here does nothing until it's
## switched on.
##
## Switching each on needs accounts and IDs that only the game's owner can create, and an
## Android plugin; see ONLINE-AND-MONEY.md at the top of the repository. Ads (AdMob) are on:
## see scripts/ads.gd. Purchases and Play Games stay off until their IDs are filled in.

## Filled in once the accounts exist (see ONLINE-AND-MONEY.md). Empty means off.
const CONFIG := {
	# AdMob (the app ID is in project.godot, under [admob]): the rewarded unit (double coins
	# after a game) and the full-screen ad between games
	"admob_rewarded_unit": "ca-app-pub-3925367501335445/5228029416",
	"admob_interstitial_unit": "ca-app-pub-3925367501335445/1065423124",
	# true: Google's test ads instead of real ones (for trying things without breaking AdMob's
	# rules about clicking your own ads)
	"admob_test_ads": false,
	# Google Play Billing: product ids from Play Console -> Monetize -> In-app products
	"product_remove_ads": "",
	"product_coins_small": "",
	"product_coins_big": "",
	# Google Play Games: the project's ID (a long number) from Play Console -> Play Games
	# Services. With it, the build adds the Play Games plugin: sign-in and the cloud save.
	"play_games_id": "",
	# Google Play Games: leaderboard ids from Play Console -> Play Games Services
	"leaderboard_best_claim": "",
	"leaderboard_wins": "",
}

## Coins each pack gives (shown in the shop once purchases are on)
const COIN_PACKS := {"product_coins_small": 1000, "product_coins_big": 5000}


static func _plugin(name: String) -> Object:
	return Engine.get_singleton(name) if Engine.has_singleton(name) else null


# ---------- Rewarded ads ----------

## Can the results screen offer "watch an ad for double coins"? (a video is loaded)
static func rewarded_ready() -> bool:
	return CONFIG.admob_rewarded_unit != "" and Ads.me != null and Ads.me.rewarded_ready()


## Shows the ad; `done` is called with true if the player watched it to the end
static func show_rewarded(done: Callable) -> void:
	if not rewarded_ready():
		done.call(false)
		return
	Ads.me.show_rewarded(done)


# ---------- Purchases ----------

static func purchases_ready() -> bool:
	return CONFIG.product_remove_ads != "" and _plugin("GodotGooglePlayBilling") != null


## Starts buying `product` (a key of CONFIG); `done` gets true when Google Play confirms
static func buy(product: String, done: Callable) -> void:
	if not purchases_ready() or CONFIG.get(product, "") == "":
		done.call(false)
		return
	# Wired up with the Play Billing plugin when purchases are switched on
	done.call(false)


# ---------- Leaderboards ----------

static func leaderboards_ready() -> bool:
	return CONFIG.leaderboard_best_claim != "" and PlayGames.me != null and PlayGames.me.is_on()


## Sends a finished game's scores (does nothing while leaderboards are off or nobody is
## signed in). Best claim is sent in tenths of a percent: set its format to one decimal place.
static func submit_scores(best_claim_pct: float, total_wins: int) -> void:
	if not leaderboards_ready():
		return
	PlayGames.me.submit(CONFIG.leaderboard_best_claim, roundi(best_claim_pct * 10.0))
	PlayGames.me.submit(CONFIG.leaderboard_wins, total_wins)


static func show_leaderboards() -> void:
	if leaderboards_ready():
		PlayGames.me.show_leaderboards()
