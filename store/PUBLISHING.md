# Publishing Color Claim on Google Play

Everything technical is ready: the build makes a Google Play **App Bundle (.aab)** that targets Android 16 (API 36), supports 16 KB memory pages and is signed with your private upload key. This guide covers the rest, in order. Steps 1 and 2 only happen once.

---

## 1. Put your upload key in GitHub (once, about 5 minutes)

You got two files from Claude: `color-claim-upload.keystore` and `upload-key-secrets.txt`.

1. **Keep a backup** of both files somewhere safe and private (for example, a private cloud drive). Never put them in the repository or share them. If you lose them, Google can reset the upload key, but it takes a support request and a few days.
2. On GitHub, open the repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**. Add two secrets, copying the values from `upload-key-secrets.txt`:
   - Name `ANDROID_KEYSTORE_BASE64`: the long block of text
   - Name `ANDROID_KEYSTORE_PASSWORD`: the password

That's it: from now on every build is signed with this key.

## 2. Create your Google Play developer account (once)

1. Go to <https://play.google.com/console/signup> and sign in with the Google account you want to publish with.
2. Choose **Personal** (unless you have a registered company), pay the one-time **US$25** fee, and complete **identity verification**. Google may take a few days to verify you.
3. Verify the contact email and phone number it asks for.

## 3. Build the App Bundle

1. On GitHub: **Actions** → **Build Color Claim HD (Godot)** → **Run workflow** → **Run workflow**.
2. After about 3 minutes, open **Releases** (on the repo's main page). The newest release has:
   - `ColorClaimHD-1.0.N.aab`: **upload this one to Google Play**
   - `ColorClaimHD-1.0.N.apk`: for installing on your own phone
3. Every run makes a new version with a higher number, which Google Play needs for each update.

> Builds signed with the new key can't install over the older test APKs (0.x and 1.0.10). Uninstall the old Color Claim HD from your phone first (you'll lose that test progress).

## 4. Create the app in Play Console

**Home → Create app**:

| Field | Answer |
|---|---|
| App name | `Color Claim: Paint the Map` |
| Default language | English (United States) (or your language) |
| App or game | **Game** |
| Free or paid | **Free** |
| Declarations | Tick the Developer Program Policies and US export laws boxes |

## 5. Turn on the privacy policy page (GitHub Pages)

On GitHub: repo **Settings** → **Pages** → under **Build and deployment**, set **Source** to **GitHub Actions**. Then on the **Actions** tab, run **Deploy to GitHub Pages** once. Your privacy policy is then at:

`https://maxdflamegaming-byte.github.io/New-game/privacy.html`

(If you'd rather skip this, the GitHub link in `listing.md` also works as a privacy policy URL.)

## 6. Fill in "App content" (Play Console → Policy and programs → App content)

| Section | What to choose |
|---|---|
| **Privacy policy** | The URL from step 5 |
| **Ads** | **No**, my app does not contain ads |
| **App access** | **All functionality is available without special access** |
| **Content rating** | Start the questionnaire. Category: **Game**. Answer honestly; the game has no blood, gore, fear, sexual content, bad language, drugs, gambling or real-money purchases, and no chat or user content. Knockouts are cartoon shapes bumping into each other. Expected result: **Everyone / PEGI 3** |
| **Target audience** | Simplest: **13 and over** (13–15, 16–17, 18+). If you include under-13s, Google's stricter Families policy applies; the game already meets it (no ads, no data), but there are more forms |
| **Data safety** | Does your app collect or share user data? **Yes** (because of Online play). Is all data encrypted in transit? **Yes**. Can users ask for data to be deleted? **No data is stored**. Data types to tick: **Personal info → Name**, **App activity → App interactions** and **Device or other IDs** (the IP address the server sees). For each: *Collected* only (not shared), **processed ephemerally**, **required** only for Online play, purpose **App functionality**. See `privacy.html` for the wording |
| **Government apps** | No |
| **Financial features** | My app doesn't provide any financial features |
| **Health apps** | No |
| **News apps** | No |

## 7. Set up the store listing

**Grow users → Store presence → Main store listing**: copy the name, short and full description from `listing.md`, and upload from this folder:

- App icon: `icon-512.png`
- Feature graphic: `feature-graphic.png`
- Phone screenshots: `screenshots/1-classic.png` to `8-profile.png`

Also under **Store settings**: category **Arcade**, and your contact email.

## 8. Closed test: 12 testers for 14 days (required for new personal accounts)

1. **Test and release → Testing → Closed testing → Create track** (or use the default "Alpha").
2. **Testers**: create an email list with **at least 12 people** (friends and family with Android phones and Gmail accounts). Save, and copy the **opt-in link**.
3. **Create new release**:
   - When asked about app signing, choose **Use Google-generated key** (Play App Signing, the default). Google keeps the final signing key safe; your upload key only proves uploads come from you.
   - Upload `ColorClaimHD-1.0.N.aab` from step 3.
   - Release name: fills in automatically. Release notes: e.g. "First test release".
   - **Save → Review release → Start rollout to Closed testing**.
4. Send testers the opt-in link. They tap **Become a tester**, then install from the Play Store link on that page.
5. Keep **at least 12 testers opted in for 14 days in a row**. Ask them to actually play and send feedback; Google asks about it later.
6. While you wait, check **Test and release → Pre-launch report**. Google runs the game on real devices and shows crashes and screenshots.

## 9. Apply for production and launch

After 14 days, **Dashboard → Apply for production**. Answer the questions about your test (how many testers, what feedback you got, what you changed). Google reviews it, usually within a week.

Once approved: **Test and release → Production → Create new release** → add the same (or a newer) `.aab` → **Start rollout to Production**. The first review usually takes a few days, and then Color Claim is live.

## Updating the game later

Make the changes, then run the workflow again (step 3). Upload the new `.aab` as a new release on the same track. The version number goes up automatically.

---

### What's already done

- Targets Android 16 (API 36); works on Android 7.0 and newer, on 64-bit phones
- 16 KB memory page support (built with Godot 4.7.2)
- App Bundle (.aab) built and checked automatically; signed with your private upload key
- Only permission: vibration. No internet, ads, analytics, accounts or purchases
- Privacy policy (`privacy.html`, `store/privacy-policy.md`)
- Store listing text, icon, feature graphic and 8 screenshots (this folder)
- Themed (monochrome) icon for Android 13+ home screens
- The game in 7 languages, and store listings translated into Spanish, Portuguese, Hindi, Indonesian, Russian and Turkish (`listing-translations.md`): add them in Play Console under **Main store listing → Manage translations**
