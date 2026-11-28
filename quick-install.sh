#!/bin/bash
# Fallout 3, Fallout: New Vegas & Skyrim (32-bit LE) native macOS (Apple Silicon) quick builder & packager.
#
# Recompiles your own PC copy of Fallout: New Vegas (Steam, GOG, or Epic),
# Fallout 3 (GOG or Steam), or The Elder Scrolls V: Skyrim 32-bit LE (Steam)
# into a standalone Apple Silicon macOS bundle ("Fallout New Vegas.app",
# "Fallout 3.app", or "Skyrim.app").
#
# Usage: quick-install.sh [--game fnv|fallout3|skyrim] [--download|--download-steam|--download-gog] [--lang <code|name>] [--dmg] [--keep-cache] [--keep-ghidra] [--unpack-drm] [--no-steam] [--with-steam] [-h|--help] [game_path]
#   --game <id>       select game explicitly: fnv, fallout3, or skyrim (default:
#                     auto-detect; a numbered menu appears when several are found)
#   --download        download your Windows copy interactively from Steam or GOG
#   --download-steam  download directly from Steam via steamcmd
#   --download-gog    download Fallout 3 / FNV directly from GOG via gogdl
#   --lang <lang>     language for Steam/GOG downloads: en (default), fr, de, es, it,
#                     pl, cs/cz, ru, ja (varies by game/store; full English names also accepted)
#   --dmg             also wrap the app in "<App Name>.dmg"
#   --keep-cache      keep ~/Library/Caches/fnv-macos after a successful build (for faster rebuilds)
#   --keep-ghidra     keep the Ghidra project and P-code JSONL after translation (implies --keep-cache)
#   --unpack-drm      unattended: allow downloading Steamless + Mono to strip SteamStub DRM
#   --no-steam        keep Steam builds in offline mode (skip Steam launcher, overlay & libsteam_api.dylib; already default for Fallout 3)
#   --with-steam      opt into Steam launcher & Overlay for Fallout 3 Steam builds (off by default)
#   -h, --help        show help text and exit
#   game_path         optional GOG installer (.exe), folder containing FalloutNV.exe,
#                     Fallout3.exe, or TESV.exe + Data/, or an existing app bundle.
set -euo pipefail

main() {
GOG_EXE_SHA256="89e7020487e80f20ddc92ea641c4433b2c6839a82f45a076e414d167d11dd0fe"
STEAM_OG_EXE_SHA256="3a87f92f011e5dc9179ddf733cf08be2b39ea6e5b7a8a9e3a9a72dafcc1b104d"
STEAM_UNPACKED_EXE_SHA256="19406942e48724d797300c4ea6be9ac69a32f670b8c35db09279a2258422739f"
F3_GOG_EXE_SHA256="df9f0e1ec2c5413a9cef2db2dde6d926b99707d528049af4eb15538587d55f99"
F3_STEAM_EXE_SHA256="c3f97c2255fa041a851c17cf372d69aaadd8694e2dc4230ba556001bbfbd2f3e"
SKYRIM_STEAM_OG_EXE_SHA256="69362f77bc56bf17570a33106d020b6c67fd8f32a294b82f8b687b9cf71efc72"
SKYRIM_STEAM_UNPACKED_CLI_SHA256="d97eb0cc0ceef0923d2234d42b382c0d033853356528b271bc043542b1f5e605"
SKYRIM_STEAM_UNPACKED_GUI_SHA256="124306c7ea4aa8c655e8d9b7b093ea30afa579e40ac0c56dee579a978f87899f"
STEAMLESS_VERSION="v3.1.0.5"
STEAMLESS_URL="https://github.com/atom0s/Steamless/releases/download/v3.1.0.5/Steamless.v3.1.0.5.-.by.atom0s.zip"
STEAMLESS_ZIP_SHA256="e3e2d22e098ff3fb359b2876aa2bed9596f0501e6ff588cbffae90a76d2dc4f5"
STEAMWORKS_URL="https://github.com/rlabrecque/Steamworks.NET/releases/download/20.1.0/Steamworks.NET_20.1.0.unitypackage"
STEAMWORKS_SHA256="3be79e6bdf53c86210267bf39f46362bb839130896006aec26364c5efc37e314"
GOGDL_VERSION="v1.4.0"
GOGDL_URL="https://github.com/Heroic-Games-Launcher/heroic-gogdl/releases/download/v1.4.0/gogdl_macos_arm64"
GOGDL_SHA256="af167d29ca822f495ff677d03c40bb9d6dc5535dac1f30d71775c91fe844149c"
GOG_AUTH_URL="https://auth.gog.com/auth?client_id=46899977096215655&redirect_uri=https%3A%2F%2Fembed.gog.com%2Fon_login_success%3Forigin%3Dclient&response_type=code&layout=client2"
GOG_FNV_ID="1454587428"
GOG_FO3_ID="1454315831"
HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
HOMEBREW_UNINSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh"
APP_NAME="Fallout New Vegas"
VOLNAME="$APP_NAME"
DEST_DIR="$HOME/Applications"
CACHE_ROOT="$HOME/Library/Caches/fnv-macos"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Presentation & Styling
# ---------------------------------------------------------------------------
FANCY=no
[ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && FANCY=yes || true

if [ "$FANCY" = yes ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 256 ]; then
	G1=$'\033[38;5;214m'  G2=$'\033[38;5;220m'  G3=$'\033[38;5;221m'
	G4=$'\033[38;5;222m'  G5=$'\033[38;5;223m'
	GOLD=$'\033[38;5;220m' GREEN=$'\033[38;5;84m' RED=$'\033[38;5;203m'
	CYAN=$'\033[38;5;51m'  BOLD=$'\033[1m' DIM=$'\033[2m' RESET=$'\033[0m'
elif [ "$FANCY" = yes ]; then
	G1=$'\033[93m' G2=$'\033[93m' G3=$'\033[33m' G4=$'\033[37m' G5=$'\033[97m'
	GOLD=$'\033[93m' GREEN=$'\033[92m' RED=$'\033[91m' CYAN=$'\033[96m'
	BOLD=$'\033[1m' DIM=$'\033[2m' RESET=$'\033[0m'
else
	G1= G2= G3= G4= G5= GOLD= GREEN= RED= CYAN= BOLD= DIM= RESET=
fi

SPIN=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
BAR_WIDTH=24

banner() {
	printf '\n'
	printf '  %s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$G1" "$RESET"
	printf '  %sFallout 3 · Fallout: New Vegas · Skyrim (32-bit LE)%s\n' "$G2$BOLD" "$RESET"
	printf '  %sNative ARM64 Static Recompiler · D3D9 → Metal · Apple Silicon%s\n' "$DIM" "$RESET"
	printf '  %s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$G4" "$RESET"
	printf '\n'
}

STEPS_TOTAL=7
STEP=0
step() {
	STEP=$((STEP + 1))
	printf '\n%s◆%s %s[%d/%d]%s %s\n' "$GOLD" "$RESET" "$BOLD" "$STEP" "$STEPS_TOTAL" "$RESET" "$1"
}
ok()   { printf '  %s✔%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '  %s⚠%s %s\n' "$GOLD" "$RESET" "$1"; }
die() {
	printf '  %s✘ error:%s %s\n' "$RED" "$RESET" "$1" >&2
	shift
	local line
	for line in "$@"; do printf '    %s\n' "$line" >&2; done
	exit 1
}

hsize() {
	awk -v b="${1:-0}" 'BEGIN {
		u[1]="B"; u[2]="KB"; u[3]="MB"; u[4]="GB"; i=1
		while (b >= 1024 && i < 4) { b /= 1024; i++ }
		if (i == 1) printf "%d %s", b, u[i]; else printf "%.1f %s", b, u[i]
	}'
}

du_bytes() {
	local kb
	kb=$(du -sk "$1" 2>/dev/null | awk 'NR==1 {print $1}')
	echo $(( ${kb:-0} * 1024 ))
}

draw_bar() {
	local glyph=$1 label=$2 cur=$3 total=$4
	local pct=0 filled=0 bar='' j=0 tdisp='?'
	if [ "$total" -gt 0 ]; then
		pct=$((cur * 100 / total))
		[ "$pct" -gt 100 ] && pct=100
		tdisp=$(hsize "$total")
	fi
	filled=$((pct * BAR_WIDTH / 100))
	while [ "$j" -lt "$BAR_WIDTH" ]; do
		if [ "$j" -lt "$filled" ]; then bar="${bar}█"; else bar="${bar}░"; fi
		j=$((j + 1))
	done
	printf '\r  %s %s %s%s%s %3d%%  %s%s / %s%s\033[K' \
		"$glyph" "$label" "$GOLD" "$bar" "$RESET" "$pct" \
		"$DIM" "$(hsize "$cur")" "$tdisp" "$RESET"
}

watch_bytes() {
	local pid=$1 label=$2 total=$3
	shift 3
	local i=0 rc=0 cur=0
	printf '\033[?25l'
	while kill -0 "$pid" 2>/dev/null; do
		cur=$("$@" 2>/dev/null || echo 0)
		draw_bar "${CYAN}${SPIN[$((i % 10))]}${RESET}" "$label" "$cur" "$total"
		i=$((i + 1))
		sleep 0.2
	done
	wait "$pid" || rc=$?
	printf '\033[?25h'
	if [ "$rc" -eq 0 ]; then
		[ "$total" -le 0 ] && total=$("$@" 2>/dev/null || echo 0)
		draw_bar "${GREEN}✔${RESET}" "$label" "$total" "$total"
		printf '\n'
	else
		printf '\r  %s✘%s %s failed\033[K\n' "$RED" "$RESET" "$label"
	fi
	return "$rc"
}

run_task() {
	local label=$1
	shift
	if [ "$FANCY" = no ]; then
		echo "==> $label"
		"$@"
		return
	fi
	local i=0 rc=0 pid
	"$@" &
	pid=$!
	printf '\033[?25l'
	while kill -0 "$pid" 2>/dev/null; do
		printf '\r  %s%s%s %s\033[K' "$CYAN" "${SPIN[$((i % 10))]}" "$RESET" "$label"
		i=$((i + 1))
		sleep 0.1
	done
	wait "$pid" || rc=$?
	printf '\033[?25h'
	if [ "$rc" -eq 0 ]; then
		printf '\r  %s✔%s %s\033[K\n' "$GREEN" "$RESET" "$label"
	else
		printf '\r  %s✘%s %s failed\033[K\n' "$RED" "$RESET" "$label"
	fi
	return "$rc"
}

run_task_to_log() {
	local log_file="$1"
	shift
	"$@" >"$log_file" 2>&1
}

run_logged_task() {
	local label="$1" log_file="$2"
	shift 2
	if ! run_task "$label" run_task_to_log "$log_file" "$@"; then
		if [ -s "$log_file" ]; then
			printf '  %sLast lines of %s:%s\n' "$DIM" "$log_file" "$RESET" >&2
			tail -n 60 "$log_file" | sed 's/^/    /' >&2 || true
		fi
		return 1
	fi
	return 0
}

# ---------------------------------------------------------------------------
# Options & System Checks
# ---------------------------------------------------------------------------
usage() {
	cat <<'EOF'
Usage: quick-install.sh [options] [game_path]

Recompiles your PC copy of Fallout 3 (GOTY), Fallout: New Vegas, or
The Elder Scrolls V: Skyrim (32-bit LE) into a standalone Apple Silicon
macOS app bundle in ~/Applications.

Options:
  --game <fnv|fallout3|skyrim>  Select game explicitly (default: auto-detect)
  --download                    Download game files interactively (Steam or GOG)
  --download-steam              Download Windows game files from Steam via steamcmd
  --download-gog                Download Fallout 3 / FNV from GOG via gogdl
  --lang <code|name>            Language for Steam/GOG downloads (default: en)
                                  Fallout 3 (Steam/GOG): en, fr, de, es, it
                                  FNV (Steam 22380): en, fr, de, es, it
                                  FNV (Steam PCR 22490): en, pl, cs, ru
                                  FNV (GOG): en, fr, de, es, it, pl, cs, ru
                                  Skyrim (Steam): en, fr, de, es, it, pl, cs, ru, ja
  --dmg                         Also wrap the built app in "<App Name>.dmg"
  --keep-cache                  Keep ~/Library/Caches/fnv-macos after building
  --keep-ghidra                 Keep Ghidra project & P-code JSONL (implies --keep-cache)
  --unpack-drm                  Unattended: strip SteamStub DRM with Steamless + Mono
  --no-steam                    Keep Steam builds offline (skip launcher & overlay)
  --with-steam                  Enable Steam launcher & Overlay for Fallout 3 Steam
  -h, --help                    Show this help message and exit

Arguments:
  game_path                     Optional GOG setup_*.exe, game folder, or .app bundle

Examples:
  ./quick-install.sh
  ./quick-install.sh --download
  ./quick-install.sh --download-gog --game fnv --lang fr
  ./quick-install.sh --download-steam --game skyrim --lang de
  ./quick-install.sh --game fallout3
  ./quick-install.sh ~/Downloads/setup_fallout_3_*.exe
EOF
}

WANT_DMG=no
DOWNLOAD_MODE=""
KEEP_CACHE=no
if { [ -n "${FNV_KEEP_CACHE:-}" ] && [ "${FNV_KEEP_CACHE}" != "0" ]; } || \
   { [ -n "${SKYRIM_KEEP_CACHE:-}" ] && [ "${SKYRIM_KEEP_CACHE}" != "0" ]; }; then
	KEEP_CACHE=yes
fi
KEEP_GHIDRA=no
UNPACK_DRM=no
NO_STEAM=no
WITH_STEAM=no
GAME_ID=""
GAME_ARG=""
LANG_RAW=""
LANG_EXPLICIT=no
LANG_CODE="en"
LANG_NAME="English"
STEAM_LANG="english"
GOG_LANG="en-US"
BREW_INSTALLED=()
# Packages installed by any run are remembered outside CACHE_ROOT: a run that fails after the
# installs must not lose the "how to uninstall" hint when the script is run again (issue #5).
BREW_STATE_DIR="$HOME/Library/Caches/fnv-macos-installer"
BREW_STATE_FILE="$BREW_STATE_DIR/brew-installed"
BREW_SELF_INSTALLED=no
BREW_ADDED_TO_PATH=no
while [ $# -gt 0 ]; do
	case "$1" in
		--dmg) WANT_DMG=yes ;;
		--download) DOWNLOAD_MODE="prompt" ;;
		--download-steam) DOWNLOAD_MODE="steam" ;;
		--download-gog) DOWNLOAD_MODE="gog" ;;
		--keep-cache) KEEP_CACHE=yes ;;
		--keep-ghidra) KEEP_GHIDRA=yes; KEEP_CACHE=yes ;;
		--unpack-drm) UNPACK_DRM=yes ;;
		--no-steam) NO_STEAM=yes ;;
		--with-steam) WITH_STEAM=yes ;;
		--game)
			shift
			[ $# -gt 0 ] || die "--game requires an argument (fnv, fallout3, or skyrim)."
			GAME_ID="$1"
			;;
		--game=*) GAME_ID="${1#--game=}" ;;
		--lang|--language)
			shift
			[ $# -gt 0 ] || die "--lang requires an argument (e.g. en, fr, de, es, it, pl, cs, ru, ja)."
			LANG_RAW="$1"
			LANG_EXPLICIT=yes
			;;
		--lang=*)
			LANG_RAW="${1#--lang=}"
			LANG_EXPLICIT=yes
			;;
		--language=*)
			LANG_RAW="${1#--language=}"
			LANG_EXPLICIT=yes
			;;
		-h|--help) usage; exit 0 ;;
		-*) die "Unknown option: $1" ;;
		*) GAME_ARG="$1" ;;
	esac
	shift
done

case "$GAME_ID" in
	""|fnv|fallout3|skyrim) ;;
	*) die "Unsupported --game value '$GAME_ID' (expected fnv, fallout3, or skyrim)." ;;
esac

if [ "$LANG_EXPLICIT" = yes ]; then
	LANG_NORM="$(printf '%s' "$LANG_RAW" | tr '[:upper:]' '[:lower:]')"
	case "$LANG_NORM" in
		en|en-us|en_us|english)
			LANG_CODE="en"; LANG_NAME="English"; STEAM_LANG="english"; GOG_LANG="en-US" ;;
		fr|fr-fr|fr_fr|french|francais|français)
			LANG_CODE="fr"; LANG_NAME="French"; STEAM_LANG="french"; GOG_LANG="fr-FR" ;;
		de|de-de|de_de|german|deutsch)
			LANG_CODE="de"; LANG_NAME="German"; STEAM_LANG="german"; GOG_LANG="de-DE" ;;
		es|es-es|es_es|spanish|espanol|español)
			LANG_CODE="es"; LANG_NAME="Spanish"; STEAM_LANG="spanish"; GOG_LANG="es-ES" ;;
		it|it-it|it_it|italian|italiano)
			LANG_CODE="it"; LANG_NAME="Italian"; STEAM_LANG="italian"; GOG_LANG="it-IT" ;;
		pl|pl-pl|pl_pl|polish|polski)
			LANG_CODE="pl"; LANG_NAME="Polish"; STEAM_LANG="polish"; GOG_LANG="pl-PL" ;;
		cs|cz|cs-cz|cs_cz|czech)
			LANG_CODE="cs"; LANG_NAME="Czech"; STEAM_LANG="czech"; GOG_LANG="cs-CZ" ;;
		ru|ru-ru|ru_ru|russian)
			LANG_CODE="ru"; LANG_NAME="Russian"; STEAM_LANG="russian"; GOG_LANG="ru-RU" ;;
		ja|jp|ja-jp|ja_jp|japanese)
			LANG_CODE="ja"; LANG_NAME="Japanese"; STEAM_LANG="japanese"; GOG_LANG="" ;;
		*)
			die "Unsupported --lang value '$LANG_RAW'." \
				"Supported codes: en, fr, de, es, it, pl, cs (or cz), ru, ja (full English names also accepted)." ;;
	esac
fi

validate_download_language() {
	local store="$1" game="$2" appid="${3:-}"
	if [ "$store" = gog ]; then
		if [ "$game" = fallout3 ]; then
			case "$LANG_CODE" in
				en|fr|de|es|it) return 0 ;;
				*) die "Fallout 3: Game of the Year Edition on GOG does not support --lang $LANG_CODE ($LANG_NAME)." \
					"Supported GOG languages for Fallout 3: en, fr, de, es, it." ;;
			esac
		elif [ "$game" = fnv ]; then
			case "$LANG_CODE" in
				en|fr|de|es|it|pl|cs|ru) return 0 ;;
				*) die "Fallout: New Vegas Ultimate Edition on GOG does not support --lang $LANG_CODE ($LANG_NAME)." \
					"Supported GOG languages for Fallout: New Vegas: en, fr, de, es, it, pl, cs, ru." ;;
			esac
		fi
	elif [ "$store" = steam ]; then
		if [ "$game" = fallout3 ]; then
			case "$LANG_CODE" in
				en|fr|de|es|it) return 0 ;;
				*) die "Fallout 3 on Steam (AppID ${appid:-22370}) does not support --lang $LANG_CODE ($LANG_NAME)." \
					"Supported Steam languages for Fallout 3: en, fr, de, es, it." ;;
			esac
		elif [ "$game" = fnv ]; then
			if [ "$appid" = "22490" ]; then
				case "$LANG_CODE" in
					en|pl|cs|ru) return 0 ;;
					*) die "Fallout: New Vegas PCR (Steam AppID 22490) only supports: en, pl, cs, ru." \
						"For $LANG_NAME, use the Global Steam edition (AppID 22380) or GOG (--download-gog)." ;;
				esac
			else
				case "$LANG_CODE" in
					en|fr|de|es|it) return 0 ;;
					pl|cs|ru)
						die "Fallout: New Vegas Global (Steam AppID 22380) does not include $LANG_NAME." \
							"Polish, Czech, and Russian on Steam require the regional PCR edition (AppID 22490), or use GOG (--download-gog --game fnv --lang $LANG_CODE)." ;;
					*) die "Fallout: New Vegas on Steam does not support --lang $LANG_CODE ($LANG_NAME)." \
						"Supported languages: en, fr, de, es, it (Global 22380) or en, pl, cs, ru (PCR 22490)." ;;
				esac
			fi
		elif [ "$game" = skyrim ]; then
			case "$LANG_CODE" in
				en|fr|de|es|it|pl|cs|ru|ja) return 0 ;;
				*) die "Skyrim (32-bit LE, Steam AppID 72850) does not support --lang $LANG_CODE ($LANG_NAME)." \
					"Supported Steam languages for Skyrim: en, fr, de, es, it, pl, cs, ru, ja." ;;
			esac
		fi
	fi
	return 0
}

if [ -n "$DOWNLOAD_MODE" ] && [ -n "$GAME_ARG" ]; then
	die "Cannot combine --download / --download-steam / --download-gog with an explicit game path."
fi
if [ "$DOWNLOAD_MODE" = gog ] && [ "$GAME_ID" = skyrim ]; then
	die "The Elder Scrolls V: Skyrim (32-bit LE) is only available on Steam (use --download-steam or --download)."
fi
if [ "$DOWNLOAD_MODE" = gog ] && [ -n "$GAME_ID" ]; then
	validate_download_language gog "$GAME_ID"
fi
if [ "$DOWNLOAD_MODE" = steam ] && [ "$GAME_ID" = fallout3 ]; then
	validate_download_language steam fallout3 22370
fi
if [ "$DOWNLOAD_MODE" = steam ] && [ "$GAME_ID" = skyrim ]; then
	validate_download_language steam skyrim 72850
fi
if [ "$DOWNLOAD_MODE" = steam ] && [ "$GAME_ID" = fnv ] && [ "$LANG_CODE" = ja ]; then
	validate_download_language steam fnv 22380
fi
if [ -n "$DOWNLOAD_MODE" ] && [ ! -t 0 ]; then
	die "--download requires an interactive terminal (Steam/GOG login requires interactive prompts)."
fi
if [ "$LANG_EXPLICIT" = yes ] && [ -z "$DOWNLOAD_MODE" ]; then
	warn "--lang $LANG_CODE ($LANG_NAME) only applies when downloading via --download / --download-steam / --download-gog (local files keep their existing language)."
fi

ensure_brew_in_path() {
	if ! command -v brew >/dev/null 2>&1 && [ -x /opt/homebrew/bin/brew ]; then
		eval "$(/opt/homebrew/bin/brew shellenv)"
		BREW_ADDED_TO_PATH=yes
	fi
}

brew_install_quiet() {
	local label="$1"
	shift
	local log_file="$TMP/brew-${#BREW_INSTALLED[@]}.log"
	if ! run_task "$label" bash -c 'log="$1"; shift; brew install "$@" >"$log" 2>&1' _ "$log_file" "$@"; then
		cat "$log_file" >&2 || true
		return 1
	fi
	return 0
}

require_brew() {
	local reason="$1"
	ensure_brew_in_path
	if command -v brew >/dev/null 2>&1; then
		return 0
	fi
	if [ ! -t 0 ]; then
		die "Homebrew is required $reason." \
			"Install Homebrew (https://brew.sh) and re-run this script:" \
			"  /bin/bash -c \"\$(curl -fsSL $HOMEBREW_INSTALL_URL)\""
	fi
	printf '\n'
	warn "Homebrew is not installed (needed $reason)."
	printf '    Homebrew is the standard macOS package manager used to install temporary\n'
	printf '    build/download tools. It is not required to play once the .app is built.\n'
	printf '    • Install location (Apple Silicon): %s/opt/homebrew%s\n' "$BOLD" "$RESET"
	printf '    • Setup may ask for your macOS admin password (sudo).\n'
	printf '    • Uninstalling Homebrew completely later requires its official uninstall script:\n'
	printf '      https://github.com/homebrew/install#uninstall-homebrew\n'
	printf '    • Official install command that will be run:\n'
	printf '      /bin/bash -c "$(curl -fsSL %s)"\n' "$HOMEBREW_INSTALL_URL"
	printf '  %s?%s Install Homebrew now? [y/N] ' "$CYAN" "$RESET"
	read -r REPLY || die "Aborted."
	case "$REPLY" in
		[yY]|[yY][eE][sS]|[sS]) ;;
		*)
			die "Homebrew is required $reason." \
				"Install it manually from https://brew.sh and re-run this script."
			;;
	esac
	printf '\n'
	/bin/bash -c "$(curl -fsSL "$HOMEBREW_INSTALL_URL")" \
		|| die "Homebrew installation failed or was cancelled."
	ensure_brew_in_path
	command -v brew >/dev/null 2>&1 \
		|| die "Homebrew installation completed, but 'brew' was not found in /opt/homebrew/bin."
	BREW_SELF_INSTALLED=yes
	ok "Installed Homebrew into /opt/homebrew"
}

# Ghidra's launcher needs a JDK on PATH or in JAVA_HOME; without one it asks the user for a path,
# which cannot work headless ("Unable to prompt user for JDK path, no TTY detected"). Homebrew
# installs the JDK ghidra depends on keg-only, so it is neither linked nor registered with
# /usr/libexec/java_home; resolve it from the formula's dependencies instead of hard-coding a version.
ghidra_jdk_home() {
	local dep prefix
	for dep in $(brew deps ghidra 2>/dev/null | grep -E '^openjdk(@[0-9]+)?$'); do
		prefix="$(brew --prefix "$dep" 2>/dev/null)" || continue
		if [ -x "$prefix/libexec/openjdk.jdk/Contents/Home/bin/java" ]; then
			printf '%s\n' "$prefix/libexec/openjdk.jdk/Contents/Home"
			return 0
		fi
		if [ -x "$prefix/bin/java" ]; then
			printf '%s\n' "$prefix"
			return 0
		fi
	done
	return 1
}

remember_brew_packages() {
	[ $# -gt 0 ] || return 0
	mkdir -p "$BREW_STATE_DIR" 2>/dev/null || return 0
	{
		cat "$BREW_STATE_FILE" 2>/dev/null || true
		printf '%s\n' "$@"
	} | awk 'NF && !seen[$0]++' >"$BREW_STATE_FILE.tmp" 2>/dev/null &&
		mv "$BREW_STATE_FILE.tmp" "$BREW_STATE_FILE" 2>/dev/null || true
}

load_brew_packages() {
	local pkg
	[ -f "$BREW_STATE_FILE" ] || return 0
	while IFS= read -r pkg; do
		[ -n "$pkg" ] || continue
		BREW_INSTALLED+=("$pkg")
	done <"$BREW_STATE_FILE"
}
load_brew_packages

banner

if [ "$(uname -sm)" != "Darwin arm64" ]; then
	die "This installer requires an Apple Silicon Mac (arm64)."
fi

OS_VER="$(sw_vers -productVersion)"
OS_MAJOR="$(echo "$OS_VER" | cut -d. -f1)"
if [ "$OS_MAJOR" -lt 14 ]; then
	die "macOS 14 (Sonoma) or newer is required (detected $OS_VER)."
fi

if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find clang >/dev/null 2>&1; then
	if [ ! -t 0 ]; then
		die "Apple Command Line Tools / Xcode not found." \
			"Run: xcode-select --install"
	fi
	printf '\n'
	warn "Apple Command Line Tools are not installed (needed for clang, python3, and codesign)."
	printf '    • Install location: %s/Library/Developer/CommandLineTools%s\n' "$BOLD" "$RESET"
	printf '    • Can be removed later with: sudo rm -rf /Library/Developer/CommandLineTools\n'
	printf '  %s?%s Launch Apple'\''s Command Line Tools installer now (xcode-select --install)? [y/N] ' "$CYAN" "$RESET"
	read -r REPLY || die "Aborted."
	case "$REPLY" in
		[yY]|[yY][eE][sS]|[sS])
			xcode-select --install 2>/dev/null || true
			printf '    Finish the macOS Command Line Tools installation window that opened,\n'
			printf '    then press Enter here to continue (or type q to quit): '
			while ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find clang >/dev/null 2>&1; do
				read -r REPLY || die "Aborted."
				case "$REPLY" in
					[qQ]|[qQ][uU][iI][tT])
						die "Apple Command Line Tools installation incomplete. Re-run this script once finished."
						;;
				esac
				if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find clang >/dev/null 2>&1; then
					printf '    Command Line Tools not ready yet. Press Enter when installation finishes (or type q to quit): '
				fi
			done
			ok "Apple Command Line Tools ready"
			;;
		*)
			die "Apple Command Line Tools / Xcode not found." \
				"Run: xcode-select --install"
			;;
	esac
fi

ensure_brew_in_path

TMP="$(mktemp -d "${TMPDIR:-/tmp}/fnv-install.XXXXXX")"
DEV=""
APP=""
GDATA=""
cleanup() {
	kill $(jobs -p) 2>/dev/null || true
	[ -n "$DEV" ] && hdiutil detach "$DEV" >/dev/null 2>&1 || true
	if [ -n "$TMP" ]; then
		if [ -n "$GDATA" ] && [ -d "$GDATA" ] && [ -n "$(ls -A "$GDATA" 2>/dev/null)" ]; then
			printf '  %s⚠ Note:%s Preserving moved game files in your user temp directory (no admin needed):\n' "$GOLD" "$RESET" >&2
			printf '    %s\n' "$APP" >&2
			printf '    Locate in Finder: open -R "%s"\n' "$APP" >&2
			printf '    Discard & free space: rm -rf "%s"\n' "$TMP" >&2
		else
			rm -rf "$TMP"
		fi
	fi
	[ "$FANCY" = yes ] && printf '\033[?25h' || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Step 1: Locate game files (Fallout 3, Fallout: New Vegas, or Skyrim)
# ---------------------------------------------------------------------------
step "Locating game files (Fallout 3, Fallout: New Vegas, or Skyrim)"

MATCHES=()
MATCH_KEYS=()
add_match() {
	local game="$1" kind="$2" path="$3" key existing
	# deduplicate by device+inode: APFS is case-insensitive, so "Fallout 3" and "fallout 3"
	# resolve to the same installation or installer file
	key="$(stat -f '%d:%i' "$path" 2>/dev/null)" || return 0
	[ -n "$key" ] || return 0
	key="$game|$kind|$key"
	for existing in "${MATCH_KEYS[@]+"${MATCH_KEYS[@]}"}"; do
		[ "$existing" = "$key" ] && return 0
	done
	MATCH_KEYS+=("$key")
	MATCHES+=("$game|$kind|$path")
}

game_display_name() {
	case "$1" in
		fallout3) echo "Fallout 3: Game of the Year Edition" ;;
		fnv) echo "Fallout: New Vegas" ;;
		skyrim) echo "The Elder Scrolls V: Skyrim (32-bit LE)" ;;
		*) echo "Game (auto-detect)" ;;
	esac
}

game_channel() {
	local dir="${1%/}" app_root
	case "$dir" in
		*/steamapps/common/*|*/Steam/steamapps/*|*/steam-download/*|*/depots/22380*|*/depots/22490*|*/depots/22370*|*/depots/22300*|*/depots/72850*)
			echo "Steam"; return ;;
	esac
	case "$dir" in
		*/Contents/Resources/GameData)
			app_root="${dir%/Contents/Resources/GameData}"
			if [ -f "$app_root/Contents/MacOS/steam_appid.txt" ] || [ -f "$app_root/Contents/Frameworks/libsteam_api.dylib" ]; then
				echo "Steam"; return
			fi
			;;
	esac
	case "$dir" in
		*/gog-download/*)
			echo "GOG"; return ;;
	esac
	if compgen -G "$dir/goggame-*.info" >/dev/null 2>&1 || compgen -G "$dir/goggame-*.hashdb" >/dev/null 2>&1; then
		echo "GOG"; return
	fi
	echo "DRM-free"
}

scan_gog_installers_in_dir() {
	local dir="${1%/}" f
	[ -d "$dir" ] || return 0
	shopt -s nullglob nocaseglob
	if [ -z "$GAME_ID" ] || [ "$GAME_ID" = fallout3 ]; then
		for f in "$dir"/setup_fallout_3_*.exe; do
			[ -f "$f" ] && add_match fallout3 gog_installer "$f"
		done
	fi
	if [ -z "$GAME_ID" ] || [ "$GAME_ID" = fnv ]; then
		for f in "$dir"/setup_fallout_new_vegas_*.exe; do
			[ -f "$f" ] && add_match fnv gog_installer "$f"
		done
	fi
	shopt -u nullglob nocaseglob
}

# Collect every installation under one root instead of stopping at the first, so a folder that
# contains multiple games (or several copies) can be offered as a choice.
scan_game_root() {
	local base="${1%/}" root dir
	for root in "$base" "$base.app"; do
		for dir in \
			"$root" \
			"$root/app" \
			"$root/Fallout New Vegas" \
			"$root/Fallout New Vegas/app" \
			"$root/Fallout New Vegas Ultimate" \
			"$root/steamapps/common/Fallout New Vegas" \
			"$root/Fallout 3" \
			"$root/Fallout 3 goty" \
			"$root/Fallout 3 GOTY" \
			"$root/Fallout 3/app" \
			"$root/steamapps/common/Fallout 3 goty" \
			"$root/steamapps/common/Fallout 3" \
			"$root/Skyrim" \
			"$root/steamapps/common/Skyrim" \
			"$root/Contents/Resources/GameData"; do
			[ -d "$dir" ] || continue
			if { [ -z "$GAME_ID" ] || [ "$GAME_ID" = fnv ]; } && [ -f "$dir/FalloutNV.exe" ] && [ -f "$dir/Data/FalloutNV.esm" ]; then
				add_match fnv dir "$dir"
			fi
			if { [ -z "$GAME_ID" ] || [ "$GAME_ID" = fallout3 ]; } && [ -f "$dir/Fallout3.exe" ] && [ -f "$dir/Data/Fallout3.esm" ]; then
				add_match fallout3 dir "$dir"
			fi
			if { [ -z "$GAME_ID" ] || [ "$GAME_ID" = skyrim ]; } && [ -f "$dir/TESV.exe" ] && [ -f "$dir/Data/Skyrim.esm" ]; then
				add_match skyrim dir "$dir"
			fi
		done
	done
}

resolve_user_input_path() {
	python3 - "$1" <<'PY'
import os, shlex, sys
raw = sys.argv[1]
stripped = raw.strip()
if not stripped:
    sys.exit(0)
direct = os.path.expanduser(stripped)
if os.path.exists(direct):
    print(direct)
    sys.exit(0)
try:
    parts = shlex.split(raw)
except ValueError:
    parts = []
if len(parts) == 1:
    print(os.path.expanduser(parts[0]))
else:
    print(direct)
PY
}

scan_explicit_path() {
	local target="$1" mode="${2:-fatal}" base_lc detected_game
	if [ -f "$target" ]; then
		base_lc="$(basename "$target" | tr '[:upper:]' '[:lower:]')"
		case "$base_lc" in
			falloutnv.exe|fallout3.exe|tesv.exe)
				scan_game_root "$(dirname "$target")"
				;;
			*.exe)
				detected_game="${GAME_ID:-}"
				if [ -z "$detected_game" ]; then
					case "$base_lc" in
						*fallout*3*) detected_game="fallout3" ;;
						*new*vegas*|*fnv*) detected_game="fnv" ;;
						*) detected_game="auto" ;;
					esac
				fi
				add_match "$detected_game" gog_installer "$target"
				;;
			*)
				if [ "$mode" = fatal ]; then
					die "Unsupported file: $target" \
						"Pass a GOG setup_*.exe installer or a folder containing FalloutNV.exe, Fallout3.exe, or TESV.exe and Data/."
				fi
				warn "Unsupported file: $target"
				return 1
				;;
		esac
	elif [ -d "$target" ]; then
		scan_game_root "$target"
		scan_gog_installers_in_dir "$target"
	else
		if [ "$mode" = fatal ]; then
			die "Could not find a GOG installer or FalloutNV.exe/Fallout3.exe/TESV.exe + Data/ in: $target"
		fi
		warn "Path not found: $target"
		return 1
	fi
	if [ ${#MATCHES[@]} -eq 0 ]; then
		if [ "$mode" = fatal ]; then
			die "Could not find a GOG installer or FalloutNV.exe/Fallout3.exe/TESV.exe + Data/ in: $target"
		fi
		warn "Could not find a GOG installer or FalloutNV.exe/Fallout3.exe/TESV.exe + Data/ in: $target"
		return 1
	fi
	return 0
}

STEAM_DL_GAME=""
STEAM_DL_APPID=""

select_steam_download_target() {
	local choice subchoice
	STEAM_DL_GAME=""
	STEAM_DL_APPID=""
	if [ "$GAME_ID" = fnv ]; then
		while true; do
			printf '\n%sSelect Fallout: New Vegas Steam edition:%s\n' "$BOLD" "$RESET"
			printf '  %s1)%s Global / Ultimate (AppID 22380 — en/fr/de/es/it) [default]\n' "$GOLD" "$RESET"
			printf '  %s2)%s Regional PCR edition (AppID 22490 — en/pl/cs/ru)\n' "$GOLD" "$RESET"
			printf '  Select [1-2]: '
			read -r choice || die "Aborted."
			case "$choice" in
				""|1) STEAM_DL_GAME="fnv"; STEAM_DL_APPID="22380"; return 0 ;;
				2)    STEAM_DL_GAME="fnv"; STEAM_DL_APPID="22490"; return 0 ;;
				*)    warn "Please enter 1 or 2." ;;
			esac
		done
	elif [ "$GAME_ID" = fallout3 ]; then
		while true; do
			printf '\n%sSelect Fallout 3 Steam edition:%s\n' "$BOLD" "$RESET"
			printf '  %s1)%s Game of the Year Edition (AppID 22370 — includes all DLC) [default]\n' "$GOLD" "$RESET"
			printf '  %s2)%s Original 2008 release (AppID 22300)\n' "$GOLD" "$RESET"
			printf '  Select [1-2]: '
			read -r choice || die "Aborted."
			case "$choice" in
				""|1) STEAM_DL_GAME="fallout3"; STEAM_DL_APPID="22370"; return 0 ;;
				2)    STEAM_DL_GAME="fallout3"; STEAM_DL_APPID="22300"; return 0 ;;
				*)    warn "Please enter 1 or 2." ;;
			esac
		done
	elif [ "$GAME_ID" = skyrim ]; then
		STEAM_DL_GAME="skyrim"
		STEAM_DL_APPID="72850"
		return 0
	else
		while true; do
			printf '\n%sWhich Steam game do you own and want to download?%s\n' "$BOLD" "$RESET"
			printf '  %s1)%s Fallout: New Vegas (AppID 22380 — Global / Ultimate)\n' "$GOLD" "$RESET"
			printf '  %s2)%s Fallout 3: Game of the Year Edition (AppID 22370 — includes all DLC)\n' "$GOLD" "$RESET"
			printf '  %s3)%s The Elder Scrolls V: Skyrim (32-bit LE, AppID 72850)\n' "$GOLD" "$RESET"
			printf '  %s4)%s Other Steam edition (FNV PCR 22490 / Fallout 3 original 22300)\n' "$GOLD" "$RESET"
			printf '  Select [1-4]: '
			read -r choice || die "Aborted."
			case "$choice" in
				1) STEAM_DL_GAME="fnv"; STEAM_DL_APPID="22380"; return 0 ;;
				2) STEAM_DL_GAME="fallout3"; STEAM_DL_APPID="22370"; return 0 ;;
				3) STEAM_DL_GAME="skyrim"; STEAM_DL_APPID="72850"; return 0 ;;
				4)
					while true; do
						printf '\n%sSelect other Steam edition:%s\n' "$BOLD" "$RESET"
						printf '  %s1)%s Fallout: New Vegas — PCR regional edition (AppID 22490)\n' "$GOLD" "$RESET"
						printf '  %s2)%s Fallout 3 — original 2008 release (AppID 22300)\n' "$GOLD" "$RESET"
						printf '  %s3)%s Back\n' "$GOLD" "$RESET"
						printf '  Select [1-3]: '
						read -r subchoice || die "Aborted."
						case "$subchoice" in
							1) STEAM_DL_GAME="fnv"; STEAM_DL_APPID="22490"; return 0 ;;
							2) STEAM_DL_GAME="fallout3"; STEAM_DL_APPID="22300"; return 0 ;;
							3) break ;;
							*) warn "Please enter 1, 2, or 3." ;;
						esac
					done
					;;
				*) warn "Please enter 1, 2, 3, or 4." ;;
			esac
		done
	fi
}

download_game_via_steamcmd() {
	select_steam_download_target
	validate_download_language steam "$STEAM_DL_GAME" "$STEAM_DL_APPID"

	ensure_brew_in_path
	if ! command -v steamcmd >/dev/null 2>&1; then
		require_brew "to install steamcmd (and build tools)"
		if ! command -v steamcmd >/dev/null 2>&1; then
			brew_install_quiet "Installing steamcmd via Homebrew" --cask steamcmd \
				|| die "Failed to install steamcmd via Homebrew."
			BREW_INSTALLED+=(steamcmd)
			remember_brew_packages steamcmd
		fi
		command -v steamcmd >/dev/null 2>&1 || die "steamcmd not found after installation."
	else
		ok "Found steamcmd ($(command -v steamcmd))"
	fi

	printf '\n  %sDownloading %s via SteamCMD (AppID %s, language: %s)%s\n' "$BOLD" "$(game_display_name "$STEAM_DL_GAME")" "$STEAM_DL_APPID" "$LANG_NAME" "$RESET"
	if [ "$STEAM_DL_GAME" = skyrim ]; then
		printf '    • Requires original 32-bit Skyrim (AppID 72850) on your Steam account — not Special/Anniversary Edition.\n'
	fi
	printf '    • Files will download into a temporary cache (~9-12 GB) and be moved into the app.\n'
	printf '    • Enter your Steam account login name (not your public display name).\n'
	printf '    • SteamCMD will prompt you directly for your password and Steam Guard code\n'
	printf '      or Mobile Authenticator approval — this script never reads your password.\n\n'

	local steam_user=""
	while true; do
		printf '  %s?%s Steam account username (or q to quit): ' "$CYAN" "$RESET"
		read -r steam_user || die "Aborted."
		case "$steam_user" in
			[qQ]|[qQ][uU][iI][tT]) die "Steam download aborted." ;;
			"") warn "Steam username cannot be empty." ;;
			*[[:space:]]*) warn "Steam account login names do not contain spaces." ;;
			*) break ;;
		esac
	done

	local download_dir steam_rc files_ok retry_choice new_user
	while true; do
		if [ "$LANG_CODE" = en ]; then
			download_dir="$CACHE_ROOT/steam-download/$STEAM_DL_APPID"
		else
			download_dir="$CACHE_ROOT/steam-download/${STEAM_DL_APPID}-${LANG_CODE}"
		fi
		mkdir -p "$download_dir"
		if [ -d "$download_dir/steamapps" ] && [ ! -f "$download_dir/.steamcmd-complete" ]; then
			printf '  %sNote:%s Resuming/validating previous download in %s\n' "$DIM" "$RESET" "$download_dir"
		fi
		rm -f "$download_dir/.steamcmd-complete"

		printf '\n'
		steam_rc=0
		steamcmd \
			+@sSteamCmdForcePlatformType windows \
			+force_install_dir "$download_dir" \
			+login "$steam_user" \
			+app_update "$STEAM_DL_APPID" -language "$STEAM_LANG" validate \
			+quit || steam_rc=$?
		printf '\n'

		files_ok=no
		if [ "$STEAM_DL_GAME" = fnv ] && [ -f "$download_dir/FalloutNV.exe" ] && [ -f "$download_dir/Data/FalloutNV.esm" ]; then
			files_ok=yes
		elif [ "$STEAM_DL_GAME" = fallout3 ] && [ -f "$download_dir/Fallout3.exe" ] && [ -f "$download_dir/Data/Fallout3.esm" ]; then
			files_ok=yes
		elif [ "$STEAM_DL_GAME" = skyrim ] && [ -f "$download_dir/TESV.exe" ] && [ -f "$download_dir/Data/Skyrim.esm" ]; then
			files_ok=yes
		fi

		if [ "$steam_rc" -eq 0 ] && [ "$files_ok" = yes ]; then
			touch "$download_dir/.steamcmd-complete"
			add_match "$STEAM_DL_GAME" dir "$download_dir"
			ok "Downloaded $(game_display_name "$STEAM_DL_GAME") (AppID $STEAM_DL_APPID) via SteamCMD"
			break
		fi

		if [ "$files_ok" = yes ]; then
			warn "SteamCMD exited with code $steam_rc; the download may be incomplete (retrying will validate missing files)."
		else
			warn "SteamCMD finished (exit $steam_rc) without the expected game files in $download_dir."
			printf '    Common causes: wrong username/password, Steam Guard timeout, or wrong edition/AppID.\n'
		fi

		while true; do
			printf '  %s?%s [r] Retry  [c] Change game/AppID  [q] Quit [r]: ' "$CYAN" "$RESET"
			read -r retry_choice || die "Aborted."
			case "$retry_choice" in
				""|[rR])
					printf '  %s?%s Steam username [%s]: ' "$CYAN" "$RESET" "$steam_user"
					read -r new_user || die "Aborted."
					if [ -n "$new_user" ]; then
						if [[ "$new_user" == *[[:space:]]* ]]; then
							warn "Steam account login names do not contain spaces; keeping '$steam_user'."
						else
							steam_user="$new_user"
						fi
					fi
					break
					;;
				[cC])
					select_steam_download_target
					validate_download_language steam "$STEAM_DL_GAME" "$STEAM_DL_APPID"
					break
					;;
				[qQ]|[qQ][uU][iI][tT])
					die "Steam download aborted."
					;;
				*)
					warn "Please enter r, c, or q."
					;;
			esac
		done
	done
}

GOG_DL_GAME=""
GOG_DL_ID=""
GOGDL_BIN=""
GOG_AUTH_FILE="$TMP/gog-auth.json"
GOG_CFG_DIR="$TMP/gogdl-cfg"

select_gog_download_target() {
	local choice
	GOG_DL_GAME=""
	GOG_DL_ID=""
	if [ "$GAME_ID" = fnv ]; then
		GOG_DL_GAME="fnv"
		GOG_DL_ID="$GOG_FNV_ID"
		return 0
	elif [ "$GAME_ID" = fallout3 ]; then
		GOG_DL_GAME="fallout3"
		GOG_DL_ID="$GOG_FO3_ID"
		return 0
	else
		while true; do
			printf '\n%sWhich GOG game do you own and want to download?%s\n' "$BOLD" "$RESET"
			printf '  %s1)%s Fallout: New Vegas Ultimate Edition (GOG ID %s)\n' "$GOLD" "$RESET" "$GOG_FNV_ID"
			printf '  %s2)%s Fallout 3: Game of the Year Edition (GOG ID %s)\n' "$GOLD" "$RESET" "$GOG_FO3_ID"
			printf '  Select [1-2] (or q to quit): '
			read -r choice || die "Aborted."
			case "$choice" in
				1) GOG_DL_GAME="fnv"; GOG_DL_ID="$GOG_FNV_ID"; return 0 ;;
				2) GOG_DL_GAME="fallout3"; GOG_DL_ID="$GOG_FO3_ID"; return 0 ;;
				[qQ]|[qQ][uU][iI][tT]) die "GOG download aborted." ;;
				*) warn "Please enter 1 or 2 (or q to quit)." ;;
			esac
		done
	fi
}

ensure_gogdl() {
	local cache_dir="$CACHE_ROOT/gogdl/$GOGDL_VERSION"
	local cached_bin="$cache_dir/gogdl"
	local dl_tmp="$TMP/gogdl_macos_arm64"
	local got_sha=""
	if [ -f "$cached_bin" ]; then
		got_sha="$(shasum -a 256 "$cached_bin" | awk '{print $1}')"
		if [ "$got_sha" = "$GOGDL_SHA256" ]; then
			chmod +x "$cached_bin" 2>/dev/null || true
			GOGDL_BIN="$cached_bin"
			ok "Using cached gogdl ($GOGDL_VERSION)"
			return 0
		fi
		rm -f "$cached_bin"
	fi
	if ! run_logged_task "Downloading heroic-gogdl ($GOGDL_VERSION)" "$TMP/download.log" \
		curl -fsSL --retry 3 "$GOGDL_URL" -o "$dl_tmp"; then
		rm -f "$dl_tmp"
		die "Failed to download heroic-gogdl ($GOGDL_VERSION) from GitHub Releases."
	fi
	got_sha="$(shasum -a 256 "$dl_tmp" | awk '{print $1}')"
	if [ "$got_sha" != "$GOGDL_SHA256" ]; then
		rm -f "$dl_tmp"
		die "Downloaded gogdl SHA-256 mismatch." \
			"Expected: $GOGDL_SHA256" \
			"Got:      $got_sha"
	fi
	mkdir -p "$cache_dir"
	mv "$dl_tmp" "$cached_bin"
	chmod +x "$cached_bin"
	GOGDL_BIN="$cached_bin"
	ok "Verified heroic-gogdl ($GOGDL_VERSION)"
}

extract_gog_auth_code() {
	python3 - "${1:-}" <<'PY'
import re, sys, urllib.parse
raw = sys.argv[1].strip().strip('\'"')
if not raw:
    sys.exit(0)
if '://' in raw or 'code=' in raw:
    parsed = urllib.parse.urlparse(raw)
    qs = urllib.parse.parse_qs(parsed.query)
    if not qs and 'code=' in raw:
        qs = urllib.parse.parse_qs(raw.lstrip('?'))
    codes = qs.get('code') or []
    if codes and codes[0].strip():
        print(codes[0].strip())
    sys.exit(0)
if re.fullmatch(r'[A-Za-z0-9._~-]+', raw):
    print(raw)
PY
}

authenticate_gog_isolated() {
	mkdir -p "$GOG_CFG_DIR"
	printf '\n  %sGOG Authentication (isolated temporary session)%s\n' "$BOLD" "$RESET"
	printf '    • Opens GOG'\''s official login page in your browser — this script never asks for\n'
	printf '      your GOG password in Terminal and never reads Heroic or other app sessions.\n'
	printf '    • After signing in, your browser reaches a blank "on_login_success" page.\n'
	printf '    • Copy that full URL from your browser address bar and paste it here.\n'
	printf '    • Credentials stay only in a private temporary file and are deleted on exit.\n\n'
	printf '    Login URL:\n      %s\n\n' "$GOG_AUTH_URL"

	local open_reply="" raw_auth="" auth_code="" gog_auth_ok="no" retry_choice=""
	local auth_out="$TMP/gog-auth-out.json"
	local auth_log="$TMP/gog-auth.log"
	while true; do
		printf '  %s?%s Open GOG login page in your default browser? [Y/n] ' "$CYAN" "$RESET"
		read -r open_reply || die "GOG login aborted."
		case "$open_reply" in
			""|[yY]|[yY][eE][sS]|[sS])
				open "$GOG_AUTH_URL" >/dev/null 2>&1 || true
				;;
			[qQ]|[qQ][uU][iI][tT])
				die "GOG download aborted."
				;;
		esac

		while true; do
			printf '  %s?%s Paste the on_login_success URL (or q to quit): ' "$CYAN" "$RESET"
			read -r raw_auth || die "GOG login aborted."
			case "$raw_auth" in
				[qQ]|[qQ][uU][iI][tT]) die "GOG download aborted." ;;
			esac
			auth_code="$(extract_gog_auth_code "$raw_auth")"
			if [ -n "$auth_code" ]; then
				break
			fi
			warn "Could not find an authorization code in what you pasted. Copy the full https://embed.gog.com/on_login_success?... URL."
		done

		rm -f "$GOG_AUTH_FILE" "$auth_out" "$auth_log"
		GOGDL_CONFIG_PATH="$GOG_CFG_DIR" "$GOGDL_BIN" \
			--auth-config-path "$GOG_AUTH_FILE" \
			auth --code "$auth_code" >"$auth_out" 2>"$auth_log" || true

		gog_auth_ok="$(python3 - "$auth_out" "$GOG_AUTH_FILE" <<'PY'
import json, sys
out_path, cfg_path = sys.argv[1], sys.argv[2]
try:
    out = json.load(open(out_path))
    if isinstance(out, dict) and out.get("error"):
        print("no")
        sys.exit(0)
except Exception:
    pass
try:
    cfg = json.load(open(cfg_path))
    tok = (cfg.get("46899977096215655") or {}).get("access_token")
    print("yes" if isinstance(tok, str) and len(tok) > 0 else "no")
except Exception:
    print("no")
PY
)"
		rm -f "$auth_out"
		chmod 600 "$GOG_AUTH_FILE" 2>/dev/null || true

		if [ "$gog_auth_ok" = yes ]; then
			rm -f "$auth_log"
			ok "Authenticated GOG session in isolated temp storage"
			return 0
		fi

		warn "GOG login failed (invalid/expired code or network error)."
		if [ -s "$auth_log" ]; then
			sed 's/^/    /' "$auth_log" >&2 || true
		fi
		while true; do
			printf '  %s?%s [r] Try again  [q] Quit [r]: ' "$CYAN" "$RESET"
			read -r retry_choice || die "GOG login aborted."
			case "$retry_choice" in
				""|[rR]) break ;;
				[qQ]|[qQ][uU][iI][tT]) die "GOG download aborted." ;;
				*) warn "Please enter r or q." ;;
			esac
		done
	done
}

find_gogdl_game_dir() {
	local game="$1" base="$2" d exe esm
	if [ "$game" = fallout3 ]; then
		exe="Fallout3.exe"; esm="Data/Fallout3.esm"
	else
		exe="FalloutNV.exe"; esm="Data/FalloutNV.esm"
	fi
	if [ -f "$base/$exe" ] && [ -f "$base/$esm" ]; then
		echo "$base"; return 0
	fi
	shopt -s nullglob
	for d in "$base"/*; do
		if [ -d "$d" ] && [ -f "$d/$exe" ] && [ -f "$d/$esm" ]; then
			shopt -u nullglob
			echo "$d"; return 0
		fi
	done
	shopt -u nullglob
	return 1
}

download_game_via_gogdl() {
	select_gog_download_target
	validate_download_language gog "$GOG_DL_GAME"
	ensure_gogdl
	authenticate_gog_isolated

	local download_dir gog_rc found_dir retry_choice
	while true; do
		if [ "$LANG_CODE" = en ]; then
			download_dir="$CACHE_ROOT/gog-download/$GOG_DL_ID"
		else
			download_dir="$CACHE_ROOT/gog-download/${GOG_DL_ID}-${LANG_CODE}"
		fi
		mkdir -p "$download_dir"
		if [ ! -f "$download_dir/.gogdl-complete" ] && [ -n "$(ls -A "$download_dir" 2>/dev/null)" ]; then
			printf '  %sNote:%s Resuming/verifying previous download in %s\n' "$DIM" "$RESET" "$download_dir"
		fi
		rm -f "$download_dir/.gogdl-complete"

		printf '\n  %sDownloading %s via gogdl (GOG ID %s, language: %s)%s\n' \
			"$BOLD" "$(game_display_name "$GOG_DL_GAME")" "$GOG_DL_ID" "$LANG_NAME" "$RESET"
		printf '    • Files download into temporary cache and are moved into the app bundle.\n\n'

		gog_rc=0
		GOGDL_CONFIG_PATH="$GOG_CFG_DIR" "$GOGDL_BIN" \
			--auth-config-path "$GOG_AUTH_FILE" \
			download "$GOG_DL_ID" \
			--platform windows \
			--lang "$GOG_LANG" \
			--with-dlcs \
			--path "$download_dir" || gog_rc=$?
		printf '\n'

		found_dir="$(find_gogdl_game_dir "$GOG_DL_GAME" "$download_dir" || true)"
		if [ "$gog_rc" -eq 0 ] && [ -n "$found_dir" ]; then
			touch "$download_dir/.gogdl-complete"
			add_match "$GOG_DL_GAME" dir "$found_dir"
			ok "Downloaded $(game_display_name "$GOG_DL_GAME") (GOG ID $GOG_DL_ID) via gogdl"
			break
		fi

		if [ -n "$found_dir" ]; then
			warn "gogdl exited with code $gog_rc; the download may be incomplete (retrying will resume missing chunks)."
		else
			warn "gogdl finished (exit $gog_rc) without the expected game files in $download_dir."
			printf '    Common causes: your GOG account does not own this title, expired auth session, disk space, or network error.\n'
		fi

		while true; do
			printf '  %s?%s [r] Retry  [l] Re-authenticate  [c] Change game  [q] Quit [r]: ' "$CYAN" "$RESET"
			read -r retry_choice || die "Aborted."
			case "$retry_choice" in
				""|[rR])
					break
					;;
				[lL])
					authenticate_gog_isolated
					break
					;;
				[cC])
					select_gog_download_target
					validate_download_language gog "$GOG_DL_GAME"
					break
					;;
				[qQ]|[qQ][uU][iI][tT])
					die "GOG download aborted."
					;;
				*)
					warn "Please enter r, l, c, or q."
					;;
			esac
		done
	done
}

download_game_interactive() {
	if [ "$GAME_ID" = skyrim ]; then
		download_game_via_steamcmd
		return
	fi
	local store_choice
	while true; do
		if [ -n "$GAME_ID" ]; then
			printf '\n%sWhich store do you own %s on?%s\n' "$BOLD" "$(game_display_name "$GAME_ID")" "$RESET"
			printf '  %s1)%s Steam (via steamcmd — installs steamcmd if needed)\n' "$GOLD" "$RESET"
			printf '  %s2)%s GOG (via gogdl — isolated temporary browser login)\n' "$GOLD" "$RESET"
		else
			printf '\n%sWhich store would you like to download from?%s\n' "$BOLD" "$RESET"
			printf '  %s1)%s Steam (Fallout 3, Fallout: New Vegas, or Skyrim — via steamcmd)\n' "$GOLD" "$RESET"
			printf '  %s2)%s GOG (Fallout 3 GOTY or Fallout: New Vegas — via gogdl)\n' "$GOLD" "$RESET"
		fi
		printf '  %s3)%s Quit\n' "$GOLD" "$RESET"
		printf '  Select [1-3]: '
		read -r store_choice || die "Aborted."
		case "$store_choice" in
			1) download_game_via_steamcmd; return ;;
			2) download_game_via_gogdl; return ;;
			3|[qQ]|[qQ][uU][iI][tT]) die "Download aborted." ;;
			*) warn "Please enter 1, 2, or 3." ;;
		esac
	done
}

if [ "$DOWNLOAD_MODE" = prompt ]; then
	download_game_interactive
elif [ "$DOWNLOAD_MODE" = steam ]; then
	download_game_via_steamcmd
elif [ "$DOWNLOAD_MODE" = gog ]; then
	download_game_via_gogdl
elif [ -n "$GAME_ARG" ]; then
	scan_explicit_path "$GAME_ARG" fatal
else
	CANDIDATES=()
	if [ -z "$GAME_ID" ] || [ "$GAME_ID" = fnv ]; then
		CANDIDATES+=(
			"/Applications/Fallout New Vegas.app"
			"$HOME/Applications/Fallout New Vegas.app"
			"$HOME/Downloads/Fallout New Vegas.app"
			"$HOME/Downloads/Fallout New Vegas"
			"$HOME/Downloads/Fallout New Vegas Ultimate"
			"$HOME/Downloads/fnv"
			"$HOME/Downloads/app"
			"$HOME/Games/Fallout New Vegas"
			"$HOME/Library/Application Support/Steam/steamapps/common/Fallout New Vegas"
			"$HOME/Steam/steamapps/common/Fallout New Vegas"
			"$HOME/Steam/fnv"
			"$HOME/Documents/Fallout New Vegas"
		)
		shopt -s nullglob
		for steam_dl in "$CACHE_ROOT/steam-download/22380" "$CACHE_ROOT/steam-download/22380-"* \
		                "$CACHE_ROOT/steam-download/22490" "$CACHE_ROOT/steam-download/22490-"*; do
			[ -f "$steam_dl/.steamcmd-complete" ] && CANDIDATES+=("$steam_dl")
		done
		for gog_dl in "$CACHE_ROOT/gog-download/$GOG_FNV_ID" "$CACHE_ROOT/gog-download/$GOG_FNV_ID-"*; do
			if [ -f "$gog_dl/.gogdl-complete" ]; then
				CANDIDATES+=("$gog_dl" "$gog_dl"/*)
			fi
		done
		CANDIDATES+=(
			"$HOME"/Downloads/depots/22380/*
			"$HOME"/depots/22380/*
			"$HOME"/Downloads/depots/22490/*
			"$HOME"/depots/22490/*
		)
		shopt -u nullglob
	fi
	if [ -z "$GAME_ID" ] || [ "$GAME_ID" = fallout3 ]; then
		CANDIDATES+=(
			"/Applications/Fallout 3.app"
			"$HOME/Applications/Fallout 3.app"
			"$HOME/Downloads/Fallout 3.app"
			"$HOME/Downloads/Fallout 3"
			"$HOME/Downloads/fallout 3"
			"$HOME/Downloads/app"
			"$HOME/Downloads/Fallout 3 goty"
			"$HOME/Downloads/Fallout 3 GOTY"
			"$HOME/Games/Fallout 3"
			"$HOME/Games/Fallout 3 GOTY"
			"$HOME/Library/Application Support/Steam/steamapps/common/Fallout 3 goty"
			"$HOME/Library/Application Support/Steam/steamapps/common/Fallout 3"
			"$HOME/Steam/steamapps/common/Fallout 3 goty"
			"$HOME/Documents/Fallout 3"
		)
		shopt -s nullglob
		for steam_dl in "$CACHE_ROOT/steam-download/22370" "$CACHE_ROOT/steam-download/22370-"* \
		                "$CACHE_ROOT/steam-download/22300" "$CACHE_ROOT/steam-download/22300-"*; do
			[ -f "$steam_dl/.steamcmd-complete" ] && CANDIDATES+=("$steam_dl")
		done
		for gog_dl in "$CACHE_ROOT/gog-download/$GOG_FO3_ID" "$CACHE_ROOT/gog-download/$GOG_FO3_ID-"*; do
			if [ -f "$gog_dl/.gogdl-complete" ]; then
				CANDIDATES+=("$gog_dl" "$gog_dl"/*)
			fi
		done
		CANDIDATES+=(
			"$HOME"/Downloads/depots/22370/*
			"$HOME"/depots/22370/*
			"$HOME"/Downloads/depots/22300/*
			"$HOME"/depots/22300/*
		)
		shopt -u nullglob
	fi
	if [ -z "$GAME_ID" ] || [ "$GAME_ID" = skyrim ]; then
		CANDIDATES+=(
			"/Applications/Skyrim.app"
			"$HOME/Applications/Skyrim.app"
			"$HOME/Downloads/Skyrim.app"
			"$HOME/Downloads/Skyrim"
			"$HOME/Games/Skyrim"
			"$HOME/Library/Application Support/Steam/steamapps/common/Skyrim"
			"$HOME/Steam/steamapps/common/Skyrim"
		)
		shopt -s nullglob
		for steam_dl in "$CACHE_ROOT/steam-download/72850" "$CACHE_ROOT/steam-download/72850-"*; do
			[ -f "$steam_dl/.steamcmd-complete" ] && CANDIDATES+=("$steam_dl")
		done
		CANDIDATES+=(
			"$HOME"/Downloads/depots/72850/*
			"$HOME"/depots/72850/*
		)
		shopt -u nullglob
	fi
	for candidate in "${CANDIDATES[@]+"${CANDIDATES[@]}"}"; do
		scan_game_root "$candidate"
	done
	for gog_dir in "$HOME/Downloads" "$HOME/Games" "$HOME/Documents" "$HOME/Desktop"; do
		scan_gog_installers_in_dir "$gog_dir"
	done
fi

if [ ${#MATCHES[@]} -eq 0 ]; then
	if [ ! -t 0 ]; then
		die "Game files or GOG installer not found (Fallout: New Vegas, Fallout 3, or Skyrim 32-bit LE)." \
			"Run interactively to download from Steam or GOG, or pass the path to your GOG setup_*.exe / game folder:" \
			"  ./quick-install.sh --download" \
			"  ./quick-install.sh --download-steam" \
			"  ./quick-install.sh --download-gog" \
			"  ./quick-install.sh ~/Downloads/setup_fallout_3_*.exe" \
			"  ./quick-install.sh ~/Downloads/\"Fallout New Vegas\"" \
			"  ./quick-install.sh \"\$HOME/Library/Application Support/Steam/steamapps/common/Skyrim\""
	fi

	while [ ${#MATCHES[@]} -eq 0 ]; do
		printf '\n%sNo local game files or GOG installers were found.%s\n' "$BOLD" "$RESET"
		printf 'How would you like to provide your copy?\n'
		if [ "$GAME_ID" = skyrim ]; then
			printf '  %s1)%s Download from Steam (via steamcmd — installs steamcmd if needed)\n' "$GOLD" "$RESET"
			printf '  %s2)%s Enter or drag-and-drop a Skyrim folder, TESV.exe, or Skyrim.app\n' "$GOLD" "$RESET"
			printf '  %s3)%s Quit\n' "$GOLD" "$RESET"
			printf '  Select [1-3]: '
			read -r REPLY || die "Aborted."
			case "$REPLY" in
				1)
					download_game_via_steamcmd
					;;
				2)
					printf '  %s?%s Drag and drop folder, .exe, or .app here (or type back): ' "$CYAN" "$RESET"
					read -r USER_PATH || die "Aborted."
					case "$USER_PATH" in
						""|back|BACK|q|Q) continue ;;
					esac
					RESOLVED_INPUT="$(resolve_user_input_path "$USER_PATH")"
					[ -n "$RESOLVED_INPUT" ] && scan_explicit_path "$RESOLVED_INPUT" interactive || true
					;;
				3|[qQ]|[qQ][uU][iI][tT])
					printf '\n  No problem. To download Skyrim from Steam next time, run ./quick-install.sh --download-steam --game skyrim.\n\n'
					exit 0
					;;
				*)
					warn "Please enter 1, 2, or 3."
					;;
			esac
		else
			printf '  %s1)%s Download from Steam (Fallout 3, Fallout: New Vegas, or Skyrim — via steamcmd)\n' "$GOLD" "$RESET"
			printf '  %s2)%s Download from GOG (Fallout 3 GOTY or Fallout: New Vegas — via gogdl)\n' "$GOLD" "$RESET"
			printf '  %s3)%s Enter or drag-and-drop a game folder, executable, or GOG setup_*.exe\n' "$GOLD" "$RESET"
			printf '  %s4)%s Quit\n' "$GOLD" "$RESET"
			printf '  Select [1-4]: '
			read -r REPLY || die "Aborted."
			case "$REPLY" in
				1)
					download_game_via_steamcmd
					;;
				2)
					download_game_via_gogdl
					;;
				3)
					printf '  %s?%s Drag and drop folder, .exe, or .app here (or type back): ' "$CYAN" "$RESET"
					read -r USER_PATH || die "Aborted."
					case "$USER_PATH" in
						""|back|BACK|q|Q) continue ;;
					esac
					RESOLVED_INPUT="$(resolve_user_input_path "$USER_PATH")"
					[ -n "$RESOLVED_INPUT" ] && scan_explicit_path "$RESOLVED_INPUT" interactive || true
					;;
				4|[qQ]|[qQ][uU][iI][tT])
					printf '\n  No problem. To use an offline GOG installer, put setup_fallout_*.exe and its .bin parts in ~/Downloads/ and re-run.\n'
					printf '  To download directly from Steam or GOG next time, run ./quick-install.sh --download.\n\n'
					exit 0
					;;
				*)
					warn "Please enter 1, 2, 3, or 4."
					;;
			esac
		fi
	done
fi

if [ ${#MATCHES[@]} -eq 1 ]; then
	RESOLVED="${MATCHES[0]}"
else
	OPTIONS=()
	for match in "${MATCHES[@]}"; do
		match_game="${match%%|*}"
		match_rest="${match#*|}"
		match_kind="${match_rest%%|*}"
		match_path="${match_rest#*|}"
		if [ "$match_kind" = gog_installer ]; then
			OPTIONS+=("$(game_display_name "$match_game") (GOG installer) — $match_path")
		else
			OPTIONS+=("$(game_display_name "$match_game") ($(game_channel "$match_path")) — $match_path")
		fi
	done
	if [ -t 0 ]; then
		printf '\n%sMultiple game installations found:%s\n' "$BOLD" "$RESET"
		menu_index=1
		for option in "${OPTIONS[@]}"; do
			printf '  %s%d)%s %s\n' "$GOLD" "$menu_index" "$RESET" "$option"
			menu_index=$((menu_index + 1))
		done
		printf '  Select the game to build [1-%d]: ' "${#OPTIONS[@]}"
		read -r REPLY
		case "$REPLY" in
			''|*[!0-9]*) die "Invalid selection: '$REPLY'." ;;
		esac
		if [ "$REPLY" -lt 1 ] || [ "$REPLY" -gt "${#OPTIONS[@]}" ]; then
			die "Selection out of range: $REPLY"
		fi
		RESOLVED="${MATCHES[$((REPLY - 1))]}"
	else
		die "Multiple game installations found; pass the folder/installer to use or --game fnv|fallout3|skyrim." "${OPTIONS[@]}"
	fi
fi

GAME_ID="${RESOLVED%%|*}"
RESOLVED_REST="${RESOLVED#*|}"
MATCH_KIND="${RESOLVED_REST%%|*}"
ASSET_SRC="${RESOLVED_REST#*|}"
SOURCE_IS_TMP_EXTRACT=no
GOG_INSTALLER_PATH=""

if [ "$MATCH_KIND" = gog_installer ]; then
	GOG_INSTALLER_PATH="$ASSET_SRC"
	ok "Found GOG installer: $GOG_INSTALLER_PATH"
	if ! command -v innoextract >/dev/null 2>&1; then
		require_brew "to install innoextract for GOG installers"
		brew_install_quiet "Installing innoextract via Homebrew" innoextract \
			|| die "Failed to install innoextract via Homebrew."
		BREW_INSTALLED+=(innoextract)
		remember_brew_packages innoextract
	fi
	GOG_OUT="$TMP/gog-extract"
	GOG_LOG="$TMP/innoextract.log"
	mkdir -p "$GOG_OUT"
	if ! run_task "Extracting GOG installer (skipping Windows redistributables)" \
		bash -c 'innoextract --exclude-temp --silent --progress=0 -d "$1" "$2" >"$3" 2>&1' _ \
		"$GOG_OUT" "$GOG_INSTALLER_PATH" "$GOG_LOG"; then
		cat "$GOG_LOG" >&2 || true
		die "innoextract failed to extract: $GOG_INSTALLER_PATH" \
			"Make sure all .bin parts of the GOG installer sit in the same folder as the .exe."
	fi
	ASSET_SRC=""
	for cand in "$GOG_OUT/app" "$GOG_OUT"; do
		if { [ "$GAME_ID" = auto ] || [ "$GAME_ID" = fallout3 ]; } && [ -f "$cand/Fallout3.exe" ] && [ -f "$cand/Data/Fallout3.esm" ]; then
			GAME_ID="fallout3"
			ASSET_SRC="$cand"
			break
		fi
		if { [ "$GAME_ID" = auto ] || [ "$GAME_ID" = fnv ]; } && [ -f "$cand/FalloutNV.exe" ] && [ -f "$cand/Data/FalloutNV.esm" ]; then
			GAME_ID="fnv"
			ASSET_SRC="$cand"
			break
		fi
	done
	[ -n "$ASSET_SRC" ] || die "Extracted GOG installer did not contain Fallout3.exe or FalloutNV.exe + Data/."
	SOURCE_IS_TMP_EXTRACT=yes
fi

if [ "$GAME_ID" = fallout3 ]; then
	GAME_LABEL="Fallout 3"
	APP_NAME="Fallout 3"
	VOLNAME="Fallout 3"
	GAME_EXE_NAME="Fallout3.exe"
	GAME_SUPPORT_DIR="Fallout3"
	GHIDRA_PROJ_NAME="f3"
elif [ "$GAME_ID" = skyrim ]; then
	GAME_LABEL="The Elder Scrolls V: Skyrim"
	APP_NAME="Skyrim"
	VOLNAME="Skyrim"
	GAME_EXE_NAME="TESV.exe"
	GAME_SUPPORT_DIR="Skyrim"
	GHIDRA_PROJ_NAME="skyrim"
else
	GAME_LABEL="Fallout: New Vegas"
	APP_NAME="Fallout New Vegas"
	VOLNAME="Fallout New Vegas"
	GAME_EXE_NAME="FalloutNV.exe"
	GAME_SUPPORT_DIR="FalloutNV"
	GHIDRA_PROJ_NAME="fnv"
fi

ok "Found $GAME_LABEL game files at: $ASSET_SRC"

EXE_PATH="$ASSET_SRC/$GAME_EXE_NAME"

has_bind_section() {
	python3 - "$1" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
pe = struct.unpack_from('<I', d, 0x3c)[0]
n = struct.unpack_from('<H', d, pe + 6)[0]
o = struct.unpack_from('<H', d, pe + 20)[0]
secs = [d[pe + 24 + o + 40 * i : pe + 24 + o + 40 * i + 8].rstrip(b'\x00') for i in range(n)]
print('yes' if b'.bind' in secs else 'no')
PY
}

is_supported_skyrim_sha() {
	[ "$1" = "$SKYRIM_STEAM_UNPACKED_CLI_SHA256" ] || [ "$1" = "$SKYRIM_STEAM_UNPACKED_GUI_SHA256" ]
}

unpack_steam_drm() {
	if ! command -v mono >/dev/null 2>&1; then
		require_brew "to install Mono for Steamless"
		brew_install_quiet "Installing Mono runtime via Homebrew" mono \
			|| die "Failed to install Mono via Homebrew."
		BREW_INSTALLED+=(mono)
		remember_brew_packages mono
	fi
	local mono_bin
	mono_bin="$(command -v mono || true)"
	[ -n "$mono_bin" ] || die "Mono runtime not found after installation."

	local steamless_dir="$CACHE_ROOT/steamless/$STEAMLESS_VERSION"
	if [ ! -f "$steamless_dir/Steamless.CLI.exe" ] || [ ! -f "$steamless_dir/Plugins/Steamless.API.dll" ]; then
		local zip_path="$TMP/steamless.zip"
		rm -rf "$steamless_dir"
		mkdir -p "$steamless_dir"
		run_logged_task "Downloading official Steamless ($STEAMLESS_VERSION)" "$TMP/download.log" \
			curl -fsSL "$STEAMLESS_URL" -o "$zip_path" \
			|| die "Failed to download Steamless ($STEAMLESS_VERSION)."
		local zip_sha
		zip_sha="$(shasum -a 256 "$zip_path" | awk '{print $1}')"
		if [ "$zip_sha" != "$STEAMLESS_ZIP_SHA256" ]; then
			rm -rf "$steamless_dir"
			die "Downloaded Steamless archive SHA-256 mismatch." \
				"Expected: $STEAMLESS_ZIP_SHA256" \
				"Got:      $zip_sha"
		fi
		run_logged_task "Extracting Steamless ($STEAMLESS_VERSION)" "$TMP/unzip.log" \
			unzip -qo "$zip_path" -d "$steamless_dir" \
			|| die "Failed to extract Steamless ($STEAMLESS_VERSION)."
		[ -f "$steamless_dir/Steamless.CLI.exe" ] || die "Steamless.CLI.exe missing after extraction."
	else
		ok "Using cached Steamless ($STEAMLESS_VERSION)"
	fi

	if [ ! -f "${EXE_PATH}.og" ]; then
		cp -p "$EXE_PATH" "${EXE_PATH}.og"
		ok "Backed up original executable to $(basename "${EXE_PATH}.og")"
	fi

	local work_dir="$TMP/steamless-work"
	local work_exe="$work_dir/$GAME_EXE_NAME"
	local log_file="$TMP/steamless.log"
	mkdir -p "$work_dir"
	cp "$EXE_PATH" "$work_exe"

	if ! run_task "Removing SteamStub DRM with Steamless CLI (Mono)" \
		bash -c 'MONO_PATH="$1" "$2" "$3" "$4" >"$5" 2>&1' _ \
		"$steamless_dir/Plugins" "$mono_bin" "$steamless_dir/Steamless.CLI.exe" "$work_exe" "$log_file"; then
		cat "$log_file" >&2 || true
		die "Steamless failed to unpack $GAME_EXE_NAME."
	fi

	local unpacked="$work_exe.unpacked.exe"
	[ -f "$unpacked" ] || { cat "$log_file" >&2 || true; die "Steamless did not produce an unpacked executable."; }
	[ "$(has_bind_section "$unpacked")" = no ] || die "Unpacked $GAME_EXE_NAME still contains a .bind section."

	mv "$unpacked" "$EXE_PATH"
	chmod +x "$EXE_PATH"
}

HAS_BIND="$(has_bind_section "$EXE_PATH")"
ACTUAL_SHA="$(shasum -a 256 "$EXE_PATH" | awk '{print $1}')"

if [ "$GAME_ID" = fallout3 ]; then
	if [ "$ACTUAL_SHA" = "$F3_GOG_EXE_SHA256" ] && [ "$HAS_BIND" = no ]; then
		ok "Verified DRM-free GOG Fallout3.exe (SHA-256 matches precomputed symbols)"
	elif [ "$ACTUAL_SHA" = "$F3_STEAM_EXE_SHA256" ] && [ "$HAS_BIND" = no ]; then
		ok "Verified DRM-free Steam Fallout3.exe 1.7.0.4 ($ACTUAL_SHA)"
	elif [ "$HAS_BIND" = yes ]; then
		warn "SteamStub DRM detected in Fallout3.exe (.bind section present, $ACTUAL_SHA)"
		printf '    The static recompiler requires an unencrypted executable.\n'
		printf '    This script can download official Steamless (%s) + Mono (if missing),\n' "$STEAMLESS_VERSION"
		printf '    back up %s to %s.og, and strip the DRM automatically.\n' "$GAME_EXE_NAME" "$GAME_EXE_NAME"
		if [ "$UNPACK_DRM" != yes ]; then
			if [ -t 0 ]; then
				printf '  %s?%s Remove SteamStub DRM now? [y/N] ' "$CYAN" "$RESET"
				read -r REPLY
				case "$REPLY" in
					[yY]|[yY][eE][sS]|[sS]) UNPACK_DRM=yes ;;
					*) die "Aborted. Cannot statically recompile a SteamStub-packed executable." ;;
				esac
			else
				die "Non-interactive session: re-run interactively or pass --unpack-drm to strip SteamStub DRM."
			fi
		fi
		unpack_steam_drm
		ACTUAL_SHA="$(shasum -a 256 "$EXE_PATH" | awk '{print $1}')"
		ok "Removed SteamStub DRM from $GAME_EXE_NAME ($ACTUAL_SHA)"
	else
		warn "$GAME_EXE_NAME SHA-256 differs from supported GOG/Steam builds ($ACTUAL_SHA)"
	fi
elif [ "$GAME_ID" = skyrim ]; then
	if is_supported_skyrim_sha "$ACTUAL_SHA" && [ "$HAS_BIND" = no ]; then
		ok "Verified unpacked Steam TESV.exe (SHA-256 matches precomputed symbols)"
	elif [ "$ACTUAL_SHA" = "$SKYRIM_STEAM_OG_EXE_SHA256" ] || [ "$HAS_BIND" = yes ]; then
		if [ "$ACTUAL_SHA" = "$SKYRIM_STEAM_OG_EXE_SHA256" ]; then
			ok "Detected original Steam TESV.exe 1.9.32.0.8 (SteamStub DRM)"
		else
			warn "SteamStub DRM detected in TESV.exe (.bind section present, $ACTUAL_SHA)"
		fi
		unpack_steam_drm
		ACTUAL_SHA="$(shasum -a 256 "$EXE_PATH" | awk '{print $1}')"
		if is_supported_skyrim_sha "$ACTUAL_SHA"; then
			ok "Removed SteamStub DRM (SHA-256 matches precomputed Skyrim symbols)"
		else
			warn "Removed SteamStub DRM, but unpacked SHA-256 differs ($ACTUAL_SHA)"
		fi
	else
		warn "$GAME_EXE_NAME SHA-256 differs from supported Skyrim 1.9.32.0.8 build ($ACTUAL_SHA)"
	fi
elif [ "$ACTUAL_SHA" = "$GOG_EXE_SHA256" ] && [ "$HAS_BIND" = no ]; then
	ok "Verified DRM-free GOG FalloutNV.exe (SHA-256 matches precomputed symbols)"
elif [ "$ACTUAL_SHA" = "$STEAM_UNPACKED_EXE_SHA256" ] && [ "$HAS_BIND" = no ]; then
	ok "Verified unpacked Steam FalloutNV.exe (SHA-256 matches precomputed Steam symbols)"
elif [ "$ACTUAL_SHA" = "$STEAM_OG_EXE_SHA256" ] || [ "$HAS_BIND" = yes ]; then
	if [ "$ACTUAL_SHA" = "$STEAM_OG_EXE_SHA256" ]; then
		warn "Detected Steam FalloutNV.exe with SteamStub DRM ($ACTUAL_SHA)"
	else
		warn "SteamStub DRM detected in FalloutNV.exe (.bind section present, $ACTUAL_SHA)"
	fi
	printf '    The static recompiler requires an unencrypted executable.\n'
	printf '    This script can download official Steamless (%s) + Mono (if missing),\n' "$STEAMLESS_VERSION"
	printf '    back up FalloutNV.exe to FalloutNV.exe.og, and strip the DRM automatically.\n'

	if [ "$UNPACK_DRM" != yes ]; then
		if [ -t 0 ]; then
			printf '  %s?%s Remove SteamStub DRM now? [y/N] ' "$CYAN" "$RESET"
			read -r REPLY
			case "$REPLY" in
				[yY]|[yY][eE][sS]|[sS]) UNPACK_DRM=yes ;;
				*) die "Aborted. Cannot statically recompile a SteamStub-packed executable." ;;
			esac
		else
			die "Non-interactive session: re-run interactively or pass --unpack-drm to strip SteamStub DRM."
		fi
	fi

	unpack_steam_drm
	ACTUAL_SHA="$(shasum -a 256 "$EXE_PATH" | awk '{print $1}')"
	if [ "$ACTUAL_SHA" = "$STEAM_UNPACKED_EXE_SHA256" ]; then
		ok "Removed SteamStub DRM (SHA-256 matches precomputed Steam symbols)"
	else
		warn "Removed SteamStub DRM, but unpacked SHA-256 differs ($ACTUAL_SHA)"
	fi
else
	warn "$GAME_EXE_NAME SHA-256 differs from supported GOG/Steam builds ($ACTUAL_SHA)"
fi

# ---------------------------------------------------------------------------
# Step 2: Check and install build tools (Homebrew)
# ---------------------------------------------------------------------------
step "Checking Homebrew tools (ghidra, unicorn, cmake, ffmpeg)"

require_brew "to install build tools (ghidra, unicorn, cmake, ffmpeg)"

MISSING_BREW=()
for pkg in ghidra unicorn cmake ffmpeg; do
	if ! brew list "$pkg" >/dev/null 2>&1 && ! command -v "$pkg" >/dev/null 2>&1; then
		MISSING_BREW+=("$pkg")
	fi
done

if [ ${#MISSING_BREW[@]} -gt 0 ]; then
	brew_install_quiet "Installing via Homebrew: ${MISSING_BREW[*]}" "${MISSING_BREW[@]}" \
		|| die "Failed to install required Homebrew packages: ${MISSING_BREW[*]}"
	BREW_INSTALLED+=("${MISSING_BREW[@]}")
	remember_brew_packages "${MISSING_BREW[@]}"
fi

HEADLESS="$(brew --prefix ghidra)/libexec/support/analyzeHeadless"
[ -x "$HEADLESS" ] || die "Ghidra analyzeHeadless not found at $HEADLESS"
UNICORN_PREFIX="$(brew --prefix unicorn)"
[ -f "$UNICORN_PREFIX/lib/libunicorn.a" ] || die "libunicorn.a not found at $UNICORN_PREFIX"

# Ghidra needs a JDK it can find by itself; hand it one explicitly (see ghidra_jdk_home).
GHIDRA_JAVA_HOME="$(ghidra_jdk_home || true)"
if [ -z "$GHIDRA_JAVA_HOME" ] && [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
	GHIDRA_JAVA_HOME="$JAVA_HOME"
fi
if [ -z "$GHIDRA_JAVA_HOME" ] && [ -x /usr/libexec/java_home ]; then
	GHIDRA_JAVA_HOME="$(/usr/libexec/java_home 2>/dev/null || true)"
fi
[ -n "$GHIDRA_JAVA_HOME" ] && [ -x "$GHIDRA_JAVA_HOME/bin/java" ] || die \
	"Ghidra could not find a Java Development Kit (JDK)." \
	"Homebrew installs one as a ghidra dependency; try: brew reinstall ghidra" \
	"Or install a JDK (for example: brew install openjdk), then re-run this script."
export JAVA_HOME="$GHIDRA_JAVA_HOME"
export PATH="$JAVA_HOME/bin:$PATH"
ok "Ghidra JDK: $JAVA_HOME"
ok "Toolchain ready (Ghidra + Unicorn + CMake + FFmpeg)"

# ---------------------------------------------------------------------------
# Step 3: Build Ogg/Vorbis native codecs (cached)
# ---------------------------------------------------------------------------
step "Preparing native Ogg/Vorbis audio codecs"

CODECS_DIR="$CACHE_ROOT/codecs"
CODEC_PREFIX="$CODECS_DIR/prefix"
if [ -f "$CODEC_PREFIX/codec-manifest.json" ] && \
   python3 -c "import sys; sys.path.insert(0, '$SCRIPT_DIR/tools'); from native_codecs import validate; validate('$CODEC_PREFIX', 'macos')" >/dev/null 2>&1; then
	ok "Using cached macOS Ogg/Vorbis codecs"
else
	CODECS_LOG="$TMP/codecs.log"
	if ! run_task "Building pinned Ogg/Vorbis static libraries" \
		bash -c 'python3 "$1" macos --out "$2" >"$3" 2>&1' _ \
		"$SCRIPT_DIR/tools/build_codecs.py" "$CODECS_DIR" "$CODECS_LOG"; then
		cat "$CODECS_LOG" >&2 || true
		die "Building Ogg/Vorbis codecs failed."
	fi
fi

# ---------------------------------------------------------------------------
# Step 4: Translate executable -> C (Ghidra + emit.py, cached)
# ---------------------------------------------------------------------------
step "Translating $GAME_EXE_NAME to native ARM64 C (cached per executable)"

SHORT_SHA="${ACTUAL_SHA:0:12}"
TRANS_WORK="$CACHE_ROOT/translate-$SHORT_SHA"
GEN_DIR="$TRANS_WORK/generated"
mkdir -p "$TRANS_WORK"

if [ -f "$GEN_DIR/table.c" ] && [ -f "$GEN_DIR/stubs.c" ] && ls "$GEN_DIR"/tu_*.c >/dev/null 2>&1; then
	ok "Using cached translated C sources ($GEN_DIR)"
else
	rm -rf "$GEN_DIR"
	# Isolate Ghidra's user settings/OSGi compiled-bundle cache per translation run so
	# cached .class files compiled under a different JDK cannot trigger UnsupportedClassVersionError,
	# and LaunchSupport does not overwrite the user's own ~/Library/ghidra settings.
	GHIDRA_PROJ="$TRANS_WORK/ghidra"
	GHIDRA_CONFIG="$TRANS_WORK/ghidra-config"
	GHIDRA_LOG="$TRANS_WORK/ghidra.log"
	PASS_OUT="$TRANS_WORK/passes"
	JSONL="$TRANS_WORK/all.jsonl"
	SCRIPTS="$SCRIPT_DIR/tools/ghidra"
	EXE_NAME="$(basename "$EXE_PATH")"

	rm -rf "$GHIDRA_CONFIG"
	mkdir -p "$GHIDRA_PROJ" "$GHIDRA_CONFIG" "$PASS_OUT"
	SYM_DIR=""
	if [ "$GAME_ID" = fallout3 ]; then
		if [ "$ACTUAL_SHA" = "$F3_GOG_EXE_SHA256" ]; then
			SYM_DIR="$SCRIPT_DIR/symbols/fallout3"
		elif [ "$ACTUAL_SHA" = "$F3_STEAM_EXE_SHA256" ]; then
			SYM_DIR="$SCRIPT_DIR/symbols/fallout3-steam"
		fi
	elif [ "$GAME_ID" = skyrim ]; then
		if is_supported_skyrim_sha "$ACTUAL_SHA"; then
			SYM_DIR="$SCRIPT_DIR/symbols/skyrim"
		fi
	else
		if [ "$ACTUAL_SHA" = "$GOG_EXE_SHA256" ]; then
			SYM_DIR="$SCRIPT_DIR/symbols/fnv"
		elif [ "$ACTUAL_SHA" = "$STEAM_UNPACKED_EXE_SHA256" ]; then
			SYM_DIR="$SCRIPT_DIR/symbols/fnv-steam"
		fi
	fi
	if [ -n "$SYM_DIR" ] && [ -f "$SYM_DIR/functions.tsv" ]; then
		ok "Using precomputed function & jump-table metadata ($SYM_DIR)"
		rm -rf "$GHIDRA_PROJ/$GHIDRA_PROJ_NAME.gpr" "$GHIDRA_PROJ/$GHIDRA_PROJ_NAME.rep"
		run_logged_task "Disassembling & exporting P-code (~1 min, no Ghidra auto-analysis)" "$TRANS_WORK/ghidra-console.log" \
			env XDG_CONFIG_HOME="$GHIDRA_CONFIG" GHIDRA_HEADLESS_MAXMEM=4G "$HEADLESS" "$GHIDRA_PROJ" "$GHIDRA_PROJ_NAME" \
			-import "$EXE_PATH" -noanalysis \
			-scriptPath "$SCRIPTS" \
			-postScript ApplyMetadataAndDump.java "$SYM_DIR" "$JSONL" \
			-log "$GHIDRA_LOG" -scriptlog "$TRANS_WORK/script.log" \
			|| die "Ghidra P-code export failed (see $TRANS_WORK/ghidra-console.log)"

		run_logged_task "Emitting C translation units (~3 min)" "$TRANS_WORK/emit.log" \
			python3 "$SCRIPT_DIR/tools/translate/emit.py" "$JSONL" "$GEN_DIR" \
			--extra "$SYM_DIR/extra_entries.json" \
			|| die "C translation failed (see $TRANS_WORK/emit.log)"
	else
		if [ -z "${GHIDRA_HEADLESS_MAXMEM:-}" ]; then
			MEM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
			if [ "$MEM_GB" -ge 24 ]; then
				export GHIDRA_HEADLESS_MAXMEM=16G
			elif [ "$MEM_GB" -ge 16 ]; then
				export GHIDRA_HEADLESS_MAXMEM=10G
			else
				export GHIDRA_HEADLESS_MAXMEM=5G
			fi
		fi

		if [ ! -f "$GHIDRA_PROJ/ghidra.done" ]; then
			rm -rf "$GHIDRA_PROJ/$GHIDRA_PROJ_NAME.gpr" "$GHIDRA_PROJ/$GHIDRA_PROJ_NAME.rep"
			printf '  %sRunning Ghidra import & auto-analysis (heap %s, first run only)...%s\n' "$DIM" "$GHIDRA_HEADLESS_MAXMEM" "$RESET"
			run_logged_task "Ghidra import & analysis ($EXE_NAME)" "$TRANS_WORK/ghidra-console.log" \
				env XDG_CONFIG_HOME="$GHIDRA_CONFIG" "$HEADLESS" "$GHIDRA_PROJ" "$GHIDRA_PROJ_NAME" -import "$EXE_PATH" \
				-log "$GHIDRA_LOG" -scriptlog "$TRANS_WORK/script.log" \
				|| die "Ghidra import & analysis failed (see $TRANS_WORK/ghidra-console.log)"
			touch "$GHIDRA_PROJ/ghidra.done"
		else
			ok "Reusing existing Ghidra project in $GHIDRA_PROJ"
		fi

		run_logged_task "Repairing functions, jump tables & CRT tables (pass 1/2)" "$TRANS_WORK/ghidra-console.log" \
			env XDG_CONFIG_HOME="$GHIDRA_CONFIG" "$HEADLESS" "$GHIDRA_PROJ" "$GHIDRA_PROJ_NAME" -process "$EXE_NAME" -noanalysis \
			-scriptPath "$SCRIPTS" \
			-postScript FixNoReturn.java \
			-postScript ResolveJumpTables.java \
			-postScript FixEntries.java "$PASS_OUT" \
			-log "$GHIDRA_LOG" \
			|| die "Ghidra pass 1/2 failed (see $TRANS_WORK/ghidra-console.log)"

		if ! run_logged_task "Repairing functions, CRT operation tables & exporting P-code (pass 2/2)" "$TRANS_WORK/ghidra-console.log" \
			env XDG_CONFIG_HOME="$GHIDRA_CONFIG" "$HEADLESS" "$GHIDRA_PROJ" "$GHIDRA_PROJ_NAME" -process "$EXE_NAME" -noanalysis \
			-scriptPath "$SCRIPTS" \
			-postScript FixNoReturn.java \
			-postScript ResolveJumpTables.java \
			-postScript ResolveCrtOperationTables.java apply "$PASS_OUT/crt-report.json" "$PASS_OUT/crt-extra.json" \
			-postScript FixEntries.java "$PASS_OUT" \
			-postScript DumpPcode.java "$JSONL" all \
			-log "$GHIDRA_LOG"; then
			warn "ResolveCrtOperationTables did not apply; retrying pass 2 without CRT table recovery"
			rm -f "$PASS_OUT/crt-report.json" "$PASS_OUT/crt-extra.json"
			run_logged_task "Repairing functions & exporting P-code (pass 2/2 fallback)" "$TRANS_WORK/ghidra-console.log" \
				env XDG_CONFIG_HOME="$GHIDRA_CONFIG" "$HEADLESS" "$GHIDRA_PROJ" "$GHIDRA_PROJ_NAME" -process "$EXE_NAME" -noanalysis \
				-scriptPath "$SCRIPTS" \
				-postScript FixNoReturn.java \
				-postScript ResolveJumpTables.java \
				-postScript FixEntries.java "$PASS_OUT" \
				-postScript DumpPcode.java "$JSONL" all \
				-log "$GHIDRA_LOG" \
				|| die "Ghidra pass 2/2 failed (see $TRANS_WORK/ghidra-console.log)"
		fi

		python3 - "$PASS_OUT/extra_entries.json" "$PASS_OUT/crt-extra.json" "$PASS_OUT/merged-extra-entries.json" <<'PY'
import json, sys
merged = {}
for path in sys.argv[1:3]:
    try:
        data = json.load(open(path))
    except FileNotFoundError:
        continue
    for k, vals in data.items():
        merged.setdefault(k, [])
        for v in vals:
            if v not in merged[k]:
                merged[k].append(v)
json.dump(merged, open(sys.argv[3], 'w'))
PY

		run_logged_task "Emitting C translation units" "$TRANS_WORK/emit.log" \
			python3 "$SCRIPT_DIR/tools/translate/emit.py" "$JSONL" "$GEN_DIR" \
			--extra "$PASS_OUT/merged-extra-entries.json" \
			|| die "C translation failed (see $TRANS_WORK/emit.log)"
	fi

	if [ "$KEEP_GHIDRA" = no ]; then
		rm -rf "$GHIDRA_PROJ" "$GHIDRA_CONFIG" "$JSONL" "$JSONL.regs.json" "$JSONL.userops.json"
		ok "Cleaned temporary Ghidra project & P-code dump to save disk space"
	fi
fi

# ---------------------------------------------------------------------------
# Step 5: Compile & link app bundle
# ---------------------------------------------------------------------------
step "Compiling native ARM64 Metal engine & game code"

OBJ_CACHE="$CACHE_ROOT/objects-$GAME_ID-$SHORT_SHA"
BUILD_OUT="$TMP/build"
mkdir -p "$BUILD_OUT"

STEAM_BUILD_ARGS=()
STEAM_DEFAULT_APPID="22380"
WANT_STEAM=no
STEAM_ELIGIBLE=no
if [ "$GAME_ID" = fallout3 ]; then
	STEAM_DEFAULT_APPID="22370"
	[ "$WITH_STEAM" = yes ] && [ "$NO_STEAM" != yes ] && WANT_STEAM=yes
	if [ "$WANT_STEAM" = yes ] && [ "$ACTUAL_SHA" != "$F3_GOG_EXE_SHA256" ] && { [ "$ACTUAL_SHA" = "$F3_STEAM_EXE_SHA256" ] || [ -f "$ASSET_SRC/steam_api.dll" ]; }; then
		STEAM_ELIGIBLE=yes
	fi
elif [ "$GAME_ID" = skyrim ]; then
	STEAM_DEFAULT_APPID="72850"
	[ "$NO_STEAM" != yes ] && WANT_STEAM=yes
	if [ "$WANT_STEAM" = yes ] && { is_supported_skyrim_sha "$ACTUAL_SHA" || [ -f "$ASSET_SRC/steam_api.dll" ]; }; then
		STEAM_ELIGIBLE=yes
	fi
else
	[ "$NO_STEAM" != yes ] && WANT_STEAM=yes
	if [ "$WANT_STEAM" = yes ] && [ "$ACTUAL_SHA" != "$GOG_EXE_SHA256" ] && { [ "$ACTUAL_SHA" = "$STEAM_UNPACKED_EXE_SHA256" ] || [ -f "$ASSET_SRC/steam_api.dll" ]; }; then
		STEAM_ELIGIBLE=yes
	fi
fi
if [ "$STEAM_ELIGIBLE" = yes ]; then
	SW_DIR="$CACHE_ROOT/steamworks/20.1.0"
	SW_DYLIB="$SW_DIR/libsteam_api.dylib"
	if [ ! -f "$SW_DYLIB" ]; then
		SW_PKG="$TMP/Steamworks.NET_20.1.0.unitypackage"
		SW_EXTRACT="$TMP/steamworks-extract"
		if run_logged_task "Downloading Steamworks.NET 20.1.0 (Valve libsteam_api.dylib)" "$TMP/download.log" \
			curl -fsSL --retry 3 "$STEAMWORKS_URL" -o "$SW_PKG"; then
			SW_GOT="$(shasum -a 256 "$SW_PKG" | awk '{print $1}')"
			if [ "$SW_GOT" = "$STEAMWORKS_SHA256" ]; then
				mkdir -p "$SW_DIR" "$SW_EXTRACT"
				tar -xzf "$SW_PKG" -C "$SW_EXTRACT"
				for d in "$SW_EXTRACT"/*; do
					[ -f "$d/asset" ] && [ -f "$d/pathname" ] || continue
					p="$(head -n 1 "$d/pathname")"
					case "$p" in
						*/Plugins/steam_api.bundle/Contents/MacOS/libsteam_api.dylib)
							cp "$d/asset" "$SW_DYLIB"
							chmod 755 "$SW_DYLIB"
							break
							;;
					esac
				done
			else
				warn "Steamworks.NET SHA-256 mismatch ($SW_GOT); building offline without Steam achievements"
			fi
		else
			warn "Failed to download Steamworks.NET; building offline without Steam achievements"
		fi
	else
		ok "Using cached Valve libsteam_api.dylib"
	fi
	if [ -f "$SW_DYLIB" ]; then
		STEAM_APPID="$STEAM_DEFAULT_APPID"
		if [ "$GAME_ID" = fnv ]; then
			if [[ "$ASSET_SRC" == *"/22490/"* ]] || [[ "$ASSET_SRC" == *"/22490" ]] \
				|| [ -f "$ASSET_SRC/../../appmanifest_22490.acf" ] \
				|| [ -f "$ASSET_SRC/steamapps/appmanifest_22490.acf" ]; then
				STEAM_APPID="22490"
			fi
		elif [ "$GAME_ID" = fallout3 ]; then
			if [[ "$ASSET_SRC" == *"/22300/"* ]] || [[ "$ASSET_SRC" == *"/22300" ]] \
				|| { [ ! -f "$ASSET_SRC/../../appmanifest_22370.acf" ] && [ ! -f "$ASSET_SRC/steamapps/appmanifest_22370.acf" ] \
					&& { [ -f "$ASSET_SRC/../../appmanifest_22300.acf" ] || [ -f "$ASSET_SRC/steamapps/appmanifest_22300.acf" ]; }; }; then
				STEAM_APPID="22300"
			fi
		fi
		STEAM_BUILD_ARGS=(--steam-api-dylib "$SW_DYLIB" --steam-appid "$STEAM_APPID")
		ok "Bundling Steam launcher, Overlay hook & libsteam_api.dylib (AppID $STEAM_APPID)"
	fi
elif [ "$GAME_ID" = fallout3 ] && [ "$NO_STEAM" != yes ] && [ "$ACTUAL_SHA" = "$F3_STEAM_EXE_SHA256" ]; then
	ok "Building Fallout 3 standalone offline (default; pass --with-steam for Steam Overlay)"
fi

printf '  %sCompiling translation units with Apple Clang (cached incrementally)...%s\n' "$DIM" "$RESET"
python3 "$SCRIPT_DIR/tools/build.py" game \
	--game "$GAME_ID" \
	--generated "$GEN_DIR" \
	--exe "$EXE_PATH" \
	--codec-prefix "$CODEC_PREFIX" \
	--unicorn-prefix "$UNICORN_PREFIX" \
	--cache "$OBJ_CACHE" \
	--out "$BUILD_OUT" \
	--app-name "$APP_NAME" \
	${STEAM_BUILD_ARGS[@]+"${STEAM_BUILD_ARGS[@]}"} \
	--no-call-trace

APP="$BUILD_OUT/$APP_NAME.app"
[ -d "$APP" ] || die "Expected built bundle not found at $APP"
ok "Compiled $APP_NAME.app"

# ---------------------------------------------------------------------------
# Step 6: Move game files into bundle & convert Bink movies
# ---------------------------------------------------------------------------
step "Moving game files into app bundle & converting intro/cutscene movies"

GDATA="$APP/Contents/Resources/GameData"
mkdir -p "$GDATA"

# If ASSET_SRC is already inside an existing .app's GameData, check if same/different
move_game_files() {
	mv "$ASSET_SRC/$GAME_EXE_NAME" "$GDATA/"
	mv "$ASSET_SRC/Data" "$GDATA/"
	for ini in "$ASSET_SRC"/*.ini; do
		[ -e "$ini" ] && mv "$ini" "$GDATA/"
	done
	[ -d "$ASSET_SRC/Skyrim" ] && mv "$ASSET_SRC/Skyrim" "$GDATA/" || true
	[ -d "$ASSET_SRC/NativeMedia" ] && mv "$ASSET_SRC/NativeMedia" "$GDATA/" || true
}

if [ "$FANCY" = yes ]; then
	MOVE_TOTAL=$(du_bytes "$ASSET_SRC")
	move_game_files &
	watch_bytes $! "Moving game files" "$MOVE_TOTAL" du_bytes "$GDATA" \
		|| die "Moving game files failed"
else
	echo "==> Moving game files into $GDATA..."
	move_game_files
fi

# Convert Data/Video/*.bik -> NativeMedia/*.mp4 for native AVFoundation playback
VIDEO_DIR=""
for cand in "$GDATA/Data/Video" "$GDATA/data/video" "$GDATA/Data/video"; do
	[ -d "$cand" ] && { VIDEO_DIR="$cand"; break; }
done

if [ -n "$VIDEO_DIR" ]; then
	mkdir -p "$GDATA/NativeMedia"
	shopt -s nullglob nocaseglob
	BIKS=("$VIDEO_DIR"/*.bik)
	shopt -u nullglob nocaseglob
	if [ ${#BIKS[@]} -gt 0 ]; then
		convert_movies() {
			for bik in "${BIKS[@]}"; do
				base="$(basename "$bik")"
				stem="${base%.*}"
				out_mp4="$GDATA/NativeMedia/$stem.mp4"
				if [ ! -f "$out_mp4" ]; then
					ffmpeg -y -v error -i "$bik" -c:v libx264 -pix_fmt yuv420p -c:a aac -movflags +faststart "$out_mp4" </dev/null || true
				fi
			done
		}
		run_logged_task "Converting ${#BIKS[@]} Bink movie(s) to MP4 for AVFoundation" "$TMP/ffmpeg.log" convert_movies || true
	fi
fi

mkdir -p \
	"$HOME/Library/Application Support/$GAME_SUPPORT_DIR/UserDocuments" \
	"$HOME/Library/Application Support/$GAME_SUPPORT_DIR/LocalAppData/$GAME_SUPPORT_DIR" \
	"$HOME/Library/Logs/$GAME_SUPPORT_DIR"

# ---------------------------------------------------------------------------
# Step 7: Ad-hoc sign & finalize
# ---------------------------------------------------------------------------
step "Signing app bundle & finalizing"

sign_bundle() {
	local dylib
	find "$APP" -name "._*" -delete 2>/dev/null || true
	xattr -cr "$APP" 2>/dev/null || true
	if [ -d "$APP/Contents/Frameworks" ]; then
		shopt -s nullglob
		for dylib in "$APP/Contents/Frameworks"/*.dylib; do
			chmod 755 "$dylib" 2>/dev/null || true
			codesign --force --sign - "$dylib"
		done
		shopt -u nullglob
	fi
	codesign --force --deep --sign - "$APP"
}
run_logged_task "Ad-hoc signing $APP_NAME.app" "$TMP/codesign.log" sign_bundle || die "Code signing failed"

is_protected_dir() {
	local p="${1%/}"
	case "$p" in
		""|/|/Applications|/Users|"$HOME"|"$HOME/Applications"|"$HOME/Desktop"|"$HOME/Documents"|"$HOME/Downloads"|"$HOME/Games"|"$HOME/Library"|/tmp|/var/tmp)
			return 0 ;;
	esac
	return 1
}

cleanup_source_leftovers() {
	[ "$SOURCE_IS_TMP_EXTRACT" = yes ] && return 0
	local src="${ASSET_SRC%/}"
	[ -d "$src" ] || return 0

	# Never delete an existing .app bundle when rebuilding from it
	case "$src" in
		*/Contents/Resources/GameData) return 0 ;;
	esac

	# Remove matching Steam appmanifest_<appid>.acf if source was a Steam steamapps/common folder
	case "$src" in
		*/steamapps/common/*)
			local steamapps_dir game_folder appids aid acf
			steamapps_dir="$(dirname "$(dirname "$src")")"
			game_folder="$(basename "$src")"
			if [ "$GAME_ID" = fallout3 ]; then
				appids="22370 22300"
			elif [ "$GAME_ID" = skyrim ]; then
				appids="72850"
			else
				appids="22380 22490"
			fi
			for aid in $appids; do
				acf="$steamapps_dir/appmanifest_${aid}.acf"
				if [ -f "$acf" ] && grep -Fqi "\"$game_folder\"" "$acf" 2>/dev/null; then
					rm -f "$acf"
					ok "Removed Steam manifest $(basename "$acf")"
				fi
			done
			;;
	esac

	# If source is an innoextract app/ folder, clean app/ + sibling tmp/ (or the dedicated parent folder)
	if [ "$(basename "$src")" = "app" ]; then
		local parent="$(dirname "$src")"
		if is_protected_dir "$parent"; then
			rm -rf "$src"
			if [ -d "$parent/tmp" ] && { [ -f "$parent/tmp/InnoCallback.dll" ] || [ -f "$parent/tmp/gog.ico" ] || [ -f "$parent/tmp/GOG.png" ]; }; then
				rm -rf "$parent/tmp"
			fi
			ok "Cleaned leftover extracted files from $src"
		else
			rm -rf "$parent"
			ok "Cleaned leftover extracted folder: $parent"
		fi
		return 0
	fi

	if ! is_protected_dir "$src"; then
		rm -rf "$src"
		ok "Cleaned leftover source folder: $src"
		case "$src" in
			*/depots/*/*)
				rmdir "$(dirname "$src")" 2>/dev/null || true
				rmdir "$(dirname "$(dirname "$src")")" 2>/dev/null || true
				;;
			*/gog-download/*/*)
				rm -f "$(dirname "$src")/.gogdl-complete"
				rmdir "$(dirname "$src")" 2>/dev/null || true
				rmdir "$(dirname "$(dirname "$src")")" 2>/dev/null || true
				;;
			*/steam-download/*|*/gog-download/*)
				rmdir "$(dirname "$src")" 2>/dev/null || true
				;;
		esac
	fi
}

cleanup_build_cache() {
	if [ "$KEEP_CACHE" = no ]; then
		rm -rf "$CACHE_ROOT"
		ok "Cleaned build & translation cache ($CACHE_ROOT; pass --keep-cache to retain it)"
	else
		ok "Kept build & translation cache at $CACHE_ROOT (--keep-cache)"
	fi
}

print_post_install_notes() {
	local brew_cmd="brew"
	if [ "$BREW_SELF_INSTALLED" = yes ] || [ "$BREW_ADDED_TO_PATH" = yes ]; then
		brew_cmd="/opt/homebrew/bin/brew"
	fi
	if [ -n "$GOG_INSTALLER_PATH" ]; then
		printf '  Original GOG installer files in %s were kept (safe to delete if you do not need a backup).\n' "$(dirname "$GOG_INSTALLER_PATH")"
	fi
	# Packages are remembered across runs, so filter to the ones still installed (a previous run may
	# have installed them and then failed before printing this hint; see issue #5).
	local still=() cask_still=() pkg
	for pkg in "${BREW_INSTALLED[@]+"${BREW_INSTALLED[@]}"}"; do
		if "$brew_cmd" list --cask --versions "$pkg" >/dev/null 2>&1; then
			cask_still+=("$pkg")
		elif "$brew_cmd" list --versions "$pkg" >/dev/null 2>&1; then
			still+=("$pkg")
		fi
	done
	if [ ${#still[@]} -gt 0 ] || [ ${#cask_still[@]} -gt 0 ]; then
		printf '\n  %sHomebrew packages installed by this installer:%s' "$BOLD" "$RESET"
		for pkg in "${still[@]+"${still[@]}"}" "${cask_still[@]+"${cask_still[@]}"}"; do printf ' %s' "$pkg"; done
		printf '\n'
		printf '  None of them are required to play. To uninstall them later:\n'
		if [ ${#still[@]} -gt 0 ]; then
			printf '    %s uninstall %s\n' "$brew_cmd" "${still[*]}"
		fi
		if [ ${#cask_still[@]} -gt 0 ]; then
			printf '    %s uninstall --cask %s\n' "$brew_cmd" "${cask_still[*]}"
		fi
		printf '    %s cleanup\n' "$brew_cmd"
		printf '  ("%s autoremove" also drops dependencies they pulled in, such as the JDK.)\n' "$brew_cmd"
	fi
	rm -f "$BREW_STATE_FILE" 2>/dev/null || true
	if [ "$BREW_SELF_INSTALLED" = yes ]; then
		printf '\n  %sHomebrew itself was installed into /opt/homebrew during this run.%s\n' "$BOLD" "$RESET"
		printf '  It is not required to play. To uninstall Homebrew completely later, run its official script:\n'
		printf '    /bin/bash -c "$(curl -fsSL %s)"\n' "$HOMEBREW_UNINSTALL_URL"
		printf '  Or to keep using brew in future Terminal sessions, run:\n'
		printf '    echo '\''eval "$(/opt/homebrew/bin/brew shellenv)"'\'' >> ~/.zprofile\n'
	fi
	printf '\n'
}

mkdir -p "$DEST_DIR"
if [ "$WANT_DMG" = no ]; then
	rm -rf "$DEST_DIR/$APP_NAME.app"
	mv "$APP" "$DEST_DIR/$APP_NAME.app"
	GDATA=""
	LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
	[ -x "$LSREG" ] && "$LSREG" -f "$DEST_DIR/$APP_NAME.app" >/dev/null 2>&1 || true
	cleanup_source_leftovers
	cleanup_build_cache
	ok "Placed $APP_NAME.app in $DEST_DIR"
	printf '\n%s✔ Done!%s %s is ready.\n' "$GREEN$BOLD" "$RESET" "$DEST_DIR/$APP_NAME.app"
	printf '  Double-click it in Applications (or Launchpad/Spotlight) to play.\n'
	printf '  Saves & INIs live in ~/Library/Application Support/%s/\n' "$GAME_SUPPORT_DIR"
	print_post_install_notes
	open -R "$DEST_DIR/$APP_NAME.app" 2>/dev/null || true
	exit 0
fi

STAGE="$TMP/stage"
mkdir -p "$STAGE"
mv "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
TMPDMG="$TMP/rw.dmg"

run_logged_task "Creating disk image" "$TMP/hdiutil.log" hdiutil create -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ -format UDRW "$TMPDMG" \
	|| die "Creating disk image failed"
rm -f "$DEST_DIR/$APP_NAME.dmg"
run_logged_task "Compressing disk image" "$TMP/hdiutil.log" hdiutil convert "$TMPDMG" -format UDZO -imagekey zlib-level=9 -o "$DEST_DIR/$APP_NAME.dmg" \
	|| die "Compressing disk image failed"
GDATA=""
cleanup_source_leftovers
cleanup_build_cache
ok "Created $DEST_DIR/$APP_NAME.dmg"
print_post_install_notes
open -R "$DEST_DIR/$APP_NAME.dmg" 2>/dev/null || true
}

main "$@"
