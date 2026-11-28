# Fallout 3, Fallout: New Vegas & Skyrim (32-bit LE) for macOS (Apple Silicon)

Native Apple Silicon (`arm64`) macOS ports of **Fallout 3: Game of the Year Edition**, **Fallout: New Vegas**, and **The Elder Scrolls V: Skyrim** (32-bit DirectX 9 "Oldrim", patch `1.9.32.0.8`), built with **x86-to-C/ARM64 static recompilation** and direct **Direct3D 9 → Apple Metal** translation. Each game is packaged as its own standalone bundle (`Fallout 3.app`, `Fallout New Vegas.app`, `Skyrim.app`) with no Wine, CrossOver, Rosetta 2, or virtual machines required.

All three titles share one unified recompiler, Metal backend, and `quick-install.sh` builder (`--game fnv|fallout3|skyrim`); the installer auto-detects installed copies and GOG installers across your Mac and asks which one to build when multiple copies are found.

## Quick Start

**What you need upfront:**
1. An **Apple Silicon Mac** (M1 or newer) running **macOS 14 (Sonoma)** or later.
2. **Your own PC copy** of at least one supported game:
   - **Fallout 3 GOTY / Fallout: New Vegas (Steam or GOG):** no manual pre-download needed — `./quick-install.sh` can fetch your **Steam** copy via `steamcmd` or your **GOG** copy directly via `gogdl` using a temporary browser login (`--download` / `--download-gog`), or extract an offline GOG backup (`setup_fallout_*.exe` + `.bin` parts) placed in `~/Downloads/`.
   - **The Elder Scrolls V: Skyrim 32-bit LE (Steam AppID `72850`, patch `1.9.32.0.8`):** Windows-only on Steam — *Special Edition* and *Anniversary Edition* are not supported. No manual pre-download needed (`--download` or `--download-steam` installs `steamcmd` and fetches it for you).

**Build & install:**

```sh
./quick-install.sh
```

`quick-install.sh` guides you through the rest interactively:
- If **Apple Command Line Tools** are missing, it offers to launch `xcode-select --install` and wait until finished.
- If **[Homebrew](https://brew.sh/)** is missing, it explains where Homebrew lives (`/opt/homebrew`) and that removing it later requires its official uninstall script, then asks for confirmation before installing it.
- It automatically installs the temporary build/download tools it needs (`ghidra`, `unicorn`, `cmake`, `ffmpeg`, plus `steamcmd`, `innoextract`, or `mono` only when needed; GOG downloads use standalone SHA-256-verified `gogdl` without extra Homebrew packages). **None of them are required to play once the `.app` is built** (see [Notes on Cleanup](#notes-on-cleanup)).
- If no local game folder or GOG installer is found, it lets you **download directly from Steam (`steamcmd`) or GOG (`gogdl`)**, or **enter / drag-and-drop** a game folder, `.exe`, `.app`, or GOG `setup_*.exe` installer.

The finished app is placed in `~/Applications/Fallout 3.app`, `~/Applications/Fallout New Vegas.app`, or `~/Applications/Skyrim.app`.

---

## Why This Port Exists (Wine Challenges vs. Recent Improvements)

*Fallout 3*, *Fallout: New Vegas*, and original 32-bit *Skyrim* share the Gamebryo / Creation Engine heritage and the same three traits that have historically made them a worst-case scenario under Wine on Apple Silicon:

1. **32-bit x86 executable**
2. **Heavy x87 (80-bit) floating-point usage** — which Rosetta 2 emulates slowly in software, requiring external hooks like `rosettax87_jit` or `x87sidecar` (rarely bundled in standard Wine wrappers).
3. **Direct3D 9** — which is unsupported by **D3DMetal (GPTK)** and **DXMT** (both focused on Direct3D 10/11/12), while the older macOS DXVK fork had limitations on top of MoltenVK.

While the Wine ecosystem has improved recently — with **Wine ARM64 + FEX** in reduced-precision mode (such as CodeWeavers' CrossOver Preview) and new D3D9-to-Metal renderers (such as `mtld3d` / `Mach9`) — many free wrappers (like Sikarugir) still rely on traditional Intel Wine + Rosetta 2.

These ports eliminate that entire stack at the root:
* **No Rosetta 2 or FEX overhead:** game code is statically recompiled to **native ARM64**, with x87 arithmetic lowered to 64-bit `double` (53-bit precision, matching what the MSVC CRT configures on Windows).
* **Lower RAM footprint:** running as a single native process without `wineserver` or x86 translation layers saves significant memory — especially valuable on **8 GB unified-memory** Apple Silicon Macs.
* **Direct D3D9 → Metal:** D3D9 calls and SM 1–3 shaders compile directly to Metal (`d3d9_metal.m` and `sm2msl.c`), with MetalFX Spatial / Bilinear upscaling and SMAA / FXAA post-processing.

---

## What Changed Compared to Upstream

This repository adapts **[FNV-iOS-Shim](https://github.com/arjuk95-dot/FNV-iOS-Shim)** (which itself builds on **[Fallout-NV-MacOS](https://github.com/thetheoryofR/Fallout-NV-MacOS)**) into unified desktop **macOS** ports across three Bethesda engines:

* **Unified `--game fnv|fallout3|skyrim` recompiler & modular macOS layer:**
  * Shared AppKit window, physical panel resolution detection, fractional relative mouse accumulation (`Cmd+Tab` release + optional acceleration toggle), DirectInput keyboard mapping (`dinput.c` / `input.c`), and `GameController.framework` support (`FNVPad.c`) live in `macos/FNVApp.m`.
  * Game-specific Settings/Launcher windows live in modular controllers (`macos/FNVOptions.h`, `macos/OptionsFallout.m`, `macos/OptionsSkyrim.m`) while preserving per-game `NSUserDefaults` preference keys.
  * Distinct bundle identities (`dev.fallout3mac.<target>`, `dev.fnvmac.<target>`, `dev.skyrimmac.<target>`), `.icns` artwork (`AppIcon-Fallout3.png`, `AppIcon.png`, `AppIcon-Skyrim.png`), `LSApplicationCategoryType: public.app-category.games`, and `lsregister -f` registration in `quick-install.sh` ensure **macOS Game Mode** shows the right icon for every app ([docs/GAME-MODE-ICONS.md](docs/GAME-MODE-ICONS.md)).
* **Audio & video pipelines (`macos/FNVAudioMixer.c`, `macos/FNVXAudioMixer.c`, `upstream/recomp/host/xaudio2.c`):**
  * **All 3 games:** `AVAudioEngine` native PCM mixer, pinned Ogg/Vorbis decoding, DirectShow pull-source (`dshow.m`), and `AVFoundation` `.mp4` playback (`FNVNativeVideo.m`, transcoded from `.bik`).
  * **Skyrim (`-DFNV_GAME_SKYRIM`):** adds XAudio2 COM shims (`upstream/recomp/host/xaudio2.c`), a dedicated XAudio2 mixer backend (`macos/FNVXAudioMixer.c`), and FFmpeg xWMA/ADPCM audio decoding (`tools/build.py` bundles `libavcodec`, `libswresample`, `libavutil`, and their transitive `.dylib` dependencies inside `Skyrim.app/Contents/Frameworks/` with `@loader_path` / `@executable_path/../Frameworks` install names so `Skyrim.app` runs standalone with no Homebrew runtime dependency).
* **Restored Unicorn Engine fallback:**
  * `upstream/recomp/host/fallback.c` + `libunicorn.a` handle any uncompiled code paths or edge-case instructions.
* **Precomputed symbol maps (`symbols/fallout3/`, `symbols/fallout3-steam/`, `symbols/fnv/`, `symbols/fnv-steam/`, `symbols/skyrim/`):**
  * `tools/ghidra/ApplyMetadataAndDump.java` cuts the Ghidra step to ~1 min P-code export + ~3 min C emission (`tools/translate/emit.py`) for all five pre-mapped targets (`symbols/skyrim/` works for both Steamless CLI and Steamless GUI unpacked `TESV.exe`). Unknown/unmapped builds fall back automatically to full Ghidra auto-analysis (`FixNoReturn.java`, `ResolveJumpTables.java`, `ResolveCrtOperationTables.java`, `FixEntries.java`, `DumpPcode.java`).
* **Engine-gated D3D9, Win32 & Steamworks shims (`upstream/recomp/host/`):**
  * Shared improvements across heap allocation (`gheap.c`), file case-folding (`shims_files.c`), kernel32/sync/text/winsock shims, SM 1–3 shader translation (`sm2msl.c`), and Metal rendering (`d3d9.c`, `d3d9_metal.m`, `d3dx9.c`), with `#ifdef FNV_GAME_SKYRIM` / `#ifdef FNV_GAME_FALLOUT3` only where engine behavior genuinely diverges (e.g., Skyrim RESZ / `0x1002` AMD vendor cues / raw depth sampling / Steam callback slot offsets, vs Fallout 3/FNV Games for Windows - LIVE stubs in `shims_xlive.c`).
  * **Optional Steamworks bridge & Overlay launcher (`shims_steam.c`, `macos/FNVSteamLauncher.c`):** bundles Valve's official ARM64 `libsteam_api.dylib` (from Steamworks.NET 20.1.0, SHA-256 verified) and launches Steam silently (`-silent`) with `gameoverlayrenderer.dylib` injected for the Metal Steam Overlay (`Shift+Tab`), status, and Steam achievements. Enabled by default for **Fallout: New Vegas** (`22380`/`22490`) and **Skyrim** (`72850`), pass `--no-steam` to omit; offline standalone by default for **Fallout 3** (`22370`/`22300`), pass `--with-steam` to enable.
* **User data & logs outside the bundle:**
  * Saves, `.ini` configs, and `plugins.txt` live under `~/Library/Application Support/<Game>/UserDocuments` (and `LocalAppData/<Game>/plugins.txt`), completely preserved across rebuilds:
    * **Fallout 3:** `~/Library/Application Support/Fallout3/` & `~/Library/Logs/Fallout3/fallout3.log`
    * **Fallout: New Vegas:** `~/Library/Application Support/FalloutNV/` & `~/Library/Logs/FalloutNV/fnv.log`
    * **Skyrim:** `~/Library/Application Support/Skyrim/` & `~/Library/Logs/Skyrim/skyrim.log`
* **Benchmarking harness (`tools/bench/`):**
  * Dedicated performance/benchmarking tooling for profiling recompilation and Metal throughput.

---

## Requirements & Supported Builds

* **Apple Silicon Mac (`arm64`)** running **macOS 14 (Sonoma)** or later.
* **Xcode Command Line Tools** (`xcode-select --install`) and **Homebrew**.
* **Your own PC copy** of at least one supported title:

### Fallout 3: Game of the Year Edition

| Store | Executable | Version | SHA-256 | Symbols |
|---|---|---|---|---|
| **GOG** | `Fallout3.exe` | 1.7.0.3 | `df9f0e1ec2c5413a9cef2db2dde6d926b99707d528049af4eb15538587d55f99` | `symbols/fallout3/` |
| **Steam** | `Fallout3.exe` | 1.7.0.4 | `c3f97c2255fa041a851c17cf372d69aaadd8694e2dc4230ba556001bbfbd2f3e` | `symbols/fallout3-steam/` |

* Steam AppID `22370` is GOTY (includes all five add-ons); AppID `22300` is the original 2008 release (falls back to full Ghidra auto-analysis if the hash differs).
* Built offline standalone by default because the 1.7.0.4 Steam patch and GOG release expose no Steam achievements or Steam Cloud; pass `--with-steam` for the Steam Overlay (`Shift+Tab`).

### Fallout: New Vegas

| Store | Executable | SHA-256 | Symbols |
|---|---|---|---|
| **GOG** | `FalloutNV.exe` | `89e7020487e80f20ddc92ea641c4433b2c6839a82f45a076e414d167d11dd0fe` | `symbols/fnv/` |
| **Steam** (after Steamless) | `FalloutNV.exe` | `19406942e48724d797300c4ea6be9ac69a32f670b8c35db09279a2258422739f` | `symbols/fnv-steam/` |
| **Steam** (original, SteamStub v2.1) | `FalloutNV.exe` | `3a87f92f011e5dc9179ddf733cf08be2b39ea6e5b7a8a9e3a9a72dafcc1b104d` | strip first |

* For Steam builds with `.bind` DRM, `quick-install.sh` asks confirmation (or pass `--unpack-drm`) to install `mono`, download SHA-256-verified Steamless CLI `v3.1.0.5`, back up `FalloutNV.exe.og`, strip DRM, and compile with Steam Overlay + **75 Steam achievements** (`--no-steam` omits Steam integration).
* **GOG / Epic / other DRM-free builds:** GOG builds launch standalone offline; unmapped DRM-free hashes fall back automatically to full Ghidra auto-analysis.

### The Elder Scrolls V: Skyrim (32-bit LE, patch 1.9.32.0.8)

| Variant | Executable | SHA-256 | Symbols |
|---|---|---|---|
| **Steam** (original, SteamStub v2.1) | `TESV.exe` | `69362f77bc56bf17570a33106d020b6c67fd8f32a294b82f8b687b9cf71efc72` | auto-unpacked first |
| **Steam** (Steamless CLI `v3.1.0.5` + Mono) | `TESV.exe` | `d97eb0cc0ceef0923d2234d42b382c0d033853356528b271bc043542b1f5e605` | `symbols/skyrim/` |
| **Steam** (Steamless GUI) | `TESV.exe` | `124306c7ea4aa8c655e8d9b7b093ea30afa579e40ac0c56dee579a978f87899f` | `symbols/skyrim/` |

* **Original 32-bit Steam LE only (AppID `72850`):** Skyrim *Special Edition* and *Anniversary Edition* are 64-bit DirectX 11 builds and are not supported.
* **Automatic SteamStub strip:** No DRM-free retail Oldrim release exists, so `quick-install.sh` automatically installs `mono` (via Homebrew if missing), fetches Steamless CLI `v3.1.0.5`, backs up `TESV.exe.og`, and unpacks `TESV.exe` with no extra prompt.
* Both Steamless CLI (`d97eb0cc...`) and Steamless GUI (`124306c7...`) unpacked executables have identical PE section payloads and entry point (`0xb568a1`) — differing by only 4 padding bytes in PE section-header strings — so both directly reuse `symbols/skyrim/` without re-running Ghidra auto-analysis.

---

## Obtaining the Windows Game Files on macOS

All output locations shown below are auto-detected by `quick-install.sh`.

### Option 1: Steam

> **Automatic SteamCMD download:** running `./quick-install.sh --download` (or running `./quick-install.sh` interactively when no local copy is found) lets you pick your game/AppID, installs `steamcmd` if needed, and downloads directly from Steam.
>
> **Steam AppIDs:**
> * **Fallout 3 GOTY:** `22370` (or `22300` for original 2008 release)
> * **Fallout: New Vegas:** `22380` (Global/Ultimate; or `22490` for regional PCR edition)
> * **Skyrim (32-bit LE):** `72850`

#### Method A — `steamcmd` (recommended)

```sh
brew install --cask steamcmd
# Fallout 3 GOTY
steamcmd +@sSteamCmdForcePlatformType windows +login <YOUR_STEAM_USERNAME> +app_update 22370 validate +quit
# Fallout: New Vegas
steamcmd +@sSteamCmdForcePlatformType windows +login <YOUR_STEAM_USERNAME> +app_update 22380 validate +quit
# The Elder Scrolls V: Skyrim (32-bit LE)
steamcmd +@sSteamCmdForcePlatformType windows +login <YOUR_STEAM_USERNAME> +app_update 72850 validate +quit
```

*Downloads directly into `~/Library/Application Support/Steam/steamapps/common/<Game>/` (or `~/Steam/steamapps/common/<Game>/`), including owned DLCs. Pass `+force_install_dir "$HOME/Downloads/<Game>"` before `+login` to use a separate directory.*

#### Method B — `DepotDownloader`

```sh
brew tap steamre/tools
brew install depotdownloader
depotdownloader -app 22380 -os windows -username <YOUR_STEAM_USERNAME> -dir "$HOME/Downloads/Fallout New Vegas"
depotdownloader -app 72850 -os windows -username <YOUR_STEAM_USERNAME> -dir "$HOME/Downloads/Skyrim"
```

*If you omit `-dir`, `./depots/<appid>/<manifest>/` under `~/` or `~/Downloads/` is also auto-detected (`22370`, `22300`, `22380`, `22490`, `72850`).*

#### Method C — Steam Client Console

1. Open Steam Console: `open "steam://open/console"`
2. Download the Windows base + DLC depots (`download_depot <APPID> <DEPOT_ID>`).
3. Merge the downloaded `depot_*` folders from `~/Library/Application Support/Steam/steamapps/content/app_<APPID>/` into a single folder so the game `.exe` and `Data/` sit together.

### Option 2: GOG (Fallout 3 GOTY & Fallout: New Vegas)

#### Method A — Automatic download via `gogdl` (easiest)

Run `./quick-install.sh --download` (or jump straight to GOG with `./quick-install.sh --download-gog`, or let interactive mode offer it when no local files are found):

* Downloads the standalone Apple Silicon **[heroic-gogdl](https://github.com/Heroic-Games-Launcher/heroic-gogdl)** binary (`v1.4.0`, verified by SHA-256 — no extra Homebrew packages and no `innoextract` extraction step needed).
* Opens the official GOG login page in your default browser (supporting 2FA/CAPTCHA naturally), asks you to paste the redirected `on_login_success?...` URL back into Terminal, and keeps the temporary OAuth session strictly inside a private temp directory deleted on exit (never touching Heroic or other apps).
* Downloads the unpacked Windows build + DLCs directly from GOG (`1454315831` for *Fallout 3 GOTY*, `1454587428` for *Fallout: New Vegas Ultimate Edition*).

#### Method B — GOG Offline Installer (optional local backup)

Download the GOG offline backup installer files into `~/Downloads/`:
* **Fallout 3 GOTY:** `setup_fallout_3_1.7.0.3_(12034).exe` plus its `.bin` parts.
* **Fallout: New Vegas:** `setup_fallout_new_vegas_*.exe` plus its `.bin` parts.

Run `./quick-install.sh` (or pass `./quick-install.sh ~/Downloads/setup_fallout_3_*.exe`). `innoextract` extracts only the playable files into a temporary directory, skipping ~350 MB of Windows redistributables.

---

## Quick Install

```sh
# Auto-detect Fallout 3, Fallout: New Vegas, and Skyrim across common paths
./quick-install.sh

# Download interactively from Steam or GOG and build immediately
./quick-install.sh --download

# Or jump straight to a specific store
./quick-install.sh --download-steam --game skyrim
./quick-install.sh --download-gog --game fnv

# Restrict auto-detection or --download to a single game
./quick-install.sh --game fallout3
./quick-install.sh --game fnv
./quick-install.sh --game skyrim

# Or pass an explicit path (GOG setup_*.exe, game folder, executable, or .app bundle)
./quick-install.sh ~/Downloads/setup_fallout_3_*.exe
./quick-install.sh "/path/to/Skyrim"

# Show all flags
./quick-install.sh --help
```

When multiple installations are found:

```text
Multiple game installations found:
  1) Fallout: New Vegas (Steam) — /Users/you/Library/Application Support/Steam/steamapps/common/Fallout New Vegas
  2) Fallout 3: Game of the Year Edition (GOG installer) — /Users/you/Downloads/setup_fallout_3_1.7.0.3_(12034).exe
  3) The Elder Scrolls V: Skyrim (32-bit LE) (Steam) — /Users/you/Library/Application Support/Steam/steamapps/common/Skyrim
  Select the game to build [1-3]:
```

Additional flags:

```sh
# Download in another language (e.g. French, German, Spanish, Italian, Polish, Czech, Russian, Japanese)
./quick-install.sh --download-gog --game fnv --lang fr
./quick-install.sh --download-steam --game skyrim --lang de

# FNV or Skyrim — opt out of Steam launcher, Overlay & libsteam_api.dylib
./quick-install.sh --no-steam

# Fallout 3 — opt into Steam launcher & Overlay (standalone offline by default)
./quick-install.sh --with-steam

# Non-interactive DRM strip (Fallout 3 / FNV), wrap output in .dmg, or keep build cache
./quick-install.sh --unpack-drm --dmg
./quick-install.sh --keep-cache   # or FNV_KEEP_CACHE=1 / SKYRIM_KEEP_CACHE=1
```

* **Download languages (`--lang <code|name>`):** defaults to `en`. Supported languages by game and store:
  * **Fallout 3 (Steam / GOG):** `en`, `fr`, `de`, `es`, `it`
  * **Fallout: New Vegas:** `en`, `fr`, `de`, `es`, `it` on Steam Global (`22380`); `en`, `pl`, `cs`, `ru` on Steam PCR (`22490`); all eight (`en`, `fr`, `de`, `es`, `it`, `pl`, `cs`, `ru`) on GOG (`1454587428`)
  * **Skyrim (Steam `72850`):** `en`, `fr`, `de`, `es`, `it`, `pl`, `cs`, `ru`, `ja`
  * If switching languages on an existing installation, remove the old `FALLOUT.INI` / `Skyrim.ini` under `~/Library/Application Support/<Game>/UserDocuments/My Games/<Game>/` (keep `Saves/`) so the new localized default INI takes effect.

> **Note on disk usage & automatic cleanup:** to avoid duplicating 9–12 GB per title, `quick-install.sh` **moves** playable files into `<App>.app/Contents/Resources/GameData/`, **removes leftover Windows-only files** and Steam's matching `appmanifest_<appid>.acf` (`22370`, `22300`, `22380`, `22490`, `72850`), and **deletes `~/Library/Caches/fnv-macos`** upon success (unless `--keep-cache` / `FNV_KEEP_CACHE=1` / `SKYRIM_KEEP_CACHE=1`). Original GOG offline installers (`setup_*.exe` + `.bin`) and existing `.app` bundles are never deleted automatically.

---

## Launcher Options, Graphics, FOV & Environment Overrides

Holding `Option` on launch (or leaving "Skip launcher" unchecked) opens the native macOS Options dialog before starting the game. The runtime detects the **physical panel pixel size** (e.g. `2560×1600` on a MacBook Air M1) rather than macOS's scaled backing resolution to avoid wasted fillrate.

On MacBooks with a camera housing (notch), the app opts out of macOS's compatibility mode so native fullscreen stays full width without macOS letterboxing. Because macOS native fullscreen still confines the window below `safeAreaInsets.top`, the runtime adjusts the output height proportionally to the below-notch screen area for all games, eliminating left/right pillarbox bars at any display scaling (including scaled modes such as "More Space") while keeping the top housing strip black and clear of HUD elements like Skyrim's compass. If you prefer to fill the corners beside the notch edge-to-edge, you can opt in to **Borderless Fullscreen (Full Panel)** under Display Mode in the launcher (or set `FNV_BORDERLESS=1`) — note the macOS trade-off: macOS Game Mode and Mission Control Spaces only engage in native Fullscreen, and Skyrim's top-center compass may sit behind the camera housing. Set `FNV_NOTCH_SAFE=0` to disable the native-fullscreen height adjustment or `FNV_NOTCH_SIM_PX` to simulate a housing height on Macs without a notch.

### Fallout 3 & Fallout: New Vegas (`OptionsFallout.m`)

* **Quality Preset:** `Keep FalloutPrefs.ini`, `Low`, `Medium`, `High`, or `Ultra` (plus Texture Size, Anisotropy, Shadow Quality, Water Quality, Screen Effects: `Off`/`Bloom`/`HDR`/`HDR + Depth of Field`).
* **Upscaler / Anti-Aliasing / Render Scale:** `MetalFX Spatial` or `Bilinear`; `Off`, `SMAA`, or `FXAA`; `50–100 %` internal render scale.
* **Field of View:** Presets `Original (75° / 55°)`, `Expanded (90° / 60°)`, `Wide (100° / 65°)`, `Custom`, or `Keep FALLOUT.INI`, synchronized with **World FOV** (`75°–105°`, `fDefaultWorldFOV`) and **1st-Person FOV** (`55°–75°`, `fDefault1stPersonFOV`).
* **Window / Mouse:** Display Mode (`Fullscreen`, opt-in `Borderless Fullscreen`, or `Windowed`) and Disable macOS mouse acceleration toggle (on by default).
* **NVSE mode (experimental, Fallout: New Vegas only):** Off by default. Enables a built-in native script-extender subset (no x86 DLL loader) for pure-script mods; currently only **Sprint Mod** is confirmed working and supported. Can also be toggled via `FNV_SCRIPT_EXT=1` / `0`.
* **Environment overrides:** `FNV_PRESET=keep|low|medium|high|ultra`, `FNV_RENDER_SCALE=50..100`, `FNV_UPSCALER=metalfx|bilinear`, `FNV_AA=off|smaa|fxaa`, `FNV_FOV=75..105`, `FNV_1ST_PERSON_FOV=55..75`, `FNV_MOUSE_ACCEL=0|1`, `FNV_SCRIPT_EXT=0|1`, `FNV_WINDOWED=1`, `FNV_BORDERLESS=1`, `FNV_NOVSYNC=1`, `FNV_OUTPUT_WIDTH`/`FNV_OUTPUT_HEIGHT`, `FNV_SKIP_LAUNCHER=1`, `FNV_STEAM_NO_OVERLAY=1`, `FNV_STEAM_DISABLE=1`, `FNV_USER_DIR`, `FNV_ROOT`.

### Skyrim (`OptionsSkyrim.m`)

* **Quality & Shadows:** `Keep SkyrimPrefs.ini`, `Low`, `Medium`, `High`, `Ultra`, plus Texture Quality, Anisotropy, Water Reflections, and Shadow Quality (`Keep`/`Low`/`Medium`/`High`/`Ultra`).
* **Upscaler / Anti-Aliasing / Render Scale:** `MetalFX Spatial` or `Bilinear`; `Off`, `SMAA`, or `FXAA` (applied at internal resolution before upscaling); `50–100 %` render scale.
* **Field of View:** Presets `Original (65° / 65°)`, `Expanded (85° / 80°)`, `Wide (95° / 85°)`, `Custom`, or `Keep Skyrim.ini`, synchronized with **World FOV** (`65°–105°`, `fDefaultWorldFOV` / `fDefaultFOV`) and **1st-Person FOV** (`65°–95°`, `fDefault1stPersonFOV`).
* **Window / Mouse:** Display Mode (`Fullscreen`, opt-in `Borderless Fullscreen`, or `Windowed`) and macOS mouse acceleration toggle (disabled by default).
* **Environment overrides:** `SKYRIM_RENDER_SCALE=50..100`, `SKYRIM_UPSCALER=metalfx|bilinear`, `SKYRIM_AA=off|smaa|fxaa`, `SKYRIM_SHADOWS=keep|low|medium|high|ultra`, `SKYRIM_FOV=65..105`, `SKYRIM_1ST_PERSON_FOV=65..95`, `SKYRIM_MOUSE_ACCEL=0|1`, `FNV_WINDOWED=1`, `FNV_BORDERLESS=1`, `FNV_NOVSYNC=1`, `SKYRIM_OUTPUT_WIDTH`/`SKYRIM_OUTPUT_HEIGHT` (or `FNV_OUTPUT_*`), `SKYRIM_SKIP_LAUNCHER=1`, `SKYRIM_STEAM_NO_OVERLAY=1`, `SKYRIM_STEAM_DISABLE=1`, `SKYRIM_USER_DIR`, `SKYRIM_ROOT`.

---

## Notes on Cleanup

**None of the Homebrew packages or build tools are needed to play once the `.app` is built.** `libunicorn.a` is statically linked into the app binary, `.bik` cutscenes are already converted to `.mp4`, Ghidra only runs during translation, and Skyrim's FFmpeg xWMA decoders (`libavcodec`, `libswresample`, `libavutil` and dependencies) are bundled directly inside `Skyrim.app/Contents/Frameworks/`.

`quick-install.sh` cleans up leftover source files, `gogdl`, and `~/Library/Caches/fnv-macos` automatically upon success (unless `--keep-cache` is passed), and intentionally does **not** uninstall global software from your Mac. At the end of a run, it prints the exact list of any Homebrew packages it installed together with a ready-to-copy `brew uninstall` command (and if `quick-install.sh` installed Homebrew itself during that run, it also prints the official Homebrew uninstall script command). Packages installed by an earlier run that failed are remembered, so a re-run still shows how to remove them.

The installer also resolves the JDK that Ghidra needs by itself, reading it from Ghidra's Homebrew dependencies (Homebrew installs it keg-only, where Ghidra's launcher cannot find it on its own). If you see Ghidra report `Unable to prompt user for JDK path, no TTY detected`, reinstall it (`brew reinstall ghidra`) or point the installer at a JDK explicitly:

```sh
export JAVA_HOME="$(brew --prefix openjdk@25)/libexec/openjdk.jdk/Contents/Home"
./quick-install.sh
```

To remove build-only tools later:

```sh
# Remove all build/download packages
for p in ghidra unicorn cmake ffmpeg mono innoextract depotdownloader steamcmd; do
  brew list "$p" &>/dev/null && brew uninstall "$p"
done && brew cleanup

# Optional: remove DepotDownloader tap
brew untap steamre/tools 2>/dev/null

# Optional: clear build cache (already removed unless --keep-cache was passed)
rm -rf ~/Library/Caches/fnv-macos
```

If you only installed Apple Command Line Tools (`sudo rm -rf /Library/Developer/CommandLineTools`) or Homebrew ([official uninstall script](https://github.com/homebrew/install#uninstall-homebrew)) for this port, you can safely remove them as well once your `.app` bundles are built.

**Keep these files to continue playing:**
* `~/Applications/Fallout 3.app`, `~/Applications/Fallout New Vegas.app`, and/or `~/Applications/Skyrim.app`.
* `~/Library/Application Support/Fallout3/`, `~/Library/Application Support/FalloutNV/`, and/or `~/Library/Application Support/Skyrim/` (saves, `.ini` settings, and `plugins.txt`).

---

## Manual Build, Tests & Repository Layout

```sh
# Compile host-only check for any target (no game files required)
python3 tools/build.py host-check --game fnv
python3 tools/build.py host-check --game fallout3
python3 tools/build.py host-check --game skyrim

# Build standalone Metal/input probe app
python3 tools/build.py probe --game fnv --out build/probe-fnv
python3 tools/build.py probe --game skyrim --out build/probe-skyrim

# Run native host/media/shim test suite
bash tests/run.sh
python3 tests/virtual_alloc_test.py
python3 tests/audio_shims_test.py
python3 tests/file_shims_case_test.py
python3 tests/movie_draw_test.py
```

### Repository layout

* `quick-install.sh` — Interactive & CLI builder/packager for all three games (`--game fnv|fallout3|skyrim`).
* `macos/` — AppKit/Metal window & input host (`FNVApp.m`), modular Options launchers (`FNVOptions.h`, `OptionsFallout.m`, `OptionsSkyrim.m`), native audio/XAudio2 mixers (`FNVAudioMixer.c`, `FNVXAudioMixer.c`), AVFoundation video (`FNVNativeVideo.m`), `GameController` gamepad bridge (`FNVPad.c`), Steam Overlay launcher (`FNVSteamLauncher.c`), and app icons (`Assets/`).
* `upstream/recomp/` — Static recompiler runtime (`rt_dispatch.c`), D3D9 → Metal renderer & SM 1–3 translator (`host/d3d9.c`, `host/d3d9_metal.m`, `host/d3dx9.c`, `host/sm2msl.c`), Win32/COM/XAudio2/GFWL/Steam/Winsock shims (`host/shims_*.c`, `host/xaudio2.c`), and Unicorn fallback (`host/fallback.c`).
* `tools/` — Apple Clang bundle builder & icon/codec helpers (`build.py`, `app_icon.py`, `build_codecs.py`, `game_inputs.py`), P-code → C translator (`tools/translate/emit.py`), Ghidra scripts (`tools/ghidra/*.java`), and profiling harness (`tools/bench/`).
* `symbols/` — Precomputed function & jump-table symbol maps (`fallout3/`, `fallout3-steam/`, `fnv/`, `fnv-steam/`, `skyrim/`).
* `tests/` — Native host, media, allocator, case-folding, and video unit tests.
* `docs/` — Game Mode icon-cache notes ([GAME-MODE-ICONS.md](docs/GAME-MODE-ICONS.md)), build/performance docs, and porting session logs.

---

## Credits

* **[Fallout-NV-MacOS](https://github.com/thetheoryofR/Fallout-NV-MacOS)** (by **thetheoryofR**) — Original x86→C/ARM64 static recompiler, D3D9→Metal renderer, Win32/COM host, and Unicorn fallback (MIT license in `upstream/LICENSE`).
* **[FNV-iOS-Shim](https://github.com/arjuk95-dot/FNV-iOS-Shim)** (by **arjuk95-dot**) — Native audio mixer (`AVAudioEngine`), Ogg/Vorbis bridge, `AVFoundation` video, DirectShow pull-source, and heap/texture/sync fixes.
* **[macIV](https://github.com/tanmayisdumb/macIV)** — App bundle packaging and `quick-install.sh` UX inspiration.
