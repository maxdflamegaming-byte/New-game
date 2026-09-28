# Working on Color Claim on your PC

## 1. Get the right Godot

Use **Godot 4.7.2** (the standard version, **not** ".NET"), from <https://godotengine.org/download/archive/4.7.2-stable/>. Any 4.7.x works. Older versions (4.4, 4.5, 4.6) can't open this project properly.

## 2. Open the project

1. Unzip `ColorClaim-full.zip` somewhere easy, like `Documents\ColorClaim`.
2. Start Godot. In the Project Manager, click **Import**.
3. Pick the file `ColorClaim\godot\project.godot`, then click **Import & Edit** (on some versions **Open**).
4. The first time, Godot spends a minute importing the fonts and icons. Wait until the bar at the bottom finishes.

## 3. Play it on the PC

Press **F5** (or the ▶ button at the top right).

| Action | Keys and mouse |
|---|---|
| Steer | Hold the left mouse button and drag, like a joystick; or **WASD** or the **arrow keys** |
| Pause | **Esc** or **P** |
| Start a game (menu or results screen) | **Enter** or **Space** |

Your PC save is kept separately from the phone's. It's in `%APPDATA%\Godot\app_userdata\Color Claim\` (the logs are in the `logs` folder there).

## 4. What's where

Everything for the game is in `godot/`:

| Path | What it is |
|---|---|
| `scenes/main.tscn` | The one scene; everything is built by `scripts/main.gd` |
| `scripts/main.gd` | Game flow, menu, results screen, HUD, controls, tutorial, saving |
| `scripts/world.gd` | The rules: maps, moving, trails, claiming land, knockouts, power-ups, hazards, bosses |
| `scripts/bots.gd` | How the bots think |
| `scripts/board_view.gd`, `player_view.gd` | Drawing the board, trails, squares and effects |
| `scripts/shaders.gd` | The shaders that draw the land and the minimap |
| `scripts/gfx.gd` | Graphics settings (Low, Medium, High; 30 or 60 FPS) |
| `scripts/progress.gd` | XP, levels, missions, streak, trophies |
| `scripts/shop.gd`, `cosmetics.gd` | The shop, skins, trails and pets |
| `scripts/*_screen.gd` | The Missions, Profile and Settings screens |
| `scripts/crash_log.gd` | The crash marker and the "Copy game log" report |
| `i18n/*.gd` | Translations (Spanish, Portuguese, Hindi, Indonesian, Russian, Turkish) |
| `assets/` | Icons and fonts |
| `tests/` | Automatic checks (see below) |

The rest of the repository:

| Path | What it is |
|---|---|
| `store/` | Google Play listing, screenshots and `PUBLISHING.md` |
| `.github/workflows/` | The automatic GitHub build |
| `color-claim/`, `shared/`, `android/` | The older web version |
| `survivors/` | Glow Survivors |

## 5. Run the automatic checks (optional)

In a terminal (Command Prompt), in the `ColorClaim` folder (replace the Godot path with yours):

```
"C:\path\to\Godot_v4.7.2-stable_win64_console.exe" --headless --path godot -s tests/flow.gd
"C:\path\to\Godot_v4.7.2-stable_win64_console.exe" --headless --path godot -s tests/sim.gd
```

Each prints `PASS` or `FAIL` lines. The last line says how many failed. They take a few minutes.

## 6. Make an APK on your PC

The GitHub build (Actions → **Build Color Claim HD (Godot)** → **Run workflow**) does all of this for you. To do it yourself instead:

1. **Export templates.** In Godot: **Editor → Manage Export Templates → Download and Install**.
2. **Java and the Android SDK.** Install **JDK 17** (for example from <https://adoptium.net>) and **Android Studio**. In Android Studio's SDK Manager, install **Android SDK Platform 36**, **Build-Tools** and **Platform-Tools**.
3. **Tell Godot where they are.** Go to **Editor → Editor Settings → Export → Android** and set the **Java SDK Path** and the **Android SDK Path**. The SDK is usually `C:\Users\<you>\AppData\Local\Android\Sdk`.
4. **Open the export window.** Go to **Project → Export** and pick the **Android** preset.
5. **Version.** Raise **Version → Code** above the version on your phone (1.0.26 is code 26, so use 27 or more) and set **Version → Name** to match, like `1.0.27`. A lower code won't install over the newer game.
6. **Signing (Keystore → Release):**
   - **To install over the builds from GitHub:** use the test key.
     - Release: `android/app/color-claim.keystore` (in this folder)
     - Release User: `colorclaim`
     - Release Password: `colorclaim`

     This key is already public in the repository and is only for testing.
   - **For Google Play:** use your private upload key, `color-claim-upload.keystore`, with Release User `upload` and your password. It isn't in this zip on purpose; use the copy you saved. A phone can't install an update signed with a different key than the installed game, so uninstall first when switching keys.
7. **Export.** Click **Export Project**, untick **Export With Debug**, and save the `.apk`.

For the Google Play bundle (`.aab`), first run **Project → Install Android Build Template**, then export the **Android Play** preset the same way. `store/PUBLISHING.md` covers uploading it.

## 7. Git and GitHub

The folder includes the full git history (`.git`). With **GitHub Desktop** (<https://desktop.github.com>): **File → Add local repository** → pick the `ColorClaim` folder. You can see every change, commit your own, and push them to the branch `claude/game-ideas-brainstorm-g3f06o`, which also starts the automatic checks on GitHub.
