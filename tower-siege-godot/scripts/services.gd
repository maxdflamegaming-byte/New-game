class_name Services
extends RefCounted
## The money side of the game: a rewarded ad (double coins after a win) and purchases (coin
## packs, removing ads) through Google AdMob and Google Play Billing. The game already calls
## these at the right moments, and everything here does nothing until it's switched on.
##
## Switching on needs accounts and IDs that only the game's owner can create (an AdMob ad unit,
## products in Play Console) and the Android plugins for them; see ONLINE-AND-MONEY.md at the
## top of the repository. Until then no ad or purchase code runs at all, nothing shows for
## players and no data is collected.

## Filled in once the accounts exist. Empty means off.
const CONFIG := {
	# AdMob: the rewarded ad unit (double coins after a win)
	"admob_rewarded_unit": "",
	# Google Play Billing: product ids from Play Console -> Monetize -> In-app products
	"product_remove_ads": "",
	"product_coins_small": "",
	"product_coins_big": "",
}

## Coins each pack gives (shown in the Upgrades screen once purchases are on)
const COIN_PACKS := {"product_coins_small": 1000, "product_coins_big": 5000}


static func _plugin(name: String) -> Object:
	return Engine.get_singleton(name) if Engine.has_singleton(name) else null


## Can the win screen offer "watch an ad for double coins"?
static func rewarded_ready() -> bool:
	return CONFIG.admob_rewarded_unit != "" and _plugin("AdMob") != null


## Shows the ad; `done` is called with true if the player watched it to the end
static func show_rewarded(done: Callable) -> void:
	if not rewarded_ready():
		done.call(false)
		return
	# Wired up with the AdMob plugin when ads are switched on
	done.call(false)


static func purchases_ready() -> bool:
	return CONFIG.product_coins_small != "" and _plugin("GodotGooglePlayBilling") != null


## Starts buying `product` (a key of CONFIG); `done` gets true when Google Play confirms
static func buy(product: String, done: Callable) -> void:
	if not purchases_ready() or CONFIG.get(product, "") == "":
		done.call(false)
		return
	# Wired up with the Play Billing plugin when purchases are switched on
	done.call(false)
