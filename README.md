# New Game

Simple, fun browser games in plain HTML, CSS and JavaScript. There is no build step and nothing to install.
Sound effects are generated in code (`shared/sfx.js`), so there are no audio files either.

## Games

### 🟦 Color Claim (`color-claim/`)
A territory game inspired by Paper.io.
- Leave your land to draw a trail, then loop back to claim everything you enclosed.
- Cut another player's trail to knock them out. If anyone touches *your* trail, or you cross it yourself, you're out.
- A 3-2-1 countdown starts each game, and everyone gets a 3-second shield after spawning.
- 7 bots with their own personalities. They path home around their own trails, and the bigger you get, the harder they come for yours.
- A red **!** (or an arrow at the screen edge) warns you when an enemy is near your trail.
- **Modes:**

  | Mode | Goal |
  |---|---|
  | Classic | Claim 50% of the map |
  | Timed | Be the biggest when the 3:00 clock runs out |
  | Daily | Same starting map for everyone today (claim 50%) |
  | Marathon | A 120×120 map (claim 60%) |
  | Teams | You + 3 bots vs 4 bots; teammates can't cut, bump or steal from each other. First team to 50% wins |

- **Maps:** Square, Round arena and Pillars (walls you slide along).
- **Power-ups:** Speed (1.6× faster), Shield (nobody can cut or bump you), Freeze (everyone else at half speed), Ghost (cross your own trail safely) and Paint Bomb (instantly claim a circle of land). Bots use them too.
- **Gold coins** appear on the map. Grab them before the bots do.
- **The Giant:** once you reach 20% (90 s into a Timed game), a big, fast boss bot arrives and hunts your trail. Knock it out for 100 coins.
- **Weekly events** rotate every Monday: Double Coins, Power-up Frenzy, Gold Rush, Speed Week and XP Boost.
- **Colorblind patterns** (in Settings) give every player's land and trail its own pattern.
- **Daily missions:** 3 new missions every day with coin rewards.
- **Player level:** every game earns XP, and each level-up pays a coin bonus.
- **Coins and the Locker:** earn coins every game (2 per % claimed, 5 per knockout, 50 for a win, 25 per trophy). Unlock 8 skins by playing or buy them, and buy trail effects (Sparkles, Bubbles, Hearts, Fire, Stars, Rainbow).
- **16 trophies** and a **stats** page (wins, best claim, knockouts, time played and best score per mode).
- A how-to-play guide on your first game, background music made in code, a kill feed, a leaderboard with a crown and a minimap.
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

## Publish online (free)

This repo has a GitHub Actions workflow (`.github/workflows/pages.yml`) that publishes the games with GitHub Pages.

1. On GitHub, open **Settings → Pages**.
2. Under **Build and deployment → Source**, choose **GitHub Actions**.
3. Push to this branch (or run the workflow from the **Actions** tab). The game link appears in the workflow run and on the Pages settings page.
