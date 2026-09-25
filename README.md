# New Game

Simple, fun browser games in plain HTML, CSS and JavaScript. There is no build step and nothing to install.
Sound effects are generated in code (`shared/sfx.js`), so there are no audio files either.

## Games

### 🟦 Color Claim (`color-claim/`)
A territory game inspired by Paper.io.
- Leave your land to draw a trail, then loop back to claim everything you enclosed.
- Cut another player's trail to knock them out. If anyone touches *your* trail, or you cross it yourself, you're out.
- Claim 50% of the map to win, against 7 bots that each have their own personality (greedy, cautious, aggressive).
- Grab power-ups: **Speed** (1.6× faster), **Shield** (nobody can cut or bump you) and **Freeze** (everyone else moves at half speed). Bots use them too.
- Unlock 8 skins by playing (Stripes, Dots, Shades, Cat, Confetti, Robot, Ninja, Rainbow). Some patterns show on your land as well. Bots wear skins too.
- Pick your own name and color. There's a live leaderboard, a crown on the leader, a kill feed and a minimap.
- Your trail flashes red with a warning sound when an enemy gets close to it.
- Animations: claimed land flashes, lost land dissolves, confetti bursts, and squares that squash, bob and blink. The camera zooms out as you grow.
- **Controls:** mouse, WASD / arrow keys, or drag on a touch screen. **P** or the pause button pauses, **M** mutes.

### ✨ Glow Survivors (`survivors/`)
A small "survivors-like" game.
- Move to dodge the swarm while your weapons fire on their own: magic bolts, orbiting blades, lightning strikes and a fire aura.
- Collect XP gems, level up, and choose 1 of 3 upgrades each time. Upgrades include critical hits, piercing, extra bolts, speed, magnet range and regeneration.
- Every minute a swarm arrives with a 👑 boss. Beat it for a 🎁 treasure chest (a free upgrade).
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
