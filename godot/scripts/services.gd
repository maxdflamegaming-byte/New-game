class_name Services
extends RefCounted
## The online and money side of the game: rewarded ads (AdMob), purchases (Google Play
## Billing) and leaderboards (Google Play Games). The game calls these at the right moments
## (the end of a game, the shop and so on), and everything here does nothing until it's
## switched on.
##
## Switching on needs accounts and IDs that only the game's owner can create, and an Android
## plugin for each service; see ONLINE-AND-MONEY.md at the top of the repository. Until
## then no ad, purchase or sign-in code is in the game at all, so nothing changes for players
## and no data is collected.

## Filled in once the accounts exist (see ONLINE-AND-MONEY.md). Empty means off.
const CONFIG := {
	# AdMob: the rewarded ad unit (double coins after a game)
	"admob_rewarded_unit": "",
	# Google Play Billing: product ids from Play Console -> Monetize -> In-app products
	"product_remove_ads": "",
	"product_coins_small": "",
	"product_coins_big": "",
	# Google Play Games: leaderboard ids from Play Console -> Play Games Services
	"leaderboard_best_claim": "",
	"leaderboard_wins": "",
}

## Coins each pack gives (shown in the shop once purchases are on)
const COIN_PACKS := {"product_coins_small": 1000, "product_coins_big": 5000}


static func _plugin(name: String) -> Object:
	return Engine.get_singleton(name) if Engine.has_singleton(name) else null


# ---------- Rewarded ads ----------

## Can the results screen offer "watch an ad for double coins"?
static func rewarded_ready() -> bool:
	return CONFIG.admob_rewarded_unit != "" and _plugin("AdMob") != null


## Shows the ad; `done` is called with true if the player watched it to the end
static func show_rewarded(done: Callable) -> void:
	if not rewarded_ready():
		done.call(false)
		return
	# Wired up with the AdMob plugin when ads are switched on
	done.call(false)


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
	return CONFIG.leaderboard_best_claim != "" and _plugin("GodotPlayGameServices") != null


## Sends a finished game's scores (does nothing while leaderboards are off)
static func submit_scores(best_claim_pct: float, total_wins: int) -> void:
	if not leaderboards_ready():
		return
	# Wired up with the Play Games plugin when leaderboards are switched on
	pass


static func show_leaderboards() -> void:
	if not leaderboards_ready():
		return
