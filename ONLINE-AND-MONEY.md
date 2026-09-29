# Ads, purchases and leaderboards: what's ready and what you need to do

The game already has the places where these go:
- the **"Watch an ad: double coins"** button on the results screen;
- scores sent to **leaderboards** after every game;
- a spot for **coin packs** and **Remove ads** in the shop.

All of it is switched **off** (see `godot/scripts/services.gd`). No ad, purchase or sign-in code is in the game yet, so today the game collects no data and the Play Store forms stay simple.

Switching each one on needs an account and some IDs that only you can create. Do the steps below for the parts you want, then send me the IDs (they're not secret, so they're fine to paste in chat). I'll then add Google's plugins, switch the parts on, update the privacy policy and tell you exactly what to change in Play Console.

> **My advice:** publish the first version **without** ads and purchases. Add them in an update once the game is live and stable. Ad and purchase code makes the app bigger and adds new ways for it to fail. That's worth avoiding while we're still tracking down the crash on your phone. Google also reviews an app with ads more strictly.

---

## 1. Rewarded ads (AdMob): "watch an ad for double coins"

**You earn:** money for each ad watched. How much varies a lot by country, roughly US$1–15 per 1,000 ads watched.

**Steps:**
1. Go to <https://admob.google.com> and sign in with the same Google account as your Play Console. Fill in your payment details.
2. **Apps → Add app → Android → "Is the app listed on a supported app store?"**
   - If the game is already on Google Play: answer **Yes** and find *Color Claim*.
   - If it isn't yet: answer **No** and name it *Color Claim*. You can link it to the store listing later.
3. In the new app: **Ad units → Add ad unit → Rewarded**. Name it `double_coins`; the reward can be anything, for example `1 Coins`.
4. **Privacy & messaging → GDPR → Create message.** This is the consent pop-up that players in Europe must see before ads; AdMob makes it for you. Publish it.
5. **Send me:**
   - the **App ID** (looks like `ca-app-pub-1234567890123456~1234567890`)
   - the **Rewarded ad unit ID** (looks like `ca-app-pub-1234567890123456/1234567890`)

**What changes:**
- **Play Console → App content → Ads:** answer **Yes, my app contains ads**.
- **Data safety:** it now includes what AdMob collects (device IDs, app activity and diagnostics, for advertising and analytics). I'll give you the exact answers.
- **Privacy policy:** I'll update it to mention AdMob.
- **Target audience:** keep it **13 and over**. Apps for children under 13 need special child-safe ad settings.

## 2. Purchases: coin packs and "Remove ads"

**Steps:**
1. **Play Console → Settings → Payments profile:** set up your merchant account. Google needs your bank details and tax information before you can sell anything.
2. **Play Console → your app → Monetize → Products → In-app products → Create product.** Make three:

   | Product ID | Name | Type | Suggested price |
   |---|---|---|---|
   | `remove_ads` | Remove ads | One-time, keep forever | US$1.99 |
   | `coins_small` | 1,000 coins | Can be bought again | US$0.99 |
   | `coins_big` | 5,000 coins | Can be bought again | US$3.99 |

   Play Console converts the prices for other countries automatically. The app must already have been uploaded once (even just to closed testing) before you can create products.
3. **Send me** the three product IDs, in case you named them differently.

**What changes:**
- **Store listing:** it shows "In-app purchases".
- **Data safety:** it adds purchase history, which Google collects.
- **Remove ads:** it only makes sense if ads (section 1) are on too.

## 3. Leaderboards (Google Play Games)

Worldwide leaderboards: **Best claim** (your biggest % of the map) and **Most wins**.

**Steps:**
1. **Play Console → your app → Grow users → Play Games Services → Setup and management → Configuration.** Choose **"No, my game doesn't use Google APIs"**, then create the Play Games Services project.
2. **Credentials → Add credential → Android.** Follow the steps. You'll need to create an OAuth consent screen in Google Cloud (Play Console links you to it); fill in the app name and your email.
3. The SHA-1 certificate fingerprint it asks for is under **Play Console → Test and release → App integrity → App signing**. Copy the **App signing key certificate → SHA-1**.
4. **Leaderboards → Create leaderboard**, twice:
   - `Best claim`: score format **Fixed point, 1 decimal place**, higher is better
   - `Most wins`: score format **Numeric**, higher is better
5. **Publish** the Play Games Services changes (Play Games has its own publish button).
6. **Send me:**
   - the **Project ID / App ID**, the long number at the top of the Play Games Services page
   - the two **leaderboard IDs** (they look like `CgkI...`)

**What changes:**
- **Players:** they can sign in with their Play Games profile. It's optional; the game still works without signing in.
- **Data safety:** it adds that Play Games collects user IDs for app functionality.

---

## What I do once you send the IDs

1. Add the official plugins to the build:
   - AdMob plugin for Godot 4
   - Google Play Billing plugin for Godot 4
   - Play Games Services plugin for Godot 4
2. Switch the APK build to Godot's Gradle build, which these plugins need.
3. Fill in `godot/scripts/services.gd` so the button, the shop packs and the leaderboards actually work, including restoring "Remove ads" on a new phone.
4. Test everything with Google's **test** ads and test purchases, so no real money moves while testing.
5. Update `privacy.html`, `store/privacy-policy.md`, the store listing and `store/PUBLISHING.md` with the new Data safety answers.
