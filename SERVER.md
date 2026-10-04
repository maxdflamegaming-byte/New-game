# The online server: how to put it on the internet

Online play works like this. A small server runs the real game in **rooms of 8**. People from anywhere join a room, and **bots fill the empty places**, so nobody waits for a match. The bots' skill follows the people in the room: newcomers meet mostly rookie bots, and high-level players mostly pros. Phones send only their steering; the server sends back what's happening about 15 times a second (roughly 12 KB/s, or 40 MB per hour of play).

Everything is built and tested:
- the server code is in `godot/server/` and `godot/scripts/net/`;
- the online mode is in the game, hidden until there's a server;
- `Dockerfile` packages the server;
- every change is checked automatically on GitHub: a local server with two test players, and the Docker image with a test player.

**It's live:** the server runs on Render's free plan at `wss://color-claim-server.onrender.com`, and the game connects there. To check it by hand, go to GitHub → **Actions** → **Online server (Docker)** → **Run workflow**: two test players join the live server and check everything matches.

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

---

# Tower Siege server (PvP, leaderboard and clans)

Tower Siege has its own small server, `tower-siege/server/server.js` (Node.js; packages `ws` and `pg`). It:
- **pairs players** for PvP (quick match by trophies, or a 4-letter friend code) and passes messages between the two. One phone runs the battle and sends what's happening about 10 times a second (a few KB each); the other sends its moves;
- keeps an **account** for each phone (an id and a secret key the game stores; no sign-up, no email), with its name, **trophies**, wins and losses. The server records every online result itself, so trophies can't simply be typed in;
- runs the **leaderboard** (top 50 players and top 50 clans) and the **clans** (create, search, join, leave; the leader can remove members; up to 25 members; a clan's trophies are its members' trophies added up).

Until the server is online, the PvP screen says it can't reach it, and **2 players on one phone** and **Practice vs bot** still work.

## Where the data is kept

Accounts and clans must survive restarts. Render's free plan **wipes its disk every time the server sleeps or restarts**, so on Render use a free Postgres database:

1. Go to <https://neon.tech> and sign up (free, no card needed).
2. Create a project (any name, a region near your Render region, e.g. Singapore).
3. On the project dashboard, copy the **connection string**. It looks like
   `postgresql://user:password@ep-something.ap-southeast-1.aws.neon.tech/neondb?sslmode=require`.
4. Paste it into the Render service as the environment variable **`DATABASE_URL`** (step 3 below).

The server makes its one table (`tower_siege`) by itself. Without `DATABASE_URL` it saves to a file, `data.json` (or the path in `DATA_FILE`): fine on your own computer or a host with a lasting disk.

## Put it on Render (free, all in the browser)

1. Go to <https://render.com> and sign in with GitHub (the same account as for the Color Claim server).
2. Click **New → Web Service** and pick **maxdflamegaming-byte/New-game**.
3. Fill in:
   - **Name:** `tower-siege-server`
   - **Branch:** `claude/military-overturn-game-sewao2` (or `main` once it's merged)
   - **Root Directory:** `tower-siege/server`
   - **Runtime:** Node
   - **Build Command:** `npm install --omit=dev`
   - **Start Command:** `node server.js`
   - **Instance Type:** Free
   - **Environment Variables:** add `DATABASE_URL` with the Neon connection string from above
4. Click **Create Web Service**. After a minute or two the logs end with
   `[server] Tower Siege server on port 10000, protocol 2, postgres storage, 0 players, 0 clans`.
   If it says `file storage`, `DATABASE_URL` isn't set, and everything will be lost when the server sleeps.
5. The address at the top should be `https://tower-siege-server.onrender.com`. The game already connects to `wss://tower-siege-server.onrender.com`. **If Render gave it a different address, send it to me** and I'll change `PVP_SERVER` in `tower-siege/pvp.js`.

(`render.yaml` also lists this service, so a Blueprint synced from this branch creates it the same way and asks for `DATABASE_URL`.)

Like the Color Claim server, the free plan **sleeps** after about 15 minutes without players. The first player then waits up to a minute; the game shows *"Waking up the server…"* meanwhile.

## Data and privacy

What the server stores per phone: the in-game name, trophies, wins, losses, the clan, and when the account was made. No email, no real name, no location. Clans store their name, tag, emblem, color, leader and members. The leaderboard shows names, clan tags and trophies to everyone. For Play Console's Data safety form that's **Name** (in-game) and **App interactions** (match results), for app functionality, stored, not shared.

## Try it on your own computer

```sh
cd tower-siege/server
npm install
node server.js            # listens on port 8090, saves to data.json
```
Then open `tower-siege/index.html?server=ws://localhost:8090` in two browser windows. The browser tests do the same with two players (`node tests/run.js siege-pvp`), and `node tests/run.js siege-store` checks the Postgres and file storage.
