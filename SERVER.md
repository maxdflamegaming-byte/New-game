# The online server: how to put it on the internet

Online play works like this. A small server runs the real game in **rooms of 8**. People from anywhere join a room, and **bots fill the empty places**, so nobody waits for a match. Phones send only their steering; the server sends back what's happening about 15 times a second (roughly 12 KB/s, or 40 MB per hour of play).

Everything is built and tested:
- the server code is in `godot/server/` and `godot/scripts/net/`;
- the online mode is in the game, hidden until there's a server;
- `Dockerfile` packages the server;
- every change is checked automatically on GitHub: a local server with two test players, and the Docker image with a test player.

What's missing is a place on the internet for the server to run. That needs an account only you can create. It takes about 10 minutes, then you send me one address.

---

## Free for now: Render's free plan

This is set up already: `render.yaml` uses Render's **free** plan. It's all in the browser, and you usually don't need a payment card.

What "free" means:
- **It sleeps.** After about 15 minutes with nobody playing, the server goes to sleep. The next player waits up to a minute while it wakes. The game keeps trying and shows *"Waking up the server..."*, then everyone plays normally. Once someone is playing, it stays awake.
- **Monthly limits.** 750 free hours a month (enough for one server all month) and 100 GB of data, which is roughly 2,000 hours of play in total. Plenty while you're starting out.
- **Upgrading later.** When you have regular players, change `plan: free` to `plan: starter` in `render.yaml` (US$7 a month, always awake). Or tell me and I'll change it.

Follow the Render steps just below. The only difference is that you can skip adding a payment card.

## Option A: Render (easiest, all in the browser)

**Cost:** free to start (see above), or the **Starter** plan at US$7 a month for a server that never sleeps.

1. Go to <https://render.com> and **sign up with your GitHub account**. (A payment card is only needed for paid plans: **Account settings → Billing**.)
2. Click **New → Blueprint**. Pick your repository **maxdflamegaming-byte/New-game** (allow Render to see it if asked).
3. Render reads the file `render.yaml` and shows a service called **color-claim-server**. Click **Apply**.
4. Wait for the first build, about 5 minutes. The logs should end with:
   `[server] Color Claim server on port 10000, protocol 1` (the port number may differ)
5. At the top of the service page is its address, like `https://color-claim-server.onrender.com`.
6. **Send me that address.**

**Region:** `render.yaml` uses **Singapore**. If most of your players are elsewhere, change `region:` to `oregon` (USA), `frankfurt` (Europe) or `ohio` (USA) before step 3. A server far away makes the game feel laggy.

## Option B: Fly.io (cheaper, uses a terminal)

**Cost:** about US$2–5 a month.

1. Sign up at <https://fly.io> and add a payment card.
2. Install **flyctl**. On Windows, open PowerShell and run:
   `pwsh -Command "iwr https://fly.io/install.ps1 -useb | iex"`
3. In the project folder (from `ColorClaim-full.zip`, or a clone of the repository), run:
   ```
   fly auth login
   fly launch --copy-config --no-deploy
   fly deploy
   ```
   If `fly launch` says the name `color-claim-server` is taken, pick another name when it asks.
4. It prints the address, like `https://color-claim-server.fly.dev`. **Send me that address.**

---

## What happens next

When you send the address, I'll:

1. **Switch online play on.** I set the address in the game (`godot/scripts/net/online_config.gd`) and add the Internet permission to the app.
2. **Update the privacy policy and the store listing.** Online, your chosen name, colour, look and moves go to the server during a game. Nothing is stored after you leave.
3. **Give you the new Data safety answers for Play Console:**
   - What's collected: **Name** (the in-game name), **App interactions** (moves during a game) and **IP address**.
   - Why: app functionality.
   - Handled only for that moment ("processed ephemerally"), not shared, and not stored.
4. **Test it against your server,** then build a new APK for you to try.

## Keeping it running

- **Where to watch it:** the server's log, on Render's **Logs** tab or with `fly logs`. Every 30 seconds it prints how many rooms and players there are.
- **Updates:** every time the game's code changes on GitHub, Render rebuilds and restarts the server by itself (`autoDeploy`). With Fly, run `fly deploy` again.
- **Old phones:** after an update that changes how the game talks to the server, older app versions are told to update.
- **Size:** one small server handles about 50 rooms (400 players at once). Past that, move up a plan, or add a second server in another region and I'll add region picking.
