# New Game

Simple, fun browser games in plain HTML, CSS and JavaScript. There is no build step and nothing to install.
Sound effects are generated in code (`shared/sfx.js`), so there are no audio files either.

## Games

### 🟦 Color Claim (`color-claim/`)
A territory game inspired by Paper.io.

**Layout:** a mobile-first home screen that also fits tablets and computers. A top bar holds your profile (live avatar, name and level), rank, coins and settings. The home screen shows your animated character and pet, a game-setup card with swipeable mode cards, map chips and bot difficulty, and a big Play button. A bottom dock opens the Shop, Missions, Season pass, Clan and Profile. Every other screen has a header with a back button and your coins. Fonts: Fredoka for titles and buttons, Nunito for text.
- Leave your land to draw a trail, then loop back to claim everything you enclosed.
- Cut another player's trail to knock them out. If anyone touches *your* trail, or you cross it yourself, you're out.
- A 3-2-1 countdown starts each game, and everyone gets a 3-second shield after spawning.
- 7 bots, each with a personality shown under its name: **Hunters** chase trails, **Turtles** make small safe loops and run early, **Explorers** make big risky loops, **Collectors** go for power-ups and coins, and **Wildcards** are unpredictable. They path home around their own trails, and the bigger you get, the harder they come for yours.
- A red **!** (or an arrow at the screen edge) warns you when an enemy is near your trail.
- **Modes:**

  | Mode | Goal |
  |---|---|
  | Classic | Claim 50% of the map |
  | Timed | Be the biggest when the 3:00 clock runs out |
  | Daily | Same starting map for everyone today (claim 50%) |
  | Weekly | This week's tournament: the same map and start all week, 3:00. Race a see-through **ghost** of your best run this week |
  | Marathon | A 120×120 map (claim 60%) |
  | Cup | 3 two-minute rounds on 3 different maps; points for your finishing place each round (10, 7, 5…); most points wins a coin prize |
  | 2 Players | Two people on one keyboard (WASD vs arrow keys) with a split screen. First to 40%, or last one standing, wins |
  | Teams | You + 3 bots vs 4 bots; teammates can't cut, bump or steal from each other. First team to 50% wins |
  | Custom | Your own rules: speed (slow, normal or fast), 2, 4 or 7 bots, power-ups (none, normal or lots), map size (small, normal or giant) and the goal (25%, 50%, 75% or a 3:00 timer). Half coins, not ranked |
  | Puzzle | A new little puzzle every day on a small map with a timer: claim X%, knock out N bots, or claim X% in a single loop. Up to 3 stars for speed, and coins for new stars |
  | Boss Battle | You (with 3 lives) against a boss: cut its trail to knock off its hearts (3 / 5 / 7 by difficulty). At half health it calls 2 guards, and on its last heart it speeds up. Beat the **King** to unlock the **Queen** (drops spiky traps, +1 heart), then the **Wizard** (blinks home and wipes his trail when you get close, +2 hearts) |

- **Bot difficulty:** Easy, Normal or Hard (Hard bots are faster and hunt harder, and pay 1.5× coins).
- **Challenge a friend:** after a game, get a short code. Your friend enters it to play the exact same starting map and bots and try to beat your score.
- **Maps:** Square, Round arena, Pillars, Maze and Islands (walls you slide along, water you can't cross), plus up to 3 of your own from the **map editor** (paint walls with mirroring, the middle stays clear for your start). Share a map with a short **map code** that friends paste into their editor.
- **Hazard maps:**
  - **Saw Mill:** spinning saws run along tracks and cut any trail they touch (a Shield keeps you safe).
  - **Storm:** from 0:40 the arena shrinks every 25 seconds, with a warning ring first. Land, trails and players caught outside are lost.
  - **Conveyor:** moving belts carry you (and your trail) around the map.
  - **Portals:** step into a portal and pop out of its twin, trail and all.
- **Ranked ladder:** Classic, Timed, Daily, Weekly and Marathon games earn or lose rank points (RP) by where you finish. Tiers: Bronze, Silver, Gold, Platinum, Diamond and Champion, each with 3 divisions, and a coin reward the first time you reach each tier. You can drop a division but never a tier.
- **Emotes:** press 1-6 or the smiley button to pop up Hi, LOL, Grr, Cool, Love or GG over your square. Nearby bots answer back, cheer their knockouts and say GG when you win (bot emotes can be turned off in Settings).
- **Season pass:** each month is a season with 20 tiers filled by XP. Every tier pays coins, and tiers 10 and 20 give that season's trail effect and skin (Lightning/Crystal or Snowflakes/Tiger).
- **Power-ups:** Speed (1.6× faster), Shield (nobody can cut or bump you), Freeze (everyone else at half speed), Ghost (cross your own trail safely) and Paint Bomb (instantly claim a circle of land). Bots use them too.
- **Gold coins** appear on the map. Grab them before the bots do.
- **The Giant:** once you reach 20% (90 s into a Timed game), a big, fast boss bot arrives and hunts your trail. Knock it out for 100 coins.
- **Weekly events** rotate every Monday: Double Coins, Power-up Frenzy, Gold Rush, Speed Week and XP Boost.
- **Colorblind patterns** (in Settings) give every player's land and trail its own pattern.
- **Accessibility:** large text, a high-contrast look and a slower game speed (75%) in Settings.
- **Map looks:** each season has its own look (Snow in winter, Garden in spring, Desert in summer, Space in autumn) with falling snow, petals, blowing sand or twinkling stars. Pick any look in Settings.
- **Power-up upgrades:** spend coins to make your power-ups last up to 60% longer (or your Paint Bomb bigger).
- **Graphics:** rounded, glossy squares, smooth glowing rope trails with sparkles, raised land edges, a wave and ring when you claim land, a soft board shadow and vignette, sparkling power-ups and glinting coins, a camera that looks ahead of you, animated skin patterns, and a rolling sea with foam around the Islands. Settings → Graphics: **Auto** (the default) watches the frame rate while you play and lowers the resolution (and at the last step the extras) until the game runs smoothly, then remembers the level for your device; **Sharpest** always draws at full sharpness, and **Fastest** draws at 1× with the extras off.
- **Photo mode:** from the pause screen, zoom, add a filter (Warm, Cool, Mono, Retro, Pop) and stickers, then save a framed picture.
- **Daily missions:** 3 new missions every day with coin rewards.
- **Weekly quest chain:** 5 quests a week (2 easy, 2 medium, 1 hard) that unlock one after another and pay 50, 75, 100, 150 and 300 coins.
- **Holiday events:** Halloween Bash (October), Winter Fest (10 Dec to 6 Jan) and Hearts Week (5 to 16 Feb) each bring a map look (with bats, snow or petals) and turn the map's coins into pumpkins, gifts or hearts. Collect enough to keep that event's skin (Pumpkin, Snowman or Cupid). The home screen announces each event two weeks ahead.
- **Smarter bots:** they gang up on a runaway leader, hunters lie in wait at the edge of their land to pounce on your trail, and bots leave room to turn near walls and the sea so they rarely trap themselves.
- **Hype moments:** an announcer calls out DOUBLE KO!, TRIPLE KO!, RAMPAGE!, MEGA LOOP!, GIGA LOOP!, CLOSE CALL!, SHUTDOWN! (knocking out the leader), COMEBACK!, milestones and the last 10 seconds. Quick back-to-back loops build a combo that pays bonus coins. The bot that knocked you out is marked for REVENGE! next game. Wins end in slow motion, and the results show a podium plus a nudge when you were close to something.
- **Player card:** make a picture of your profile (character, pet, level, rank, clan and best numbers) to save and share.
- **Clans:** start a clan with a name, a 2-4 letter tag, an emblem and a colour. Your tag shows on your name (and on your teammates in Teams), every game earns clan points that level the clan up, and each week your clan races a rival clan in a clan war worth 250 coins.
- **Daily streak:** the first game each day pays coins, more for every day in a row (20 up to 150 on day 7, then 100 a day). Day 7 unlocks the Star Sprite pet.
- **Pets:** a little friend follows your square: Chick, Slime, Bat, Kitty (Silver rank), Dragon (Gold), UFO (Platinum) and Star Sprite (7-day streak). Some bots bring pets too.
- **Player level:** every game earns XP, and each level-up pays a coin bonus.
- **Coins and the Locker:** earn coins every game (2 per % claimed, 5 per knockout, 50 for a win, 25 per trophy). Unlock 8 skins by playing or buy them (plus the animated Galaxy and Lava skins in the shop), and buy trail effects (Sparkles, Bubbles, Hearts, Fire, Stars, Rainbow).
- **33 trophies** on 2 pages (wear one as a **badge** next to your name) and a **stats** page (wins, best claim, knockouts, time played and best score per mode).
- **Tutorial:** a 5-step guided level (leave land, loop home, grab a power-up, cut a practice bot, claim 15%) that pays 50 coins the first time. It's offered on the how-to-play screen.
- **Instant replay:** after a game, watch the last 10 seconds again, or turn it into a looping **GIF** to download or share.
- A how-to-play guide on your first game, background music made in code (Sunny or Night style in Settings, plus a boss theme), a kill feed, a leaderboard with a crown and a minimap.
- **On phones:** install it to your home screen and play offline. It vibrates on knockouts and hits, and has bigger buttons plus a choice of controls: drag joystick (normal or large) or one-thumb **tap to turn** (hold the left or right half of the screen).
- **Controls:** mouse, WASD / arrow keys, or touch. **P** or the pause button pauses, **M** mutes sound, **N** toggles music.

### ✨ Glow Survivors (`survivors/`)
A small "survivors-like" game.
- Move to dodge the swarm while your weapons fire on their own: magic bolts, orbiting blades, lightning strikes and a fire aura.
- **4 characters**, each with its own starting weapon and stats:

  | Character | Starts with | Unlock |
  |---|---|---|
  | Mage | Magic Bolt | Free |
  | Knight | 2 orbiting blades, 150 HP, a bit slower | Survive 3:00 |
  | Storm Witch | Storm Call Lv 2, 80 HP, quick | Defeat a boss |
  | Pyro | Fire Aura Lv 2 + Regeneration | Reach level 15 |

- **Weapon evolutions:** max a weapon, take its partner upgrade, and an evolution card appears.

  | Weapon (max level) | + Partner | Evolves into |
  |---|---|---|
  | Split Shot (5) | Quick Cast | 🌠 Arcane Barrage: homing bolts that pierce 3 more and hit 50% harder |
  | Orbiting Blade (6) | Swift Boots | 💫 Blade Storm: wide-swinging, faster, double-damage blades |
  | Storm Call (5) | Lucky Hits | ⛈️ Thunder God: faster strikes that chain to 2 more enemies |
  | Fire Aura (5) | Regeneration | ☄️ Inferno: huge double-damage aura that heals you |

- Collect XP gems, level up, and choose 1 of 3 upgrades each time. Upgrades include critical hits, piercing, extra bolts, speed, magnet range and regeneration.
- Every minute a swarm arrives with a 👑 boss. Beat it for a 🎁 treasure chest (a free upgrade).
- **At 10:00 the Reaper arrives.** It can't be hurt and keeps getting faster, and another one comes every minute after that. How long can you last?
- Enemies sometimes drop items: ❤️ heals, 🧲 pulls in every gem, and 💣 clears the screen.
- Effects: parallax starfield, glowing bullets with trails, wobbling enemies, damage numbers that pop (crits in gold), a level-up shockwave, screen shake and a low-health warning.
- **Controls:** WASD / arrow keys, or drag on a touch screen. **P** or the pause button pauses, **M** mutes.

## Play

Open `index.html` in a browser, or serve the folder locally:

```sh
python3 -m http.server 8000
# then visit http://localhost:8000
```

## Android app (APK)

`android/` wraps Color Claim in a small Android app: the game runs full screen from files inside the app, so it works offline, and the back button pauses the game or goes back a screen. GIFs, photos and player cards are saved to **Downloads/Color Claim**.

A GitHub Actions workflow (`.github/workflows/android.yml`) builds the APK every time the game changes and puts it on the repo's **Releases** page. To install it:

1. On your Android phone or tablet, open the repo's **Releases** page and tap the newest **ColorClaim-1.0.N.apk**.
2. Open the download. If Android asks, allow your browser (or files app) to install apps.
3. Newer versions install over older ones and keep your progress.

The APK is signed with `android/app/color-claim.keystore`, so every build can update the last one. That key is only for installing the APK directly; a Play Store release should use a private key kept out of the repo. To build it yourself you need the Android SDK: `cd android && ./gradlew assembleRelease`.

## Publish online (free)

This repo has a GitHub Actions workflow (`.github/workflows/pages.yml`) that publishes the games with GitHub Pages every time this branch is pushed. **Pages has to be switched on once by the repo owner**, otherwise every run fails with "Get Pages site failed".

1. On GitHub, open **Settings → Pages**.
2. Under **Build and deployment → Source**, choose **GitHub Actions**.
3. Open the **Actions** tab, pick **Deploy to GitHub Pages** and click **Run workflow** (or just push again).

The games are then at **https://maxdflamegaming-byte.github.io/New-game/** (Color Claim at `/New-game/color-claim/`). From there they can be installed to a phone's home screen and played offline. Only the game folders are published, not the tests.

## Tests

Browser tests drive Color Claim (and a little of Glow Survivors) in headless Chromium with [Playwright](https://playwright.dev). There are 21 suites and about 420 checks: game rules, bots, every mode and map, menus and layouts at phone and tablet sizes, saving, the GIF replay, and an audit that plays 67 bots-only games and checks the board stays consistent.

```sh
npm install                  # installs Playwright (once)
npx playwright install chromium
npm test                     # every suite, about 4 minutes
node tests/run.js phase-p    # only suites whose name contains "phase-p"
```

- `tests/run.js` runs the suites one by one, serves the repo on port 8765 while they run, and exits non-zero if anything fails.
- `tests/suites/` has one file per suite; each prints a `PASS` or `FAIL` line per check.
- Screenshots land in `tests/output/` (not committed).
- Two checks decode images with Python and Pillow (`pip install pillow`).
- `perf.js` checks Auto graphics: slow frames step the resolution down, smooth play steps it back up.
