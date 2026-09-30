#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$*"
}

echo "[1/12] shell syntax"
for file in "$ROOT/ori" "$ROOT"/lib/*.sh "$ROOT/tests/test.sh"; do
  bash -n "$file" || fail "syntax: $file"
done
pass "shell syntax"

echo "[2/12] executable entry point"
[[ -x "$ROOT/ori" ]] || fail "ori is not executable"
grep -Fq 'main "$@"' "$ROOT/ori" || fail "ori does not dispatch main"
pass "entry point"

echo "[3/12] game profiles"
python3 - "$ROOT/config/blind.plist" "$ROOT/config/blind-de.plist" "$ROOT/config/wotw.plist" <<'PY'
import plistlib, sys
expected = [
    ("blind", 261570, "ori.exe"),
    ("blind-de", 387290, "OriDE.exe"),
    ("wotw", 1057090, "oriwotw.exe"),
]
for path, exp in zip(sys.argv[1:], expected):
    with open(path, "rb") as f:
        p = plistlib.load(f)
    slug, appid, exe = exp
    assert p["slug"] == slug
    assert p["steamAppId"] == appid
    assert p["executable"] == exe
    assert p["runtimeVersion"] == "3.1.1"
    assert p["preferredRenderer"] == "DXMT"
    assert p["preferredRendererVersion"] == "0.80"
    if p["slug"] in ("blind", "blind-de"):
        assert p["highDpiAware"] == 1
    assert p["display"]["targetWidth"] == 1920
    assert p["display"]["targetHeight"] == 1080
    if p["slug"] in ("blind", "blind-de"):
        assert p["display"]["retinaMode"] == "y"
        assert p["display"]["dpi"] == 192
    else:
        assert p["display"]["retinaMode"] == "n"
    assert p["display"]["videoMemoryMB"] == 8192
    assert p["environment"]["WINEESYNC"] == "1"
    assert p["environment"]["MONO_THREADS_SUSPEND"] == "1"
    assert p["environment"]["D3DM_FORCE_D3D11"] == "1"
    if p["slug"] in ("blind", "blind-de"):
        assert p["environment"]["WINEMSYNC"] == "1"
        assert p["screenmanagerRegistry"] == 1
        assert p["fullscreenRegistryName"] == "Screenmanager Is Fullscreen mode_h3981298716"
    else:
        assert p["environment"]["WINEMSYNC"] == "0"
        assert p["fullscreenRegistryName"] == "Screenmanager Fullscreen mode_h3630240806"
    assert p["audio"]["driver"] == "coreaudio"
PY
pass "game profiles"

echo "[4/12] runtime pin"
grep -Fq 'RUNTIME_VERSION="3.1.1"' "$ROOT/lib/whisky.sh" || fail "runtime is not pinned"
grep -Fq 'RUNTIME_SHA256="01f3a1b43b98065fe20c529c1023b61dd79a6d2ad93bba6040865f646481ccf3"' "$ROOT/lib/whisky.sh" || fail "runtime checksum is not pinned"
pass "runtime pin"

echo "[5/12] multi-game detection contract"
grep -Fq 'manifest_for_appid 261570' "$ROOT/lib/steam.sh" || fail "Blind Forest detection missing"
grep -Fq 'manifest_for_appid 387290' "$ROOT/lib/steam.sh" || fail "Blind Forest DE detection missing"
grep -Fq 'manifest_for_appid 1057090' "$ROOT/lib/steam.sh" || fail "Will of the Wisps detection missing"
grep -Fq 'load_game_profile "blind"' "$ROOT/lib/steam.sh" || fail "Blind Forest profile selection missing"
grep -Fq 'load_game_profile "wotw"' "$ROOT/lib/steam.sh" || fail "WotW profile selection missing"
pass "multi-game detection"

echo "[6/12] forced Unity display arguments"
grep -Fq -- '-force-d3d11' "$ROOT/lib/steam.sh" || fail "D3D11 force missing"
grep -Fq -- '-screen-width' "$ROOT/lib/steam.sh" || fail "screen width arg missing"
grep -Fq -- '-screen-height' "$ROOT/lib/steam.sh" || fail "screen height arg missing"
grep -Fq -- '-screen-fullscreen' "$ROOT/lib/steam.sh" || fail "fullscreen arg missing"
pass "Unity display args"

echo "[7/12] tuning contract"
grep -Fq 'TUNING_SCHEMA_VERSION="16"' "$ROOT/lib/whisky.sh" || fail "tuning schema not bumped"
grep -Fq 'DXMT_SHADER_CACHE_PATH' "$ROOT/lib/whisky.sh" || fail "DXMT shader cache path missing"
grep -Fq 'DXMT_SHADER_CACHE="1"' "$ROOT/lib/whisky.sh" || fail "DXMT shader cache not enabled"
grep -Fq 'show_dxmt_logs()' "$ROOT/lib/steam.sh" || fail "DXMT log command missing"
grep -Fq 'DXMT_CONFIG' "$ROOT/lib/whisky.sh" || fail "DXMT frame pacing env missing"
grep -Fq 'd3d11.preferredMaxFrameRate=60;' "$ROOT/config/blind.plist" || fail "Blind Forest 60 FPS Metal pacing missing"
grep -Fq 'CaptureDisplaysForFullscreen' "$ROOT/lib/whisky.sh" || fail "macOS fullscreen capture tuning missing"
grep -Fq 'EnableAppNap' "$ROOT/lib/whisky.sh" || fail "App Nap disable tuning missing"
grep -Fq 'GAME_RUNTIME_LOG' "$ROOT/lib/whisky.sh" || fail "dedicated runtime log missing"
grep -Fq 'WINE_MACH_PORT_TIMEOUT' "$ROOT/lib/whisky.sh" || fail "modern macOS Wine compatibility env missing"
grep -Fq 'WINE_THREAD_PRIORITY_PRESERVE' "$ROOT/lib/whisky.sh" || fail "Wine thread-priority compatibility env missing"
grep -Fq 'DXVK_ASYNC' "$ROOT/lib/whisky.sh" || fail "Steam DXVK async env missing"
grep -Fq 'steamwebhelper.exe' "$ROOT/lib/whisky.sh" || fail "Steam helper AppDefaults scope missing"
grep -Fq "reg add \"\$steam_key\" /v d3d11" "$ROOT/lib/whisky.sh" || fail "Steam helper DXVK overrides missing"
grep -Fq 'sync_program_dll_overrides()' "$ROOT/lib/whisky.sh" || fail "per-program DLL override sync missing"
grep -Fq 'AppDefaults' "$ROOT/lib/whisky.sh" || fail "Wine AppDefaults override scope missing"
if grep -Fq 'export WINEDLLOVERRIDES' "$ROOT/lib/whisky.sh"; then
  fail "WINEDLLOVERRIDES must not leak into Steam/helper environment"
fi
grep -Fq 'deploy_dxvk()' "$ROOT/lib/whisky.sh" || fail "DXVK deployment missing"
grep -Fq 'HIGHDPIAWARE' "$ROOT/lib/whisky.sh" || fail "high-DPI awareness override missing"
grep -Fq "VideoMemorySize" "$ROOT/lib/whisky.sh" || fail "VRAM reporting override missing"
grep -Fq "MONO_THREADS_SUSPEND" "$ROOT/lib/whisky.sh" || fail "Unity performance environment missing"
grep -Fq "HelBuflen" "$ROOT/lib/whisky.sh" || fail "audio buffer tuning missing"
grep -Fq "RetinaMode" "$ROOT/lib/whisky.sh" || fail "Retina handling missing"
grep -Fq "screenmanagerRegistry" "$ROOT/lib/whisky.sh" || fail "profile-aware registry handling missing"
grep -Fq "screenWidthRegistryName" "$ROOT/lib/whisky.sh" || fail "profile width registry key handling missing"
grep -Fq "fullscreenRegistryName" "$ROOT/lib/whisky.sh" || fail "profile fullscreen registry key handling missing"
pass "tuning contract"

echo "[8/12] path safety"
grep -Fq 'rm -rf "$ORI_PREFIX"' "$ROOT/lib/whisky.sh" || fail "prefix reset is not scoped"
if grep -REn 'rm[[:space:]]+-rf[[:space:]]+(")?(~|\$HOME)(/|["[:space:]]|$)' "$ROOT/lib" "$ROOT/ori"; then
  fail "broad home-directory deletion found"
fi
pass "path safety"

echo "[9/12] one-command README"
grep -Fq './ori' "$ROOT/README.md" || fail "README ./ori missing"
grep -Fq 'auto-detect' "$ROOT/README.md" || fail "README auto-detect missing"
pass "README"

echo "[10/12] direct launch bypass"
grep -Fq 'prepare_direct_ori_launch()' "$ROOT/lib/steam.sh" || fail "direct Ori launcher missing"
grep -Fq 'steam_appid.txt' "$ROOT/lib/steam.sh" || fail "steam_appid.txt setup missing"
grep -Fq 'wine_game_program_cwd' "$ROOT/lib/steam.sh" || fail "direct game executable launch missing"
grep -Fq 'SteamAppId=' "$ROOT/lib/whisky.sh" || fail "Steam App ID environment hint missing"
grep -Fq 'kill_wine_session' "$ROOT/lib/steam.sh" || fail "Steam/CEF session cleanup missing"
pass "direct launch bypass"

echo "[11/12] Steam helper DXVK isolation"
if grep -Fq -- '-cef-disable-gpu' "$ROOT/lib/steam.sh"; then
  fail "obsolete Steam CEF software-rendering flag still present"
fi
grep -Fq 'steamservice.exe' "$ROOT/lib/whisky.sh" || fail "Steam service helper override missing"
pass "Steam helper DXVK isolation"

echo "[12/12] secret/logging safety"
if grep -REni '(steamloginsecure|refresh[_-]?token|access[_-]?token|password|passwd).*(echo|printf)' "$ROOT/lib" "$ROOT/ori"; then
  fail "possible secret logging"
fi
pass "secret/logging safety"

echo "All static and fixture tests passed."
